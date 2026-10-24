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

			-- Swimming (see Movement/Swimming). In deep water the server maps
			-- Idle -> SwimIdle, Walk/Trot -> Swim, Run/Sprint -> SwimFast.
			["SwimIdleSpeed"] = 0,
			["SwimSpeed"] = 10,
			["SwimFastSpeed"] = 20,

			["MaxStamina"] = 100,
			["RunStaminaDrain"] = 0.5,
			["SprintStaminaDrain"] = 1,

			["TrotStaminaGain"] = 4,
			["WalkStaminaGain"] = 7,
			["IdleStaminaGain"] = 15,

			["SwimStaminaDrain"] = 0.5,
			["SwimFastStaminaDrain"] = 1.5, -- below the penalty threshold it slows toward SwimSpeed
			["SwimIdleStaminaGain"] = 1,    -- treading water rests a little

			-- When low on health (below threshold), max reduction in speed (penalty).
			["MaxHealthSpeedPenalty"] = 0.15,
			["StaminaPenaltyThreshold"] = 0.5,
			["HealthPenaltyThreshold"] = 0.5,

			["Acceleration"] = 120,
			["Deceleration"] = 200,

			["BaseTurnRate"] = 6,        -- turning circle when stopped
			["IdleTurnRate"] = 7,        -- Turning circle when idle (overrides BaseTurnRate)
			["WalkTurnRate"] = 4,         -- Turning circle when walking
			["TrotTurnRate"] = 5,         -- Turning circle when trotting
			["RunTurnRate"] = 4,          -- Turning circle when running
			["SprintTurnRate"] = 4,       -- Turning circle when sprinting (overrides BaseTurnRate)
			["SwimIdleTurnRate"] = 3,     -- treading water
			["SwimTurnRate"] = 2.5,       -- swimming
			["SwimFastTurnRate"] = 2,     -- swimming hard

			-- Demanded-turn-angle (deg) -> speed multiplier, linearly interpolated
			-- (see MovementMath.EvaluateTurnBrakeCurve). The wolf plants hard for
			-- sharp turns but never fully stops.
			["TurnBrakeCurve"] = {
				{ Angle = 0,   Brake = 1 },
				{ Angle = 10,  Brake = 0.9 },    -- micro-corrections are free
				{ Angle = 45,  Brake = 0.6 },
				{ Angle = 90,  Brake = 0.25 },
				{ Angle = 180, Brake = 0.2 },
			},

			["MaxTiltAngle"] = 30,
			["TiltSensitivity"] = 0.5,
			["TiltSpeed"] = 2,

			-- Procedural body language (see Movement/BodyArticulation). Chains
			-- are processed in order; a chain may only Follow one declared
			-- before it. Bank replaces the whole-body tilt above for this
			-- creature (MovementController zeroes it when Bank is present).
			["BodyArticulation"] = {
				["SpeedRef"] = "WalkSpeed", -- fully on at a trot
				["IdleScale"] = 0.25,       -- still articulates a little when turning on the spot
				["Chains"] = {
					{ -- rear falls behind the chest, then swings through
						["Name"] = "Spine",
						["Bones"] = { "Back.001", "Back.002", "Lowe Back" },
						["Weights"] = { 0.25, 0.35, 0.40 }, -- lumbar bends most
						["MaxYaw"] = 45,
						["Frequency"] = 2.5,
						["Damping"] = 0.8,   -- < 1: slight overshoot = follow-through
					},
					{ -- head looks where the player is steering before the body gets there
						["Name"] = "Neck",
						["Bones"] = { "Neck.001", "Neck.002" },
						["Weights"] = { 0.45, 0.55 },
						["MaxYaw"] = 40,
						["Frequency"] = 6.0, -- must beat the body's turn rate or there is no lead
						["Damping"] = 1.0,   -- no overshoot on the head
						["TracksTarget"] = true,
					},
					{ -- trails the spine with more lag and a looser spring
						["Name"] = "Tail",
						["Bones"] = { "Tail.001", "Tail.002", "Tail.003", "Tail.004", "Tail.005", "Tail.006", "Tail.007" },
						["MaxYaw"] = 55,
						["Frequency"] = 1.8,
						["Damping"] = 1,
						["Follows"] = "Spine",
					},
				},
				["Bank"] = {
					["Bone"] = "Chest",
					["MaxRoll"] = 18,
					["Frequency"] = 2.5,
					["Damping"] = 0.9,
				},
			},

			-- Terrain foot planting (see Movement/LegIK). Every distance is a
			-- fraction of the leg's own rest length and the paw's ground
			-- clearance is read off the rig, so there is nothing here to
			-- re-tune if the creature is rescaled.
			["LegIK"] = {
				["Legs"] = {
					{ ["Name"] = "FrontLeft",  ["Upper"] = "Shoulder.L", ["Mid"] = "Forearm.L", ["Foot"] = "Front Paw.L" },
					{ ["Name"] = "FrontRight", ["Upper"] = "Shoulder.R", ["Mid"] = "Forearm.R", ["Foot"] = "Front Paw.R" },
					{ ["Name"] = "BackLeft",   ["Upper"] = "Thigh.L",    ["Mid"] = "Leg.L",     ["Foot"] = "Back Paw.L" },
					{ ["Name"] = "BackRight",  ["Upper"] = "Thigh.R",    ["Mid"] = "Leg.R",     ["Foot"] = "Back Paw.R" },
				},
				-- Ancestor of the whole body, so lowering it lets an
				-- over-reaching leg touch down instead of stretching straight.
				["BodyBone"] = "Body IK CTRL",
			},

			-- Attention (see Movement/HeadLook). Composes with the Neck chain
			-- above: that leads into a TURN, this aims at a THING.
			["HeadLook"] = {
				["Bones"] = { "Neck.002", "Head" },
				["Weights"] = { 0.4, 0.6 }, -- head carries more than the neck
				["Aim"] = "Nose",           -- marks "forward" without assuming a bone axis
				["MaxYaw"] = 55,
				["MaxPitch"] = 35,
				["Response"] = 6,
				["Radius"] = 60,
				["Cone"] = 120,
			},

			-- Interruptible sharp turns (see Movement/TurnInPlace). Authored
			-- clips loop while the demand persists; movement stays available.
			-- To experiment with procedural 180 footwork again, replace its row
			-- with { ["Angle"] = 180, ["Duration"] = 1.6 } (PawStepper is retained).
			["TurnInPlace"] = {
				["MinAngle"] = 90, -- deg: smaller demands use ordinary steering
				-- Most speed kept while a turn clip plays (x WalkSpeed, eased like
				-- the brake curve). The clips plant the paws: 0.05 at a sprint is
				-- ~3.7 studs/s instead of the curve's 14.6, which slid.
				["Brake"] = 0.01,
				-- SpeedMultiplier scales playback, rotation timing and the turn's
				-- rate cap together. 1 = current pace; 1.3 = 30% faster; omitted = 1.
				["Turns"] = {
					{ ["Angle"] = 110,  ["Left"] = "Turn90Left", ["Right"] = "Turn90Right", ["SpeedMultiplier"] = 1.4 },
					{ ["Angle"] = 210, ["Left"] = "Turn180Left", ["Right"] = "Turn180Right", ["SpeedMultiplier"] = 1.3 },
				},
			},

			["Swimming"] = {
				["FloatDepth"] = 0.3, -- root this fraction of its standing height under the surface
				["Buoyancy"] = 2,     -- 1/s: how fast the body settles to that height
			},

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

				-- Placeholders: the Idle / Walk / Trot clips until swim clips exist.
				["SwimIdle"] = "rbxassetid://78565435936342",
				["Swim"] = "rbxassetid://114896327132532",
				["SwimFast"] = "rbxassetid://80974184092808",

				-- Authored turn overlays (TurnInPlace above).
				["Turn90Left"] = "rbxassetid://140093023419940",
				["Turn90Right"] = "rbxassetid://76931076997938",
				["Turn180Left"] = "rbxassetid://101609312038608",
				["Turn180Right"] = "rbxassetid://133302248316884",
			}
		},
	}
}
