--[[
	Info (compatibility shim)

	The creature configuration data now lives in
	`ReplicatedStorage.Modules.Stats.CreatureStats`. This module is kept as
	a thin re-export so any non-updated references (or external scripts)
	continue to work.

	New code should require `Stats` and use `Stats.Creatures` (or any of
	the flattened helpers) — see `Stats/init.luau` for details.
]]

return require(script.Parent:WaitForChild("Stats"):WaitForChild("CreatureStats"))
