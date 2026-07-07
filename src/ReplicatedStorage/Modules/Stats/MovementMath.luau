--[[
	MovementMath

	Pure math helpers used by the movement system. No side effects, no
	Roblox-instance mutation — just numbers in, numbers out, so the
	formulas can be tweaked / unit-tested in isolation.
]]

local MovementMath = {}

-- ===== Turn brake ============================================================

-- Speed multiplier from how SHARP a turn the player is DEMANDING this frame,
-- evaluated from the creature's TurnBrakeCurve (see CreatureStats): an ordered
-- list of { Angle (deg), Brake (0..1) } control points, linearly interpolated.
-- `angleDiff` is the angle (radians) between the current heading and the
-- desired (input) heading.
--
-- Why a per-creature curve and not a sensitivity scalar: each species gets its
-- own full relation between turn sharpness and speed loss — a wolf's curve
-- reaches 0 (a demanded reversal stops it completely, The-Isle-style) while a
-- horse's bottoms out above 0 (it always keeps some momentum). The old
-- one-formula-fits-all sensitivity could not express that.
--
-- Why the ANGLE and not a turn rate: a per-frame rate is angleDiff / dt, which
-- explodes at high FPS for the SAME tiny heading gap, so the brake became
-- framerate-dependent and bit while sprinting straight. The raw angle is
-- frame-rate invariant. The "free zone" for micro-corrections lives in the
-- curve itself (first control points at Brake = 1).
--
-- This is a stats fetch, so it fails loud on a malformed curve — no fallbacks.
export type TurnBrakePoint = { Angle: number, Brake: number }

function MovementMath.EvaluateTurnBrakeCurve(angleDiff: number, curve: { TurnBrakePoint }): number
	assert(curve and #curve >= 2, "MovementMath: TurnBrakeCurve needs at least two control points")

	local angle = math.deg(angleDiff)
	if angle <= curve[1].Angle then
		return curve[1].Brake
	end

	for i = 2, #curve do
		local p0, p1 = curve[i - 1], curve[i]
		assert(p1.Angle > p0.Angle, "MovementMath: TurnBrakeCurve angles must be strictly increasing")
		if angle <= p1.Angle then
			local t = (angle - p0.Angle) / (p1.Angle - p0.Angle)
			return p0.Brake + (p1.Brake - p0.Brake) * t
		end
	end

	return curve[#curve].Brake
end

-- ===== Speed integration =====================================================

-- One-step speed integration toward `targetSpeed` using separate
-- acceleration and deceleration rates. Returns the new speed.
function MovementMath.Accelerate(
	currentSpeed: number,
	targetSpeed: number,
	dt: number,
	acceleration: number,
	deceleration: number
): number
	local diff = targetSpeed - currentSpeed
	if math.abs(diff) < 0.1 then
		return targetSpeed
	end

	local change
	if diff > 0 then
		change = acceleration * dt
		if change > diff then change = diff end
	else
		change = -deceleration * dt
		if change < diff then change = diff end
	end

	return currentSpeed + change
end

-- ===== Gait resolution =======================================================

local GAIT_ORDER = { "Idle", "Walk", "Trot", "Run", "Sprint" }
local GAIT_TIER = { Idle = 1, Walk = 2, Trot = 3, Run = 4, Sprint = 5 }

-- Hysteresis around each gait boundary, as a fraction of the boundary speed.
-- The measured velocity of a creature cruising AT a config speed sits exactly
-- on a band edge (walking = WalkSpeed = the Walk/Trot boundary), so physics
-- jitter from slopes / reorientation would flap the band every frame without
-- a dead zone: you must EXCEED a boundary by this margin to shift up, and
-- fall BELOW it by the same margin to shift back down.
local GAIT_HYSTERESIS = 0.12

-- The Idle boundary is absolute (a fraction of 0 is 0): moving faster than
-- IDLE_EXIT_SPEED leaves Idle; dropping under IDLE_ENTER_SPEED re-enters it.
local IDLE_EXIT_SPEED = 1.2
local IDLE_ENTER_SPEED = 0.6

-- Visual gait band from the creature's MEASURED velocity (smoothed, horizontal),
-- with hysteresis against the previous gait. Reading the actual velocity makes
-- the animation fully dynamic — it climbs the ladder while accelerating and
-- descends it while decelerating, including client-side speed changes (turn
-- brake) the server-driven WalkSpeed never sees. The hysteresis + the caller's
-- smoothing are what prevent the instantaneous Idle->Walk / Walk->Trot flicker
-- that raw per-frame velocity produced on slopes.
--
-- `currentGait` must be one of the five locomotion gaits — passing anything
-- else is a programming error and fails loud.
function MovementMath.ResolveGaitFromVelocity(
	speed: number,
	currentGait: string,
	walkSpeed: number,
	trotSpeed: number,
	runSpeed: number
): string
	local tier = GAIT_TIER[currentGait]
	assert(tier, `MovementMath: "{tostring(currentGait)}" is not a locomotion gait`)

	-- upBound[i] = speed to exceed to leave tier i upward;
	-- downBound[i] = speed to fall below to drop from tier i+1 back to i.
	local upBound = {
		IDLE_EXIT_SPEED,
		walkSpeed * (1 + GAIT_HYSTERESIS),
		trotSpeed * (1 + GAIT_HYSTERESIS),
		runSpeed * (1 + GAIT_HYSTERESIS),
	}
	local downBound = {
		IDLE_ENTER_SPEED,
		walkSpeed * (1 - GAIT_HYSTERESIS),
		trotSpeed * (1 - GAIT_HYSTERESIS),
		runSpeed * (1 - GAIT_HYSTERESIS),
	}

	while tier < #GAIT_ORDER and speed > upBound[tier] do
		tier += 1
	end
	while tier > 1 and speed < downBound[tier - 1] do
		tier -= 1
	end

	return GAIT_ORDER[tier]
end

return MovementMath
