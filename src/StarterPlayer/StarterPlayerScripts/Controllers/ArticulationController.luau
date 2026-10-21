--[[
	ArticulationController (Knit controller, client)

	Runs the procedural body layers — BodyArticulation, LegIK, HeadLook — for
	every OTHER player's creature this client can see. Bone.Transform does not
	replicate, so everything the local MovementController produces for our own
	creature is invisible to everyone else unless each client re-derives it
	locally, which it can, from state that does replicate: the root part's
	orientation and velocity, the terrain, and where the other creatures are.

	The local player's creature is owned by MovementController (it has richer
	signals — the demanded heading and turn sign for head anticipation); this
	controller never touches it.

	Attach is synchronous and silent about "not yet": it constructs the layers
	only once the root, the Humanoid, the species attributes and every
	configured bone are present, and otherwise simply returns. A once-a-second
	sweep over the players is the ONLY retry — it also brings back a creature
	that streamed out and in (StreamingEnabled is on; SpawnService streams the
	rig atomically so root and bones arrive together). Which creature a
	character is comes from the attributes SpawnService stamps on the
	character MODEL before parenting it, so they are present the moment the
	model is. A genuine config bug fails loud, once, and is not retried.

	Signals for a remote creature:
	  Facing / Up : the root's LookVector / UpVector
	  Speed       : horizontal AssemblyLinearVelocity capped at the replicated
	                WalkSpeed (BodyArticulation smooths it, same as local)
	  TargetDir   : Facing extrapolated by the root's yaw rate over LEAD_TIME,
	                clamped to MAX_LEAD — anticipation from angular momentum,
	                since the remote player's input is invisible
	  Pivoting    : the root spinning on the spot at a walking turn's rate with
	                no turn clip playing — a stepped standstill turn, which
	                replicates only as the root turning. The paws then step
	                exactly as on the owner's screen.
	  Otherwise LegIK and HeadLook need no remote-specific signal: the legs
	  probe the terrain themselves, and HeadLook picks its target from
	  positions every client already shares, so a creature looks at the same
	  thing on every screen.

	Creatures beyond MAX_DISTANCE from the camera are suppressed: their gain
	eases to 0, their bones are released, and only their springs keep ticking.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Common = require(ReplicatedStorage.Modules.Common)
local BodyArticulation = require(ReplicatedStorage.Modules.Movement.BodyArticulation)
local BoneWriter = require(ReplicatedStorage.Modules.Movement.BoneWriter)
local LegIK = require(ReplicatedStorage.Modules.Movement.LegIK)
local HeadLook = require(ReplicatedStorage.Modules.Movement.HeadLook)
local TurnInPlace = require(ReplicatedStorage.Modules.Movement.TurnInPlace)

local MAX_DISTANCE = 200 -- studs from the camera
-- A root turning on the spot between these rates (rad/s) is a stepped turn:
-- the snap of a small swivel is far faster, a drift far slower.
local PIVOT_MAX_SPEED = 1.5 -- studs/s: any faster and it is walking, not pivoting
local PIVOT_MIN_RATE = 0.4
local PIVOT_MAX_RATE = 6
-- The remote head lead is yaw rate x LEAD_TIME, minus the neck spring's own
-- steady-state lag while tracking a ramp (2*zeta/w = 0.053 s for the wolf's
-- 6 Hz critically damped neck). 0.13 s therefore shows ~27 deg at 6 rad/s —
-- near the neck's cap without pinning it. MAX_LEAD keeps a spinning root from
-- extrapolating past the body's rear and flipping the lead to the outside.
local LEAD_TIME = 0.13
local MAX_LEAD = math.pi * 0.5
local RECONCILE_INTERVAL = 1 -- s between sweeps for characters with no entry

local ArticulationController = Knit.CreateController({ Name = "ArticulationController" })

type Entry = {
	writer: BoneWriter.BoneWriter,
	articulation: BodyArticulation.BodyArticulation?,
	legIK: LegIK.LegIK?,
	headLook: HeadLook.HeadLook?,
	hrp: BasePart,
	humanoid: Humanoid,
	turnClips: { [string]: true }, -- animation ids of the creature's turn clips
}

-- Is this creature turning on the spot with no turn clip — a stepped turn?
-- Only the root's motion replicates, so that is all it is read from; a clip
-- turn animates its own paws and is left alone.
local function isPivoting(entry: Entry, up: Vector3): boolean
	local hrp = entry.hrp
	local vel = hrp.AssemblyLinearVelocity
	if (vel - up * up:Dot(vel)).Magnitude > PIVOT_MAX_SPEED then
		return false
	end
	local rate = math.abs(hrp.AssemblyAngularVelocity:Dot(up))
	if rate < PIVOT_MIN_RATE or rate > PIVOT_MAX_RATE then
		return false
	end
	if next(entry.turnClips) then
		local animator = entry.humanoid:FindFirstChildOfClass("Animator")
		for _, track in if animator then animator:GetPlayingAnimationTracks() else {} do
			local anim = track.Animation
			if anim and entry.turnClips[anim.AnimationId] and track.WeightCurrent > 0.3 then
				return false
			end
		end
	end
	return true
end

function ArticulationController:KnitInit()
	self.entries = {} :: { [Model]: Entry }
	-- Characters the sweep must not revisit: species with no config, or a
	-- config bug already reported.
	self.settled = {} :: { [Model]: boolean }
	self.reconcileClock = 0
end

function ArticulationController:_detach(char: Model)
	local entry = self.entries[char]
	if entry then
		entry.writer:Release()
		self.entries[char] = nil
	end
	self.settled[char] = nil
end

-- Construct the layers if the character is ready; do nothing if it is not yet.
function ArticulationController:_attach(char: Model)
	if self.entries[char] or self.settled[char] or not char.Parent then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local characterName = char:GetAttribute("CharacterName")
	if not hrp or not humanoid or not characterName then
		return -- still replicating, or the default rig before the first morph
	end
	local ok, err = pcall(function()
		local info = Common.GetInfo(characterName, char:GetAttribute("Gender"))
		-- Every bone every configured layer needs, waited for as one set: a
		-- half-built creature would articulate but not plant its feet.
		local required = {}
		local function need(names: { string })
			table.move(names, 1, #names, #required + 1, required)
		end
		if info.BodyArticulation then
			need(BodyArticulation.RequiredBones(info.BodyArticulation))
		end
		if info.LegIK then
			need(LegIK.RequiredBones(info.LegIK))
		end
		if info.HeadLook then
			need(HeadLook.RequiredBones(info.HeadLook))
		end
		if #required == 0 then
			self.settled[char] = true -- this species has no procedural layers
			return
		end
		if #BoneWriter.Missing(char, required) > 0 then
			return -- bones still arriving; the sweep tries again
		end
		-- Replicated tracks are matched by asset id: the id is what the
		-- owner's Animator sends.
		local turnClips = {}
		if info.TurnInPlace then
			for name in TurnInPlace.ClipNames(info.TurnInPlace) do
				local id = info.Animations and info.Animations[name]
				if id then
					turnClips[id] = true
				end
			end
		end
		local writer = BoneWriter.new()
		self.entries[char] = {
			writer = writer,
			articulation = BodyArticulation.fromInfo(char, info, writer),
			legIK = LegIK.fromInfo(char, info, writer),
			headLook = HeadLook.fromInfo(char, info, writer),
			hrp = hrp :: BasePart,
			humanoid = humanoid :: Humanoid,
			turnClips = turnClips,
		}
	end)
	if not ok then
		warn(`ArticulationController: {char.Name}: {err}`)
		self.settled[char] = true
	end
end

function ArticulationController:_track(player: Player)
	if player == Players.LocalPlayer then
		return
	end
	player.CharacterAdded:Connect(function(char)
		self:_attach(char)
	end)
	player.CharacterRemoving:Connect(function(char)
		self:_detach(char)
	end)
	if player.Character then
		self:_attach(player.Character)
	end
end

-- The only retry path: characters that were not ready when CharacterAdded
-- fired, or that streamed out and back in without one.
function ArticulationController:_reconcile()
	-- Forget characters that are gone, so the table cannot hold dead models.
	for char in pairs(self.settled) do
		if not char.Parent then
			self.settled[char] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if player ~= Players.LocalPlayer and char then
			self:_attach(char)
		end
	end
end

function ArticulationController:KnitStart()
	for _, p in Players:GetPlayers() do
		self:_track(p)
	end
	Players.PlayerAdded:Connect(function(p)
		self:_track(p)
	end)

	-- PreSimulation passes the physics step's delta time as its only argument.
	RunService.PreSimulation:Connect(function(dt: number)
		self.reconcileClock += dt
		if self.reconcileClock >= RECONCILE_INTERVAL then
			self.reconcileClock = 0
			self:_reconcile()
		end

		local camera = workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position
		for char, entry in pairs(self.entries) do
			local hrp = entry.hrp
			-- An atomically streamed-out model is removed whole, so its root
			-- keeps the (detached) model as Parent: test the model, not the part.
			if not char.Parent or not hrp.Parent then
				self:_detach(char) -- streamed out or destroyed; the sweep re-attaches if it returns
				continue
			end
			local rootCF = hrp.CFrame
			local look = rootCF.LookVector
			local up = rootCF.UpVector
			local suppressed = camPos ~= nil and (hrp.Position - camPos).Magnitude > MAX_DISTANCE

			-- Same order as the local driver: the legs and head correct the
			-- pose the spine produced.
			entry.writer:BeginFrame()
			if entry.articulation then
				local vel = hrp.AssemblyLinearVelocity
				local lead = math.clamp(hrp.AssemblyAngularVelocity.Y * LEAD_TIME, -MAX_LEAD, MAX_LEAD)
				entry.articulation:Update({
					Facing = look,
					Up = up,
					TargetDir = CFrame.Angles(0, lead, 0) * look,
					Speed = math.min(Vector3.new(vel.X, 0, vel.Z).Magnitude, entry.humanoid.WalkSpeed),
					Suppressed = suppressed,
				}, dt)
			end
			if entry.legIK then
				entry.legIK:Update({
					Up = up,
					Suppressed = suppressed,
					Pivoting = not suppressed and isPivoting(entry, up),
				}, dt)
			end
			if entry.headLook then
				entry.headLook:Update({ Facing = look, Up = up, Suppressed = suppressed }, dt)
			end
			entry.writer:EndFrame()
		end
	end)
end

return ArticulationController
