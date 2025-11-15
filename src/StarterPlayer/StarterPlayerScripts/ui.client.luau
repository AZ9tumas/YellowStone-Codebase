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

-- ui
local ScreenGui = playerGui:WaitForChild("Menu")
local SpawnButton: TextButton = ScreenGui:WaitForChild("SpawnButton")
local statsFrame: Frame = ScreenGui:WaitForChild("Frame")
local fadeFrame: Frame = ScreenGui:WaitForChild("Transition")

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
	ContentProvider:PreloadAsync(player.Character:GetDescendants(), function(a, b)
		print(a, b)
	end)
	
	task.wait()
	createTween(false)
end)

local function updateStats()
	if char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
		statsFrame.Health.Text = "Health: " .. tostring(char.Humanoid.Health):match("^(%d+)")
		statsFrame.Speed.Text = "Speed: " .. tostring(char.Humanoid.WalkSpeed):match("^(%d+)")
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