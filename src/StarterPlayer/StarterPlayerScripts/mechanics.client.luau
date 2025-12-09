local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- Modules
local PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
local Controls = PlayerModule:GetControls()

local params = {
	CurrentWalkingStyle = "Walk",
	CurrentRunningStyle = "Sprint",
	CurrentState = "Idle",
	CurrentFacingDirection = Vector3.new(0, 0, 0),
}

staminaValue.Changed:Connect(function()
	local tw = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(staminaProgress, tw, {Size = UDim2.new(1, 0, staminaValue.Value, 0)}):Play()
end)

function updateMovement()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local moveVector = Controls:GetMoveVector()

	local laststate = params.CurrentState

	if moveVector.Magnitude > 0 then
		params.CurrentState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and params.CurrentRunningStyle or params.CurrentWalkingStyle
		params.CurrentFacingDirection = hum.MoveDirection
	else
		params.CurrentState = "Idle"
	end

	-- check for change
	if laststate ~= params.CurrentState then
		if hum.WalkSpeed > 1 and params.CurrentState == "Idle" then
			Controls:Disable()
			task.wait(0.1)
			
			local lastdir = player:GetAttribute("LastDirection") :: Vector3
			hum:Move(lastdir or params.CurrentFacingDirection)
			print("Moving to", lastdir or params.CurrentFacingDirection)
		end

		SprintFunc:InvokeServer(params.CurrentState)
		Controls:Enable()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Z then
		
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
		attackLabel.Text = "Attack: " .. string.format("%.2f", newAttack)
	end
end)

RunService.Heartbeat:Connect(updateMovement)