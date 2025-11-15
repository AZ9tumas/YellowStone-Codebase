-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InitClientScripts: RemoteEvent = Remotes:WaitForChild("InitClientScripts")

InitClientScripts.OnClientEvent:Connect(function()
	script.Parent.mechanics.Enabled = true
end)