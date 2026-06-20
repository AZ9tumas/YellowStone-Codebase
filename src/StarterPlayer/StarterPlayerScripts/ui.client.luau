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
local Knit = require(ReplicatedStorage.Packages.Knit)

-- ui
local ScreenGui = playerGui:WaitForChild("Menu")
local horise: TextButton = ScreenGui:WaitForChild("Horsie")
local muleDeer: TextButton = ScreenGui:WaitForChild("MuleDeer")
local statsFrame: Frame = ScreenGui:WaitForChild("Frame")
local fadeFrame: Frame = ScreenGui:WaitForChild("Transition")
local HungerText: TextBox = statsFrame:WaitForChild("Food_Thirst"):WaitForChild("Hunger")
local ThirstText: TextBox = statsFrame:WaitForChild("Food_Thirst"):WaitForChild("Thirst")

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

local function buttonClick(button: TextButton)
	createTween(true)
	
	task.wait(1)
	-- request spawn via Knit (replaces the ByteNet spawn packet)
	local SpawnService = Knit.GetService("SpawnService")
	SpawnService:Spawn(button.Name, "Male"):catch(warn)

	-- Wait for character to be replaced
	local newChar = player.CharacterAdded:Wait()
	workspace.CurrentCamera.CameraSubject = newChar:WaitForChild("HumanoidRootPart")
	
	-- load
	local descendants = newChar:GetDescendants()
	local len = #descendants
	button.Text = "Loading... 0/" .. tostring(len)
	local c = 0
	
	ContentProvider:PreloadAsync(descendants, function(a, b)
		c += 1
		button.Text = "Loading... " .. tostring(c) .. "/" .. tostring(len)
	end)

	button.Text = button.Name:upper()
	
	task.wait()
	createTween(false)
end

horise.MouseButton1Click:Connect(function()
	buttonClick(horise)
end)

muleDeer.MouseButton1Click:Connect(function()
	buttonClick(muleDeer)
end)

local function updateStats()
	if char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
		local hmr = char:FindFirstChild("HumanoidRootPart")
		if not hmr then return end
		local vel = char.Humanoid.WalkSpeed
		statsFrame.Health.Text = "Health: " .. tostring(char.Humanoid.Health):match("^(%d+)")
		statsFrame.Speed.Text = "Speed: " .. tostring(vel):match("^(%d+)")
		
		if commonM.IsSpawned(player) then
			local info = commonM.GetPlayerInfo(player)
			if info.MaxStamina then
				statsFrame.Stamina.Text = "Stamina: " .. tostring(staminaValue.Value * info.MaxStamina):match("^(%d+)")
			end
		end
		if char:GetAttribute("Hunger") and char:GetAttribute("Thirst") then
			HungerText.Text = "Hunger: " .. tostring(math.ceil(char:GetAttribute("Hunger")))
			ThirstText.Text = "Thirst: " .. tostring(math.ceil(char:GetAttribute("Thirst")))
		else
			--warn("Hunger, Thirst, or both are missing attributes from this character.")
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