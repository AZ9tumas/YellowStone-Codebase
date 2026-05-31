--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Events
local HealthModifier: RemoteEvent = ReplicatedStorage.Remotes.HealthModifier

--// Functions
function DamageApplication(Player: Player,Humanoid: Humanoid,DamageAmount: number)
	print(Humanoid)
	Humanoid.Health += DamageAmount
end

--// Connections
HealthModifier.OnServerEvent:Connect(DamageApplication)