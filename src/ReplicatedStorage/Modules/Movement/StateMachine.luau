--[[
	StateMachine

	Per-character state controller. Deliberately small: it holds exactly two
	pieces of state and exposes the operations the movement loop needs.

	  gait   : string  -- current locomotion stage. SET each frame from the
	                       creature's measured velocity (MovementController +
	                       Stats.ResolveGaitFromVelocity), or a turn-in-place
	                       state (Turn90*/Turn180*) while one is running. This is
	                       the VISUAL state and drives the animation; it is NOT
	                       the value sent to the server (the controller sends the
	                       input intent).
	  action : string? -- current action (Eat/Drink/Fight/Rest...), or nil

	Why gait is speed-derived, not input-derived:
	  * The server owns WalkSpeed and ramps it toward the player's input intent;
	    the measured velocity follows it (minus client-side turn braking).
	    Reading the visual gait from the velocity makes the animation climb the
	    ladder while accelerating AND descend it while coasting to a stop, with
	    zero extra network traffic.
	  * There is one gait store, so the old two-store desync is impossible.

	Restrictions live with the action that owns them (blockedGaits / guard in
	MovementStates), evaluated at request time from the context table (`ctx`):
	  {
	    hasMoveInput : boolean,
	    shiftHeld    : boolean,
	    walkStyle    : string,  -- "Walk" or "Trot"  (Z toggle)
	    runStyle     : string,  -- "Run"  or "Sprint" (X toggle)
	    currentSpeed : number,
	    -- guards may read anything added here later (stamina, grounded, ...)
	  }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)
local MovementStates = require(script.Parent.MovementStates)

local StateMachine = {}
StateMachine.__index = StateMachine

export type Context = {
	hasMoveInput: boolean,
	shiftHeld: boolean,
	walkStyle: string,
	runStyle: string,
	currentSpeed: number,
	[any]: any,
}

export type StateMachine = {
	gait: string,
	action: string?,
	GaitChanged: Signal.Signal<string, string>,
	ActionChanged: Signal.Signal<string?, string?>,

	SetGait: (self: StateMachine, name: string) -> (),
	RequestAction: (self: StateMachine, name: string, ctx: Context) -> (boolean, string?),
	ClearAction: (self: StateMachine) -> (),
	GetRestDepth: (self: StateMachine) -> number,
	IsResting: (self: StateMachine) -> boolean,
	DeepenRest: (self: StateMachine) -> (),
	ShallowRest: (self: StateMachine) -> (),
	AbortActionsIfNeeded: (self: StateMachine, ctx: Context) -> (),
	GetGait: (self: StateMachine) -> string,
	GetAction: (self: StateMachine) -> string?,
	HasAction: (self: StateMachine) -> boolean,
	FreezesMovement: (self: StateMachine) -> boolean,
	EffectiveState: (self: StateMachine) -> string,
	Destroy: (self: StateMachine) -> (),
}

function StateMachine.new(): StateMachine
	local self = setmetatable({}, StateMachine)

	self.gait = "Idle"
	self.action = nil :: string?

	-- (newGait, oldGait)
	self.GaitChanged = Signal.new()
	-- (newAction: string?, oldAction: string?)
	self.ActionChanged = Signal.new()

	return self
end

-- Gait is SET from speed by the controller (Stats.ResolveGaitFromVelocity), not
-- resolved from input here; the controller may also set a turn-in-place state
-- (category Turn), which shares the gait slot because both drive the single
-- locomotion animation track. Fires GaitChanged on a real change.
function StateMachine:SetGait(name: string)
	assert(
		MovementStates.IsGait(name) or MovementStates.IsTurn(name),
		`StateMachine: "{tostring(name)}" is not a gait or turn state`
	)
	if self.gait == name then
		return
	end
	local old = self.gait
	self.gait = name
	self.GaitChanged:Fire(name, old)
end

-- Try to start an action. Returns (true) on success, or (false, reason) when a
-- restriction blocks it. Unknown action names are a programming error and fail
-- loud (assert) rather than silently returning false.
function StateMachine:RequestAction(name: string, ctx: Context): (boolean, string?)
	local def = MovementStates.Get(name)
	assert(def.category == MovementStates.Category.Action, `StateMachine: "{name}" is not an action`)

	if self.action == name then
		return true
	end

	-- Resting owns the action slot and is exited via movement input, not by
	-- starting another action — stand up first.
	if self:IsResting() then
		return false, "resting"
	end

	-- Restriction 1: blocked from the current gait (e.g. no Eat while Sprinting).
	if def.blockedGaits and def.blockedGaits[self.gait] then
		return false, `blocked while {self.gait}`
	end

	-- Restriction 2: optional custom predicate for everything else.
	if def.guard and not def.guard(ctx) then
		return false, "guard rejected"
	end

	self:_setAction(name)
	return true
end

function StateMachine:ClearAction()
	self:_setAction(nil)
end

-- Single mutation point for the action slot. Fires ActionChanged(new, old) on a
-- real change; a no-op when the slot already holds `name`.
function StateMachine:_setAction(name: string?)
	if self.action == name then
		return
	end
	local old = self.action
	self.action = name
	self.ActionChanged:Fire(name, old)
end

-- ===== Resting (layered posture) ============================================
-- Resting is a stack of frozen postures (Rest1 -> Rest2). It reuses the single
-- action slot, so it animates like any action and excludes Eat/Drink/Fight for
-- free. R deepens it; movement input pops one level; popping past Rest1 stands
-- the creature back up. Depth is DERIVED from the action name — no second store
-- to desync.
StateMachine.RestLevels = { "Rest1", "Rest2" } -- index === depth

function StateMachine:GetRestDepth(): number
	for depth, name in ipairs(StateMachine.RestLevels) do
		if self.action == name then
			return depth
		end
	end
	return 0
end

function StateMachine:IsResting(): boolean
	return self:GetRestDepth() > 0
end

-- R key: enter resting, or sink one posture deeper. Capped at the deepest
-- level. Ignored while a non-rest action (Eat/Drink/Fight) owns the slot.
function StateMachine:DeepenRest()
	if self.action and not self:IsResting() then
		return
	end
	local depth = self:GetRestDepth()
	local nextDepth = math.min(depth + 1, #StateMachine.RestLevels)
	if nextDepth ~= depth then
		self:_setAction(StateMachine.RestLevels[nextDepth])
	end
end

-- Movement input: rise one posture shallower. Rising past Rest1 stands up.
-- No-op when not resting.
function StateMachine:ShallowRest()
	local depth = self:GetRestDepth()
	if depth == 0 then
		return
	end
	self:_setAction(if depth == 1 then nil else StateMachine.RestLevels[depth - 1])
end

-- Cancel the active action if movement input arrives and the action declares
-- abortOnMove (eat/drink are cancelled by moving; fight is not).
function StateMachine:AbortActionsIfNeeded(ctx: Context)
	if not self.action then
		return
	end
	local def = MovementStates.Get(self.action)
	if def.abortOnMove and ctx.hasMoveInput then
		self:ClearAction()
	end
end

function StateMachine:GetGait(): string
	return self.gait
end

function StateMachine:GetAction(): string?
	return self.action
end

function StateMachine:HasAction(): boolean
	return self.action ~= nil
end

-- True when an action is active that suppresses locomotion (Eat/Drink). The
-- movement loop uses this to report Idle to the server and stop driving the
-- forward velocity.
function StateMachine:FreezesMovement(): boolean
	if not self.action then
		return false
	end
	return MovementStates.Get(self.action).freezesMovement == true
end

-- The single state that best describes the character right now — a freezing
-- action takes precedence (you are "Eating", not "Idle"); otherwise the gait.
-- Non-freezing actions (Fight) layer on top of the gait and do not replace it.
function StateMachine:EffectiveState(): string
	if self.action and MovementStates.Get(self.action).freezesMovement then
		return self.action
	end
	return self.gait
end

function StateMachine:Destroy()
	self.GaitChanged:Destroy()
	self.ActionChanged:Destroy()
end

return StateMachine
