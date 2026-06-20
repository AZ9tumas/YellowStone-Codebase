--[[
	StateMachine

	Per-character state controller. Deliberately small: it holds exactly two
	pieces of state and exposes the operations the movement loop needs.

	  gait   : string  -- current locomotion stage, DERIVED from input each frame
	  action : string? -- current action (Eat/Drink/Fight/...), or nil

	Why this is not the old StateManager:
	  * No transition graph / priority table / restrictions registry. A gait is
	    a pure function of input + speed (ResolveGait), so the "is this
	    transition legal" question never arises and the two-store desync bug
	    (params.CurrentState vs StateManager.currentState) is structurally
	    impossible — there is one store.
	  * Restrictions live with the action that owns them (blockedGaits / guard
	    in MovementStates), evaluated at request time.

	The context table (`ctx`) carries everything resolution + guards need:
	  {
	    hasMoveInput : boolean,
	    shiftHeld    : boolean,
	    walkStyle    : string,  -- "Walk" or "Trot"  (Z toggle)
	    runStyle     : string,  -- "Run"  or "Sprint" (X toggle)
	    currentSpeed : number,
	    walkSpeed    : number,  -- creature config (for ConstrainState)
	    trotSpeed    : number,  -- creature config
	    -- guards may read anything added here later (stamina, grounded, ...)
	  }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)
local MovementStates = require(script.Parent.MovementStates)
local Stats = require(ReplicatedStorage.Modules.Stats)

local StateMachine = {}
StateMachine.__index = StateMachine

export type Context = {
	hasMoveInput: boolean,
	shiftHeld: boolean,
	walkStyle: string,
	runStyle: string,
	currentSpeed: number,
	walkSpeed: number,
	trotSpeed: number,
	[any]: any,
}

function StateMachine.new()
	local self = setmetatable({}, StateMachine)

	self.gait = "Idle"
	self.action = nil :: string?

	-- (newGait, oldGait)
	self.GaitChanged = Signal.new()
	-- (newAction: string?, oldAction: string?)
	self.ActionChanged = Signal.new()

	return self
end

-- Pure derivation: gait is a function of the current inputs, nothing else.
function StateMachine:ResolveGait(ctx: Context): string
	if not ctx.hasMoveInput then
		return "Idle"
	end

	local desired = if ctx.shiftHeld then ctx.runStyle else ctx.walkStyle

	-- Clamp an up-shift (e.g. Idle -> Sprint) down to whatever the creature has
	-- physically accelerated to, so the animation/state never teleports ahead
	-- of real speed.
	return Stats.ConstrainState(desired, ctx.currentSpeed, ctx.walkSpeed, ctx.trotSpeed)
end

function StateMachine:SetGait(name: string)
	assert(MovementStates.IsGait(name), `StateMachine: "{tostring(name)}" is not a gait`)
	if self.gait == name then
		return
	end
	local old = self.gait
	self.gait = name
	self.GaitChanged:Fire(name, old)
end

-- Convenience: resolve + apply in one call.
function StateMachine:UpdateGait(ctx: Context)
	self:SetGait(self:ResolveGait(ctx))
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

	-- Restriction 1: blocked from the current gait (e.g. no Eat while Sprinting).
	if def.blockedGaits and def.blockedGaits[self.gait] then
		return false, `blocked while {self.gait}`
	end

	-- Restriction 2: optional custom predicate for everything else.
	if def.guard and not def.guard(ctx) then
		return false, "guard rejected"
	end

	local old = self.action
	self.action = name
	self.ActionChanged:Fire(name, old)
	return true
end

function StateMachine:ClearAction()
	if not self.action then
		return
	end
	local old = self.action
	self.action = nil
	self.ActionChanged:Fire(nil, old)
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
