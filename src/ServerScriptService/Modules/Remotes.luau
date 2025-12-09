local module = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InitClientScripts: RemoteEvent = Remotes:WaitForChild("InitClientScripts")

-- modules
local repModules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(repModules:WaitForChild("Common"))
local infoM = require(repModules:WaitForChild("Info"))

local spawnAssets = script.Parent.Parent:WaitForChild("SpawnAssets")

-- assets
local models = ServerStorage:WaitForChild("Models")

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

	return stuff.AttackDamage * (1 - totalCost)
end

function module.UpdateStamina(plr: Player, dt: number)
	local plrStamina = plr.PlayerStats.Stamina
	local stuff = commonM.GetPlayerInfo(plr)
	if not stuff or not plr.Character or not plr.Character:FindFirstChild("Humanoid") then return end

	local humanoid = plr.Character.Humanoid
	local stateType: string = plr:GetAttribute("State")
	if not stateType then return end

	local reqSpeed = stuff[stateType .. "Speed"]
	local trotSpeed = stuff.TrotSpeed
	local staminaDrainKey = stateType .. "StaminaDrain"
	
	local pdiff = (stuff.SprintSpeed - stuff.RunSpeed) / stuff.RunSpeed
	local healthScale = healthBasedSpeedMultiplier(humanoid, stuff.MaxHealthSpeedPenalty, stuff.HealthPenaltyThreshold)

	--[[
		Possible states: Idle -> Walk / Trot -> Run / Sprint : (min / max)

		On drain states (Run, Sprint), reduce stamina (based on provided drain rates) and adjust speed
		if stamina is below threshold.
		In case the player is sprinting (and not running), apply an extra speed boost which is 
		equal to trotspeed * pdiff (percentage difference between Run and Sprint speeds).
		When stamina is 0, it will be equal to trotspeed.

		On gain states, increase stamina (based on provided gain rates) and set speed to requested speed.
		
		For acceleration and deceleration, we directly use provided values, except
		when it is for Idle, we try to decelerate to zero almost instantly (high deceleration).
	]]

	local finalDeceleration = stuff.Deceleration
	if stateType == "Idle" then
		--finalDeceleration = stuff.IdleDeceleration or stuff.SprintSpeed * 1.5
		finalDeceleration = humanoid.WalkSpeed * 1.5
	end

	if stuff[staminaDrainKey] then
		local drainAmount = stuff[staminaDrainKey] * dt

		local currentStaminaPoints = plrStamina.Value * stuff.MaxStamina
		local newStaminaPoints = math.max(currentStaminaPoints - drainAmount, 0)
		plrStamina.Value = newStaminaPoints / stuff.MaxStamina

		local finalSpeed = reqSpeed

		if plrStamina.Value < stuff.StaminaPenaltyThreshold then
			finalSpeed = trotSpeed + (reqSpeed - trotSpeed) * plrStamina.Value
			if stateType == "Sprint" then
				finalSpeed += trotSpeed * pdiff * (if plrStamina.Value > 0 then 1 else 0)
			end
		end

		accelerate(plr, humanoid, finalSpeed * healthScale, dt, stuff.Acceleration, finalDeceleration)
	else
		local staminaGainKey = stateType .. "StaminaGain"
		local gainAmount = (stuff[staminaGainKey] or 0) * dt

		local currentStaminaPoints = plrStamina.Value * stuff.MaxStamina
		local newStaminaPoints = math.min(currentStaminaPoints + gainAmount, stuff.MaxStamina)
		plrStamina.Value = newStaminaPoints / stuff.MaxStamina

		accelerate(plr, humanoid, reqSpeed * healthScale, dt, stuff.Acceleration, finalDeceleration)
	end
end

function module.Sprint(plr: Player, sprintType: string)
	-- State change func, main logic handled in UpdateStamina
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local stuff = commonM.GetPlayerInfo(plr)
	if not stuff then return end
	if stuff[sprintType .. "Speed"] == nil then return end

	plr:SetAttribute("State", sprintType)

	if sprintType == "Idle" then
		local lastdir = plr:GetAttribute("LastDirection") :: Vector3
		if lastdir and lastdir.Magnitude > 0 then
			-- Apply momentum deceleration over time
			local momentumDuration = 0.5 -- Duration in seconds
			local momentumStrength = 3 -- Scale factor for initial momentum strength
			local startTime = os.clock()
			
			task.spawn(function()
				while os.clock() - startTime < momentumDuration do
					local elapsed = os.clock() - startTime
					local progress = elapsed / momentumDuration
					local momentumFactor = (1 - progress) * momentumStrength
					
					if hum and hum.Parent and plr:GetAttribute("State") == "Idle" then
						--hum:Move(lastdir * momentumFactor)
					else
						break -- Exit if humanoid is destroyed or state changed
					end
					
					task.wait()
				end
			end)
		end
	end

	plr:SetAttribute("LastDirection", hum.MoveDirection)
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
	plr:SetAttribute("State", "Walk")
	
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
	
	InitClientScripts:FireClient(plr)
	
	-- server scripts
	for _, v in pairs(sc) do
		v.Enabled = true
	end
	
	return true
end

return module

