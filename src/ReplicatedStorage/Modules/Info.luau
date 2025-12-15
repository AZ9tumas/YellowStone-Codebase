return {
	["Horsie"] = {
		["Male"] = {
			["IdleSpeed"] = 0,
			["WalkSpeed"] = 15,
			["TrotSpeed"] = 28,
			["RunSpeed"] = 42,
			["SprintSpeed"] = 55,

			["MaxStamina"] = 100,
			["RunStaminaDrain"] = 8,
			["SprintStaminaDrain"] = 25,

			["TrotStaminaGain"] = 5,
			["WalkStaminaGain"] = 10,
			["IdleStaminaGain"] = 15,

			-- When low on health (below threshold), max reduction in speed (penalty).
			["MaxHealthSpeedPenalty"] = 0.15,
			["StaminaPenaltyThreshold"] = 0.5,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 25,
			["Deceleration"] = 10,

			-- Turning Configuration (Heavier feel)
			["BaseTurnRate"] = 4.5,        -- Slower turning circle when stopped
			["TurnSpeedDecay"] = 0.05,      -- Speed reduces turn ability significantly
			["TurnBrakeSensitivity"] = 3.0, -- Brakes hard when trying to turn sharp (no implementation yet)

			["MaxTiltAngle"] = 20,
			["TiltSensitivity"] = 0.8,
			["TiltSpeed"] = 2,

			["AttackDamage"] = 10,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2,

			["Animations"] = {
				["Idle"] = "rbxassetid://136029428239739",
				["Walk"] = "rbxassetid://120913580241056",
				["Trot"] = "rbxassetid://110236947455051",
				["Run"] = "rbxassetid://105596983928158",
				["Sprint"] = "rbxassetid://138964694481815",
			}
		},
		["Female"] = {
			["IdleSpeed"] = 0,
			["WalkSpeed"] = 15,
			["TrotSpeed"] = 28,
			["RunSpeed"] = 40,
			["SprintSpeed"] = 52,

			["MaxStamina"] = 120,
			["RunStaminaDrain"] = 8,
			["SprintStaminaDrain"] = 25,

			["TrotStaminaGain"] = 6,
			["WalkStaminaGain"] = 12,
			["IdleStaminaGain"] = 18,

			["MaxHealthSpeedPenalty"] = 0.15,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 25,
			["Deceleration"] = 10,

			-- Turning Configuration (Agile feel)
			["BaseTurnRate"] = 4.2,        -- Sharper turning circle when stopped
			["TurnSpeedDecay"] = 0.07,     -- Maintains better turning at high speeds
			["TurnBrakeSensitivity"] = 2.0, -- Doesn't lose as much speed on turns

			["MaxTiltAngle"] = 20,
			["TiltSensitivity"] = 0.8,
			["TiltSpeed"] = 2,

			["AttackDamage"] = 10,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2,

			["Animations"] = {
				["Idle"] = "rbxassetid://123456791",
				["Walk"] = "rbxassetid://123456792",
				["Trot"] = "rbxassetid://123456793",
				["Run"] = "rbxassetid://123456794",
				["Sprint"] = "rbxassetid://123456795",
			}
		}
	},

	["MuleDeer"] = {
		["Male"] = {
			["IdleSpeed"] = 0,
			["WalkSpeed"] = 15,
			["TrotSpeed"] = 28,
			["RunSpeed"] = 42,
			["SprintSpeed"] = 55,

			["MaxStamina"] = 100,
			["RunStaminaDrain"] = 8,
			["SprintStaminaDrain"] = 25,

			["TrotStaminaGain"] = 5,
			["WalkStaminaGain"] = 10,
			["IdleStaminaGain"] = 15,

			-- When low on health (below threshold), max reduction in speed (penalty).
			["MaxHealthSpeedPenalty"] = 0.15,
			["StaminaPenaltyThreshold"] = 0.5,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 25,
			["Deceleration"] = 10,

			["BaseTurnRate"] = 3.5,        -- Slower turning circle when stopped
			["TurnSpeedDecay"] = 0.1,      -- Speed reduces turn ability significantly
			["TurnBrakeSensitivity"] = 3.0, -- Brakes hard when trying to turn sharp (not implemented yet)

			["MaxTiltAngle"] = 20,
			["TiltSensitivity"] = 0.8,
			["TiltSpeed"] = 2,

			["AttackDamage"] = 10,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2,

			["Animations"] = {
				["Idle"] = "rbxassetid://122354167240358",
				["Walk"] = "rbxassetid://78416478020514",
				["Trot"] = "rbxassetid://115522221508138",
				["Run"] = "rbxassetid://130969140443746",
				["Sprint"] = "rbxassetid://137863725830650",
			}
		},
		["Female"] = {
			["IdleSpeed"] = 0,
			["WalkSpeed"] = 15,
			["TrotSpeed"] = 28,
			["RunSpeed"] = 40,
			["SprintSpeed"] = 52,

			["MaxStamina"] = 120,
			["RunStaminaDrain"] = 8,
			["SprintStaminaDrain"] = 25,

			["TrotStaminaGain"] = 6,
			["WalkStaminaGain"] = 12,
			["IdleStaminaGain"] = 18,

			["MaxHealthSpeedPenalty"] = 0.15,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 25,
			["Deceleration"] = 10,

			-- Turning Configuration (Agile feel)
			["BaseTurnRate"] = 4.2,        -- Sharper turning circle when stopped
			["TurnSpeedDecay"] = 0.07,     -- Maintains better turning at high speeds
			["TurnBrakeSensitivity"] = 2.0, -- Doesn't lose as much speed on turns

			["MaxTiltAngle"] = 20,
			["TiltSensitivity"] = 0.8,
			["TiltSpeed"] = 2,

			["AttackDamage"] = 10,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2,

			["Animations"] = {
				["Idle"] = "rbxassetid://123456791",
				["Walk"] = "rbxassetid://123456792",
				["Trot"] = "rbxassetid://123456793",
				["Run"] = "rbxassetid://123456794",
				["Sprint"] = "rbxassetid://123456795",
			}
		}
	}
}