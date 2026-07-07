--[[
	Common

	Player -> creature-config lookup. This is the canonical "fetch from the
	stats table" path, so it follows the project's loud-failure rule: it does
	NOT fall back to {} or nil when data is missing. A player without a
	CharacterName/Gender attribute, or a creature with no stats row, is a bug we
	want surfaced immediately — not masked by a silent default that produces a
	mystery later.

	Callers that legitimately run before the player has spawned a creature must
	gate on `player:GetAttribute("CharacterName")` themselves (or use a guarded
	query); they must not rely on this returning an empty table.
]]

local module = {}

local Stats = require(script.Parent:WaitForChild("Stats"))
local CreatureStats = Stats.Creatures

-- Per-species/gender creature config row (see Stats/CreatureStats.luau). Keyed
-- indexer covers gait-derived lookups (e.g. `info[gait .. "Speed"]`,
-- `info[gait .. "TurnRate"]`) that aren't fixed field names.
export type CreatureInfo = {
	[string]: any,

	IdleSpeed: number,
	WalkSpeed: number,
	TrotSpeed: number,
	RunSpeed: number,
	SprintSpeed: number,

	MaxStamina: number,
	RunStaminaDrain: number,
	SprintStaminaDrain: number,

	TrotStaminaGain: number,
	WalkStaminaGain: number,
	IdleStaminaGain: number,

	MaxHealthSpeedPenalty: number,
	StaminaPenaltyThreshold: number,
	HealthPenaltyThreshold: number,

	Acceleration: number,
	Deceleration: number,

	BaseTurnRate: number,
	-- Demanded-turn-angle (deg) -> speed multiplier control points, linearly
	-- interpolated (MovementMath.EvaluateTurnBrakeCurve). Required per creature.
	TurnBrakeCurve: { { Angle: number, Brake: number } },
	-- Turn-in-place tuning. Optional: only creatures with Turn90*/Turn180*
	-- animations define it; without it the feature is disabled for the creature.
	TurnInPlace: {
		MaxSpeed: number,
		MinAngle: number,
		Angle180: number,
		ExitAngle: number,
	}?,

	MaxTiltAngle: number,
	TiltSensitivity: number,
	TiltSpeed: number,

	TerrainAlignmentEnabled: boolean,
	TerrainAlignmentSpeed: number,
	MaxTerrainPitch: number,
	MaxTerrainRoll: number,
	MaxTerrainAngle: number,
	MaxClimbAngle: number,
	TerrainRaycastDistance: number,

	AttackDamage: number,
	StaminaAttackCost: number,
	HealthAttackCost: number,

	Animations: { [string]: string },
}

-- Returns the creature config table for a spawned player. Fails loud if the
-- player is not properly set up.
function module.GetPlayerInfo(plr: Player): CreatureInfo
	local characterName = plr:GetAttribute("CharacterName")
	assert(characterName, `GetPlayerInfo: player "{plr.Name}" has no CharacterName attribute (not spawned?)`)

	local byName = CreatureStats[characterName]
	assert(byName, `GetPlayerInfo: no creature stats for "{characterName}"`)

	local gender = plr:GetAttribute("Gender")
	assert(gender, `GetPlayerInfo: player "{plr.Name}" has no Gender attribute`)

	local byGender = byName[gender]
	assert(byGender, `GetPlayerInfo: no stats for "{characterName}.{gender}"`)

	return byGender
end

-- Has the player been morphed into a creature yet? Use this to gate code that
-- may run before spawn (e.g. UI polling) so GetPlayerInfo's asserts only fire
-- on genuine data bugs.
function module.IsSpawned(plr: Player): boolean
	local characterName = plr:GetAttribute("CharacterName")
	if not characterName then
		return false
	end
	local byName = CreatureStats[characterName]
	if not byName then
		return false
	end
	local gender = plr:GetAttribute("Gender")
	return gender ~= nil and byName[gender] ~= nil
end

return module
