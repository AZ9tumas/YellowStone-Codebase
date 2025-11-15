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

local HEALTH_THRESHOLD_RATIO = 0.5

local function healthSpeedMultiplier(humanoid: Humanoid?, speedReduction: number?): number
	if not humanoid or not speedReduction or speedReduction <= 0 then
		return 1
	end

	local threshold = humanoid.MaxHealth * HEALTH_THRESHOLD_RATIO
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
	local healthScale = healthSpeedMultiplier(humanoid, stuff.SpeedReductionHealth)

	if stuff[staminaDrainKey] then
		local drainAmount = stuff[staminaDrainKey] * dt

		local currentStaminaPoints = plrStamina.Value * stuff.MaxStamina
		local newStaminaPoints = math.max(currentStaminaPoints - drainAmount, 0)
		plrStamina.Value = newStaminaPoints / stuff.MaxStamina

		local finalSpeed = reqSpeed

		if plrStamina.Value < 0.5 then
			finalSpeed = trotSpeed + (reqSpeed - trotSpeed) * plrStamina.Value
			if stateType == "Sprint" then
				finalSpeed += trotSpeed * pdiff * (if plrStamina.Value > 0 then 1 else 0)
			end
		end

		humanoid.WalkSpeed = finalSpeed * healthScale
	else
		local staminaGainKey = stateType .. "StaminaGain"
		local gainAmount = (stuff[staminaGainKey] or 0) * dt

		local currentStaminaPoints = plrStamina.Value * stuff.MaxStamina
		local newStaminaPoints = math.min(currentStaminaPoints + gainAmount, stuff.MaxStamina)
		plrStamina.Value = newStaminaPoints / stuff.MaxStamina

		humanoid.WalkSpeed = reqSpeed * healthScale
	end
end

function module.Sprint(plr: Player, sprintType: string)
	local stuff = commonM.GetPlayerInfo(plr)
	if not stuff then return end

	local reqSpeed = stuff[sprintType .. "Speed"]
	local trotSpeed = stuff.TrotSpeed
	local plrStamina = plr.PlayerStats.Stamina
	local humanoid = plr.Character and plr.Character:FindFirstChild("Humanoid")
	local healthScale = healthSpeedMultiplier(humanoid, stuff.SpeedReductionHealth)

	if (sprintType == "Run" or sprintType == "Sprint") and plrStamina.Value <= 0.5 then
		plr.Character.Humanoid.WalkSpeed = (trotSpeed + (reqSpeed - trotSpeed) * plrStamina.Value) * healthScale
	end

	plr:SetAttribute("State", sprintType)
	plr.Character.Humanoid.WalkSpeed = reqSpeed * healthScale
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

