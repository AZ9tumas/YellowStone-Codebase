-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--// Spawn base (single part players are placed on top of)
local SpawnBase: BasePart = Workspace:WaitForChild("Base")

-- remotes folder
local Remotes = ReplicatedStorage.Remotes

-- FootstepSFX folder
local FootstepSFX_Folder = ReplicatedStorage.FootstepSFX

-- modules
local serverModules = script.Parent.Modules
local repModules = ReplicatedStorage:WaitForChild("Modules")
local remotesM = require(serverModules.Remotes)
local packets = require(repModules.Packets)
local ReplicateSounds = Remotes.ReplicateSounds

-- assets
local models = ServerStorage:WaitForChild("Models")

packets.spawn.listen(function(data, player)
	remotesM.Morph(player, data.charName, data.gender, SpawnBase)
end)

packets.sprint.listen(function(data, player)
	remotesM.Sprint(player, data.sprintType)
end)

packets.attack.listen(function(_, player)
	remotesM.Attack(player)
end)

Players.PlayerAdded:Connect(function(plr)
	plr.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
	plr.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

	remotesM.InitStats(plr)
end)

ReplicateSounds.OnServerEvent:Connect(function(player,char)
	if char:FindFirstChild("HumanoidRootPart") then
		for _,v in FootstepSFX_Folder:GetChildren() do
			v:Clone().Parent = char.HumanoidRootPart
		end
	else
		warn("No HumanoidRootPart found inside this character model.")
	end
end)

RunService.Heartbeat:Connect(function(dt)
	for _, v in pairs(Players:GetPlayers()) do
		remotesM.UpdateStamina(v, dt)
	end
end)