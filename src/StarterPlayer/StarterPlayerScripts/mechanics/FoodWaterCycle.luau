local FoodWaterCycle = {

	FoodWaterCycle_Stats = {

		["HungerDecayRate"] = -0.7,
		["ThirstDecayRate"] = -0.4, 
		["HungerRegenRate"] = 2,
		["ThirstRegenRate"] = 4,
		["HungerMax"] = 100,
		["ThirstMax"] = 100,
		["HungerHealthDecay"] = -2,
		["ThirstHealthDecay"] = -3

	},
}

function FoodWaterCycle.FoodWaterVariable_Initialise(char: Model,HungerMax,ThirstMax)
	if char:GetAttribute("Hunger") then
		char:SetAttribute("Hunger",HungerMax)
	end
	if char:GetAttribute("Thirst") then
		char:SetAttribute("Thirst",ThirstMax)
	end
end

function FoodWaterCycle.FoodWaterVariable_Change(VariableOfChange: number,ChangeFactor: number)
	local NewVariable = math.clamp(VariableOfChange + (ChangeFactor),0,100)
	return NewVariable
end

return FoodWaterCycle