--[[
	MovementMath

	Pure math helpers used by the movement system. No side effects, no
	Roblox-instance mutation — just numbers in, numbers out, so the
	formulas can be tweaked / unit-tested in isolation.
]]

local MovementMath = {}

-- Turning circle gets wider as speed increases.
--   maxTurnRate = baseTurnRate / (1 + currentSpeed * turnSpeedDecay)
function MovementMath.GetMaxTurnRate(baseTurnRate: number, currentSpeed: number, turnSpeedDecay: number): number
	return baseTurnRate / (1 + (currentSpeed * turnSpeedDecay))
end

-- Brake factor applied to forward speed during a turn. Sharper turns taken at
-- higher speed shed more momentum ("plant & push off" rather than a wheeled
-- drift), but only gently — a single readable penalty term instead of the old
-- compounding hyperbola, which slowed gentle turns far too hard (a 90° turn
-- used to drop you to ~13% speed). Now:
--   straight  -> 1.00      45° @ full speed -> ~0.89
--   90°       -> ~0.78     180° @ full speed -> ~0.55
-- and at a crawl you keep almost all your speed (pivot freely). Floored at 0.4
-- so the creature never stalls mid-turn.
function MovementMath.GetBrakeFactor(angleDiff: number, currentSpeed: number, turnBrakeSensitivity: number): number
	local sharpness = angleDiff / math.pi -- 0 = straight, 1 = full reversal
	local speedFactor = math.clamp(currentSpeed / 50, 0, 1)
	local penalty = sharpness * speedFactor * turnBrakeSensitivity * 0.15
	return math.clamp(1 - penalty, 0.4, 1)
end

-- Multiplier applied to turn rate when redirecting. Sharper desired angle
-- => faster turn so the character finishes aligning quicker.
function MovementMath.GetTurnBoost(angleDiff: number): number
	return 1 + (angleDiff * 0.5)
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
