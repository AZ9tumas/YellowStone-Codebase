--[[
	mechanics (survival / UI host)

	The per-life client host for everything that is NOT core locomotion:
	  * MechanicsUI wiring (stamina bar, Walk/Sprint labels, attack label)
	  * Attack input (MB1 -> CombatService)
	  * Eat / Drink (ContextAction E) routed THROUGH the new state system so the
	    "no eat/drink while sprinting" restriction + move-to-cancel are enforced
	    by MovementController's StateMachine.
	  * Food / water resource cycle (uses the unchanged plain RemoteEvents)
	  * HUD + footstep client enable

	Locomotion itself (turning, velocity, gait, tilt, terrain) lives in the Knit
	MovementController. This host just talks to it via Knit.GetController.

	Replaces the old ByteNet `initClientScripts` entry point with
	SpawnService.Spawned, and the `attack`/`attackReturn` packets with
	CombatService:Attack().
]]

--// Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local starterGui = player.PlayerGui

--// Plain RemoteEvents (NOT migrated to Knit — kept as-is)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HealthModifier: RemoteEvent = Remotes:WaitForChild("HealthModifier")
local FoodQuantity: RemoteEvent = Remotes:WaitForChild("FoodQuantityRemote")
local ReplicateSounds: RemoteEvent = Remotes:WaitForChild("ReplicateSounds")

--// Modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local Knit = require(ReplicatedStorage.Packages.Knit)
local FoodWaterCycle = require(script.FoodWaterCycle)
local ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

--// Tunables
local FoodWaterCycle_Interval = 1
local FoodDecayInterval = 1 -- seconds between food value reductions
local FoodDecayRate = 5 -- food removed per tick

local HerbivoreFoodSources: Folder = Workspace:WaitForChild("HerbivoreFoodSources")
local DrinkableWaterSources: Folder = Workspace:WaitForChild("DrinkableWaterSources")

--// Per-life state
local IsEating = false
local IsDrinking = false
local Eat_Drink_Delay = false
local generation = 0 -- bumped each spawn so stale loops/connections stop
local connections: { RBXScriptConnection } = {}

local function IsPlayerMoving(): boolean
	return ControlModule:GetMoveVector().Magnitude > 0
end

local function cleanup()
	generation += 1
	IsEating, IsDrinking = false, false
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	ContextActionService:UnbindAction("Eat/Drink")
end

local function initialize()
	cleanup()
	local myGen = generation

	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid")
	if not hum then
		warn("mechanics: invalid character")
		return
	end

	local MovementController = Knit.GetController("MovementController")
	local CombatService = Knit.GetService("CombatService")

	-- ===== UI =====
	local MechanicsUi = starterGui:WaitForChild("MechanicsUI", 5)
	if not MechanicsUi then
		return
	end
	local staminaProgress = MechanicsUi:WaitForChild("Background"):WaitForChild("Progress")
	local MechanicToggleFrame = MechanicsUi:WaitForChild("MechanicToggleFrame")
	local WalkLabel = MechanicToggleFrame:WaitForChild("Walk")
	local SprintLabel = MechanicToggleFrame:WaitForChild("Sprint")

	local ScreenGui = starterGui:WaitForChild("Menu", 5)
	local statsFrame = ScreenGui and ScreenGui:WaitForChild("Frame")
	local attackLabel = statsFrame and statsFrame:WaitForChild("Attack")

	local statsFolder = player:WaitForChild("PlayerStats", 5)
	local staminaValue = statsFolder and statsFolder:WaitForChild("Stamina")

	-- Gait-style labels reflect the MovementController (which owns Z/X toggles).
	WalkLabel.Text = MovementController:GetWalkingStyle()
	SprintLabel.Text = MovementController:GetRunningStyle()
	table.insert(connections, MovementController.StylesChanged:Connect(function(walkStyle, runStyle)
		WalkLabel.Text = walkStyle
		SprintLabel.Text = runStyle
	end))

	-- Stamina bar
	if staminaValue then
		table.insert(connections, staminaValue.Changed:Connect(function()
			local tw = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(staminaProgress, tw, { Size = UDim2.new(1, 0, staminaValue.Value, 0) }):Play()
		end))
	end

	-- Attack (MB1) -> single round-trip to CombatService.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			CombatService:Attack():andThen(function(dmg)
				if attackLabel then
					attackLabel.Text = "Attack: " .. string.format("%.2f", dmg)
				end
			end)
		end
	end))

	-- ===== Eat / Drink (gated through the state system) =====
	task.spawn(function()
		FoodWaterCycle.FoodWaterVariable_Initialise(
			char,
			FoodWaterCycle.FoodWaterCycle_Stats["ThirstMax"],
			FoodWaterCycle.FoodWaterCycle_Stats["HungerMax"]
		)

		local Humanoid = char:WaitForChild("Humanoid")
		local FoodWaterDetector = char:WaitForChild("FoodWaterDetector")
		local Animator = Humanoid:WaitForChild("Animator")
		local E, D = script:WaitForChild("Eat"), script:WaitForChild("Drink")
		local EatAnim: AnimationTrack = Animator:LoadAnimation(E)
		local DrinkAnim: AnimationTrack = Animator:LoadAnimation(D)
		EatAnim.Priority, DrinkAnim.Priority = Enum.AnimationPriority.Action, Enum.AnimationPriority.Action

		ContextActionService:BindActionAtPriority("Eat/Drink", function(_, inputState)
			if inputState == Enum.UserInputState.Begin and not Eat_Drink_Delay then
				if EatAnim.IsPlaying or DrinkAnim.IsPlaying then
					return
				end

				local Character = player.Character
				local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
				if not HRP then
					return
				end

				local DetectionParams = OverlapParams.new()
				DetectionParams.FilterDescendantsInstances = { HerbivoreFoodSources, DrinkableWaterSources }
				DetectionParams.FilterType = Enum.RaycastFilterType.Include
				local found = Workspace:GetPartsInPart(FoodWaterDetector, DetectionParams)

				for _, v in found do
					local canEat = v:GetAttribute("HerbivoreFood")
						and not IsPlayerMoving()
						and v:GetAttribute("Withered") == false
						and Character:GetAttribute("Hunger") ~= 100
						and not IsEating
					local canDrink = v:GetAttribute("DrinkableWaterSource")
						and not IsPlayerMoving()
						and Character:GetAttribute("Thirst") ~= 100

					if canEat then
						-- Ask the state system first — rejected while Run/Sprint.
						local ok = MovementController:RequestAction("Eat")
						if not ok then
							break
						end
						IsEating = true
						EatAnim:AdjustSpeed(1)
						EatAnim:Play()
						repeat
							FoodQuantity:FireServer(v, FoodDecayRate)
							task.wait(FoodDecayInterval)
						until not MovementController:IsActionActive("Eat")
							or v:GetAttribute("Withered") == true
							or Character:GetAttribute("Hunger") == 100
						IsEating = false
						MovementController:ClearAction()
						EatAnim:Stop()
						EatAnim:AdjustSpeed(-1)
						EatAnim:Play()
						task.wait(EatAnim.Length)
						EatAnim:Stop()
						Eat_Drink_Delay = true
						task.delay(FoodDecayInterval, function()
							Eat_Drink_Delay = false
						end)
						break
					elseif canDrink then
						local ok = MovementController:RequestAction("Drink")
						if not ok then
							break
						end
						IsDrinking = true
						DrinkAnim:AdjustSpeed(1)
						DrinkAnim:Play()
						repeat
							task.wait()
						until not MovementController:IsActionActive("Drink")
							or Character:GetAttribute("Thirst") == 100
						IsDrinking = false
						MovementController:ClearAction()
						DrinkAnim:Stop()
						DrinkAnim:AdjustSpeed(-1)
						DrinkAnim:Play()
						task.wait(DrinkAnim.Length)
						DrinkAnim:Stop()
						Eat_Drink_Delay = true
						task.delay(FoodDecayInterval, function()
							Eat_Drink_Delay = false
						end)
						break
					end
				end
			elseif inputState == Enum.UserInputState.End then
				-- Releasing E stops eating/drinking; clearing the action lets the
				-- repeat loops above exit.
				IsEating, IsDrinking = false, false
				if MovementController:IsActionActive("Eat") or MovementController:IsActionActive("Drink") then
					MovementController:ClearAction()
				end
			end
		end, false, 2, Enum.KeyCode.E)

		-- Hunger / thirst decay. Stops when this life ends (generation bump).
		while task.wait(FoodWaterCycle_Interval) do
			if generation ~= myGen then
				break
			end
			if char:GetAttribute("Thirst") and char:GetAttribute("Hunger") then
				local thirstRate = if IsDrinking
					then FoodWaterCycle.FoodWaterCycle_Stats["ThirstRegenRate"]
					else FoodWaterCycle.FoodWaterCycle_Stats["ThirstDecayRate"]
				char:SetAttribute("Thirst", FoodWaterCycle.FoodWaterVariable_Change(char:GetAttribute("Thirst"), thirstRate))

				local hungerRate = if IsEating
					then FoodWaterCycle.FoodWaterCycle_Stats["HungerRegenRate"]
					else FoodWaterCycle.FoodWaterCycle_Stats["HungerDecayRate"]
				char:SetAttribute("Hunger", FoodWaterCycle.FoodWaterVariable_Change(char:GetAttribute("Hunger"), hungerRate))

				if char:GetAttribute("Hunger") == 0 then
					HealthModifier:FireServer(Humanoid, FoodWaterCycle.FoodWaterCycle_Stats["HungerHealthDecay"])
				end
				if char:GetAttribute("Thirst") == 0 then
					HealthModifier:FireServer(Humanoid, FoodWaterCycle.FoodWaterCycle_Stats["ThirstHealthDecay"])
				end
			end
		end
	end)

	-- ===== HUD + footsteps =====
	local guiFolder = ReplicatedStorage:FindFirstChild("GUI")
	if guiFolder and guiFolder:FindFirstChild("HUD") and script:FindFirstChild("HUDMasterScript")
		and not script.HUDMasterScript:FindFirstChild("HUD")
	then
		script.HUDMasterScript.Enabled = false
		local HUDClone: ScreenGui = guiFolder.HUD:Clone()
		local HUDMasterScriptClone = script.HUDMasterScript:Clone()
		script.HUDMasterScript:Destroy()
		HUDMasterScriptClone.Parent = script
		HUDClone.Parent = HUDMasterScriptClone
		HUDMasterScriptClone.Enabled = true
	elseif script:FindFirstChild("HUDMasterScript") then
		script.HUDMasterScript.Enabled = true
	end

	if script:FindFirstChild("FootstepSFXClient") then
		script.FootstepSFXClient.Enabled = true
	end

	ReplicateSounds:FireServer(char)

	print("mechanics: client systems initialized")
end

-- Wait for Knit, then init on every spawn.
Knit.OnStart():andThen(function()
	local SpawnService = Knit.GetService("SpawnService")
	SpawnService.Spawned:Connect(initialize)

	-- Handle the case where we are already spawned when this connects.
	if player:GetAttribute("CharacterName") and player.Character then
		initialize()
	end
end)
