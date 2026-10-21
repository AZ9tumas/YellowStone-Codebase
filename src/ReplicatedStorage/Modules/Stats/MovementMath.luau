--[[
	MovementMath

	Pure math helpers used by the movement system. No side effects, no
	Roblox-instance mutation — just numbers in, numbers out, so the
	formulas can be tweaked / unit-tested in isolation.
]]

local MovementStates = require(script.Parent.Parent.Movement.MovementStates)

local MovementMath = {}

-- ===== Turn brake ============================================================

-- Speed multiplier from how SHARP a turn the player is DEMANDING this frame,
-- evaluated from the creature's TurnBrakeCurve (see CreatureStats): an ordered
-- list of { Angle (deg), Brake (0..1) } control points, linearly interpolated.
-- `angleDiff` is the angle (radians) between the current heading and the
-- desired (input) heading.
--
-- Why a per-creature curve and not a sensitivity scalar: each species gets its
-- own full relation between turn sharpness and speed loss — an agile wolf
-- sheds most of its speed on a reversal, a heavy horse keeps more momentum.
-- A single sensitivity number could not express that.
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

-- The gait ladder lives in MovementStates; derive the name -> tier lookup from
-- it so there is exactly one place to edit when a gait is added.
local GAIT_ORDER = MovementStates.GaitOrder
local GAIT_TIER = {}
for tier, name in ipairs(GAIT_ORDER) do
	GAIT_TIER[name] = tier
end

-- Both edges of the hysteresis band sit ABOVE the slower gait's cruising
-- speed. A symmetric band around that speed traps deceleration in the faster
-- gait: settling at TrotSpeed never crosses TrotSpeed * 0.88. Keep the existing
-- upshift margin, but downshift before reaching the slower cruise. The gap
-- between the two edges still absorbs physics jitter.
local GAIT_UP_MARGIN = 0.12
local GAIT_DOWN_MARGIN = 0.06

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
		walkSpeed * (1 + GAIT_UP_MARGIN),
		trotSpeed * (1 + GAIT_UP_MARGIN),
		runSpeed * (1 + GAIT_UP_MARGIN),
	}
	local downBound = {
		IDLE_ENTER_SPEED,
		walkSpeed * (1 + GAIT_DOWN_MARGIN),
		trotSpeed * (1 + GAIT_DOWN_MARGIN),
		runSpeed * (1 + GAIT_DOWN_MARGIN),
	}

	while tier < #GAIT_ORDER and speed > upBound[tier] do
		tier += 1
	end
	while tier > 1 and speed < downBound[tier - 1] do
		tier -= 1
	end

	return GAIT_ORDER[tier]
end

-- ===== Spring-damper ==========================================================

-- Convert animator-friendly tuning (response frequency in Hz, damping ratio)
-- into the stiffness / damping the integrator wants. zeta < 1 overshoots and
-- settles (follow-through); zeta = 1 is critically damped; > 1 is sluggish.
function MovementMath.SpringParams(frequencyHz: number, dampingRatio: number): (number, number)
	assert(frequencyHz > 0, "MovementMath: spring Frequency must be > 0")
	assert(dampingRatio > 0, "MovementMath: spring Damping must be > 0")
	local w = 2 * math.pi * frequencyHz
	return w * w, 2 * dampingRatio * w
end

-- One step of a damped spring toward `goal`, integrated EXACTLY (closed-form
-- solution of x'' = s(goal - x) - d x'). Unlike Euler / repeated lerps this
-- is unconditionally stable and produces the identical trajectory at any
-- frame rate, including across dt spikes — the same class of bug this repo
-- already fixed once in the turn brake. Port of Daniel Holden's
-- spring_damper_exact with a stationary goal. Returns (newX, newV).
function MovementMath.SpringDamperExact(
	x: number,
	v: number,
	goal: number,
	stiffness: number,
	damping: number,
	dt: number
): (number, number)
	local eps = 1e-5
	local s, d, c = stiffness, damping, goal
	local y = d * 0.5
	local disc = s - d * d * 0.25

	if math.abs(disc) < eps then
		-- Critically damped.
		local j0 = x - c
		local j1 = v + j0 * y
		local e = math.exp(-y * dt)
		return j0 * e + dt * j1 * e + c, -y * j0 * e - y * dt * j1 * e + j1 * e
	elseif disc > 0 then
		-- Under damped: decaying oscillation.
		local w = math.sqrt(disc)
		local off = x - c
		local j = math.sqrt((v + y * off) ^ 2 / (w * w + eps) + off * off)
		local p = math.atan((v + off * y) / (-off * w + eps))
		if off <= 0 then
			j = -j
		end
		local e = math.exp(-y * dt)
		local cs, sn = math.cos(w * dt + p), math.sin(w * dt + p)
		return j * e * cs + c, -y * j * e * cs - w * j * e * sn
	else
		-- Over damped.
		local r = math.sqrt(d * d - 4 * s)
		local y0, y1 = (d + r) * 0.5, (d - r) * 0.5
		local j1 = (c * y0 - x * y0 - v) / (y1 - y0)
		local j0 = x - j1 - c
		local e0, e1 = math.exp(-y0 * dt), math.exp(-y1 * dt)
		return j0 * e0 + j1 * e1 + c, -y0 * j0 * e0 - y1 * j1 * e1
	end
end

return MovementMath
