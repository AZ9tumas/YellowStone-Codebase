local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local starterGui = player.PlayerGui
local MechanicsUi = starterGui:WaitForChild("MechanicsUI")

local MovementController = require(script.MovementController)

local ScreenGui = starterGui:WaitForChild("Menu")
local statsFrame: Frame = ScreenGui:WaitForChild("Frame")
local attackLabel: TextLabel = statsFrame:WaitForChild("Attack")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local packets = require(modules:WaitForChild("Packets"))

local staminaProgress: Frame = MechanicsUi:WaitForChild("Background"):WaitForChild("Progress")
local statsFolder = player:WaitForChild("PlayerStats")
local staminaValue: NumberValue = statsFolder:WaitForChild("Stamina")
local MechanicToggleFrame = MechanicsUi:WaitForChild("MechanicToggleFrame")
local WalkLabel: TextLabel = MechanicToggleFrame:WaitForChild("Walk")
local SprintLabel: TextLabel = MechanicToggleFrame:WaitForChild("Sprint")

local controller = MovementController.new(player, camera, packets)

staminaValue.Changed:Connect(function()
	local tw = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(staminaProgress, tw, {Size = UDim2.new(1, 0, staminaValue.Value, 0)}):Play()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Z then
		local newState = controller:ToggleWalkingStyle()
		WalkLabel.Text = newState

	elseif input.KeyCode == Enum.KeyCode.X then
		local newState = controller:ToggleRunningStyle()
		SprintLabel.Text = newState

	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		packets.attack.send()
		attackLabel.Text = "Attacking..." 
	end
end)

packets.attackReturn.listen(function(data)
	attackLabel.Text = "Attack: " .. string.format("%.2f", data)
end)

RunService:BindToRenderStep("MechanicMovement", Enum.RenderPriority.Character.Value + 1, function(dt)
	controller:Update(dt)
end)

ContextActionService:BindAction("MoveForward", function(...) controller:UpdateMoveDir(...) end, true, Enum.KeyCode.W, Enum.KeyCode.Up)
ContextActionService:BindAction("MoveBackward", function(...) controller:UpdateMoveDir(...) end, true, Enum.KeyCode.S, Enum.KeyCode.Down)
ContextActionService:BindAction("RotateLeft", function(...) controller:HandleRotation(...) end, true, Enum.KeyCode.A, Enum.KeyCode.Left)
ContextActionService:BindAction("RotateRight", function(...) controller:HandleRotation(...) end, true, Enum.KeyCode.D, Enum.KeyCode.Right)

ContextActionService:SetTitle("MoveForward", "Forward")
ContextActionService:SetTitle("MoveBackward", "Backward")
ContextActionService:SetTitle("RotateLeft", "Left")
ContextActionService:SetTitle("RotateRight", "Right")

local function cleanup()
	RunService:UnbindFromRenderStep("MechanicMovement")
	
	ContextActionService:UnbindAction("MoveForward")
	ContextActionService:UnbindAction("MoveBackward")
	ContextActionService:UnbindAction("RotateLeft")
	ContextActionService:UnbindAction("RotateRight")
end

player.CharacterRemoving:Connect(function()
	cleanup()
end)