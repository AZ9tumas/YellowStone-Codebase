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
local MovementStates = require(modules:WaitForChild("Movement"):WaitForChild("MovementStates"))
local Knit = require(ReplicatedStorage.Packages.Knit)

-- ui
local ScreenGui = playerGui:WaitForChild("Menu")
local horise: TextButton = ScreenGui:WaitForChild("Horsie")
local muleDeer: TextButton = ScreenGui:WaitForChild("MuleDeer")
local statsFrame: Frame = ScreenGui:WaitForChild("Frame")
local fadeFrame: Frame = ScreenGui:WaitForChild("Transition")
local HungerText: TextBox = statsFrame:WaitForChild("Hunger")
local ThirstText: TextBox = statsFrame:WaitForChild("Thirst")

local staminaValue: NumberValue = player:WaitForChild("PlayerStats"):WaitForChild("Stamina")

-- Movement debug read-outs. All labels live in the Menu.Frame (added in Studio);
-- we only reference them here.
local BreakText: TextLabel = statsFrame:WaitForChild("Break")
local AngleText: TextLabel = statsFrame:WaitForChild("Angle")
local StateText: TextLabel = statsFrame:WaitForChild("State")
local TurnRateText: TextLabel = statsFrame:WaitForChild("TurnRate")
local TurnRPSText: TextLabel = statsFrame:WaitForChild("TurnRPS")
local CamRateText: TextLabel = statsFrame:WaitForChild("CamRate")
local MaxTurnText: TextLabel = statsFrame:WaitForChild("MaxTurn")
-- Body-articulation read-outs. Optional labels: the HUD keeps working if the
-- creature has no BodyArticulation config or the labels were never added.
local SpineText: TextLabel? = statsFrame:FindFirstChild("Spine") :: TextLabel?
local BankText: TextLabel? = statsFrame:FindFirstChild("Bank") :: TextLabel?

-- ===== Debug panel layout ====================================================
-- Motion rows. Speed and Accel are MEASURED from the root's physics velocity;
-- Cmd / Limit / Server are what the code asked for, kept alongside so the two
-- can be compared. Rows missing from the Studio frame are cloned from Speed,
-- so the panel is defined here and syncs with Rojo.
local SpeedText: TextLabel = statsFrame:WaitForChild("Speed")
local function row(name: string): TextLabel
	local label = statsFrame:FindFirstChild(name) :: TextLabel?
	if not label then
		label = SpeedText:Clone()
		label.Name = name
		label.Text = name .. ":"
		label.Parent = statsFrame
	end
	return label
end
local AccelText = row("Accel") -- measured change in speed, studs/s^2
local PeakText = row("Peak") -- largest measured rise / drop over PEAK_WINDOW
local CmdText = row("Cmd") -- controller's commanded speed, and the server's WalkSpeed
local LimitText = row("Limit") -- configured Acceleration / Deceleration
local ServerText = row("Server") -- gait the server is driving speed for

-- Smaller, wider rows so the whole panel fits on screen and each row holds
-- about 20 characters. Rows grow downward if their text wraps (Spine, Bank).
local PANEL_WIDTH = 240
local ROW_HEIGHT = 26
local ROW_TEXT_SIZE = 18
local ROW_ORDER = {
	"Speed", "Accel", "Peak", "Cmd", "Limit", "Server",
	"State", "Break", "Angle", "TurnRate", "TurnRPS", "MaxTurn", "CamRate",
	"Stamina", "Health", "Thirst", "Hunger", "Attack",
	"Spine", "Bank",
}
statsFrame.AutomaticSize = Enum.AutomaticSize.Y
statsFrame.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
for order, name in ROW_ORDER do
	local label = statsFrame:FindFirstChild(name)
	if label and (label:IsA("TextLabel") or label:IsA("TextBox")) then
		label.LayoutOrder = order
		label.Size = UDim2.fromOffset(PANEL_WIDTH - 5, ROW_HEIGHT)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextSize = ROW_TEXT_SIZE
	end
end

-- ===== Measured motion =======================================================
-- Acceleration is the change in measured horizontal speed across
-- ACCEL_WINDOW: long enough to swallow single-step physics jitter, short
-- enough that a burst lasting a few tenths of a second still shows. Peak
-- holds the extremes so a burst can be read after it is over.
local ACCEL_WINDOW = 0.1 -- s
local PEAK_WINDOW = 1 -- s
local speedSamples: { { t: number, v: number } } = {} -- oldest first
local accelSamples: { { t: number, a: number } } = {}

local function resetMotion()
	table.clear(speedSamples)
	table.clear(accelSamples)
end

-- Records this frame's speed; returns (accel, peak rise, peak drop).
local function measureMotion(now: number, speed: number): (number, number, number)
	table.insert(speedSamples, { t = now, v = speed })
	-- Keep exactly one sample at or before the window start as the baseline.
	while speedSamples[2] and speedSamples[2].t <= now - ACCEL_WINDOW do
		table.remove(speedSamples, 1)
	end
	local base = speedSamples[1]
	local accel = if now > base.t then (speed - base.v) / (now - base.t) else 0

	table.insert(accelSamples, { t = now, a = accel })
	while accelSamples[1].t < now - PEAK_WINDOW do
		table.remove(accelSamples, 1)
	end
	local rise, drop = 0, 0
	for _, sample in accelSamples do
		rise = math.max(rise, sample.a)
		drop = math.max(drop, -sample.a)
	end
	return accel, rise, drop
end

local movementController -- populated once Knit.OnStart fires

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
	movementController = Knit.GetController("MovementController")

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

	local parents : {Frame | TextButton} = muleDeer.Parent:GetChildren()
	for i, v in pairs(parents) do
		if v:IsA("TextButton") then
			v.MouseButton1Click:Connect(function()
				buttonClick(v)
			end)
		end
	end

	--[[
	horise.MouseButton1Click:Connect(function()
		buttonClick(horise)
	end)

	muleDeer.MouseButton1Click:Connect(function()
		buttonClick(muleDeer)
	end)]]

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
		statsFrame.Health.Text = "Health: " .. tostring(char.Humanoid.Health):match("^(%d+)")

		local info = if commonM.IsSpawned(player) then commonM.GetPlayerInfo(player) else nil

		-- Speed / Accel / Peak = MEASURED horizontal physics velocity
		-- (AssemblyLinearVelocity) and its rate of change, so they show what the
		-- body really did, whatever the code asked for.
		local av = hmr.AssemblyLinearVelocity
		local speed = Vector3.new(av.X, 0, av.Z).Magnitude
		local accel, rise, drop = measureMotion(os.clock(), speed)
		SpeedText.Text = string.format("Speed: %.1f", speed)
		AccelText.Text = string.format("Accel: %+.0f", accel)
		PeakText.Text = string.format("Peak: +%.0f/-%.0f", rise, drop)

		-- Limit = the creature's configured Acceleration / Deceleration: the
		-- server's WalkSpeed ramp. Server = the gait it ramps toward (the
		-- reported intent, mapped onto the swim ladder in water).
		LimitText.Text = if info then string.format("Limit: +%g/-%g", info.Acceleration, info.Deceleration) else "Limit: —"
		local intent = player:GetAttribute("State")
		local serverGait = if intent and char:GetAttribute("Swimming") then MovementStates.SwimGaitFor[intent] else intent
		ServerText.Text = "Server: " .. tostring(serverGait or "—")

		-- Break = turn-speed penalty · Angle = facing-to-input gap (deg)
		-- TurnRate = turnRPS / maxTurn (raw) · TurnRPS = turn rate (rad/s)
		-- CamRate = camera yaw rate (rad/s) · MaxTurn = gait's turn cap (rad/s)
		if movementController then
			-- Cmd = speed the controller handed the physics (WalkSpeed x Break) ·
			-- WS = the server's WalkSpeed
			CmdText.Text = string.format("Cmd: %.1f WS: %.1f", movementController:GetCommandedSpeed(), char.Humanoid.WalkSpeed)
			BreakText.Text = string.format("Break: %.2f", movementController:GetTurnBrake())
			AngleText.Text = string.format("Angle: %.1f", movementController:GetTurnAngle())
			TurnRateText.Text = string.format("TurnRate: %.2f", movementController:GetTurnRateFraction())
			TurnRPSText.Text = string.format("TurnRPS: %.2f", movementController:GetTurnRateRPS())
			CamRateText.Text = string.format("CamRate: %.2f", movementController:GetCamYawRate())
			MaxTurnText.Text = string.format("MaxTurn: %.2f", movementController:GetMaxTurnRate())
			StateText.Text = "State: " .. movementController:GetState()

			-- Chains = each configured chain's bend (deg) · feet = each paw's
			-- terrain correction (studs) · Bank = chest roll (deg) · Gain =
			-- speed gain · Omega = physical yaw rate (rad/s) · Look = head aim
			-- off the body's facing (deg) with the feet that found ground.
			local art = movementController:GetArticulationDebug()
			local legs = movementController:GetLegIKDebug()
			local look = movementController:GetHeadLookDebug()
			if SpineText then
				local parts = {}
				if art then
					for name, deg in art.Chains do
						parts[#parts + 1] = string.format("%s: %.1f", name, deg)
					end
					table.sort(parts)
				end
				if legs then
					local feet = {}
					for name, studs in legs.Legs do
						feet[#feet + 1] = string.format("%s: %+.2f", name, studs)
					end
					table.sort(feet)
					parts[#parts + 1] = table.concat(feet, " ")
				end
				SpineText.Text = if #parts > 0 then table.concat(parts, "  ") else "Chains: —"
			end
			if BankText then
				if art or legs or look then
					local bits = {}
					if art then
						bits[#bits + 1] =
							string.format("Bank: %.1f  Gain: %.2f  Omega: %.2f", art.Bank or 0, art.Gain, art.Omega)
					end
					if legs then
						bits[#bits + 1] = string.format("Feet: %d/4  Drop: %.2f", legs.Grounded, legs.BodyDrop)
					end
					if look then
						bits[#bits + 1] = string.format(
							"Look: %.0f/%.0f %s",
							look.Yaw,
							look.Pitch,
							if look.HasTarget then "*" else "-"
						)
					end
					BankText.Text = table.concat(bits, "  ")
				else
					BankText.Text = "Bank: —"
				end
			end
		end

		if info then
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
	resetMotion()
	conn = RunService.RenderStepped:Connect(updateStats)
end)

conn = RunService.RenderStepped:Connect(updateStats)
