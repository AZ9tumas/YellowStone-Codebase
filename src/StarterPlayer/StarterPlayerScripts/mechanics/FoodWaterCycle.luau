local FoodWaterCycle = {

	FoodWaterCycle_Stats = {

		["HungerDecayRate"] = -0.6,
		["ThirstDecayRate"] = -0.9, 
		["HungerRegenRate"] = 1,
		["ThirstRegenRate"] = 1,
		["HungerMax"] = 100,
		["ThirstMax"] = 100,
		["HungerHealthDecay"] = -2,
		["ThirstHealthDecay"] = -6

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