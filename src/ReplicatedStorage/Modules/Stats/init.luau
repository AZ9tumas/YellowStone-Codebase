--[[
	Stats Module

	Aggregator for all gameplay tuning and math used by the movement /
	stamina / combat systems. Sub-modules are delegated via metatable so
	callers can do `Stats.Accelerate(...)` or `Stats.GetPlayerInfo(...)`
	directly, mirroring the RaceThroughTime stats pattern.

	Sub-modules:
		- CreatureStats : per-species/gender configuration tables
		                  (speeds, stamina, turning, terrain alignment, ...)
		- MovementMath  : pure math helpers for movement (acceleration,
		                  turn rate, brake factor, state constraint, ...)
		- StaminaMath   : pure math helpers for stamina drain/gain and
		                  health-based speed penalties
]]

local MovementStates = require(script.Parent:WaitForChild("Movement"):WaitForChild("MovementStates"))

local CreatureStats = require(script:WaitForChild("CreatureStats"))
local MovementMath  = require(script:WaitForChild("MovementMath"))
local StaminaMath   = require(script:WaitForChild("StaminaMath"))

local Stats = {
	Creatures = CreatureStats,
	Movement  = MovementMath,
	Stamina   = StaminaMath,

	-- Ordered gait ladder (slow -> fast). Re-exported from MovementStates,
	-- which owns it — do not redeclare the list here.
	MovementStages = MovementStates.GaitOrder,
}

-- Flatten sub-module functions onto the root for convenient access
-- (Stats.Accelerate, Stats.HealthBasedSpeedMultiplier, ...).
local Delegates = {}
for _, sub in ipairs({ MovementMath, StaminaMath }) do
	for key, value in pairs(sub) do
		Delegates[key] = value
	end
end

return setmetatable(Stats, {
	__index = function(_, key)
		return Delegates[key]
	end,
})
