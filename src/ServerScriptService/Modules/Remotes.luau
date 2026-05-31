local module = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- modules
local repModules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(repModules:WaitForChild("Common"))
local Stats   = require(repModules:WaitForChild("Stats"))
local CreatureStats = Stats.Creatures
local packets = require(repModules:WaitForChild("Packets"))

local initClientScripts = packets.initClientScripts
local spawnAssets = script.Parent.Parent:WaitForChild("SpawnAssets")

-- assets
local models = ServerStorage:WaitForChild("Models")
-- Body movers were ported from RaceThroughTime and live in
-- ReplicatedStorage.Movers (AlignPosition + AlignOrientation). They are
-- cloned onto each character's HumanoidRootPart with RigidityEnabled = true
-- so the client controller can drive position / rotation directly.
local moversFolder = ReplicatedStorage:WaitForChild("Movers")

function module.Attack(plr: Player)
    local stuff = commonM.GetPlayerInfo(plr)
    if not stuff or not plr.Character or not plr.Character:FindFirstChild("Humanoid") then return end

    local humanoid = plr.Character.Humanoid
    local finalDamage = Stats.GetAttackDamage(
        stuff.AttackDamage,
        humanoid,
        plr.PlayerStats.Stamina.Value,
        stuff.HealthAttackCost,
        stuff.StaminaAttackCost,
        stuff.HealthPenaltyThreshold,
        stuff.StaminaPenaltyThreshold
    )

    packets.attackReturn.sendTo(finalDamage, plr)
end

function module.UpdateStamina(plr: Player, dt: number)
    local plrStamina = plr.PlayerStats.Stamina
    local stuff = commonM.GetPlayerInfo(plr)
    if not stuff or not plr.Character or not plr.Character:FindFirstChild("Humanoid") then return end

    local humanoid = plr.Character.Humanoid

    local stateType: string = plr:GetAttribute("State")
    if not stateType then return end

    local reqSpeed       = stuff[stateType .. "Speed"]
    local staminaDrainKey = stateType .. "StaminaDrain"
    local healthScale = Stats.HealthBasedSpeedMultiplier(humanoid, stuff.MaxHealthSpeedPenalty, stuff.HealthPenaltyThreshold)

    -- Idle decelerates aggressively so the character stops quickly when input
    -- is released; running states use the per-creature deceleration value.
    local finalDeceleration = stuff.Deceleration
    if stateType == "Idle" then
        finalDeceleration *= stuff.SprintSpeed * 1.5
    end

    -- Apply stamina drain (Run / Sprint) or gain (Idle / Walk / Trot) and
    -- compute the post-penalty target speed.
    local finalSpeed = reqSpeed
    if stuff[staminaDrainKey] then
        plrStamina.Value = Stats.ApplyStaminaDrain(plrStamina.Value, stuff.MaxStamina, stuff[staminaDrainKey] * dt)
        finalSpeed = Stats.GetStaminaPenalizedSpeed(
            reqSpeed, stuff.TrotSpeed, stuff.RunSpeed, stuff.SprintSpeed,
            plrStamina.Value, stuff.StaminaPenaltyThreshold, stateType
        )
    else
        local gainAmount = (stuff[stateType .. "StaminaGain"] or 0) * dt
        plrStamina.Value = Stats.ApplyStaminaGain(plrStamina.Value, stuff.MaxStamina, gainAmount)
    end

    humanoid.WalkSpeed = Stats.Accelerate(
        humanoid.WalkSpeed,
        finalSpeed * healthScale,
        dt,
        stuff.Acceleration,
        finalDeceleration
    )
end

function module.Sprint(plr: Player, sprintType: string)
    -- State change func, main logic handled in UpdateStamina

    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hmr = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hmr then return end
    
    local stuff = commonM.GetPlayerInfo(plr)
    if not stuff then return end
    if stuff[sprintType .. "Speed"] == nil then return end

    plr:SetAttribute("State", sprintType)
    return true
end

function module.InitStats(plr: Player)
    local statsFolder = Instance.new("Folder", plr)
    statsFolder.Name = "PlayerStats"
    local staminaValue = Instance.new("NumberValue", statsFolder)
    staminaValue.Value = 1
    staminaValue.Name = "Stamina"
end

function module.InitChar(plr: Player, charName: string, gender: string)
    local charInfo = CreatureStats[charName]
    if not charInfo then return false, "No such character" end

    charInfo = charInfo[gender]
    if not charInfo then return false, "No such gender" end

    local hum = plr.Character:FindFirstChild("Humanoid")
    if not hum then return false, "No humanoid" end

    hum.WalkSpeed = charInfo.WalkSpeed
end

-- Clone the AlignOrientation body mover from ReplicatedStorage.Movers and
-- create a LinearVelocity for planar locomotion.
--
-- Locomotion split:
--   * LinearVelocity (VelocityConstraintMode = Plane) drives X / Z motion.
--     It physically cannot apply force on Y, so gravity + the Humanoid
--     (HipHeight, CanCollide parts) fully own the vertical axis. This is
--     the standard Roblox pattern for "plane only" body movers and is
--     immune to the position-feedback ratchet that AlignPosition with
--     MaxAxesForce.Y = 0 suffers from in practice.
--
--   * AlignOrientation (force based, RigidityEnabled = false) drives
--     facing. Rigid orientation would force-rotate the HRP through
--     ground geometry, causing the penetration solver to eject the
--     character upward, so we keep it force based.
function module.AddBodyMovers(plr: Player)
    local char = plr.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local ao = moversFolder:FindFirstChild("AlignOrientation")

    -- Single attachment shared by AlignOrientation (OneAttachment) and
    -- LinearVelocity.
    local a1 = Instance.new("Attachment")
    a1.Name = "PhysicsAttachment"
    a1.Parent = hrp

    -- LinearVelocity (plane-locked) for horizontal locomotion.
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

-- Setup animations folder under player with Animation instances
function module.SetupAnimations(plr: Player, charName: string, gender: string)
    local charInfo = CreatureStats[charName]
    if not charInfo then 
        warn("SetupAnimations: No character info found for " .. charName)
        return false 
    end

    charInfo = charInfo[gender]
    if not charInfo then 
        warn("SetupAnimations: No gender info found for " .. gender)
        return false 
    end

    local animations = charInfo.Animations
    if not animations then
        warn("SetupAnimations: No animations defined for " .. charName .. " " .. gender)
        return false
    end

    -- Remove existing animations folder if it exists
    local existingFolder = plr:FindFirstChild("Animations")
    if existingFolder then
        existingFolder:Destroy()
    end

    -- Create new animations folder under player
    local animationsFolder = Instance.new("Folder")
    animationsFolder.Name = "Animations"
    animationsFolder.Parent = plr

    -- Create Animation instances for each state animation
    for stateName, animationId in pairs(animations) do
        local animation = Instance.new("Animation")
        animation.Name = stateName
        animation.AnimationId = animationId
        animation.Parent = animationsFolder
    end
    
    return true
end

function module.Morph(plr: Player, charName: string, gender: string, SpawnBase: BasePart)
    local charInfo = CreatureStats[charName]
    if not charInfo then return false, "No such character" end

    local modelsUnderGender = models:FindFirstChild(gender)
    if not modelsUnderGender then return false, "No such gender" end

    local reqModel = modelsUnderGender:FindFirstChild(charName)
    if not reqModel then return false, "No such model" end

    local currChar = plr.Character
    local newChar: Model = reqModel:Clone()
    newChar.Parent = workspace
    newChar.Name = plr.Name

    plr.Character = newChar
    currChar:Destroy()

    -- init stats
    module.InitChar(plr, charName, gender)
    plr:SetAttribute("CharacterName", charName)
    plr:SetAttribute("Gender", gender)
    plr:SetAttribute("State", "Idle")
    
    module.AddBodyMovers(plr)
    
    -- Setup animations folder under player
    module.SetupAnimations(plr, charName, gender)

    -- setup scripts and spawn assets
    local sc = {}
    for _, v in pairs(spawnAssets:GetChildren()) do
        local cl = v:Clone()
        local pr = plr.Character
        
        if v:IsA("ScreenGui") then
            pr = plr.PlayerGui
        elseif v:IsA("Script") then
            table.insert(sc, cl)
        end
        
        cl.Parent = pr
    end
    
    initClientScripts.sendTo({}, plr)
    
    -- server scripts
    for _, v in pairs(sc) do
        v.Enabled = true
	end
	
	-- Spawn on top of the provided base part. Random X / Z inset stops
	-- multiple players landing on the exact same pivot. Y is the part's
	-- top surface plus the character's vertical half-extent so the rig
	-- doesn't intersect the base on appear.
	local cf = CFrame.new(0, 0, 0)
	if SpawnBase and SpawnBase.Parent then
		local bp = SpawnBase.Position
		local bs = SpawnBase.Size
		local inset = 4
		local jitterX = (math.random() * 2 - 1) * math.max(bs.X * 0.5 - inset, 0)
		local jitterZ = (math.random() * 2 - 1) * math.max(bs.Z * 0.5 - inset, 0)

		local _, charSize = newChar:GetBoundingBox()
		local spawnY = bp.Y + bs.Y * 0.5 + charSize.Y * 0.5 + 0.5

		cf = CFrame.new(bp.X + jitterX, spawnY, bp.Z + jitterZ)
	end
	newChar:PivotTo(cf)
    
    return true
end

return module