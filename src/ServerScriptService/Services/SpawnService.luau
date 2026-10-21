--[[
	SpawnService

	Owns character creation. Replaces the ByteNet `spawn` packet (request) and
	`initClientScripts` packet (the "you're ready, start your client systems"
	broadcast).

	Flow:
	  client  -> SpawnService.Client:Spawn(charName, gender)
	  server  -> morph + body movers + animations + spawn assets + pivot to base
	  server  -> Client.Spawned:Fire(player)   (client controllers build off this)

	Validation vs assertion:
	  charName/gender come from the client and are UNTRUSTED, so they are
	  validated with explicit early returns (reject bad input) rather than
	  asserted. Internal invariants still fail loud elsewhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local CreatureStats = Stats.Creatures

local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		-- Fired to a player once their creature is fully set up, with the new
		-- character model (nil on the client if it has not replicated yet).
		Spawned = Knit.CreateSignal(),
	},
})

-- ===== Setup helpers (ported from the old Modules/Remotes) =====================

-- Set the humanoid's starting WalkSpeed from config.
local function initChar(player: Player, charInfo)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.WalkSpeed = charInfo.WalkSpeed
end

-- Clone the AlignOrientation body mover from ReplicatedStorage.Movers and build
-- a plane-locked LinearVelocity for horizontal locomotion.
--
-- Locomotion split (unchanged, deliberate):
--   * LinearVelocity (VelocityConstraintMode = Plane) drives X/Z only. It
--     physically cannot apply force on Y, so gravity + the Humanoid own the
--     vertical axis — immune to the position-feedback vertical ratchet.
--   * AlignOrientation (force based, RigidityEnabled = false) drives facing.
--     Rigid orientation would force-rotate the HRP through geometry and eject
--     the character upward, so it stays force based.
--   * SwimLift, a Y-only LinearVelocity, is disabled on land. In deep water
--     the client enables it to float the body at the surface (see
--     Movement/Swimming) — there is no ground there for the ratchet to push on.
local function addBodyMovers(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local moversFolder = ReplicatedStorage:WaitForChild("Movers")
	local ao = moversFolder:FindFirstChild("AlignOrientation")

	-- Single attachment shared by AlignOrientation (OneAttachment) and LinearVelocity.
	local a1 = Instance.new("Attachment")
	a1.Name = "PhysicsAttachment"
	a1.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "LinearVelocity"
	lv.Attachment0 = a1
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.zero
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	lv.Enabled = true
	lv.ForceLimitsEnabled = false
	lv.Parent = hrp

	local lift = Instance.new("LinearVelocity")
	lift.Name = "SwimLift"
	lift.Attachment0 = a1
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lift.LineDirection = Vector3.yAxis
	lift.LineVelocity = 0
	lift.ForceLimitsEnabled = false
	lift.Enabled = false
	lift.Parent = hrp

	if ao then
		local newAo = ao:Clone()
		newAo.Mode = Enum.OrientationAlignmentMode.OneAttachment
		newAo.Attachment0 = a1
		newAo.CFrame = CFrame.lookAt(Vector3.zero, hrp.CFrame.LookVector)
		newAo.RigidityEnabled = false
		newAo.Enabled = true
		newAo.Parent = hrp
	end
end

-- Build the per-player Animations folder the client AnimationController reads.
local function setupAnimations(player: Player, charInfo): boolean
	local animations = charInfo.Animations
	if not animations then
		warn("SpawnService: no animations defined for this creature/gender")
		return false
	end

	local existing = player:FindFirstChild("Animations")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Animations"
	folder.Parent = player

	for stateName, animationId in pairs(animations) do
		local animation = Instance.new("Animation")
		animation.Name = stateName
		animation.AnimationId = animationId
		animation.Parent = folder
	end

	return true
end

-- Clone the footstep sound emitters onto the character's HRP. Relocated here
-- from the old remotes.server ReplicateSounds listener so it happens as part of
-- spawn (the server already has the character in hand).
local function attachFootstepSounds(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("SpawnService: no HumanoidRootPart to attach footstep sounds to")
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("FootstepSFX")
	if not folder then
		return
	end
	for _, v in folder:GetChildren() do
		v:Clone().Parent = hrp
	end
end

-- Pivot the new character onto the spawn base, with a little random inset so
-- players don't stack on the exact same point.
local function placeOnBase(char: Model, spawnBase: BasePart?)
	local cf = CFrame.new(0, 0, 0)
	if spawnBase and spawnBase.Parent then
		local bp = spawnBase.Position
		local bs = spawnBase.Size
		local inset = 4
		local jitterX = (math.random() * 2 - 1) * math.max(bs.X * 0.5 - inset, 0)
		local jitterZ = (math.random() * 2 - 1) * math.max(bs.Z * 0.5 - inset, 0)

		local _, charSize = char:GetBoundingBox()
		local spawnY = bp.Y + bs.Y * 0.5 + charSize.Y * 0.5 + 0.5

		cf = CFrame.new(bp.X + jitterX, spawnY, bp.Z + jitterZ)
	end
	char:PivotTo(cf)
end

-- Make the rig a physically real creature.
--
-- The models ship from Blender with EVERY part CanCollide = false and the mass
-- sitting on the cosmetic meshes while the HumanoidRootPart is Massless. That
-- leaves the creature with no collision geometry at all: the only thing holding
-- it up is the Humanoid's own floor probe. Measured consequences — it walks
-- straight through a solid wall at 60 studs/s, and anywhere the probe comes up
-- empty there is nothing to land on, which is the "clipping through the floor"
-- report.
--
-- The contract, enforced here rather than in the models so it holds for every
-- creature and gender and cannot be lost when a rig is re-exported:
--   * HumanoidRootPart is the physics body — it collides and carries the mass.
--   * Everything else is decoration — no collision, no mass.
--
-- Only the root collides on purpose. The visible wolf is ~7 studs long; giving
-- the meshes collision would snag it on every slope and doorway, which is also
-- why this does not resize the root. Size and HipHeight are left exactly as
-- authored: the Humanoid holds the root's BOTTOM at HipHeight above the floor,
-- so changing either would move the whole body and re-tune LegIK by accident.
local function applyPhysicsContract(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		warn("SpawnService: no HumanoidRootPart — the creature will have no collision")
		return
	end
	hrp.CanCollide = true
	hrp.Massless = false
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d ~= hrp then
			d.CanCollide = false
			d.Massless = true
		end
	end
end

-- Put a creature back when it ends up below the world.
--
-- Collision cannot solve this one. Roblox does not eject a body that is
-- already INSIDE terrain — verified with a plain collidable part, which sinks
-- exactly the same way a creature does — and the Humanoid's floor probe is a
-- sensor, not a support, so it finds nothing either. That state is reachable
-- in normal play: a fast descent can end up under the surface, and with
-- StreamingEnabled a creature can outrun the terrain streaming in beneath it.
-- Left alone the character accelerates to FallenPartsDestroyHeight and is
-- destroyed, which is the "fell through the floor and never came back" report.
--
-- So remember where it was last genuinely standing and put it back there. The
-- trigger sits just above the destroy height — far below any reachable ground
-- — so a legitimate fall down a cliff is never interrupted.
local GUARD_INTERVAL = 0.25 -- s between ground samples
-- Just past where a standing root sits (HipHeight + half the root). Any deeper
-- and a creature falling PAST a ledge would record it as somewhere it stood.
local GUARD_PROBE = 6 -- studs
-- A body in flight can still pass within probe range of geometry, so the
-- sample also requires it to be near-stationary vertically. Without this the
-- guard learns a "safe" spot mid-fall and rescues the creature straight back
-- into the ground it was falling through.
local GUARD_MAX_FALL = 5 -- studs/s
local RESCUE_MARGIN = 50 -- studs above FallenPartsDestroyHeight

local function startFallGuard(player: Player, char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local safe = hrp.CFrame
	local clock = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not (char.Parent and hrp.Parent) then
			conn:Disconnect()
			return
		end
		if hrp.Position.Y < Workspace.FallenPartsDestroyHeight + RESCUE_MARGIN then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.CFrame = safe
			warn(`SpawnService: {player.Name} fell out of the world; returned to the last solid ground`)
			return
		end
		-- Sample rather than test the Humanoid state: FloorMaterial belongs to
		-- a character the client owns, and a raycast is true wherever the
		-- authority sits.
		clock += dt
		if clock < GUARD_INTERVAL then
			return
		end
		clock = 0
		if
			math.abs(hrp.AssemblyLinearVelocity.Y) < GUARD_MAX_FALL
			and Workspace:Raycast(hrp.Position, Vector3.new(0, -GUARD_PROBE, 0), params)
		then
			safe = hrp.CFrame
		end
	end)
end

-- ===== Core morph ============================================================

-- Returns ok:boolean, error:string?. Untrusted input -> validate, don't assert.
function SpawnService:Morph(player: Player, charName: string, gender: string): (boolean, string?)
	local charInfo = CreatureStats[charName]
	if not charInfo then
		return false, "No such character"
	end

	local genderInfo = charInfo[gender]
	if not genderInfo then
		return false, "No such gender"
	end

	local models = ServerStorage:WaitForChild("Models")
	local modelsUnderGender = models:FindFirstChild(gender)
	if not modelsUnderGender then
		return false, "No model folder for gender"
	end

	local reqModel = modelsUnderGender:FindFirstChild(charName)
	if not reqModel then
		return false, "No such model"
	end

	local currChar = player.Character
	local newChar: Model = reqModel:Clone()
	-- Stamp the species on the model BEFORE it is parented: attributes
	-- replicate with the instance, so every client sees the correct creature
	-- the moment CharacterAdded fires. The Player attributes below are set
	-- afterwards and can lag that event on other clients.
	newChar:SetAttribute("CharacterName", charName)
	newChar:SetAttribute("Gender", gender)
	-- The rig streams as one unit: the root part and the skinned mesh that
	-- carries every bone arrive and leave together, so the client-side
	-- articulation never sees half a creature.
	newChar.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- Before parenting: the rig must never exist in the world for even a frame
	-- without its collision set up.
	applyPhysicsContract(newChar)
	newChar.Parent = Workspace
	newChar.Name = player.Name

	player.Character = newChar
	if currChar then
		currChar:Destroy()
	end

	-- Attributes + base stats
	initChar(player, genderInfo)
	player:SetAttribute("CharacterName", charName)
	player:SetAttribute("Gender", gender)
	player:SetAttribute("State", "Idle")

	addBodyMovers(player)
	setupAnimations(player, genderInfo)
	attachFootstepSounds(newChar)

	-- Spawn assets (per-spawn GUIs + server scripts cloned from ServerScriptService.SpawnAssets)
	local spawnAssets = ServerScriptService:WaitForChild("SpawnAssets")
	local serverScripts = {}
	for _, v in spawnAssets:GetChildren() do
		local cl = v:Clone()
		if v:IsA("ScreenGui") then
			cl.Parent = player.PlayerGui
		elseif v:IsA("Script") then
			table.insert(serverScripts, cl)
			cl.Parent = player.Character
		else
			cl.Parent = player.Character
		end
	end

	local spawnBase = Workspace:FindFirstChild("Base")
	placeOnBase(newChar, spawnBase :: BasePart?)

	-- Tell the client it can build its movement systems now (replaces
	-- initClientScripts). The new character rides along: the model streams
	-- atomically and can arrive AFTER this remote, in which case the client
	-- receives nil and waits for CharacterAdded instead of binding to the
	-- previous character that player.Character may still resolve to.
	startFallGuard(player, newChar)

	self.Client.Spawned:Fire(player, newChar)

	-- Enable any cloned server scripts after the client has been notified.
	for _, v in serverScripts do
		v.Enabled = true
	end

	return true
end

-- ===== Client API ============================================================

function SpawnService.Client:Spawn(player: Player, charName: string, gender: string): (boolean, string?)
	-- Basic type-guard on untrusted input.
	if type(charName) ~= "string" or type(gender) ~= "string" then
		return false, "Invalid spawn arguments"
	end
	return self.Server:Morph(player, charName, gender)
end

return SpawnService
