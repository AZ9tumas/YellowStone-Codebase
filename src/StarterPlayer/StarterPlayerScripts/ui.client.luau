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
local SpawnRemote: RemoteFunction = remotes:WaitForChild("Spawn")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(modules:WaitForChild("Common"))

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
	local success, errmsg = SpawnRemote:InvokeServer("Horsie", "Male")
	if not success then
		return error(errmsg)
	end
	
	workspace.CurrentCamera.CameraSubject = player.Character:WaitForChild("HumanoidRootPart")
	
	-- load
	local len = #player.Character:GetDescendants()
	SpawnButton.Text = "Loading... 0/0"
	local c = 0
	
	ContentProvider:PreloadAsync(player.Character:GetDescendants(), function(a, b)
		c += 1
		SpawnButton.Text = "Loading... " .. tostring(c) .. "/" .. tostring(len)
	end)

	SpawnButton.Text = "SPAWN"
	
	task.wait()
	createTween(false)
end)

local function updateStats()
	if char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
		statsFrame.Health.Text = "Health: " .. tostring(char.Humanoid.Health):match("^(%d+)")
		statsFrame.Speed.Text = "Speed: " .. tostring(char.Humanoid.WalkSpeed):match("^(%d+)")
		
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