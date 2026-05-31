--// Services
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Remotes
local Remotes: Folder = ReplicatedStorage.Remotes
local FoodQuantity: RemoteEvent = Remotes.FoodQuantityRemote

--// Variables
local HerbivoreFoodSources: Folder = Workspace.HerbivoreFoodSources


local FoodQuantity_RegenInterval = 15 --\\ Amount of seconds between each regen cycle
local FoodQuantity_RegenRate = 8 --\\ Amount of food added each regen cycle
local WitheredFoodQuantity_RegenRate = 4 --\\ Amount of food added each regen cycle whilst afflicted with the withered status

local WitheredStatus_Length = 30 --\\ Amount of seconds the withered status lasts for
local StuntedGrowth_Length = 30 --\\ Amount of seconds the stunted growth status lasts for

local RecentlyEaten_Timer = 7


--// Functions
function LinearInterpolation(StartValue: number, EndValue: number, Percent: number): number
	if Percent <= 1 and Percent >= 0 then
		return StartValue + (EndValue - StartValue) * Percent
	else
		warn("Percent must be between 0 and 1")
	end
end


function WitheredStatus_Reset(FoodSource: MeshPart,Berries: MeshPart,LargeLeaves: MeshPart)
	FoodSource:SetAttribute("Withered",false)
	FoodSource:SetAttribute("StuntedGrowth",true)
	Berries.Transparency = 0
	LargeLeaves.Transparency = 0
	task.delay(StuntedGrowth_Length,function()
		FoodSource:SetAttribute("StuntedGrowth",false)
	end)
end


function FoodQuantity_Change( player, FoodSource: MeshPart, QuantityDecay: number)
	
	if FoodSource:GetAttribute("FoodValue") and FoodSource:GetAttribute("Withered") == false then
		FoodSource:SetAttribute("FoodValue", math.clamp(FoodSource:GetAttribute("FoodValue") - QuantityDecay,0,100))
		
		if FoodSource:GetAttribute("FoodValue") == 0 then
			local Edible: Model = FoodSource.Parent:FindFirstChild("Edible",true)
			print(Edible, "edible here")
			local Berries: MeshPart,LargeLeaves: MeshPart = Edible:FindFirstChild("Berries",true),Edible:FindFirstChild("LargeLeaves",true)
			print(Berries,Edible, "berries and edible here")
			if Berries and LargeLeaves then
				Berries.Transparency = 1
				LargeLeaves.Transparency = 0.1
			end
			FoodSource:SetAttribute("Withered",true)
			task.delay(WitheredStatus_Length,function()
				
				WitheredStatus_Reset(FoodSource,Berries,LargeLeaves)
			end)
		end
		
		RecentlyEaten_Timer = 7
		
		if not FoodSource:GetAttribute("RecentlyEaten") then
			FoodSource:SetAttribute("RecentlyEaten",true)
			coroutine.wrap(function()
				while RecentlyEaten_Timer > 0 do
					RecentlyEaten_Timer -= 1
					task.wait(1)
				end
				FoodSource:SetAttribute("RecentlyEaten",false)
			end)()

		end
		
	end
end


function FoodQuantity_RegenLoop()
	while task.wait(FoodQuantity_RegenInterval) do
		print("print statement")
		for _,v in HerbivoreFoodSources:GetChildren() do
			
			local FoodPart = v:FindFirstChild("FoodPart",true)
			if FoodPart and FoodPart:GetAttribute("FoodValue") and FoodPart:GetAttribute("Withered") == false and FoodPart:GetAttribute("RecentlyEaten") == false then
				if not FoodPart:GetAttribute("StuntedGrowth") then
					FoodPart:SetAttribute("FoodValue", math.clamp(FoodPart:GetAttribute("FoodValue") + FoodQuantity_RegenRate,0,100))
				else
					FoodPart:SetAttribute("FoodValue", math.clamp(FoodPart:GetAttribute("FoodValue") + WitheredFoodQuantity_RegenRate,0,100))
				end
			end
		end
	end
end

--// Connections/Looping
local FoodQuantity_Connection: RBXScriptConnection = FoodQuantity.OnServerEvent:Connect(FoodQuantity_Change)

for _,v in HerbivoreFoodSources:GetChildren() do
	local FoodPart: MeshPart = v:FindFirstChild("FoodPart",true)
	local Edible: Model = v:FindFirstChild("Edible",true)
	
	FoodPart:GetAttributeChangedSignal("FoodValue"):Connect(function()
		if FoodPart:GetAttribute("FoodValue") == 100 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,1))
		elseif FoodPart:GetAttribute("FoodValue") >= 90 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.9))
		elseif FoodPart:GetAttribute("FoodValue") >= 80 and FoodPart:GetAttribute("FoodValue") < 89 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.8))
		elseif FoodPart:GetAttribute("FoodValue") >= 70 and FoodPart:GetAttribute("FoodValue") < 79 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.7))
		elseif FoodPart:GetAttribute("FoodValue") >= 60 and FoodPart:GetAttribute("FoodValue") < 69 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.6))
		elseif FoodPart:GetAttribute("FoodValue") >= 50 and FoodPart:GetAttribute("FoodValue") < 59 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.5))
		elseif FoodPart:GetAttribute("FoodValue") >= 40 and FoodPart:GetAttribute("FoodValue") < 49 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.4))
		elseif FoodPart:GetAttribute("FoodValue") >= 30 and FoodPart:GetAttribute("FoodValue") < 39 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.3))
		elseif FoodPart:GetAttribute("FoodValue") >= 20 and FoodPart:GetAttribute("FoodValue") < 29 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.2))
		elseif FoodPart:GetAttribute("FoodValue") >= 10 and FoodPart:GetAttribute("FoodValue") < 19 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0.1))
		elseif FoodPart:GetAttribute("FoodValue") == 0 then
			Edible:ScaleTo(LinearInterpolation(0.6,1,0))
		end
		
		
	end)
end

coroutine.wrap(FoodQuantity_RegenLoop)()