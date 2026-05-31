local module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local repModules = ReplicatedStorage:WaitForChild("Modules")
local Stats = require(repModules:WaitForChild("Stats"))
local CreatureStats = Stats.Creatures

return module
