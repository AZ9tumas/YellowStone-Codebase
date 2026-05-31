--[[
	Common

	Player-info lookup and the small client-facing Sprint helper. The big
	stats / math helpers were moved into `Stats` — this module now just
	indexes into `Stats.Creatures` for the per-player config table.
]]

local module = {}

local Stats = require(script.Parent:WaitForChild("Stats"))
local CreatureStats = Stats.Creatures

function module.GetPlayerInfo(plr: Player)
	local CharacterName = plr:GetAttribute("CharacterName")
	if not CreatureStats[CharacterName] then return {} end

	local Gender = plr:GetAttribute("Gender")
	if not CreatureStats[CharacterName][Gender] then return end

	return CreatureStats[CharacterName][Gender]
end

-- Client-facing sprint helper (kept for backwards compatibility).
-- The authoritative state -> speed logic lives server-side in
-- `ServerScriptService.Modules.Remotes.UpdateStamina`.
function module.Sprint(plr: Player, sprintType: string)
	local stuff = module.GetPlayerInfo(plr)
	if not stuff then return end

	if sprintType == "Walk" then
		plr.Character.Humanoid.WalkSpeed = stuff.WalkSpeed
		return
	end

	local reqSpeed = stuff[sprintType .. "Speed"]
	if not reqSpeed then return end

	local trotSpeed = stuff.TrotSpeed
	local plrStamina = plr.PlayerStats.Stamina

	if (sprintType == "Run" or sprintType == "Sprint") and plrStamina.Value <= 0.5 then
		plr.Character.Humanoid.WalkSpeed = trotSpeed + (reqSpeed - trotSpeed) * plrStamina.Value
	else
		plr.Character.Humanoid.WalkSpeed = reqSpeed
	end

	plr:SetAttribute("State", sprintType)
end

return module
