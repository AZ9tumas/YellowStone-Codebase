--// Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--// Variables
local Player = Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()
local Humanoid: Humanoid = Char:WaitForChild("Humanoid")
local HUD = script:WaitForChild("HUD")
local HUDFrame = HUD:WaitForChild("HUDFrame")
local HealthFolder: Folder = HUDFrame:WaitForChild("Health")
local StaminaFolder: Folder = HUDFrame:WaitForChild("Stamina")
local HealthFill: ImageLabel,StaminaFill: ImageLabel = HealthFolder:WaitForChild("HealthFill"),StaminaFolder:WaitForChild("StaminaFill")

--// Add HUD
HUD.Parent = Player.PlayerGui

--// Functions
function UpdateStats()
	
	if Char and Humanoid then
		TweenService:Create(HealthFill,TweenInfo.new(0.2),{Transparency = ((Humanoid.Health*100)/Humanoid.MaxHealth)/100}):Play()
	end
	
	if Char and Char:GetAttribute("Stamina") then
		StaminaFill.Transparency = ((Char:GetAttribute("Stamina")*100)/Char:GetAttribute("MaxStamina"))/100
	end
	
end

--// StatUpdate Loop
while Humanoid.Health > 0 do
	UpdateStats()
	task.wait(0.1)
end