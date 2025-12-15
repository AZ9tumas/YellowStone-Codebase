local module = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- modules
local repModules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(repModules:WaitForChild("Common"))
local infoM = require(repModules:WaitForChild("Info"))
local packets = require(repModules:WaitForChild("Packets"))

local initClientScripts = packets.initClientScripts
local spawnAssets = script.Parent.Parent:WaitForChild("SpawnAssets")

-- assets
local models = ServerStorage:WaitForChild("Models")
local physicsControllers = ServerStorage:WaitForChild("Assets"):WaitForChild("PhysicsControllers")

local function healthBasedSpeedMultiplier(humanoid: Humanoid?, speedReduction: number?, thresholdRatio: number?): number
    if not humanoid or not speedReduction or speedReduction <= 0 then
        return 1
    end

    local threshold = humanoid.MaxHealth * (thresholdRatio or 0.5)
    if threshold <= 0 then
        return 1
    end

    local health = humanoid.Health
    if health >= threshold then
        return 1
    end

    local ratio = math.clamp(health / threshold, 0, 1)
    return 1 - speedReduction * (1 - ratio)
end

local function accelerate(plr: Player, humanoid: Humanoid, targetSpeed: number, dt: number, acceleration: number, deceleration: number)
    local currentSpeed = humanoid.WalkSpeed
    local diff = targetSpeed - currentSpeed
    
    if math.abs(diff) < 0.1 then
        humanoid.WalkSpeed = targetSpeed
        return
    end

    local change = 0
    if diff > 0 then
        change = acceleration * dt
        if change > diff then change = diff end
    else
        change = -deceleration * dt
        if change < diff then change = diff end
    end

    humanoid.WalkSpeed = currentSpeed + change
end

function module.Attack(plr: Player)
    
    local stuff = commonM.GetPlayerInfo(plr)
    if not stuff or not plr.Character or not plr.Character:FindFirstChild("Humanoid") then return end

    local humanoid = plr.Character.Humanoid
    local totalCost = 0

    if (humanoid.Health <= stuff.HealthPenaltyThreshold * humanoid.MaxHealth) then
        totalCost += stuff.HealthAttackCost * (1 - humanoid.Health / (stuff.HealthPenaltyThreshold * humanoid.MaxHealth))
    end

    if (plr.PlayerStats.Stamina.Value <= stuff.StaminaPenaltyThreshold) then
        totalCost += stuff.StaminaAttackCost * (1 - plr.PlayerStats.Stamina.Value / stuff.StaminaPenaltyThreshold)
    end

    print("Attack total cost:", totalCost, stuff.AttackDamage * (1 - totalCost))

    local finalDamage = stuff.AttackDamage * (1 - totalCost)
    packets.attackReturn.sendTo(finalDamage, plr)
end

function module.UpdateStamina(plr: Player, dt: number)
    local plrStamina = plr.PlayerStats.Stamina
    local stuff = commonM.GetPlayerInfo(plr)
    if not stuff or not plr.Character or not plr.Character:FindFirstChild("Humanoid") then return end

    local character = plr.Character
    local humanoid = character.Humanoid
    local hrp = character:FindFirstChild("HumanoidRootPart")
    
    local stateType: string = plr:GetAttribute("State")
    if not stateType then return end

    local reqSpeed = stuff[stateType .. "Speed"]
    local trotSpeed = stuff.TrotSpeed
    local staminaDrainKey = stateType .. "StaminaDrain"
    
    local pdiff = (stuff.SprintSpeed - stuff.RunSpeed) / stuff.RunSpeed
    local healthScale = healthBasedSpeedMultiplier(humanoid, stuff.MaxHealthSpeedPenalty, stuff.HealthPenaltyThreshold)

    -- Base deceleration
    local finalDeceleration = stuff.Deceleration
    if stateType == "Idle" then
        finalDeceleration = humanoid.WalkSpeed * 1.5
    end
    
    -- Calculate target speed based on Stamina/State
    local finalSpeed = reqSpeed

    if stuff[staminaDrainKey] then
        local drainAmount = stuff[staminaDrainKey] * dt

        local currentStaminaPoints = plrStamina.Value * stuff.MaxStamina
        local newStaminaPoints = math.max(currentStaminaPoints - drainAmount, 0)
        plrStamina.Value = newStaminaPoints / stuff.MaxStamina

        if plrStamina.Value < stuff.StaminaPenaltyThreshold then
            finalSpeed = trotSpeed + (reqSpeed - trotSpeed) * plrStamina.Value
            if stateType == "Sprint" then
                finalSpeed += trotSpeed * pdiff * (if plrStamina.Value > 0 then 1 else 0)
            end
        end
    else
        local staminaGainKey = stateType .. "StaminaGain"
        local gainAmount = (stuff[staminaGainKey] or 0) * dt

        local currentStaminaPoints = plrStamina.Value * stuff.MaxStamina
        local newStaminaPoints = math.min(currentStaminaPoints + gainAmount, stuff.MaxStamina)
        plrStamina.Value = newStaminaPoints / stuff.MaxStamina
    end

    if hrp and stuff.BaseTurnRate and stuff.TurnSpeedDecay and false then
        local currentTurnRate = math.abs(hrp.AssemblyAngularVelocity.Y)
        
        if currentTurnRate > 0.1 then
            local maxAllowedSpeed = ((stuff.BaseTurnRate / currentTurnRate) - 1) / stuff.TurnSpeedDecay
            maxAllowedSpeed = math.max(0, maxAllowedSpeed)
            finalSpeed = math.min(finalSpeed, maxAllowedSpeed)
        end
    end

    accelerate(plr, humanoid, finalSpeed * healthScale, dt, stuff.Acceleration, finalDeceleration)
end

function module.Sprint(plr: Player, sprintType: string)
    -- State change func, main logic handled in UpdateStamina

    print(plr, sprintType)
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
    local charInfo = infoM[charName]
    if not charInfo then return false, "No such character" end

    charInfo = charInfo[gender]
    if not charInfo then return false, "No such gender" end

    local hum = plr.Character:FindFirstChild("Humanoid")
    if not hum then return false, "No humanoid" end

    hum.WalkSpeed = charInfo.WalkSpeed

    print("Set default walkspeed to", charInfo.WalkSpeed)
end

function module.AddBodyMovers(plr: Player)
    local char = plr.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local lv = physicsControllers:FindFirstChild("LinearVelocity")
    local ao = physicsControllers:FindFirstChild("AlignOrientation")
    local av = physicsControllers:FindFirstChild("AngularVelocity")

    local a1 = Instance.new("Attachment", hrp)
    a1.Name = "PhysicsAttachment"
    
    if lv then
        local newLv = lv:Clone()
        newLv.VectorVelocity = Vector3.zero
        newLv.Parent = hrp
        newLv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
        newLv.PlaneVelocity = Vector2.new(0, 0)
        newLv.Attachment0 = a1
        newLv.Enabled = false
    end
    
    if ao then
        local newAo = ao:Clone()
        newAo.CFrame = CFrame.lookAt(Vector3.zero, hrp.CFrame.LookVector)
        newAo.Parent = hrp
        newAo.Attachment0 = a1
        newAo.Enabled = true
    end

    if av then
        local newAv = av:Clone()
        newAv.AngularVelocity = Vector3.new(0, 0, 0)
        newAv.Parent = hrp
        newAv.Attachment0 = a1
        newAv.Enabled = false
    end
end

-- Setup animations folder under player with Animation instances
function module.SetupAnimations(plr: Player, charName: string, gender: string)
    local charInfo = infoM[charName]
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

    print("SetupAnimations: Created animations folder for " .. plr.Name .. " with " .. #animationsFolder:GetChildren() .. " animations")
    return true
end

function module.Morph(plr: Player, charName: string, gender: string)
    local modelsUnderGender = models:FindFirstChild(gender)
    if not modelsUnderGender then return false, "No such gender" end

    local reqModel = modelsUnderGender:FindFirstChild(charName)
    if not reqModel then return false, "No such model" end

    print(reqModel)

    local currChar = plr.Character
    local newChar = reqModel:Clone()
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
    
    return true
end

return module