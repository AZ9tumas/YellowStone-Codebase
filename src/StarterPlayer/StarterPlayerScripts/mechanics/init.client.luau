--// Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local starterGui = player.PlayerGui
--// Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HealthModifier: RemoteEvent = Remotes:WaitForChild("HealthModifier")
local FoodQuantity: RemoteEvent = Remotes:WaitForChild("FoodQuantityRemote")

-- Modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local packets = require(modules:WaitForChild("Packets"))
local MovementController = require(script.MovementController)
local FoodWaterCycle = require(script.FoodWaterCycle)

-- ControlModule for checking player movement input (used for custom movement system)
local ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

--// ChildScripts
local HUDMasterScript = script.HUDMasterScript

-- Variables that need to be re-initialized
local controller = nil
local staminaConnection = nil
local inputConnection = nil
local renderConnection = nil
local attackReturnConnection = nil

-- Food/Water Variables



local FoodWaterCycle_Interval = 1
local IsEating: boolean = false
local IsDrinking: boolean = false

local HerbivoreFoodSources: Folder = Workspace:WaitForChild("HerbivoreFoodSources")
local DrinkableWaterSources: Folder = Workspace:WaitForChild("DrinkableWaterSources")

local FoodDecayInterval = 1 --\\ Amount of seconds between each food value reduction
local FoodDecayRate = 5 --\\ Amount of food removed

local Eat_Drink_Delay = false


-- Helper function to check if player is moving (uses ControlModule for custom movement system)
local function IsPlayerMoving(): boolean
	local moveVector = ControlModule:GetMoveVector()
	return moveVector.Magnitude > 0
end

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
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char
	local hum = char:WaitForChild("Humanoid")
	if not char then return end
	
	-- Check if it's a valid character (e.g. has HumanoidRootPart)
	
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
		print(dmg,"damage var")
		if attackLabel then attackLabel.Text = "Attack: " .. string.format("%.2f", dmg) end
	end)
	
	renderConnection = RunService.RenderStepped:Connect(function(dt)
		if controller then controller:Update(dt) end
	end)
	
	local function FoodWater_Loop()
		
	end
	coroutine.wrap(function()
		FoodWaterCycle.FoodWaterVariable_Initialise(char,FoodWaterCycle.FoodWaterCycle_Stats["ThirstMax"],FoodWaterCycle.FoodWaterCycle_Stats["HungerMax"])
		
		local Humanoid: Humanoid = char:WaitForChild("Humanoid")
		local FoodWaterDetector = char:WaitForChild("FoodWaterDetector")
		local Animator: Animator = Humanoid:WaitForChild("Animator")
		local E,D = script:WaitForChild("Eat"),script:WaitForChild("Drink")
		local EatAnim: AnimationTrack = Animator:LoadAnimation(E)
		local DrinkAnim: AnimationTrack = Animator:LoadAnimation(D)
		EatAnim.Priority,DrinkAnim.Priority = Enum.AnimationPriority.Action,Enum.AnimationPriority.Action
		
		ContextActionService:UnbindAction("Eat/Drink")
		ContextActionService:BindActionAtPriority("Eat/Drink", function(ActionName,InputState,InputType)
			
			if InputState == Enum.UserInputState.Begin and not Eat_Drink_Delay then
				if EatAnim.IsPlaying == true or DrinkAnim.IsPlaying == true then return end
				
				local Character = player.Character
				local HRP: Part = Character:WaitForChild("HumanoidRootPart")
				
				if HRP then
					
					local DetectionParams = OverlapParams.new()
					DetectionParams.FilterDescendantsInstances = {HerbivoreFoodSources,DrinkableWaterSources}
					DetectionParams.FilterType = Enum.RaycastFilterType.Include
					local Food_WaterScan = workspace:GetPartsInPart(FoodWaterDetector,DetectionParams)
					
					for _,v in Food_WaterScan do
						
						if v:GetAttribute("HerbivoreFood") and not IsPlayerMoving() and v:GetAttribute("Withered") == false and Character:GetAttribute("Hunger") ~= 100 and not EatAnim.IsPlaying and IsEating == false then
							print("Food Detected")
							EatAnim:AdjustSpeed(1)
							EatAnim:Play()
							IsEating = true
							repeat
							FoodQuantity:FireServer(v,FoodDecayRate)
							task.wait(FoodDecayInterval) 
							until IsPlayerMoving() or IsEating == false or v:GetAttribute("Withered") == true or Character:GetAttribute("Hunger") == 100
							EatAnim:Stop()
							EatAnim:AdjustSpeed(-1)
							EatAnim:Play()
							task.wait(EatAnim.Length)
							EatAnim:Stop()
							Eat_Drink_Delay = true
							task.delay(FoodDecayInterval,function()
								Eat_Drink_Delay = false
							end)
							break
							
						elseif v:GetAttribute("DrinkableWaterSource") and not IsPlayerMoving() and Character:GetAttribute("Thirst") ~= 100 then
							
							print("WaterDetected")
							DrinkAnim:AdjustSpeed(1)
							DrinkAnim:Play()
							IsDrinking = true
							repeat task.wait() until IsPlayerMoving() or IsDrinking == false or Character:GetAttribute("Thirst") == 100
							DrinkAnim:Stop()
							DrinkAnim:AdjustSpeed(-1)
							DrinkAnim:Play()
							task.wait(DrinkAnim.Length)
							DrinkAnim:Stop()
							Eat_Drink_Delay = true
							task.delay(FoodDecayInterval,function()
								Eat_Drink_Delay = false
							end)
							break
							
						end
						
					end
				end
				
			elseif InputState == Enum.UserInputState.End then
				IsEating,IsDrinking = false,false
			end
			
		end,false,2,Enum.KeyCode.E)
		
		while task.wait(FoodWaterCycle_Interval) do
			if char:GetAttribute("Thirst") and char:GetAttribute("Hunger") then

				if IsDrinking == true then
					char:SetAttribute("Thirst",FoodWaterCycle.FoodWaterVariable_Change(char:GetAttribute("Thirst"),FoodWaterCycle.FoodWaterCycle_Stats["ThirstRegenRate"]))
				else
					char:SetAttribute("Thirst",FoodWaterCycle.FoodWaterVariable_Change(char:GetAttribute("Thirst"),FoodWaterCycle.FoodWaterCycle_Stats["ThirstDecayRate"]))
				end

				if IsEating == true then
					char:SetAttribute("Hunger",FoodWaterCycle.FoodWaterVariable_Change(char:GetAttribute("Hunger"),FoodWaterCycle.FoodWaterCycle_Stats["HungerRegenRate"]))
				else
					char:SetAttribute("Hunger",FoodWaterCycle.FoodWaterVariable_Change(char:GetAttribute("Hunger"),FoodWaterCycle.FoodWaterCycle_Stats["HungerDecayRate"]))
				end

				if char:GetAttribute("Hunger") == 0 then
					HealthModifier:FireServer(Humanoid,FoodWaterCycle.FoodWaterCycle_Stats["HungerHealthDecay"])
				end

				if char:GetAttribute("Thirst") == 0 then
					HealthModifier:FireServer(Humanoid,FoodWaterCycle.FoodWaterCycle_Stats["ThirstHealthDecay"])
				end
				
			end
		end
	end)()       
	
	if ReplicatedStorage:FindFirstChild("GUI"):FindFirstChild("HUD") and script.HUDMasterScript and not script.HUDMasterScript:FindFirstChild("HUD") then
		script.HUDMasterScript.Enabled = false
		local HUDClone: ScreenGui =  ReplicatedStorage.GUI.HUD:Clone()
		local HUDMasterScriptClone = script.HUDMasterScript:Clone()
		print(HUDClone)
		script.HUDMasterScript:Destroy() 
		HUDMasterScriptClone.Parent = script
		HUDClone.Parent = HUDMasterScriptClone
		HUDMasterScript = HUDMasterScriptClone
		HUDMasterScript.Enabled = true
	else
		script.HUDMasterScript.Enabled = true
	end
	print("Client scripts successfully initialized.")
end



packets.initClientScripts.listen(Initialize)