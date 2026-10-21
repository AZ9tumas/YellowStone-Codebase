--[[
	MovementStates

	Single source of truth for every movement state. Pure data — no behaviour,
	no Roblox instances. Two orthogonal categories:

	  * GAIT   — locomotion stages (Idle/Walk/Trot/Run/Sprint). The visual gait
	             is DERIVED every frame from the creature's measured velocity
	             (Stats.ResolveGaitFromVelocity) — speed bands with hysteresis.
	             There is deliberately NO transition graph: a gait is a function
	             of the current speed, so it can never desync. In water the
	             swim ladder (SwimIdle/Swim/SwimFast) replaces it.

	  * ACTION — discrete, guarded, interruptible activities (Eat/Drink/Fight/
	             Rest, and anything added later). One action at a time. An
	             action is requested explicitly and may be rejected.

	Adding a state = add one row here. Restrictions stay declarative:
	  * blockedGaits[gait] = true  -> cannot start the action from that gait
	                                  (the "no eat/drink while sprinting" rule)
	  * guard(context) -> boolean  -> optional predicate for anything
	                                  blockedGaits can't express (stamina,
	                                  airborne, cooldown...). Omit when unused.
]]

local MovementStates = {}

export type Category = "Gait" | "Action"

export type StateDefinition = {
	category: Category,
	animation: string,
	-- Action-only:
	swimming: boolean?, -- Gait-only: a rung of the swim ladder
	freezesMovement: boolean?, -- locomotion is suppressed while this action runs
	abortOnMove: boolean?, -- movement input cancels the action
	blockedGaits: { [string]: boolean }?, -- gaits from which the action cannot start
	guard: ((context: any) -> boolean)?, -- optional extra entry predicate
}

MovementStates.Category = {
	Gait = "Gait" :: Category,
	Action = "Action" :: Category,
}

-- THE gait ladder, slowest to fastest. Index === tier. This is the single
-- source of ordering: Stats.MovementStages and MovementMath's gait resolution
-- both read it, so adding a gait means editing this list and the row below —
-- nothing else.
MovementStates.GaitOrder = { "Idle", "Walk", "Trot", "Run", "Sprint" }

-- The swim ladder, used instead of GaitOrder in water (see Movement/Swimming).
-- Clients never report these: they keep sending their land intent and the
-- server maps it through SwimGaitFor, so it alone decides who is swimming.
MovementStates.SwimOrder = { "SwimIdle", "Swim", "SwimFast" }
MovementStates.SwimGaitFor = {
	Idle = "SwimIdle",
	Walk = "Swim",
	Trot = "Swim",
	Run = "SwimFast",
	Sprint = "SwimFast",
}

MovementStates.Definitions = {
	Idle = { category = "Gait", animation = "Idle" },
	Walk = { category = "Gait", animation = "Walk" },
	Trot = { category = "Gait", animation = "Trot" },
	Run = { category = "Gait", animation = "Run" },
	Sprint = { category = "Gait", animation = "Sprint" },
	SwimIdle = { category = "Gait", animation = "SwimIdle", swimming = true },
	Swim = { category = "Gait", animation = "Swim", swimming = true },
	SwimFast = { category = "Gait", animation = "SwimFast", swimming = true },

	Eat = {
		category = "Action",
		animation = "Eat",
		freezesMovement = true,
		abortOnMove = true,
		blockedGaits = { Run = true, Sprint = true, SwimIdle = true, Swim = true, SwimFast = true },
	},
	Drink = {
		category = "Action",
		animation = "Drink",
		freezesMovement = true,
		abortOnMove = true,
		blockedGaits = { Run = true, Sprint = true, SwimIdle = true, Swim = true, SwimFast = true },
	},
	Fight = {
		category = "Action",
		animation = "Fight",
		freezesMovement = false, -- Fight causes movement; treated like eat/drink otherwise
		abortOnMove = false,
		blockedGaits = {},
	},

	-- Resting is a layered posture (Rest1 -> Rest2). It freezes locomotion like
	-- Eat/Drink, but movement input does NOT plainly abort it — the StateMachine
	-- steps it one level shallower instead (see DeepenRest / ShallowRest), so
	-- abortOnMove stays false here. Animations are TBD; the states exist now so
	-- the controls + freeze behaviour work and a track can be dropped in later.
	Rest1 = {
		category = "Action",
		animation = "Rest1",
		freezesMovement = true,
		abortOnMove = false,
	},
	Rest2 = {
		category = "Action",
		animation = "Rest2",
		freezesMovement = true,
		abortOnMove = false,
	},
} :: { [string]: StateDefinition }

-- Loud lookup: fail fast instead of returning nil for an unknown state. There
-- is no sensible fallback for "what is this state" — a missing entry is a bug.
function MovementStates.Get(name: string): StateDefinition
	local def = MovementStates.Definitions[name]
	assert(def, `MovementStates: unknown state "{tostring(name)}"`)
	return def
end

function MovementStates.IsGait(name: string): boolean
	return MovementStates.Get(name).category == MovementStates.Category.Gait
end

function MovementStates.IsSwimming(name: string): boolean
	return MovementStates.Get(name).swimming == true
end

function MovementStates.IsAction(name: string): boolean
	return MovementStates.Get(name).category == MovementStates.Category.Action
end

return MovementStates
