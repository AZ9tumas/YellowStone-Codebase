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

			-- Turning Configuration
			["BaseTurnRate"] = 4.5,
			["TurnSpeedDecay"] = 0.05, --(imo, lower is better)
			["TurnBrakeSensitivity"] = 3.0,

			-- Tilt
			["MaxTiltAngle"] = 20,
			["TiltSensitivity"] = 0.8,
			["TiltSpeed"] = 2,

			-- Terrain Alignment
			["TerrainAlignmentEnabled"] = true,
			["TerrainAlignmentSpeed"] = 3,
			["MaxTerrainPitch"] = 45,
			["MaxTerrainRoll"] = 30,
			["MaxTerrainAngle"] = 40, -- Hard cap on overall terrain tilt (deg)
			["MaxClimbAngle"] = 35, -- Forward slope past which the creature cannot climb (deg)
			["TerrainRaycastDistance"] = 25,

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

			-- Terrain Alignment
			["TerrainAlignmentEnabled"] = true,
			["TerrainAlignmentSpeed"] = 3,
			["MaxTerrainPitch"] = 45,
			["MaxTerrainRoll"] = 30,
			["MaxTerrainAngle"] = 40, -- Hard cap on overall terrain tilt (deg)
			["MaxClimbAngle"] = 35, -- Forward slope past which the creature cannot climb (deg)
			["TerrainRaycastDistance"] = 25,

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
			["WalkSpeed"] = 7,
			["TrotSpeed"] = 16,
			["RunSpeed"] = 42,
			["SprintSpeed"] = 73,

			["MaxStamina"] = 100,
			["RunStaminaDrain"] = 0.5,
			["SprintStaminaDrain"] = 1,

			["TrotStaminaGain"] = 4,
			["WalkStaminaGain"] = 7,
			["IdleStaminaGain"] = 15,

			-- When low on health (below threshold), max reduction in speed (penalty).
			["MaxHealthSpeedPenalty"] = 0.15,
			["StaminaPenaltyThreshold"] = 0.5,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 60,
			["Deceleration"] = 60,

			["BaseTurnRate"] = 10,        -- Slower turning circle when stopped
			["IdleTurnRate"] = 10,        -- Turning circle when idle (overrides BaseTurnRate)
			["WalkTurnRate"] = 8,         -- Turning circle when walking
			["TrotTurnRate"] = 6,         -- Turning circle when trotting
			["RunTurnRate"] = 4,          -- Turning circle when running
			["SprintTurnRate"] = 2,       -- Turning circle when sprinting (overrides BaseTurnRate)
			["SwimmingTurnRate"] = 5,     -- Turning circle when swimming

			["TurnSpeedDecay"] = 0.04,      -- Speed reduces turn ability significantly
			["TurnBrakeSensitivity"] = 2.6, -- Brakes hard when trying to turn sharp

			["MaxTiltAngle"] = 30,
			["TiltSensitivity"] = 0.5,
			["TiltSpeed"] = 2,

			-- Terrain Alignment
			["TerrainAlignmentEnabled"] = true,
			["TerrainAlignmentSpeed"] = 6,
			["MaxTerrainPitch"] = 45,
			["MaxTerrainRoll"] = 30,
			["MaxTerrainAngle"] = 40, -- Hard cap on overall terrain tilt (deg)
			["MaxClimbAngle"] = 35, -- Forward slope past which the creature cannot climb (deg)
			["TerrainRaycastDistance"] = 35,

			["AttackDamage"] = 30,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2,

			["Animations"] = {
				["Idle"] = "rbxassetid://129340490638132",
				["Walk"] = "rbxassetid://97341094250554",
				["Trot"] = "rbxassetid://88285359887554",
				["Run"] = "rbxassetid://128103557572394",
				["Sprint"] = "rbxassetid://112573917060283",
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

			-- Terrain Alignment
			["TerrainAlignmentEnabled"] = true,
			["TerrainAlignmentSpeed"] = 3,
			["MaxTerrainPitch"] = 45,
			["MaxTerrainRoll"] = 30,
			["MaxTerrainAngle"] = 40, -- Hard cap on overall terrain tilt (deg)
			["MaxClimbAngle"] = 35, -- Forward slope past which the creature cannot climb (deg)
			["TerrainRaycastDistance"] = 25,

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