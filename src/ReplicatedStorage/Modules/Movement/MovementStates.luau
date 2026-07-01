--[[
	MovementStates

	Single source of truth for every movement-related state. Pure data — no
	behaviour, no Roblox instances. The state system is split into two
	orthogonal layers and this table describes both:

	  * GAIT   — locomotion stages (Idle/Walk/Trot/Run/Sprint). The VISUAL gait
	             is *derived* every frame from the server-driven WalkSpeed (see
	             Stats.GaitFromSpeed) — pure speed bands. There is deliberately
	             NO transition graph: a gait is a function of the current speed,
	             not of the previous gait, so it can never desync.

	  * ACTION — discrete, guarded, interruptible activities (Eat/Drink/Fight,
	             and anything added later). Only one action runs at a time. An
	             action is requested explicitly and may be rejected by its
	             restrictions.

	Adding a new state later = add one row here. Restrictions stay declarative:
	  * blockedGaits[gait] = true   -> cannot start the action while in that gait
	                                   (this is the "no eat/drink while sprinting" rule)
	  * guard(context) -> boolean   -> optional predicate for anything the simple
	                                   blockedGaits set can't express (low stamina,
	                                   airborne, on cooldown, ...). Return false to
	                                   reject. Omit it when not needed.
]]

local MovementStates = {}

export type Category = "Gait" | "Action"

export type StateDefinition = {
	category: Category,
	animation: string,
	-- Gait-only:
	tier: number?, -- ordering, slow (0) -> fast; used by gait resolution
	-- Action-only:
	freezesMovement: boolean?, -- locomotion is suppressed while this action runs
	abortOnMove: boolean?, -- movement input cancels the action
	blockedGaits: { [string]: boolean }?, -- gaits from which the action cannot start
	guard: ((context: any) -> boolean)?, -- optional extra entry predicate
}

MovementStates.Category = {
	Gait = "Gait" :: Category,
	Action = "Action" :: Category,
}

-- Ordered gait tiers, slowest to fastest. Index === tier. Reference ordering
-- for the Idle -> Walk -> Trot -> Run -> Sprint speed ladder.
MovementStates.GaitOrder = { "Idle", "Walk", "Trot", "Run", "Sprint" }

MovementStates.Definitions = {
	Idle = { category = "Gait", tier = 0, animation = "Idle" },
	Walk = { category = "Gait", tier = 1, animation = "Walk" },
	Trot = { category = "Gait", tier = 2, animation = "Trot" },
	Run = { category = "Gait", tier = 3, animation = "Run" },
	Sprint = { category = "Gait", tier = 4, animation = "Sprint" },

	Eat = {
		category = "Action",
		animation = "Eat",
		freezesMovement = true,
		abortOnMove = true,
		blockedGaits = { Run = true, Sprint = true },
	},
	Drink = {
		category = "Action",
		animation = "Drink",
		freezesMovement = true,
		abortOnMove = true,
		blockedGaits = { Run = true, Sprint = true },
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

function MovementStates.IsAction(name: string): boolean
	return MovementStates.Get(name).category == MovementStates.Category.Action
end

return MovementStates
