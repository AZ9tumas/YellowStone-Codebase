local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local starterGui = player.PlayerGui

-- Modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local packets = require(modules:WaitForChild("Packets"))
local MovementController = require(script.MovementController)

-- Variables that need to be re-initialized
local controller = nil
local staminaConnection = nil
local inputConnection = nil
local renderConnection = nil
local attackReturnConnection = nil

local function Cleanup()
	if controller then
		controller:Destroy()
		controller = nil
	end
	
	if staminaConnection then staminaConnection:Disconnect() staminaConnection = nil end
	if inputConnection then inputConnection:Disconnect() inputConnection = nil end
	if renderConnection then renderConnection:Disconnect() renderConnection = nil end
	if attackReturnConnection then attackReturnConnection:Disconnect() attackReturnConnection = nil end
end

local function Initialize(data)
	Cleanup()
	
	local char = player.Character
	if not char then return end
	
	-- Check if it's a valid character (e.g. has HumanoidRootPart)
	local hrp = char:WaitForChild("HumanoidRootPart")
	local hum = char:WaitForChild("Humanoid")
	
	if not hrp or not hum then
		warn("Invalid character for mechanics initialization")
		return
	end

	-- UI Setup
	local MechanicsUi = starterGui:WaitForChild("MechanicsUI", 5)
	if not MechanicsUi then return end
	
	local staminaProgress = MechanicsUi:WaitForChild("Background"):WaitForChild("Progress")
	local MechanicToggleFrame = MechanicsUi:WaitForChild("MechanicToggleFrame")
	local WalkLabel = MechanicToggleFrame:WaitForChild("Walk")
	local SprintLabel = MechanicToggleFrame:WaitForChild("Sprint")
	
	local ScreenGui = starterGui:WaitForChild("Menu", 5)
	local statsFrame = ScreenGui and ScreenGui:WaitForChild("Frame")
	local attackLabel = statsFrame and statsFrame:WaitForChild("Attack")
	
	local statsFolder = player:WaitForChild("PlayerStats", 5)
	local staminaValue = statsFolder and statsFolder:WaitForChild("Stamina")

	-- Controller
	controller = MovementController.new(player, camera, packets)
	
	-- Connections
	if staminaValue then
		staminaConnection = staminaValue.Changed:Connect(function()
			local tw = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(staminaProgress, tw, {Size = UDim2.new(1, 0, staminaValue.Value, 0)}):Play()
		end)
	end
	
	inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.Z then
			if controller then
				local newState = controller:ToggleWalkingStyle()
				if WalkLabel then WalkLabel.Text = newState end
			end

		elseif input.KeyCode == Enum.KeyCode.X then
			if controller then
				local newState = controller:ToggleRunningStyle()
				if SprintLabel then SprintLabel.Text = newState end
			end

		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			packets.attack.send()
			if attackLabel then attackLabel.Text = "Attacking..." end
		end
	end)
	
	attackReturnConnection = packets.attackReturn.listen(function(dmg)
		if attackLabel then attackLabel.Text = "Attack: " .. string.format("%.2f", dmg) end
	end)
	
	renderConnection = RunService.RenderStepped:Connect(function(dt)
		if controller then controller:Update(dt) end
	end)

	print("Client scripts successfully initialized.")
end

packets.initClientScripts.listen(Initialize)
