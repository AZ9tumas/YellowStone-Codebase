--[[
	CombatService

	Replaces the ByteNet `attack` (request) + `attackReturn` (response) pair with
	a single client-callable method that returns the computed damage — one round
	trip instead of two one-way packets.

	Behaviour is preserved from the prototype: this computes the post-penalty
	attack damage (reduced by low health / low stamina) and returns it. Applying
	damage to a target is part of the future Fight mechanic and is intentionally
	not done here yet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local Common = require(ReplicatedStorage.Modules.Common)

local CombatService = Knit.CreateService({
	Name = "CombatService",
	Client = {},
})

-- Returns the final damage value for the attacker. Returns 0 when the player is
-- in no position to attack (not spawned / no humanoid) — a control result, not
-- a masked data lookup.
function CombatService.Client:Attack(player: Player): number
	if not Common.IsSpawned(player) then
		return 0
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local statsFolder = player:FindFirstChild("PlayerStats")
	local stamina = statsFolder and statsFolder:FindFirstChild("Stamina")
	if not humanoid or not stamina then
		return 0
	end

	local info = Common.GetPlayerInfo(player)

	return Stats.GetAttackDamage(
		info.AttackDamage,
		humanoid,
		stamina.Value,
		info.HealthAttackCost,
		info.StaminaAttackCost,
		info.HealthPenaltyThreshold,
		info.StaminaPenaltyThreshold
	)
end

return CombatService
