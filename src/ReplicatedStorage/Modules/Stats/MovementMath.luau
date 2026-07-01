--[[
	MovementMath

	Pure math helpers used by the movement system. No side effects, no
	Roblox-instance mutation — just numbers in, numbers out, so the
	formulas can be tweaked / unit-tested in isolation.
]]

local MovementMath = {}

-- Turn-brake band, expressed as ANGLES (framerate-independent). Below FREE the
-- demanded heading change costs nothing — holding a line only ever asks for a
-- fraction of a degree (camera-relative move-vector noise), which must not bleed
-- speed. The penalty ramps up to full by FULL.
local TURN_ANGLE_FREE = math.rad(5)
local TURN_ANGLE_FULL = math.rad(75)

-- Speed multiplier from how SHARP a turn the player is DEMANDING this frame:
-- `angleDiff` is the angle between the current heading and the desired (input)
-- heading. Straight / micro-correction => 1; a hard turn => heavy penalty.
--
-- Why the ANGLE and not a turn rate: a per-frame rate is angleDiff / dt, which
-- explodes at high FPS for the SAME tiny heading gap (a constant 0.72° gap read
-- 0.18 at 60 FPS but 0.43 at 138 FPS), so the brake became framerate-dependent
-- and bit while sprinting straight. The raw angle is frame-rate invariant.
--
-- The per-state max turn rate is still honoured — it caps how fast the creature
-- rotates, so a sharp turn at a slow-turning gait (Sprint) keeps this penalty
-- applied for MORE frames -> more total speed shed, exactly as intended.
--
-- Speed ∝ 1 / (1 + charged · sensitivity); floored so it slows hard but never
-- freezes.
function MovementMath.GetTurnSpeedFactor(angleDiff: number, sensitivity: number): number
	local charged = math.clamp((angleDiff - TURN_ANGLE_FREE) / (TURN_ANGLE_FULL - TURN_ANGLE_FREE), 0, 1)
	return math.clamp(1 / (1 + charged * sensitivity), 0.1, 1)
end

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

-- Visual gait band for a given speed. Exact thresholds, NO buffer: a creature
-- at exactly walkSpeed is still Walking, at exactly trotSpeed still Trotting,
-- and so on. Anything above runSpeed is Sprint; zero (or below) is Idle.
--
-- The server ramps WalkSpeed smoothly toward the player's intent, so reading
-- this band each frame makes the ANIMATION climb the ladder while accelerating
-- and descend it while coasting to a stop — derived locally from the already
-- replicated WalkSpeed, so it costs no network traffic.
function MovementMath.GaitFromSpeed(
	speed: number,
	walkSpeed: number,
	trotSpeed: number,
	runSpeed: number
): string
	if speed <= 0 then
		return "Idle"
	elseif speed <= walkSpeed then
		return "Walk"
	elseif speed <= trotSpeed then
		return "Trot"
	elseif speed <= runSpeed then
		return "Run"
	end
	return "Sprint"
end

return MovementMath
