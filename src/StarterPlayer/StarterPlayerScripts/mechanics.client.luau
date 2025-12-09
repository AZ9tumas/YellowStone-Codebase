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

	MomentumActive = false,
	MomentumStartTime = 0,
	MomentumDuration = 0.5, -- Duration of momentum effect in seconds
	MomentumStrength = 2, -- Initial momentum strength multiplier
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

	-- Handle momentum deceleration
	if params.MomentumActive then
		local elapsed = os.clock() - params.MomentumStartTime
		local progress = math.min(elapsed / params.MomentumDuration, 1)
		
		-- Calculate deceleration factor (1 to 0 over duration)
		local momentumFactor = (1 - progress) * params.MomentumStrength
		
		if momentumFactor > 0.01 then
			-- Apply momentum in the last facing direction with decreasing strength
			local momentumDirection = params.CurrentFacingDirection
			if momentumDirection.Magnitude > 0 then
				hum:Move(momentumDirection * momentumFactor)
			end
		else
			-- Momentum complete
			params.MomentumActive = false
			--Controls:Enable()
		end
	end

	if moveVector.Magnitude > 0 then
		params.CurrentState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and params.CurrentRunningStyle or params.CurrentWalkingStyle
		params.CurrentFacingDirection = hum.MoveDirection
		
		-- Cancel momentum if player starts moving again
		if params.MomentumActive then
			--params.MomentumActive = false
			--Controls:Enable()
		end
	else
		params.CurrentState = "Idle"
	end

	-- check for change
	if laststate ~= params.CurrentState then
		if hum.WalkSpeed > 1 and params.CurrentState == "Idle" then
			-- Start momentum deceleration
			params.MomentumActive = true
			params.MomentumStartTime = os.clock()
			--Controls:Disable()
		end

		SprintFunc:InvokeServer(params.CurrentState)
		
		-- Only enable controls if not in momentum
		if not params.MomentumActive then
			--Controls:Enable()
		end
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

RunService:BindToRenderStep("MechanicMovement", Enum.RenderPriority.Character.Value + 1, updateMovement)