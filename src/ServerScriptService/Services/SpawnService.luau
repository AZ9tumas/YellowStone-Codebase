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
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local CreatureStats = Stats.Creatures

local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		-- Fired to a player once their creature is fully set up.
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

	-- Tell the client it can build its movement systems now (replaces initClientScripts).
	self.Client.Spawned:Fire(player)

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
