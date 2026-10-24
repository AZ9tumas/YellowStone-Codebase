--[[
	HeadLook

	Head/neck aiming over the live gait pose. CameraTracking creatures follow
	the owner's camera direction; others attend to the nearest creature.
	With no aim, the layer relaxes back onto the animated pose.

	This is inverse kinematics in the same sense LegIK is: a world direction
	or point goes in and the joint angles that aim at it come out. It composes with
	BodyArticulation's neck rather than replacing it: that chain leads into a
	TURN (where the creature is steering), this one corrects the resulting pose
	toward a look direction or target. Both use the shared BoneWriter.

	Sign safety: the only rotation this performs is "swing direction A onto
	direction B about A x B", the same primitive LegIK's hip uses and the one
	behaviour measured directly on the rig. Nothing here assumes which local
	axis of a bone points forward, so it needs no per-rig axis constants.
	  * The aim direction is read from the pivot bone to an `Aim` bone further
	    down the skull (the wolf uses "Nose") — whatever the rig's bone axes
	    are, the line between two joints is unambiguous.
	  * The target direction is clamped inside a yaw/pitch cone by REBUILDING
	    it from the body basis, not by rotating, so the clamp cannot flip a
	    sign either.

	Splitting the swing across several bones by weight is exact for the
	direction: rotations about a common axis add, so 0.4 on the neck plus 0.6
	on the head aims exactly where 1.0 on the head would, spread over a nicer
	curve. It does move the head's origin slightly, so a very close target is
	aimed at a little loosely — irrelevant at the ranges this runs at.

	Bone.Transform does not replicate; every client runs this for every
	creature it can see. HeadLookService shares the owner's camera direction
	for observers; automatic attention uses positions all clients already know.
]]

local Players = game:GetService("Players")

local BoneWriter = require(script.Parent.BoneWriter)

local HeadLook = {}
HeadLook.__index = HeadLook

local EPS = 1e-4
local DT_MAX = 0.1
local STRENGTH_RESPONSE = 4 -- 1/s, fade in when a target appears and out when it goes
local ACQUIRE_INTERVAL = 0.25 -- s between target sweeps; the aim itself is per-frame
local ANGLE_EPS = 1e-6

local DEF_RESPONSE = 6 -- 1/s, how fast the aim slews
local DEF_RADIUS = 60 -- studs
local DEF_CONE = 120 -- deg, half-angle the creature will turn its head within

-- Shared by the local publisher and server/observer drivers.
HeadLook.DIRECTION_ATTRIBUTE = "HeadLookDirection"
HeadLook.SEND_INTERVAL = 0.1 -- at most 10 updates/s; bone smoothing is per-frame
HeadLook.KEEPALIVE_INTERVAL = 0.5 -- retry the final pose if a rate-limited update was dropped
HeadLook.CHANGE_COS = math.cos(math.rad(0.5)) -- ignore sub-degree camera jitter on the network

export type Config = {
	Bones: { string }, -- neck..head, in that order; they share the swing
	Aim: string, -- bone further down the skull that marks "forward"
	Weights: { number }?, -- share of the swing per bone; omitted = even split
	MaxYaw: number, -- deg from the body's facing
	MaxPitch: number, -- deg
	Response: number?, -- 1/s, aim slew rate
	CameraTracking: boolean?, -- true: owner's camera; false/nil: nearest creature
	Radius: number?, -- studs; how far away a target may be
	Cone: number?, -- deg half-angle; targets outside are ignored
}

export type Signals = {
	Facing: Vector3, -- the root's LookVector
	Up: Vector3, -- the root's UpVector
	Target: Vector3?, -- world point; omit to self-acquire when CameraTracking is off
	Direction: Vector3?, -- world look direction; takes precedence over Target
	Suppressed: boolean?, -- resting / frozen / far away: eases out and lets go
}

export type Debug = {
	Yaw: number, -- deg off the body's facing
	Pitch: number, -- deg
	HasTarget: boolean,
	Gain: number, -- 0..1
}

export type HeadLook = typeof(setmetatable(
	{} :: {
		writer: BoneWriter.BoneWriter,
		character: Model,
		bones: { Bone },
		weights: { number },
		pivot: Bone,
		aim: Bone,
		maxYaw: number,
		maxPitch: number,
		response: number,
		cameraTracking: boolean,
		radius: number,
		cosCone: number,
		dir: Vector3?, -- smoothed aim direction, world
		strength: number,
		clock: number,
		acquired: Vector3?,
		yaw: number,
		pitch: number,
		hasTarget: boolean,
	},
	HeadLook
))

-- ===== construction ==========================================================

function HeadLook.RequiredBones(config: Config): { string }
	local names = table.clone(config.Bones or {})
	if config.Aim then
		names[#names + 1] = config.Aim
	end
	return names
end

function HeadLook.MissingBones(character: Model, config: Config): { string }
	return BoneWriter.Missing(character, HeadLook.RequiredBones(config))
end

function HeadLook.fromInfo(character: Model, info: { [string]: any }, writer: BoneWriter.BoneWriter): HeadLook?
	local config = info.HeadLook
	if not config then
		return nil
	end
	return HeadLook.new(character, config, writer)
end

function HeadLook.new(character: Model, config: Config, writer: BoneWriter.BoneWriter): HeadLook
	assert(type(config) == "table", "HeadLook: config missing")
	assert(writer, "HeadLook: a BoneWriter is required")
	assert(type(config.Bones) == "table" and #config.Bones > 0, "HeadLook: config has no Bones")
	assert(type(config.Aim) == "string", "HeadLook: config needs an Aim bone")
	assert(config.CameraTracking == nil or type(config.CameraTracking) == "boolean", "HeadLook: CameraTracking must be boolean")
	assert(
		type(config.MaxYaw) == "number" and type(config.MaxPitch) == "number",
		"HeadLook: config needs numeric MaxYaw and MaxPitch"
	)

	local claim = BoneWriter.Claimer(character, "HeadLook")
	local bones = {}
	for _, n in config.Bones do
		bones[#bones + 1] = claim(n, "Bones")
	end

	local weights = config.Weights
	if weights then
		assert(#weights == #bones, `HeadLook: {#bones} bones but {#weights} weights`)
		local sum = 0
		for _, w in weights do
			assert(w >= 0, "HeadLook: negative weight")
			sum += w
		end
		assert(math.abs(sum - 1) < 1e-3, `HeadLook: weights sum to {sum}, expected 1`)
	else
		weights = table.create(#bones, 1 / #bones)
	end

	-- The aim bone is only ever READ, so it is looked up rather than claimed:
	-- it may well be a bone some other layer writes.
	local byName, count = BoneWriter.Index(character)
	local aim = byName[config.Aim]
	assert(aim, `HeadLook: Aim names bone "{config.Aim}" which does not exist on the rig`)
	assert(count[config.Aim] == 1, `HeadLook: Aim names bone "{config.Aim}" which is ambiguous`)

	local self = setmetatable({}, HeadLook)
	self.writer = writer
	self.character = character
	self.bones = bones
	self.weights = weights
	self.pivot = bones[#bones] -- the head: last bone in the chain
	self.aim = aim
	self.maxYaw = math.rad(config.MaxYaw)
	self.maxPitch = math.rad(config.MaxPitch)
	self.response = config.Response or DEF_RESPONSE
	self.cameraTracking = config.CameraTracking == true
	self.radius = config.Radius or DEF_RADIUS
	self.cosCone = math.cos(math.rad(config.Cone or DEF_CONE))
	self.dir = nil
	self.strength = 0
	self.clock = math.huge -- acquire on the very first frame
	self.acquired = nil
	self.yaw = 0
	self.pitch = 0
	self.hasTarget = false
	return self
end

-- ===== target selection ======================================================

-- Camera directions also cross a remote boundary. Reject malformed vectors
-- before they can enter bone math or replicated character attributes.
function HeadLook.UnitDirection(direction: any): Vector3?
	if typeof(direction) ~= "Vector3" then
		return nil
	end
	local length = direction.Magnitude
	if not (length > EPS and length < math.huge) then
		return nil
	end
	return direction / length
end

local function clampDirection(d: Vector3, f: Vector3, right: Vector3, up: Vector3, maxYaw: number, maxPitch: number): (Vector3, number, number)
	local x, y, z = d:Dot(f), d:Dot(right), d:Dot(up)
	local yaw = math.clamp(math.atan2(y, x), -maxYaw, maxYaw)
	local pitch = math.clamp(math.atan2(z, math.sqrt(x * x + y * y)), -maxPitch, maxPitch)
	local cp = math.cos(pitch)
	return f * (cp * math.cos(yaw)) + right * (cp * math.sin(yaw)) + up * math.sin(pitch), yaw, pitch
end

-- The nearest other player's creature inside the radius and the cone. Derived
-- only from positions every client already has, so it needs no replication
-- and every observer picks the same target.
function HeadLook.FindTarget(character: Model, origin: Vector3, facing: Vector3, radius: number, cosCone: number): Vector3?
	local best, bestDist = nil, radius
	for _, player in Players:GetPlayers() do
		local other = player.Character
		if other and other ~= character then
			local root = other:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local delta = root.Position - origin
				local dist = delta.Magnitude
				if dist > EPS and dist < bestDist and delta.Unit:Dot(facing) >= cosCone then
					best, bestDist = root.Position, dist
				end
			end
		end
	end
	return best
end

-- ===== per-frame =============================================================

function HeadLook:Update(signals: Signals, dt: number)
	local up, facing = signals.Up, signals.Facing
	if up.Magnitude < EPS or facing.Magnitude < EPS or up.X ~= up.X or facing.X ~= facing.X then
		return
	end
	up = up.Unit
	dt = math.clamp(dt, 1e-4, DT_MAX)

	-- Body basis, orthonormalised so a pitched body still gets a clean cone.
	local f = facing - up * up:Dot(facing)
	if f.Magnitude < EPS then
		return
	end
	f = f.Unit
	local right = f:Cross(up)
	if right.Magnitude < EPS then
		return
	end
	right = right.Unit

	local writer = self.writer
	for _, bone in ipairs(self.bones) do
		writer:Prepare(bone)
	end

	local pivotPos = self.pivot.TransformedWorldCFrame.Position
	local aimDir = self.aim.TransformedWorldCFrame.Position - pivotPos
	if aimDir.Magnitude < EPS then
		return
	end
	aimDir = aimDir.Unit

	local direction = HeadLook.UnitDirection(signals.Direction)
	local target = signals.Target
	if direction == nil and target == nil and not self.cameraTracking and not signals.Suppressed then
		self.clock += dt
		if self.clock >= ACQUIRE_INTERVAL then
			self.clock = 0
			self.acquired = HeadLook.FindTarget(self.character, pivotPos, f, self.radius, self.cosCone)
		end
		target = self.acquired
	end

	local wanted: Vector3? = nil
	if not direction and target then
		direction = HeadLook.UnitDirection(target - pivotPos)
	end
	if direction and not signals.Suppressed then
		wanted = clampDirection(direction, f, right, up, self.maxYaw, self.maxPitch)
	end
	self.hasTarget = wanted ~= nil

	local alpha = 1 - math.exp(-self.response * dt)
	if wanted then
		-- Slew the aim, seeding on the first sighting so the head does not
		-- snap round from a stale direction.
		local dir = if self.dir then self.dir + (wanted - self.dir) * alpha else wanted
		self.dir = if dir.Magnitude > EPS then dir.Unit else wanted
	end
	if self.dir then
		-- The body may have turned since last frame. Bound the retained world
		-- direction during active aiming AND fade-out, before applying its gain.
		local dir, yaw, pitch = clampDirection(self.dir, f, right, up, self.maxYaw, self.maxPitch)
		self.dir = dir
		if wanted then
			self.yaw, self.pitch = yaw, pitch
		end
	end
	self.strength += ((if wanted then 1 else 0) - self.strength) * (1 - math.exp(-STRENGTH_RESPONSE * dt))
	if not wanted then
		self.yaw, self.pitch = self.yaw * (1 - alpha), self.pitch * (1 - alpha)
	end

	local dir = self.dir
	if not dir or self.strength < 1e-3 then
		return -- nothing to aim at: EndFrame hands the bones back
	end

	local axis = aimDir:Cross(dir)
	if axis.Magnitude < EPS then
		return
	end
	local angle = math.acos(math.clamp(aimDir:Dot(dir), -1, 1)) * self.strength
	if angle < ANGLE_EPS then
		return
	end
	axis = axis.Unit
	for i, bone in ipairs(self.bones) do
		local share = angle * self.weights[i]
		if share > ANGLE_EPS then
			writer:Add(bone, CFrame.fromAxisAngle(bone.TransformedWorldCFrame:VectorToObjectSpace(axis), share))
		end
	end
end

-- ===== introspection =========================================================

function HeadLook:GetDebug(): Debug
	return {
		Yaw = math.deg(self.yaw),
		Pitch = math.deg(self.pitch),
		HasTarget = self.hasTarget,
		Gain = self.strength,
	}
end

return HeadLook
