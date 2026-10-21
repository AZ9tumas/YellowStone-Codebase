--[[
	LegIK

	Terrain foot planting for a skinned quadruped. The authored animation
	stays in charge of WHEN a paw lifts and HOW HIGH; this layer only moves the
	ground it is measured from, so paws meet a slope, a rock or a step instead
	of floating above it or sinking through it, and a stride, a turn step or a
	hop keeps its lift.

	This is the genuine inverse-kinematics half of the movement stack:
	BodyArticulation bends the spine by forward kinematics (angles in, pose
	out), while here a world-space contact point comes in and the joint angles
	that reach it come out.

	Per leg, per frame:
	  1. Strip last frame's solve so the probe sees the animated pose.
	  2. Raycast down from the paw. The correction is how far the ground sits
	     from the ground the rig's BIND pose stands on, clamped and smoothed
	     so an edge or a gap cannot pop it.
	  3. Lower the body by the deepest correction so an over-reaching leg can
	     still touch down instead of stretching straight.
	  4. Two-bone solve placing the paw at its bind-pose height over that
	     ground, plus however far the CLIP lifts it above that height. The
	     lift is read from the clip alone (BoneWriter:Animated), so a spine
	     bend or chest bank above the leg is taken back out and a planted paw
	     stays planted; a clip that reaches a paw BELOW its bind height (the
	     wolf's sprint does) has it held on the ground, not pushed into it.
	  5. Roll the paw onto the ground normal.

	Measured on the wolf, the bind pose and every clip but the sprint stand the
	paws on one plane about 0.55 studs above the floor the Humanoid holds the
	root over, so on flat ground every leg corrects by about -0.55 and the
	body drop does the work. Correcting each paw straight onto the ground
	instead (as this layer first did) also cancelled every stride: up to 1.4
	studs of sprint lift, with the body held at full drop the whole time.

	The solve treats the PAW as the end effector, not the ankle/wrist above it.
	Only two bones are ever rotated (the hip and the knee), so everything below
	the knee — the ankle joint included — is rigid within the frame, and the
	law of cosines on hip->knee->paw therefore lands the paw exactly. Aiming
	the ankle instead and shifting the target by the ankle-to-paw gap treats a
	rotation as a translation, which misses by (paw lever) x (swing angle):
	measured at 0.002 studs on the wolf's short front pastern but 0.2 on its
	long hock, and re-solving to chase that error diverges the moment the limb
	has to straighten. Solving for the paw has neither problem and needs no
	iteration.

	The solve (measured on the rig, see the wiki):
	  * Bend the knee about the limb's OWN plane normal, changing only the
	    interior angle. The plane the animation put the limb in therefore acts
	    as the pole vector — there is none to configure, none to get wrong, and
	    the knee can never flip to the other side mid-stride. This is the main
	    reason not to route this through IKControl, whose Pole is unreliable on
	    multi-segment chains.
	  * The limb is then the right length by construction, so ONE rotation
	    about the hip lands the paw exactly on the target.

	Everything measured in studs is authored as a FRACTION of that leg's own
	rest length, and the paw's ground clearance is read off the rest rig. A
	creature of any size therefore needs no numeric tuning at all — the wolf
	config is four bone quads and nothing else.

	Turning on the spot (Signals.Pivoting) the paws come off the animation's
	footwork altogether: PawStepper keeps each one planted in the world while
	the body turns above it and steps it when it falls too far behind, and the
	body crouches a little (Crouch) so the legs can reach. Everything else here
	carries on — the ground under each paw, the lift of a step, the solve.

	Bone.Transform does not replicate, so like BodyArticulation this runs on
	every client for every creature it can see.
]]

local BoneWriter = require(script.Parent.BoneWriter)
local PawStepper = require(script.Parent.PawStepper)

local LegIK = {}
LegIK.__index = LegIK

local EPS = 1e-4
local DT_MAX = 0.1 -- hitch guard on the smoothing step
local BLEND_RESPONSE = 8 -- 1/s, ease in/out when suppression changes
local BLEND_EPS = 1e-3 -- below this the layer stops touching bones entirely
local STEP_BLEND_RESPONSE = 12 -- 1/s, handing the paws to the stepper and back

-- Fractions of a leg's rest length (upper + mid segment). Scale-free.
local DEF_MAX_LIFT = 0.45
local DEF_MAX_DROP = 0.45
local DEF_RAY_UP = 0.6
local DEF_RAY_DOWN = 1.2
local DEF_MAX_BODY_DROP = 0.25
local DEF_RESPONSE = 14 -- 1/s, smoothing of each foot's correction
local DEF_MAX_FOOT_TILT = 35 -- deg
local DEF_CROUCH = 0.08 -- extra body drop while stepping, fraction of the average leg


export type LegConfig = {
	Name: string,
	Upper: string, -- hip / shoulder: the bone that swings the whole limb
	Mid: string, -- knee / elbow: the bone whose interior angle changes
	Foot: string, -- paw: the end effector, the contact reference, and what gets tilted
}

export type Config = {
	Legs: { LegConfig },
	BodyBone: string?, -- lowered so an over-reaching leg can reach; omit to disable
	AlignFeet: boolean?, -- roll the paw onto the ground normal (default true)
	MaxLift: number?, -- all five below are fractions of the leg's rest length
	MaxDrop: number?,
	RayUp: number?,
	RayDown: number?,
	MaxBodyDrop: number?,
	Response: number?, -- 1/s
	MaxFootTilt: number?, -- deg
	Crouch: number?, -- extra body drop while stepping, fraction of the average leg
	Step: PawStepper.Config?, -- tuning for turning on the spot (see PawStepper)
}

export type Signals = {
	Up: Vector3, -- the root's UpVector: the axis corrections are applied along
	Suppressed: boolean?, -- resting / frozen / far away: eases out and lets go
	Pivoting: boolean?, -- turning on the spot: the paws step instead of following the pose
}

export type Debug = {
	Legs: { [string]: number }, -- each foot's correction, studs
	Grounded: number, -- feet that found ground this frame
	BodyDrop: number, -- studs
	Gain: number, -- 0..1
	Stepping: number?, -- paws in the air while stepping; nil when not stepping
}

type Leg = {
	name: string,
	upper: Bone,
	mid: Bone,
	foot: Bone,
	part: BasePart, -- what the rig's bones hang from
	chain: { Bone }, -- part -> paw, to rebuild the clip's own pose
	chainBind: { CFrame }, -- each chain bone's CFrame (static rig data)
	bind: CFrame, -- the paw joint's bind pose relative to `part`
	clearance: number, -- paw joint's height above its lowest toe in the bind pose, studs
	length: number, -- studs: the two solved segments, the yardstick for every fraction
	maxLift: number,
	maxDrop: number,
	rayUp: number,
	rayDown: number,
	offset: number, -- smoothed ground height vs the bind pose's ground, along up, studs
	normal: Vector3, -- smoothed ground normal
	grounded: boolean,
	target: Vector3, -- this frame's contact point for the paw
}

export type LegIK = typeof(setmetatable(
	{} :: {
		writer: BoneWriter.BoneWriter,
		legs: { Leg },
		bodyBone: Bone?,
		maxBodyDrop: number,
		alignFeet: boolean,
		response: number,
		maxFootTilt: number,
		rayParams: RaycastParams,
		bodyDrop: number,
		blend: number,
		groundedCount: number,
		stepper: PawStepper.PawStepper,
		stepWeight: number, -- 0..1, how far the paws are handed to the stepper
		stepping: boolean,
		crouch: number, -- studs
		feet: { Vector3 }, -- this frame's paws under the pose, reused
	},
	LegIK
))

-- ===== construction ==========================================================

function LegIK.RequiredBones(config: Config): { string }
	local names = {}
	for _, leg in ipairs(config.Legs or {}) do
		names[#names + 1] = leg.Upper
		names[#names + 1] = leg.Mid
		names[#names + 1] = leg.Foot
	end
	if config.BodyBone then
		names[#names + 1] = config.BodyBone
	end
	return names
end

function LegIK.MissingBones(character: Model, config: Config): { string }
	return BoneWriter.Missing(character, LegIK.RequiredBones(config))
end

-- The bones from the part the rig hangs from down to `bone`, and that part.
local function chainTo(bone: Bone): ({ Bone }, BasePart?)
	local chain = {}
	local node: Instance? = bone
	while node and node:IsA("Bone") do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	return chain, if node and node:IsA("BasePart") then node else nil
end

-- A chain's BIND pose relative to its part: the bone CFrames alone, no
-- Transform anywhere. (Bone.WorldPosition is not this: it leaves out only the
-- bone's OWN Transform and includes every ancestor's, i.e. the animated pose.)
local function bindOf(chain: { Bone }): CFrame
	local cf = CFrame.identity
	for _, b in chain do
		cf *= b.CFrame
	end
	return cf
end

-- How far the paw joint sits above its lowest toe in the bind pose: the height
-- it rides at when the paw is flat on the ground. Read off the bind pose, so
-- it is the same whatever the creature is doing when the layer is built, and
-- it scales with the rig, so it never needs authoring.
local function bindClearance(foot: Bone, part: BasePart, up: Vector3): number
	local joint = (part.CFrame * bindOf((chainTo(foot)))).Position
	local best = 0
	for _, d in foot:GetDescendants() do
		if d:IsA("Bone") then
			best = math.max(best, up:Dot(joint - (part.CFrame * bindOf((chainTo(d)))).Position))
		end
	end
	return best
end

function LegIK.fromInfo(character: Model, info: { [string]: any }, writer: BoneWriter.BoneWriter): LegIK?
	local config = info.LegIK
	if not config then
		return nil
	end
	return LegIK.new(character, config, writer)
end

function LegIK.new(character: Model, config: Config, writer: BoneWriter.BoneWriter): LegIK
	assert(type(config) == "table", "LegIK: config missing")
	assert(writer, "LegIK: a BoneWriter is required")
	assert(type(config.Legs) == "table" and #config.Legs > 0, "LegIK: config declares no Legs")

	-- The rig's own up, for the bind-pose clearance measurement below. Falls
	-- back through the model's pivot rather than world up: a rig authored or
	-- stored on its side would otherwise measure clearance along the wrong
	-- axis and silently plant its feet badly.
	local root = (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) :: BasePart?
	local up = if root then root.CFrame.UpVector else character:GetPivot().UpVector

	local claim = BoneWriter.Claimer(character, "LegIK")
	local self = setmetatable({}, LegIK)
	self.writer = writer
	self.legs = {}
	self.bodyDrop = 0
	self.blend = 0
	self.groundedCount = 0
	self.alignFeet = config.AlignFeet ~= false
	self.response = config.Response or DEF_RESPONSE
	self.maxFootTilt = math.rad(config.MaxFootTilt or DEF_MAX_FOOT_TILT)

	local seen: { [string]: boolean } = {}
	local totalLength = 0
	for _, lc in ipairs(config.Legs) do
		local where = `leg "{tostring(lc.Name)}"`
		assert(type(lc.Name) == "string", "LegIK: every leg needs a Name")
		assert(not seen[lc.Name], `LegIK: duplicate leg "{lc.Name}"`)
		seen[lc.Name] = true

		local upper = claim(lc.Upper, where)
		local mid = claim(lc.Mid, where)
		local foot = claim(lc.Foot, where)

		-- Rest length of the two solved segments: the yardstick every
		-- distance in this config is a fraction of.
		local length = (mid.WorldPosition - upper.WorldPosition).Magnitude
			+ (foot.WorldPosition - mid.WorldPosition).Magnitude
		assert(length > EPS, `LegIK: {where} has zero length — check Upper/Mid/Foot are three different joints`)
		totalLength += length

		-- Walking this chain with the clip's own transforms gives where the
		-- CLIP puts the paw, before any procedural layer bent the body above.
		local chain, part = chainTo(foot)
		assert(part, `LegIK: {where} paw "{lc.Foot}" does not hang from a part`)
		local chainBind = table.create(#chain)
		for i, b in chain do
			chainBind[i] = b.CFrame
		end

		self.legs[#self.legs + 1] = {
			name = lc.Name,
			upper = upper,
			mid = mid,
			foot = foot,
			part = part,
			chain = chain,
			chainBind = chainBind,
			bind = bindOf(chain),
			clearance = bindClearance(foot, part, up),
			length = length,
			maxLift = (config.MaxLift or DEF_MAX_LIFT) * length,
			maxDrop = (config.MaxDrop or DEF_MAX_DROP) * length,
			rayUp = (config.RayUp or DEF_RAY_UP) * length,
			rayDown = (config.RayDown or DEF_RAY_DOWN) * length,
			offset = 0,
			normal = up,
			grounded = false,
			target = Vector3.zero,
		}
	end

	self.bodyBone = if config.BodyBone then claim(config.BodyBone, "BodyBone") else nil
	self.maxBodyDrop = (config.MaxBodyDrop or DEF_MAX_BODY_DROP) * (totalLength / #self.legs)

	-- The stepper tells the legs apart by where the bind pose stands each paw
	-- relative to the root: left or right of it, ahead of it or behind.
	local rootCF = if root then root.CFrame else character:GetPivot()
	local specs = {}
	for i, leg in self.legs do
		local rel = rootCF:PointToObjectSpace((leg.part.CFrame * leg.bind).Position)
		specs[i] = { length = leg.length, left = rel.X < 0, front = rel.Z < 0 }
	end
	self.stepper = PawStepper.new(specs, config.Step)
	self.stepWeight = 0
	self.stepping = false
	self.crouch = (config.Crouch or DEF_CROUCH) * (totalLength / #self.legs)
	self.feet = table.create(#self.legs)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	self.rayParams = params

	return self
end

-- ===== the solve =============================================================

-- Place `leg.foot` on `target` by bending the knee and swinging the hip.
function LegIK:_solve(leg: Leg, target: Vector3, up: Vector3)
	local writer = self.writer
	local a = leg.upper.TransformedWorldCFrame.Position
	local b = leg.mid.TransformedWorldCFrame.Position
	local c = leg.foot.TransformedWorldCFrame.Position

	local lab = (b - a).Magnitude
	local lcb = (c - b).Magnitude
	local reach = (target - a).Magnitude
	if lab < EPS or lcb < EPS or reach < EPS then
		return
	end
	-- Never fully straight and never folded through itself: both leave the
	-- limb plane undefined for the next frame's solve.
	-- Out of reach simply saturates here: the limb straightens and points at
	-- the target, which is the right visual degradation for a step too tall.
	local lat = math.clamp(reach, math.abs(lab - lcb) + EPS, lab + lcb - EPS)

	-- Knee: interior angle only, about the limb's own plane normal.
	local ba, bc = a - b, c - b
	local cur = math.acos(math.clamp(ba.Unit:Dot(bc.Unit), -1, 1))
	local want = math.acos(math.clamp((lab * lab + lcb * lcb - lat * lat) / (2 * lab * lcb), -1, 1))
	local hinge = ba:Cross(bc)
	if hinge.Magnitude < EPS then
		hinge = (b - a):Cross(up) -- limb dead straight: bend in the sagittal plane
	end
	if hinge.Magnitude >= EPS and math.abs(want - cur) > 1e-6 then
		writer:Add(leg.mid, CFrame.fromAxisAngle(leg.mid.TransformedWorldCFrame:VectorToObjectSpace(hinge.Unit), want - cur))
	end

	-- Hip: the limb now spans exactly `lat`, so one rotation lands it.
	local from = leg.foot.TransformedWorldCFrame.Position - a
	local to = target - a
	if from.Magnitude < EPS or to.Magnitude < EPS then
		return
	end
	local axis = from:Cross(to)
	if axis.Magnitude < EPS then
		return
	end
	local ang = math.acos(math.clamp(from.Unit:Dot(to.Unit), -1, 1))
	if ang > 1e-6 then
		writer:Add(leg.upper, CFrame.fromAxisAngle(leg.upper.TransformedWorldCFrame:VectorToObjectSpace(axis.Unit), ang))
	end
end

-- ===== per-frame =============================================================

function LegIK:Update(signals: Signals, dt: number)
	local up = signals.Up
	if up.Magnitude < EPS or up.X ~= up.X then
		return
	end
	up = up.Unit
	dt = math.clamp(dt, 1e-4, DT_MAX)

	local goal = if signals.Suppressed then 0 else 1
	self.blend += (goal - self.blend) * (1 - math.exp(-BLEND_RESPONSE * dt))
	if self.blend < BLEND_EPS then
		-- Eased out: EndFrame hands the bones back to the animation, and a turn
		-- in progress is dropped rather than resumed later from stale plants.
		if self.stepping then
			self.stepper:Reset()
			self.stepping, self.stepWeight = false, 0
		end
		return
	end

	local writer = self.writer
	local alpha = 1 - math.exp(-self.response * dt)

	-- Strip last frame's solve first, so every probe below reads the pose the
	-- animation and BodyArticulation just produced rather than our own output.
	if self.bodyBone then
		writer:Prepare(self.bodyBone)
	end
	for _, leg in ipairs(self.legs) do
		writer:Prepare(leg.upper)
		writer:Prepare(leg.mid)
		writer:Prepare(leg.foot)
	end

	-- Where the pose holds each paw this frame: the homes the stepper plants
	-- the paws around while the body turns on the spot.
	local feet = self.feet
	for i, leg in ipairs(self.legs) do
		feet[i] = leg.foot.TransformedWorldCFrame.Position
	end
	local stepper = self.stepper
	self.stepping = stepper:Update(feet, up, signals.Pivoting == true, dt)
	local sw = self.stepWeight
		+ ((if self.stepping then 1 else 0) - self.stepWeight) * (1 - math.exp(-STEP_BLEND_RESPONSE * dt))
	self.stepWeight = sw

	-- Probe. A foot with nothing under it relaxes to the clip's own pose, so a
	-- creature in the air needs no separate airborne signal.
	local deepest = 0
	local grounded = 0
	for i, leg in ipairs(self.legs) do
		local pFoot = feet[i]
		local partCF = leg.part.CFrame
		local bindH = up:Dot((partCF * leg.bind).Position)
		-- How far the clip alone raises the paw joint above its bind-pose
		-- height: a lift it authored (kept) or, below zero, a reach down.
		local clipCF = partCF
		for i, b in leg.chain do
			clipCF = clipCF * leg.chainBind[i] * writer:Animated(b)
		end
		local clipH = up:Dot(clipCF.Position) - bindH
		-- Across the ground the paw goes where the pose holds it — or, turning
		-- on the spot, wherever the stepper has it planted or swinging.
		local pAt, stepLift = pFoot, 0
		if sw > 1e-3 then
			local pos, lift = stepper:Get(i)
			local across = pos - pFoot
			across -= up * up:Dot(across)
			pAt = pFoot + across * (sw * self.blend)
			stepLift = lift * sw
		end
		local hit = workspace:Raycast(pAt + up * leg.rayUp, -up * (leg.rayUp + leg.rayDown), self.rayParams)
		local raw, normal
		if hit then
			-- The ground under this paw against the ground the bind pose
			-- stands on. Only this is smoothed: a step's lift must reach the
			-- paw undelayed.
			raw = math.clamp(up:Dot(hit.Position) - bindH + leg.clearance, -leg.maxDrop, leg.maxLift)
			normal = hit.Normal
			leg.grounded = true
			grounded += 1
		else
			-- Eases the paw back to exactly where the clip holds it.
			raw, normal = math.min(clipH, 0), up
			leg.grounded = false
		end
		leg.offset += (raw - leg.offset) * alpha
		local n = leg.normal + (normal - leg.normal) * alpha
		leg.normal = if n.Magnitude > EPS then n.Unit else up
		-- Recorded against the pre-drop pose; the body moves next, and the
		-- solve reads the paw again afterwards, so the drop cancels itself.
		local want = bindH + leg.offset + math.max(clipH, 0) + stepLift
		leg.target = pAt + up * ((want - up:Dot(pFoot)) * self.blend)
		if leg.grounded then
			deepest = math.min(deepest, leg.offset)
		end
	end

	-- Lower the body so the deepest-reaching leg can touch down rather than
	-- stretch straight. Runs before the legs: it is their common ancestor.
	if self.bodyBone then
		self.bodyDrop += (math.clamp(deepest, -self.maxBodyDrop, 0) - self.bodyDrop) * alpha
		-- Stepping, the body also crouches a little, so a planted leg has the
		-- reach to stay put while the body turns away above it.
		local d = (self.bodyDrop - self.crouch * sw) * self.blend
		if math.abs(d) > EPS then
			writer:Add(self.bodyBone, CFrame.new(self.bodyBone.TransformedWorldCFrame:VectorToObjectSpace(up * d)))
		end
	end

	for _, leg in ipairs(self.legs) do
		self:_solve(leg, leg.target, up)

		if self.alignFeet and leg.grounded then
			local axis = up:Cross(leg.normal)
			if axis.Magnitude > EPS then
				local tilt = math.min(math.atan2(axis.Magnitude, up:Dot(leg.normal)), self.maxFootTilt) * self.blend
				if tilt > 1e-6 then
					writer:Add(
						leg.foot,
						CFrame.fromAxisAngle(leg.foot.TransformedWorldCFrame:VectorToObjectSpace(axis.Unit), tilt)
					)
				end
			end
		end
	end

	self.groundedCount = grounded
end

-- ===== introspection =========================================================

function LegIK:GetDebug(): Debug
	local legs = {}
	for _, leg in ipairs(self.legs) do
		legs[leg.name] = leg.offset
	end
	return {
		Legs = legs,
		Grounded = self.groundedCount,
		BodyDrop = self.bodyDrop,
		Gain = self.blend,
		Stepping = if self.stepping then self.stepper:Airborne() else nil,
	}
end

return LegIK
