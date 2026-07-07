--[[
	MovementStates

	Single source of truth for every movement-related state. Pure data — no
	behaviour, no Roblox instances. The state system is split into two
	orthogonal layers and this table describes both:

	  * GAIT   — locomotion stages (Idle/Walk/Trot/Run/Sprint). The VISUAL gait
	             is *derived* every frame from the creature's measured velocity
	             (see Stats.ResolveGaitFromVelocity) — speed bands with
	             hysteresis. There is deliberately NO transition graph: a gait
	             is a function of the current speed, so it can never desync.

	  * TURN   — turn-in-place one-shots (Turn90/Turn180, left/right). They live
	             on the gait layer (exactly one locomotion track at a time) but
	             are triggered by the input/facing angle gap while standing, not
	             by speed, so they get their own category. Non-looping; never
	             sent to the server (the intent stays a locomotion gait).

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

export type Category = "Gait" | "Turn" | "Action"

export type StateDefinition = {
	category: Category,
	animation: string,
	-- Gait-only:
	tier: number?, -- ordering, slow (0) -> fast; used by gait resolution
	-- Turn-only:
	looped: boolean?, -- turn one-shots set false; nil means looping (all gaits)
	-- Action-only:
	freezesMovement: boolean?, -- locomotion is suppressed while this action runs
	abortOnMove: boolean?, -- movement input cancels the action
	blockedGaits: { [string]: boolean }?, -- gaits from which the action cannot start
	guard: ((context: any) -> boolean)?, -- optional extra entry predicate
}

MovementStates.Category = {
	Gait = "Gait" :: Category,
	Turn = "Turn" :: Category,
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

	-- Turn-in-place one-shots. Gait-layer overrides driven by MovementController
	-- (input/facing angle gap while near-stationary), not by speed. Non-looping:
	-- the controller paces the root rotation to the track and exits the state
	-- when the gap closes or the track ends. MovementService rejects these as a
	-- reported state (category ~= Gait), so they are purely visual/client-side.
	Turn90Left = { category = "Turn", animation = "Turn90Left", looped = false },
	Turn90Right = { category = "Turn", animation = "Turn90Right", looped = false },
	Turn180Left = { category = "Turn", animation = "Turn180Left", looped = false },
	Turn180Right = { category = "Turn", animation = "Turn180Right", looped = false },

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

function MovementStates.IsTurn(name: string): boolean
	return MovementStates.Get(name).category == MovementStates.Category.Turn
end

function MovementStates.IsAction(name: string): boolean
	return MovementStates.Get(name).category == MovementStates.Category.Action
end

return MovementStates
