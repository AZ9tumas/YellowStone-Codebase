--[[
	ui (spawn menu + stats HUD)

	Spawn menu is LOCKED until LoadingController reports both client preload and
	server data load are complete. The white Transition frame is faded back out
	off SpawnService.Spawned (the canonical "you are morphed" event), NOT
	player.CharacterAdded:Wait() — so a failed/rejected morph can never leave the
	player stuck on a white screen.
]]

local Players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

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

local buttons: { TextButton } = { horise, muleDeer }

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

local function setButtonsEnabled(enabled: boolean)
	for _, b in buttons do
		b.Active = enabled
		b.AutoButtonColor = enabled
		b.Text = if enabled then b.Name:upper() else "LOADING..."
	end
end

-- Menu starts locked: the player can't pick a creature until LoadingController
-- reports client preload AND server data load are finished.
setButtonsEnabled(false)

-- ===== Spawn flow ============================================================
local spawning = false

local function finishSpawnVisual()
	local newChar = player.Character or player.CharacterAdded:Wait()
	local hrp = newChar:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		workspace.CurrentCamera.CameraSubject = hrp
	end

	-- Preload the freshly-spawned character's assets behind the fade.
	pcall(function()
		ContentProvider:PreloadAsync(newChar:GetDescendants())
	end)

	task.wait()
	createTween(false)
	spawning = false
	setButtonsEnabled(true)
end

local function abortSpawnVisual(reason: string?)
	warn("ui: spawn failed -", reason)
	createTween(false)
	spawning = false
	setButtonsEnabled(true)
end

Knit.OnStart():andThen(function()
	local SpawnService = Knit.GetService("SpawnService")
	local LoadingController = Knit.GetController("LoadingController")

	-- A successful morph finishes the visual transition. Driven off Spawned (the
	-- canonical "you are morphed" event) instead of CharacterAdded, so a failed
	-- morph can never leave us stuck on the white Transition frame.
	SpawnService.Spawned:Connect(function()
		if spawning then
			finishSpawnVisual()
		end
	end)

	local function buttonClick(button: TextButton)
		if spawning or not LoadingController:IsLoaded() then
			return
		end
		spawning = true
		setButtonsEnabled(false)
		createTween(true)

		task.wait(1)
		-- request spawn via Knit (replaces the ByteNet spawn packet)
		SpawnService:Spawn(button.Name, "Male")
			:andThen(function(ok: boolean, err: string?)
				-- ok == false is a *resolved* rejection from the server (bad input,
				-- missing model, ...). The Spawned signal drives the success path,
				-- so here we only need to recover from failure.
				if not ok then
					abortSpawnVisual(err)
				end
			end)
			:catch(function(e)
				abortSpawnVisual(tostring(e))
			end)
	end

	horise.MouseButton1Click:Connect(function()
		buttonClick(horise)
	end)

	muleDeer.MouseButton1Click:Connect(function()
		buttonClick(muleDeer)
	end)

	-- Unlock the menu once loading completes.
	LoadingController:OnLoaded(function()
		if not spawning then
			setButtonsEnabled(true)
		end
	end)
end)

-- ===== Stats HUD =============================================================
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
