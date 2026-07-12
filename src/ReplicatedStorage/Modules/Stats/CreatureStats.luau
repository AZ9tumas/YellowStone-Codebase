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

			-- Demanded-turn-angle (deg) -> speed multiplier, linearly interpolated
			-- (see MovementMath.EvaluateTurnBrakeCurve). A heavy horse always keeps
			-- some momentum through a turn, so the curve never reaches 0.
			["TurnBrakeCurve"] = {
				{ Angle = 0,   Brake = 1 },
				{ Angle = 5,   Brake = 1 },    -- micro-corrections are free
				{ Angle = 40,  Brake = 0.45 },
				{ Angle = 75,  Brake = 0.25 },
				{ Angle = 180, Brake = 0.25 },
			},

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

			["BaseTurnRate"] = 10,        -- turning circle when stopped
			["IdleTurnRate"] = 10,        -- Turning circle when idle (overrides BaseTurnRate)
			["WalkTurnRate"] = 6,         -- Turning circle when walking
			["TrotTurnRate"] = 6,         -- Turning circle when trotting
			["RunTurnRate"] = 4,          -- Turning circle when running
			["SprintTurnRate"] = 4,       -- Turning circle when sprinting (overrides BaseTurnRate)
			["SwimmingTurnRate"] = 4,     -- Turning circle when swimming

			-- Demanded-turn-angle (deg) -> speed multiplier, linearly interpolated
			-- (see MovementMath.EvaluateTurnBrakeCurve). An agile deer sheds speed
			-- on sharp turns but never fully stops.
			["TurnBrakeCurve"] = {
				{ Angle = 0,   Brake = 1 },
				{ Angle = 5,   Brake = 1 },    -- micro-corrections are free
				{ Angle = 45,  Brake = 0.42 },
				{ Angle = 75,  Brake = 0.28 },
				{ Angle = 180, Brake = 0.28 },
			},

			["MaxTiltAngle"] = 30,
			["TiltSensitivity"] = 0.5,
			["TiltSpeed"] = 2,

			-- Terrain Alignment
			["TerrainAlignmentEnabled"] = true,
			["TerrainAlignmentSpeed"] = 6,
			["MaxTerrainPitch"] = 45,
			["MaxTerrainRoll"] = 30,
			["MaxTerrainAngle"] = 50, -- Hard cap on overall terrain tilt (deg)
			["MaxClimbAngle"] = 45, -- Forward slope past which the creature cannot climb (deg)
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
	},

	["Wolf"] = {
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

			["BaseTurnRate"] = 10,        -- turning circle when stopped
			["IdleTurnRate"] = 10,        -- Turning circle when idle (overrides BaseTurnRate)
			["WalkTurnRate"] = 6,         -- Turning circle when walking
			["TrotTurnRate"] = 6,         -- Turning circle when trotting
			["RunTurnRate"] = 4,          -- Turning circle when running
			["SprintTurnRate"] = 4,       -- Turning circle when sprinting (overrides BaseTurnRate)
			["SwimmingTurnRate"] = 4,     -- Turning circle when swimming

			-- Demanded-turn-angle (deg) -> speed multiplier, linearly interpolated
			-- (see MovementMath.EvaluateTurnBrakeCurve). The wolf plants for sharp
			-- turns: at 120°+ the brake reaches 0, so a demanded reversal stops it
			-- completely and resolves as a turn-in-place (The-Isle-style).
			["TurnBrakeCurve"] = {
				{ Angle = 0,   Brake = 1 },
				{ Angle = 10,  Brake = 1 },    -- micro-corrections are free
				{ Angle = 45,  Brake = 0.6 },
				{ Angle = 90,  Brake = 0.2 },
				{ Angle = 120, Brake = 0 },
				{ Angle = 180, Brake = 0 },
			},

			-- Turn-in-place (requires the Turn90*/Turn180* animations below).
			["TurnInPlace"] = {
				["MaxSpeed"] = 2.5, -- studs/s: at/below this actual speed the turn happens in place
				["MinAngle"] = 55,  -- deg input/facing gap that starts a turn-in-place
				["Angle180"] = 120, -- deg gap at/above which the 180 animation is used
				["ExitAngle"] = 12, -- deg gap below which the turn is considered finished
			},

			["MaxTiltAngle"] = 30,
			["TiltSensitivity"] = 0.5,
			["TiltSpeed"] = 2,

			-- Terrain Alignment
			["TerrainAlignmentEnabled"] = true,
			["TerrainAlignmentSpeed"] = 6,
			["MaxTerrainPitch"] = 45,
			["MaxTerrainRoll"] = 30,
			["MaxTerrainAngle"] = 50, -- Hard cap on overall terrain tilt (deg)
			["MaxClimbAngle"] = 45, -- Forward slope past which the creature cannot climb (deg)
			["TerrainRaycastDistance"] = 35,

			["AttackDamage"] = 30,
			["StaminaAttackCost"] = 0.2,
			["HealthAttackCost"] = 0.2,

			["Animations"] = {
				["Idle"] = "rbxassetid://78565435936342",
				["Walk"] = "rbxassetid://114896327132532",
				["Trot"] = "rbxassetid://80974184092808",
				["Run"] = "rbxassetid://102193505149804",
				["Sprint"] = "rbxassetid://128343239222496",

				-- Turn-in-place one-shots (names match MovementStates turn states).
				["Turn90Left"] = "rbxassetid://140093023419940",
				["Turn90Right"] = "rbxassetid://76931076997938",
				["Turn180Left"] = "rbxassetid://101609312038608",
				["Turn180Right"] = "rbxassetid://133302248316884",
			}
		},
	}
}
