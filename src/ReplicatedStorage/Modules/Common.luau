local module = {}

local infoM = require(script.Parent:WaitForChild("Info"))

function module.GetPlayerInfo(plr: Player)

	local CharacterName = plr:GetAttribute("CharacterName")
	if not infoM[CharacterName] then return {} end

	local Gender = plr:GetAttribute("Gender")
	if not infoM[CharacterName][Gender] then return end

	return infoM[CharacterName][Gender]
end

function module.Sprint(plr: Player, sprintType: string)
	local stuff = module.GetPlayerInfo(plr)
	if not stuff then return end

	if sprintType == "Walk" then
		plr.Character.Humanoid.WalkSpeed = stuff.WalkSpeed; return;
	end

	local reqSpeed = stuff[sprintType .. "Speed"]
	local trotSpeed = stuff["TrotSpeed"]
	local plrStamina = plr.PlayerStats.Stamina

	if sprintType == "Run" or sprintType == "Sprint" and plrStamina.Value <= 0.5 then
		plr.Character.Humanoid.WalkSpeed = trotSpeed + (reqSpeed - trotSpeed) * plrStamina.Value
	end

	plr:SetAttribute("State", sprintType)

	plr.Character.Humanoid.WalkSpeed = reqSpeed
end

return module
