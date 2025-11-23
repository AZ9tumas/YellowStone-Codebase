local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local starterGui = player.PlayerGui
local MechanicsUi = starterGui:WaitForChild("MechanicsUI")

local ScreenGui = starterGui:WaitForChild("Menu")
local statsFrame: Frame = ScreenGui:WaitForChild("Frame")
local attackLabel: TextLabel = statsFrame:WaitForChild("Attack")

-- remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SprintFunc: RemoteFunction = remotes:WaitForChild("Sprint")
local AttackFunc: RemoteFunction = remotes:WaitForChild("Attack")

local staminaProgress: Frame = MechanicsUi:WaitForChild("Background"):WaitForChild("Progress")
local statsFolder = player:WaitForChild("PlayerStats")
local staminaValue: NumberValue = statsFolder:WaitForChild("Stamina")
local MechanicToggleFrame = MechanicsUi:WaitForChild("MechanicToggleFrame")
local WalkLabel: TextLabel = MechanicToggleFrame:WaitForChild("Walk")
local SprintLabel: TextLabel = MechanicToggleFrame:WaitForChild("Sprint")

local params = {
	CurrentWalkingStyle = "Walk",
	CurrentRunningStyle = "Sprint",
	CurrentState = "Walk"
}

staminaValue.Changed:Connect(function()
	local tw = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(staminaProgress, tw, {Size = UDim2.new(1, 0, staminaValue.Value, 0)}):Play()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.LeftShift then
		SprintFunc:InvokeServer(params.CurrentRunningStyle)
		params.CurrentState = params.CurrentRunningStyle
		
	elseif input.KeyCode == Enum.KeyCode.Z then
		
		local oldState = params.CurrentWalkingStyle
		params.CurrentWalkingStyle = if params.CurrentWalkingStyle == "Walk" then "Trot" else "Walk"
		WalkLabel.Text = params.CurrentWalkingStyle
		
		if oldState ~= params.CurrentRunningStyle then
			SprintFunc:InvokeServer(params.CurrentWalkingStyle)
		end

	elseif input.KeyCode == Enum.KeyCode.X then
		
		if params.CurrentState == params.CurrentRunningStyle then
			SprintFunc:InvokeServer(params.CurrentRunningStyle)
		end
		
		params.CurrentRunningStyle = if params.CurrentRunningStyle == "Sprint" then "Run" else "Sprint"
		SprintLabel.Text = params.CurrentRunningStyle

	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local newAttack = AttackFunc:InvokeServer()
		attackLabel.Text = "Attack: " .. tostring(newAttack)
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		SprintFunc:InvokeServer(params.CurrentWalkingStyle)
		params.CurrentState = params.CurrentWalkingStyle
	end
end)