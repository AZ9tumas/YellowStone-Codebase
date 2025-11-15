local module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local repModules = ReplicatedStorage:WaitForChild("Modules")
local infoM = require(repModules:WaitForChild("Info"))

return module
