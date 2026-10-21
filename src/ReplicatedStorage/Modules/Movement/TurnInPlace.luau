--[[
	TurnInPlace

	Input-driven sharp turns using the creature's authored turn clips.

	The clips are in-place step cycles: the root never turns in them (a clip's
	first and last frames are identical), but the planted paws sweep backwards
	under the body exactly as if it were turning above them. Measured on the
	wolf, a Turn90 clip's planted paws carry the body 88-89 degrees over one
	play, on a smoothstep ease-in/ease-out (3p^2 - 2p^3, within 0.01 at every
	tenth of the clip) — the animator keyed a 90 degree root turn with default
	easing and the export dropped it. This module puts it back: the physical
	body follows that curve, but each step is clamped to the LIVE heading gap
	and gait turn-rate cap. Input always wins over the animation timeline.

	The clip always plays at its authored speed. Nothing here speeds a clip
	up or slows it down; the body is paced to the clip, never the reverse.
	The turn nearest the demanded gap is chosen — by ratio, because the body
	turns at gap / Angle times the turn's own pace — so a quarter turn plays
	the 90 and an about-face the 180.

	A turn configured with a Duration instead of clips has no animation at
	all: the body turns over Duration on the same curve while the idle pose
	holds, and the paws are stepped procedurally by LegIK's PawStepper, which
	the drivers switch on for as long as IsStepping() says so.

	Release input or face the requested heading and the turn stops immediately.
	Reverse the demand and the opposite clip starts; keep demanding a sharp
	turn and the clip loops. This module owns only rotation and the visual
	overlay. It never freezes translation or changes the server's gait intent.
]]

local AnimationController = require(script.Parent.Parent.AnimationController)

local TurnInPlace = {}
TurnInPlace.__index = TurnInPlace

local FADE = 0.1 -- s: short blend when input interrupts the clip
local ALIGN_EPS = 1e-3 -- rad: same tolerance as ordinary steering

-- One turn: either a pair of clips, or a Duration and no clips (stepped).
export type TurnConfig = {
	Angle: number, -- deg the body turns over one play of the turn
	Left: string?, -- clip names in the creature's Animations table
	Right: string?,
	Duration: number?, -- s: no clip; the paws are stepped procedurally
}

export type Config = {
	MinAngle: number, -- deg: smaller demands use ordinary steering
	Turns: { TurnConfig },
}

export type Signals = {
	Facing: Vector3, -- current flat facing
	Gap: number, -- rad from the facing to the demanded heading
	Sign: number, -- +1 = the demand is to the left, -1 = to the right
	Steering: boolean, -- the player is asking to move at all
	Grounded: boolean,
	Blocked: boolean, -- an action owns the animation layer
	MaxTurnRate: number, -- rad/s, preserves the gait's steering cap
}

type Turn = {
	label: string, -- the clip's name, or Step<angle><side> for a stepped turn
	stepped: boolean,
	sign: number,
	angle: number, -- rad budget for this cycle, clamped to live input each frame
	length: number, -- s, one play of the clip, or the stepped turn's Duration
	elapsed: number,
}

export type TurnInPlace = typeof(setmetatable(
	{} :: {
		minAngle: number,
		turns: { TurnConfig },
		animations: AnimationController.AnimationController,
		turn: Turn?,
	},
	TurnInPlace
))

-- The ease the clips were animated with (see the header).
local function smoothstep(p: number): number
	return p * p * (3 - 2 * p)
end

-- The turn whose own angle is nearest the demanded gap, by ratio.
local function nearestTurn(turns: { TurnConfig }, gapDeg: number): TurnConfig
	local best, bestErr = turns[1], math.huge
	for _, turn in turns do
		local err = math.abs(math.log(gapDeg / turn.Angle))
		if err < bestErr then
			best, bestErr = turn, err
		end
	end
	return best
end

-- Every clip name the creature's turns play, as a set.
function TurnInPlace.ClipNames(config: Config): { [string]: true }
	local names = {}
	if type(config.Turns) ~= "table" then
		return names
	end
	for _, turn in config.Turns do
		if turn.Left then
			names[turn.Left] = true
		end
		if turn.Right then
			names[turn.Right] = true
		end
	end
	return names
end

-- The creature's optional TurnInPlace block: nil when it has none (feature
-- off). Every clip it names must be one of the creature's animations, so a
-- typo fails here, at spawn, rather than on the first turn.
function TurnInPlace.fromInfo(
	info: { [string]: any },
	animations: AnimationController.AnimationController
): TurnInPlace?
	local config = info.TurnInPlace
	if not config then
		return nil
	end
	return TurnInPlace.new(config, info.Animations or {}, animations)
end

function TurnInPlace.new(
	config: Config,
	animationIds: { [string]: string },
	animations: AnimationController.AnimationController
): TurnInPlace
	assert(type(config) == "table", "TurnInPlace: config missing")
	assert(animations, "TurnInPlace: an AnimationController is required")
	assert(
		type(config.MinAngle) == "number" and config.MinAngle > 0 and config.MinAngle <= 180,
		"TurnInPlace: MinAngle must be in (0, 180]"
	)
	assert(type(config.Turns) == "table" and #config.Turns > 0, "TurnInPlace: config declares no Turns")
	local function known(name: any, where: string)
		assert(
			type(name) == "string" and animationIds[name] ~= nil,
			`TurnInPlace: {where} "{tostring(name)}" is not in the creature's Animations`
		)
	end
	for i, turn in config.Turns do
		assert(type(turn.Angle) == "number" and turn.Angle > 0, `TurnInPlace: turn {i} needs a positive Angle`)
		if turn.Duration ~= nil then
			assert(
				type(turn.Duration) == "number" and turn.Duration > 0,
				`TurnInPlace: turn {i} Duration must be a positive number`
			)
			assert(
				turn.Left == nil and turn.Right == nil,
				`TurnInPlace: turn {i} has both clips and a Duration; a stepped turn has no clips`
			)
		else
			known(turn.Left, `turn {i} Left`)
			known(turn.Right, `turn {i} Right`)
		end
	end

	local self = setmetatable({}, TurnInPlace)
	self.minAngle = math.rad(config.MinAngle)
	self.turns = config.Turns
	self.animations = animations
	self.turn = nil
	return self
end

-- Returns this frame's facing, or nil to use ordinary steering. The caller
-- continues applying velocity and reporting movement intent in either case.
function TurnInPlace:Update(signals: Signals, dt: number): Vector3?
	if signals.Blocked or not signals.Grounded or not signals.Steering or signals.Gap <= ALIGN_EPS then
		self:Cancel()
		return nil
	end

	local turn = self.turn
	local timelineDt = dt
	if turn and signals.Sign ~= turn.sign then
		self:Cancel()
		turn = nil
	end

	if not turn or turn.elapsed >= turn.length then
		if signals.Gap < self.minAngle then
			self:Cancel()
			return nil
		end
		-- Carry the fractional frame past a loop boundary. Dropping it would
		-- slowly drift the body away from clips whose length isn't a multiple
		-- of dt (the right 180 is 25/24 seconds). The gait cap still uses dt.
		if turn then
			timelineDt += turn.elapsed - turn.length
		end
		local pick = nearestTurn(self.turns, math.deg(signals.Gap))
		local side = if signals.Sign > 0 then "Left" else "Right"
		local label, length
		if pick.Duration then
			self.animations:StopTurn(FADE)
			label, length = `Step{pick.Angle}{side}`, pick.Duration
		else
			label = if signals.Sign > 0 then pick.Left else pick.Right
			local track = self.animations:PlayTurn(label, FADE)
			if not track then
				self:Cancel()
				return nil -- not loaded yet: turn the ordinary way this time
			end
			length = track.Length
		end
		turn = {
			label = label,
			stepped = pick.Duration ~= nil,
			sign = signals.Sign,
			angle = signals.Gap,
			length = length,
			elapsed = 0,
		}
		self.turn = turn
	end

	local before = smoothstep(turn.elapsed / turn.length)
	turn.elapsed += timelineDt
	local after = smoothstep(math.min(turn.elapsed / turn.length, 1))
	local step = math.min(turn.angle * (after - before), signals.Gap, signals.MaxTurnRate * dt)
	local facing = CFrame.Angles(0, step * turn.sign, 0) * signals.Facing
	if signals.Gap - step <= ALIGN_EPS then
		self:Cancel()
	end
	return facing.Unit
end

-- Cut a running turn short (input, an action, leaving the ground). The
-- body keeps whatever it has turned so far.
function TurnInPlace:Cancel()
	local turn = self.turn
	if turn then
		self.turn = nil
		if not turn.stepped then
			self.animations:StopTurn(FADE)
		end
	end
end

-- A stepped (clip-less) turn is running: the paws are LegIK's to step.
function TurnInPlace:IsStepping(): boolean
	return self.turn ~= nil and self.turn.stepped
end

-- The running turn for the debug HUD — its clip, or Step<angle><side> — or nil.
function TurnInPlace:GetLabel(): string?
	return if self.turn then self.turn.label else nil
end

return TurnInPlace
