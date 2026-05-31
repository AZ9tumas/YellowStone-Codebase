--// Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGUI = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Variables
local Player = Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()
local Humanoid: Humanoid = Char:WaitForChild("Humanoid")
local Playerstats: Folder = Player:WaitForChild("PlayerStats")
local HUD = script:WaitForChild("HUD")
local HUDFrame = HUD:WaitForChild("HUDFrame")
local HealthFolder: Folder = HUDFrame:WaitForChild("Health")
local StaminaFolder: Folder = HUDFrame:WaitForChild("Stamina")
local HungerFolder: Folder = HUDFrame:WaitForChild("Hunger")
local ThirstFolder: Folder = HUDFrame:WaitForChild("Thirst")
local HealthFill: ImageLabel,StaminaFill: ImageLabel,HungerFill: ImageLabel, ThirstFill: ImageLabel = HealthFolder:WaitForChild("HealthFill"),StaminaFolder:WaitForChild("StaminaFill"),HungerFolder:WaitForChild("HungerFill"),ThirstFolder:WaitForChild("ThirstFill")
local HealthFillGradient: UIGradient,StaminaFillGradient: UIGradient,HungerFillGradient: UIGradient,ThirstFillGradient: UIGradient = HealthFill:WaitForChild("UIGradient1"),StaminaFill:WaitForChild("UIGradient2"),HungerFill:WaitForChild("UIGradient3"),ThirstFill:WaitForChild("UIGradient4")
local FoodWaterCycle = require(script.Parent:WaitForChild("FoodWaterCycle"))

--\\ Modules
local CommonFunctions = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CommonFunctions"))

--// Add HUD
HUD.Parent = Player.PlayerGui

--// Commands
StarterGUI:SetCoreGuiEnabled(Enum.CoreGuiType.Health,false)

--// Functions
function UpdateStats()
	
	if Char and Humanoid then
		TweenService:Create(HealthFillGradient,TweenInfo.new(0.5),{Offset = Vector2.new(0,CommonFunctions.LinearInterpolation(0.1,0.9,(1 - ((Humanoid.Health*100)/Humanoid.MaxHealth)/100)))}):Play()
	end
	
	if Char and Playerstats.Stamina then
		TweenService:Create(StaminaFillGradient,TweenInfo.new(0.5),{Offset = Vector2.new(0,CommonFunctions.LinearInterpolation(0.05,0.9,(1 - (Playerstats.Stamina.Value*100)/100)))}):Play()
	end

	if Char and Char:GetAttribute("Hunger") then
		TweenService:Create(HungerFillGradient,TweenInfo.new(0.5),{Offset = Vector2.new(0,CommonFunctions.LinearInterpolation(0.1,0.85,(1 - ((Char:GetAttribute("Hunger")*100)/FoodWaterCycle.FoodWaterCycle_Stats["HungerMax"])/100)))}):Play()
	end
	
	if Char and Char:GetAttribute("Thirst") then
		TweenService:Create(ThirstFillGradient,TweenInfo.new(0.5),{Offset = Vector2.new(0,CommonFunctions.LinearInterpolation(0.1,0.85,(1 - ((Char:GetAttribute("Thirst")*100)/FoodWaterCycle.FoodWaterCycle_Stats["ThirstMax"])/100)))}):Play()
	end
	
end

--// StatUpdate Loops
while task.wait(0.1) do
	if Humanoid.Health > 0 then
		UpdateStats()
	else
		break
	end
end