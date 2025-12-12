local Players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

-- remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(modules:WaitForChild("Common"))
local packets = require(modules:WaitForChild("Packets"))
local spawnPacket = packets.spawn

-- ui
local ScreenGui = playerGui:WaitForChild("Menu")
local SpawnButton: TextButton = ScreenGui:WaitForChild("SpawnButton")
local statsFrame: Frame = ScreenGui:WaitForChild("Frame")
local fadeFrame: Frame = ScreenGui:WaitForChild("Transition")

local staminaValue: NumberValue = player:WaitForChild("PlayerStats"):WaitForChild("Stamina")

local function createTween(fadein)
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	tweenService:Create(
		fadeFrame,
		info,
		{
			Transparency = if fadein then 0 else 1
		}
	):Play()
end

SpawnButton.MouseButton1Down:Connect(function()
	print("Hello")
	
	createTween(true)
	
	task.wait(1)
	-- send packet here
	spawnPacket.send({
		charName = "Horsie",
		gender = "Male"
	})
	
	-- Wait for character to be replaced
	local newChar = player.CharacterAdded:Wait()
	workspace.CurrentCamera.CameraSubject = newChar:WaitForChild("HumanoidRootPart")
	
	-- load
	local descendants = newChar:GetDescendants()
	local len = #descendants
	SpawnButton.Text = "Loading... 0/" .. tostring(len)
	local c = 0
	
	ContentProvider:PreloadAsync(descendants, function(a, b)
		c += 1
		SpawnButton.Text = "Loading... " .. tostring(c) .. "/" .. tostring(len)
	end)

	SpawnButton.Text = "SPAWN"
	
	task.wait()
	createTween(false)
end)

local function updateStats()
	if char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
		local vel = Vector3.zero.Magnitude
		local hmr = char:FindFirstChild("HumanoidRootPart")
		if not hmr then return end
		local lv = hmr:FindFirstChild("LinearVelocity")
		if lv then
			vel = lv.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane and lv.PlaneVelocity.Magnitude or lv.VectorVelocity.Magnitude
		end
		statsFrame.Health.Text = "Health: " .. tostring(char.Humanoid.Health):match("^(%d+)")
		statsFrame.Speed.Text = "Speed: " .. tostring(vel):match("^(%d+)")
		
		local info = commonM.GetPlayerInfo(player)
		if info.MaxStamina then
			statsFrame.Stamina.Text = "Stamina: " .. tostring(staminaValue.Value * info.MaxStamina):match("^(%d+)")
		end
	end
end

local conn: RBXScriptConnection
player.CharacterAdded:Connect(function(c)
	if conn then
		conn:Disconnect()
	end

	char = c
	conn = RunService.RenderStepped:Connect(updateStats)
end)

conn = RunService.RenderStepped:Connect(updateStats)