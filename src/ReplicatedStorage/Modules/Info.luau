return {
	["Horsie"] = {
		["Male"] = {
			["WalkSpeed"] = 15,
			["TrotSpeed"] = 28,
			["RunSpeed"] = 42,
			["SprintSpeed"] = 55,

			["MaxStamina"] = 100,
			["RunStaminaDrain"] = 8,
			["SprintStaminaDrain"] = 25,

			["TrotStaminaGain"] = 5,
			["WalkStaminaGain"] = 10,

			-- When low on health (below threshold), max reduction in speed (penalty).
			["MaxHealthSpeedPenalty"] = 0.15,
			["StaminaPenaltyThreshold"] = 0.5,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 25,
			["Deceleration"] = 10,

			["AttackDamage"] = 10,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2
		},
		["Female"] = {
			["WalkSpeed"] = 15,
			["TrotSpeed"] = 28,
			["RunSpeed"] = 40,
			["SprintSpeed"] = 52,

			["MaxStamina"] = 120,
			["RunStaminaDrain"] = 8,
			["SprintStaminaDrain"] = 25,

			["TrotStaminaGain"] = 6,
			["WalkStaminaGain"] = 12,

			["MaxHealthSpeedPenalty"] = 0.15,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 25,
			["Deceleration"] = 10,

			["AttackDamage"] = 10,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2
		}
	}
}
