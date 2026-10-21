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
local BodyArticulation = require(script.Parent:WaitForChild("Movement"):WaitForChild("BodyArticulation"))
local LegIK = require(script.Parent:WaitForChild("Movement"):WaitForChild("LegIK"))
local HeadLook = require(script.Parent:WaitForChild("Movement"):WaitForChild("HeadLook"))
local TurnInPlace = require(script.Parent:WaitForChild("Movement"):WaitForChild("TurnInPlace"))
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
	-- Procedural body language (spine lag, neck lead, tail whip, chest bank).
	-- Optional: absent = disabled for the creature. The schema lives with the
	-- module that consumes it.
	BodyArticulation: BodyArticulation.Config?,
	LegIK: LegIK.Config?,
	HeadLook: HeadLook.Config?,
	-- Standstill turns played from the creature's turn clips. Optional.
	TurnInPlace: TurnInPlace.Config?,

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

-- The creature config row for a species + gender. Fails loud on an unknown
-- pair — there is no sensible default creature.
function module.GetInfo(characterName: string, gender: string): CreatureInfo
	local byName = CreatureStats[characterName]
	assert(byName, `GetInfo: no creature stats for "{tostring(characterName)}"`)
	local byGender = byName[gender]
	assert(byGender, `GetInfo: no stats for "{characterName}.{tostring(gender)}"`)
	return byGender
end

-- Returns the creature config table for a spawned player. Fails loud if the
-- player is not properly set up.
function module.GetPlayerInfo(plr: Player): CreatureInfo
	local characterName = plr:GetAttribute("CharacterName")
	assert(characterName, `GetPlayerInfo: player "{plr.Name}" has no CharacterName attribute (not spawned?)`)
	local gender = plr:GetAttribute("Gender")
	assert(gender, `GetPlayerInfo: player "{plr.Name}" has no Gender attribute`)
	return module.GetInfo(characterName, gender)
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
