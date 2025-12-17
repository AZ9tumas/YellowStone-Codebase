--[[
	StateManager Module
	
	A flexible state management system designed to handle multiple state transitions
	with associated properties like walkspeed, animations, and restrictions.
	
	Supports states: Idle, Walk, Trot, Run, Sprint, and can be extended for
	Attack, Swimming, Eat, Drink, etc.
]]

local StateManager = {}
StateManager.__index = StateManager
export type StateConfig = {
	name: string,
	speed: number?,
	canTransitionTo: {string}?,
	restrictions: {string}?,
	priority: number?,
}

export type StateManagerType = {
	currentState: string,
	previousState: string?,
	states: {[string]: StateConfig},
	onStateChanged: ((newState: string, oldState: string?) -> ())?,
	player: Player?,
}

-- Default state configurations with transitions and priorities
local DEFAULT_STATES: {[string]: StateConfig} = {
	["Idle"] = {
		name = "Idle",
		speed = 0,
		canTransitionTo = {"Walk", "Trot", "Run", "Sprint", "Attack", "Eat", "Drink", "Swimming"},
		priority = 0,
	},
	["Walk"] = {
		name = "Walk",
		speed = 15,
		canTransitionTo = {"Idle", "Trot", "Run", "Sprint", "Attack", "Swimming"},
		priority = 1,
	},
	["Trot"] = {
		name = "Trot",
		speed = 28,
		canTransitionTo = {"Idle", "Walk", "Run", "Sprint", "Attack", "Swimming"},
		priority = 2,
	},
	["Run"] = {
		name = "Run",
		speed = 42,
		canTransitionTo = {"Idle", "Walk", "Trot", "Sprint", "Attack", "Swimming"},
		priority = 3,
	},
	["Sprint"] = {
		name = "Sprint",
		speed = 55,
		canTransitionTo = {"Idle", "Walk", "Trot", "Run", "Attack"},
		restrictions = {"LowStamina"},
		priority = 4,
	},
	["Attack"] = {
		name = "Attack",
		speed = 0,
		canTransitionTo = {"Idle", "Walk", "Trot", "Run", "Sprint"},
		priority = 5,
	},
	["Swimming"] = {
		name = "Swimming",
		speed = 20,
		canTransitionTo = {"Idle", "Walk", "Trot"},
		priority = 3,
	},
	["Eat"] = {
		name = "Eat",
		speed = 0,
		canTransitionTo = {"Idle"},
		priority = 2,
	},
	["Drink"] = {
		name = "Drink",
		speed = 0,
		canTransitionTo = {"Idle"},
		priority = 2,
	},
}

function StateManager.new(player: Player?, initialState: string?)
	local self = setmetatable({}, StateManager)
	
	self.player = player
	self.currentState = initialState or "Idle"
	self.previousState = nil
	self.states = {}
	self.stateChangeCallbacks = {}
	self.restrictions = {}
	
	-- Copy default states
	for stateName, stateConfig in pairs(DEFAULT_STATES) do
		self.states[stateName] = {
			name = stateConfig.name,
			speed = stateConfig.speed,
			canTransitionTo = stateConfig.canTransitionTo and table.clone(stateConfig.canTransitionTo) or {},
			restrictions = stateConfig.restrictions and table.clone(stateConfig.restrictions) or {},
			priority = stateConfig.priority or 0,
		}
	end
	
	return self
end

-- Register a custom state or override an existing one
function StateManager:RegisterState(config: StateConfig)
	if not config or not config.name then
		warn("StateManager: Invalid state config provided")
		return false
	end
	
	self.states[config.name] = {
		name = config.name,
		speed = config.speed or 0,
		canTransitionTo = config.canTransitionTo and table.clone(config.canTransitionTo) or {},
		restrictions = config.restrictions and table.clone(config.restrictions) or {},
		priority = config.priority or 0,
	}
	
	return true
end

function StateManager:AddRestriction(restrictionName: string)
	self.restrictions[restrictionName] = true
end

function StateManager:RemoveRestriction(restrictionName: string)
	self.restrictions[restrictionName] = nil
end

function StateManager:HasRestriction(restrictionName: string): boolean
	return self.restrictions[restrictionName] == true
end

function StateManager:CanTransitionTo(targetState: string): boolean
	local currentStateConfig = self.states[self.currentState]
	local targetStateConfig = self.states[targetState]
	
	if not currentStateConfig or not targetStateConfig then
		return false
	end
	
	local canTransition = false
	if currentStateConfig.canTransitionTo then
		for _, allowedState in ipairs(currentStateConfig.canTransitionTo) do
			if allowedState == targetState then
				canTransition = true
				break
			end
		end
	end
	
	if not canTransition then
		return false
	end
	
	if targetStateConfig.restrictions then
		for _, restriction in ipairs(targetStateConfig.restrictions) do
			if self:HasRestriction(restriction) then
				return false
			end
		end
	end
	
	return true
end

function StateManager:TransitionTo(targetState: string, force: boolean?): boolean
	if not force and not self:CanTransitionTo(targetState) then
		return false
	end
	
	local targetStateConfig = self.states[targetState]
	if not targetStateConfig then
		warn("StateManager: Unknown state: " .. targetState)
		return false
	end
	
	local oldState = self.currentState
	self.previousState = oldState
	self.currentState = targetState
	
	-- fire all callbacks
	for _, callback in ipairs(self.stateChangeCallbacks) do
		task.spawn(callback, targetState, oldState, targetStateConfig)
	end
	
	return true
end

function StateManager:GetCurrentState(): string
	return self.currentState
end

function StateManager:GetPreviousState(): string?
	return self.previousState
end

function StateManager:GetStateConfig(stateName: string?): StateConfig?
	local state = stateName or self.currentState
	return self.states[state]
end

function StateManager:GetStateSpeed(stateName: string?, creatureInfo: {[string]: any}?): number
	local state = stateName or self.currentState
	local stateConfig = self.states[state]
	
	if not stateConfig then
		return 0
	end
	
	if creatureInfo then
		local speedKey = state .. "Speed"
		if creatureInfo[speedKey] then
			return creatureInfo[speedKey]
		end
	end
	
	return stateConfig.speed or 0
end

function StateManager:OnStateChanged(callback: (newState: string, oldState: string?, stateConfig: StateConfig?) -> ())
	table.insert(self.stateChangeCallbacks, callback)
	
	return function()
		for i, cb in ipairs(self.stateChangeCallbacks) do
			if cb == callback then
				table.remove(self.stateChangeCallbacks, i)
				break
			end
		end
	end
end

function StateManager:GetAvailableTransitions(): {string}
	local currentStateConfig = self.states[self.currentState]
	if not currentStateConfig or not currentStateConfig.canTransitionTo then
		return {}
	end
	
	local available = {}
	for _, stateName in ipairs(currentStateConfig.canTransitionTo) do
		if self:CanTransitionTo(stateName) then
			table.insert(available, stateName)
		end
	end
	
	return available
end

function StateManager:GetStatePriority(stateName: string?): number
	local state = stateName or self.currentState
	local stateConfig = self.states[state]
	return stateConfig and stateConfig.priority or 0
end

function StateManager:AddTransition(fromState: string, toState: string)
	local stateConfig = self.states[fromState]
	if not stateConfig then
		warn("StateManager: Unknown state: " .. fromState)
		return false
	end
	
	if not stateConfig.canTransitionTo then
		stateConfig.canTransitionTo = {}
	end
	
	for _, existing in ipairs(stateConfig.canTransitionTo) do
		if existing == toState then
			return true
		end
	end
	
	table.insert(stateConfig.canTransitionTo, toState)
	return true
end

function StateManager:RemoveTransition(fromState: string, toState: string)
	local stateConfig = self.states[fromState]
	if not stateConfig or not stateConfig.canTransitionTo then
		return false
	end
	
	for i, existing in ipairs(stateConfig.canTransitionTo) do
		if existing == toState then
			table.remove(stateConfig.canTransitionTo, i)
			return true
		end
	end
	
	return false
end

function StateManager:Destroy()
	self.stateChangeCallbacks = {}
	self.states = {}
	self.restrictions = {}
	self.player = nil
end

return StateManager