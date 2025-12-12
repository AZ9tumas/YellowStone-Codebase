-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- modules
local serverModules = script.Parent.Modules
local repModules = ReplicatedStorage:WaitForChild("Modules")
local remotesM = require(serverModules.Remotes)
local packets = require(repModules.Packets)

-- assets
local models = ServerStorage:WaitForChild("Models")

packets.spawn.listen(function(data, player)
	remotesM.Morph(player, data.charName, data.gender)
end)

packets.sprint.listen(function(data, player)
	print(remotesM.Sprint(player, data.sprintType))
end)

packets.attack.listen(function(_, player)
	remotesM.Attack(player)
end)

Players.PlayerAdded:Connect(function(plr)
	--plr.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
	--plr.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

	remotesM.InitStats(plr)
end)

RunService.Heartbeat:Connect(function(dt)
	for _, v in pairs(Players:GetPlayers()) do
		remotesM.UpdateStamina(v, dt)
	end
end)
