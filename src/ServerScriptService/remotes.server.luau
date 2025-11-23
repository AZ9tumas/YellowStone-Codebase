-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spawnRemote: RemoteFunction = remotes:WaitForChild("Spawn")
local sprintRemote: RemoteFunction = remotes:WaitForChild("Sprint")
local attackRemote: RemoteFunction = remotes:WaitForChild("Attack")

-- modules
local serverModules = script.Parent.Modules
local remotesM = require(serverModules.Remotes)

-- assets
local models = ServerStorage:WaitForChild("Models")

spawnRemote.OnServerInvoke = remotesM.Morph
sprintRemote.OnServerInvoke = remotesM.Sprint
attackRemote.OnServerInvoke = remotesM.Attack

Players.PlayerAdded:Connect(function(plr)
	remotesM.InitStats(plr)
end)

RunService.Heartbeat:Connect(function(dt)
	for _, v in pairs(Players:GetPlayers()) do
		remotesM.UpdateStamina(v, dt)
	end
end)
