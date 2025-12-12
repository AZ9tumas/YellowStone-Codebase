-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("Modules")
local packets = require(modules:WaitForChild("Packets"))
local initClientScripts = packets.initClientScripts

initClientScripts.listen(function(data)
	script.Parent.mechanics.Enabled = true
end)