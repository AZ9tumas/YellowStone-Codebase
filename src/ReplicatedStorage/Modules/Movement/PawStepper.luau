--[[
	PawStepper

	Procedural footwork for a creature turning on the spot, run by LegIK. No
	animation is involved: when a paw lifts, where it lands and how high it
	swings all come from the body's own motion.

	While engaged every paw stays where it is on the ground and the body turns
	above it. Each paw has a HOME — where the pose holds it under the body this
	frame — and home turns with the body, so a planted paw falls behind it.
	Once it is Trigger behind, the paw steps: it lifts, swings along an arc and
	lands ahead of where home is heading, so it can stand a while before it has
	to step again.

	Diagonal paws step together (the footfall pairing of a trot), and a paw
	never lifts while one beside it or at the same end is off the ground, so the
	body always stands on a diagonal pair. A paw that could not get away in time
	is dragged along at MaxLag rather than left to stretch its leg straight.

	Released, the stepper keeps stepping — no lead, and a smaller threshold —
	until every paw is back under its home, and only then hands the paws back
	to the animation. A turn therefore ends standing square with nothing left
	to slide.

	Everything is measured across the ground: distances are taken in the plane
	square to the body's up, and LegIK finds the ground under each paw and adds
	the lift. Lengths are fractions of each leg's own length, so a creature of
	any size needs no retuning.
]]

local PawStepper = {}
PawStepper.__index = PawStepper

local DT_MAX = 0.1
local VEL_RESPONSE = 20 -- 1/s, smoothing of each home's measured velocity
-- Released, a body travelling faster than this (average leg lengths per second)
-- has walked off out of the turn: its gait takes the paws back at once.
local MOVE_RELEASE = 0.4

local DEF_TRIGGER = 0.2 -- lag that makes a planted paw step
local DEF_SETTLE = 0.06 -- lag still worth a step once released
local DEF_MAX_LAG = 0.42 -- a planted paw is dragged rather than fall further behind
local DEF_MAX_STEP = 0.75 -- longest step
local DEF_LIFT = 0.35 -- step height, as a fraction of the step's length
local DEF_MAX_LIFT = 0.16
local DEF_STEP_TIME = 0.15 -- s, one step's flight
local DEF_LEAD = 0.3 -- how far past home a paw lands, in flights of home travel
local DEF_PAIR = 0.35 -- a diagonal partner joins a step once this far to its own trigger

export type Config = {
	Trigger: number?,
	Settle: number?,
	MaxLag: number?,
	MaxStep: number?,
	Lift: number?,
	MaxLift: number?,
	StepTime: number?, -- s
	Lead: number?,
	Pair: number?,
}

export type LegSpec = {
	length: number, -- studs: every distance above is a fraction of this
	left: boolean,
	front: boolean,
}

type Leg = {
	length: number,
	left: boolean,
	front: boolean,
	home: Vector3,
	homeVel: Vector3,
	plant: Vector3,
	stepping: boolean,
	from: Vector3,
	to: Vector3,
	t: number, -- 0..1 through the flight
	height: number,
	pos: Vector3,
	lift: number,
	steps: number,
}

export type PawStepper = typeof(setmetatable(
	{} :: {
		legs: { Leg },
		active: boolean,
		trigger: number,
		settle: number,
		maxLag: number,
		maxStep: number,
		liftRatio: number,
		maxLift: number,
		stepTime: number,
		lead: number,
		pair: number,
		drags: number,
		up: Vector3,
	},
	PawStepper
))

local function flat(v: Vector3, up: Vector3): Vector3
	return v - up * up:Dot(v)
end

local function smoothstep(p: number): number
	return p * p * (3 - 2 * p)
end

function PawStepper.new(specs: { LegSpec }, config: Config?): PawStepper
	local c: Config = config or {}
	assert(#specs > 0, "PawStepper: no legs")
	local self = setmetatable({}, PawStepper)
	self.legs = {}
	for i, s in specs do
		assert(type(s.length) == "number" and s.length > 0, `PawStepper: leg {i} needs a positive length`)
		self.legs[i] = {
			length = s.length,
			left = s.left,
			front = s.front,
			home = Vector3.zero,
			homeVel = Vector3.zero,
			plant = Vector3.zero,
			stepping = false,
			from = Vector3.zero,
			to = Vector3.zero,
			t = 0,
			height = 0,
			pos = Vector3.zero,
			lift = 0,
			steps = 0,
		}
	end
	self.active = false
	self.trigger = c.Trigger or DEF_TRIGGER
	self.settle = c.Settle or DEF_SETTLE
	self.maxLag = c.MaxLag or DEF_MAX_LAG
	self.maxStep = c.MaxStep or DEF_MAX_STEP
	self.liftRatio = c.Lift or DEF_LIFT
	self.maxLift = c.MaxLift or DEF_MAX_LIFT
	self.stepTime = c.StepTime or DEF_STEP_TIME
	self.lead = c.Lead or DEF_LEAD
	self.pair = c.Pair or DEF_PAIR
	self.drags = 0
	self.up = Vector3.yAxis
	assert(self.settle < self.trigger, "PawStepper: Settle must be below Trigger")
	assert(self.trigger < self.maxLag, "PawStepper: Trigger must be below MaxLag")
	assert(self.stepTime > 0, "PawStepper: StepTime must be positive")
	return self
end

-- Two paws beside each other or at the same end may not be off the ground
-- together; only a diagonal pair may.
local function neighbours(a: Leg, b: Leg): boolean
	return a.left == b.left or a.front == b.front
end

function PawStepper:_free(leg: Leg): boolean
	for _, other in self.legs do
		if other ~= leg and other.stepping and neighbours(leg, other) then
			return false
		end
	end
	return true
end

function PawStepper:_step(leg: Leg, engaged: boolean)
	local up = self.up
	local to
	if engaged then
		-- Land where home will be once the flight is over, plus a lead so the
		-- paw can stand a while before home has passed it by Trigger again.
		local lead = leg.homeVel * (self.stepTime * self.lead)
		local cap = 0.6 * self.trigger * leg.length
		if lead.Magnitude > cap then
			lead = lead.Unit * cap
		end
		to = leg.home + leg.homeVel * self.stepTime + lead
	else
		to = leg.home
	end
	local d = flat(to - leg.plant, up)
	local maxStep = self.maxStep * leg.length
	if d.Magnitude > maxStep then
		to = leg.plant + d.Unit * maxStep
		d = d.Unit * maxStep
	end
	leg.from, leg.to, leg.t, leg.stepping = leg.plant, to, 0, true
	leg.height = math.min(d.Magnitude * self.liftRatio, self.maxLift * leg.length)
	leg.steps += 1
end

-- Advance one frame. `homes` are the paws' positions under the pose, in leg
-- order; `engaged` says the body is turning on the spot. Returns whether the
-- stepper owns the paws this frame — true until a released turn has settled.
function PawStepper:Update(homes: { Vector3 }, up: Vector3, engaged: boolean, dt: number): boolean
	dt = math.clamp(dt, 1e-4, DT_MAX)
	local legs = self.legs

	if not self.active then
		if not engaged then
			return false
		end
		-- Engage from the pose as it stands: every paw planted at its home.
		self.active = true
		for i, leg in legs do
			local h = homes[i]
			leg.home, leg.homeVel, leg.plant = h, Vector3.zero, h
			leg.stepping, leg.pos, leg.lift = false, h, 0
		end
	end
	self.up = up

	-- Homes, and how fast each is sweeping across the ground.
	local a = 1 - math.exp(-VEL_RESPONSE * dt)
	for i, leg in legs do
		local h = homes[i]
		leg.homeVel += (flat(h - leg.home, up) / dt - leg.homeVel) * a
		leg.home = h
	end

	-- Released while the body is going somewhere: settling steps would only
	-- fight the gait that is carrying the paws now.
	if not engaged then
		local mean, reach = Vector3.zero, 0
		for _, leg in legs do
			mean += leg.homeVel
			reach += leg.length
		end
		if (mean / #legs).Magnitude > MOVE_RELEASE * reach / #legs then
			self:Reset()
			return false
		end
	end

	-- Flights in progress; a paw that lands is planted where it came down.
	for _, leg in legs do
		if leg.stepping then
			leg.t += dt / self.stepTime
			if leg.t >= 1 then
				leg.stepping = false
				leg.plant = leg.to
			end
		end
	end

	-- A planted paw never falls further than MaxLag behind: past that it is
	-- dragged, which reads as a slip rather than a leg locked straight.
	for _, leg in legs do
		if not leg.stepping then
			local d = flat(leg.home - leg.plant, up)
			local maxLag = self.maxLag * leg.length
			if d.Magnitude > maxLag then
				leg.plant += d.Unit * (d.Magnitude - maxLag)
				self.drags += 1
			end
		end
	end

	-- New steps, the furthest behind first. Released, only a paw not yet back
	-- under its home steps, and it lands exactly there.
	local trigger = if engaged then self.trigger else self.settle
	local order = {}
	for _, leg in legs do
		if not leg.stepping and flat(leg.home - leg.plant, up).Magnitude >= trigger * leg.length then
			order[#order + 1] = leg
		end
	end
	table.sort(order, function(x, y)
		return flat(x.home - x.plant, up).Magnitude / x.length > flat(y.home - y.plant, up).Magnitude / y.length
	end)
	for _, leg in order do
		if not leg.stepping and self:_free(leg) then
			self:_step(leg, engaged)
			-- Bring the diagonal partner along if it is well on its way to
			-- needing a step anyway: the pair lands together, like a trot.
			for _, other in legs do
				if
					other ~= leg
					and not other.stepping
					and not neighbours(leg, other)
					and self:_free(other)
					and flat(other.home - other.plant, up).Magnitude >= self.pair * trigger * other.length
				then
					self:_step(other, engaged)
				end
			end
		end
	end

	local settled = true
	for _, leg in legs do
		if leg.stepping then
			local s = smoothstep(leg.t)
			leg.pos = leg.from:Lerp(leg.to, s)
			leg.lift = leg.height * math.sin(math.pi * leg.t)
			settled = false
		else
			leg.pos = leg.plant
			leg.lift = 0
			if flat(leg.home - leg.plant, up).Magnitude > self.settle * leg.length then
				settled = false
			end
		end
	end

	if not engaged and settled then
		self.active = false
	end
	return self.active
end

-- This frame's position for leg `i` (only its placement across the ground
-- counts; LegIK puts it on the ground) and how high the paw is swinging.
function PawStepper:Get(i: number): (Vector3, number)
	local leg = self.legs[i]
	return leg.pos, leg.lift
end

function PawStepper:IsActive(): boolean
	return self.active
end

-- Drop everything and hand the paws straight back (LegIK eased right out).
function PawStepper:Reset()
	self.active = false
	for _, leg in self.legs do
		leg.stepping, leg.lift = false, 0
	end
end

-- Paws off the ground right now, for the debug HUD.
function PawStepper:Airborne(): number
	local n = 0
	for _, leg in self.legs do
		if leg.stepping then
			n += 1
		end
	end
	return n
end

return PawStepper
