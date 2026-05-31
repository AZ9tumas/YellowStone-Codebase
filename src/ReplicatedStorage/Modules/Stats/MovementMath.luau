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

-- Brake factor applied to forward speed during a turn.
-- Sharper turns + higher speeds cause stronger deceleration ("plant & push off"
-- feel rather than a wheeled drift). Clamped to [0.05, 1] so the character
-- never freezes mid-turn.
function MovementMath.GetBrakeFactor(angleDiff: number, currentSpeed: number, turnBrakeSensitivity: number): number
	local speedFactor = math.clamp(currentSpeed / 30, 0, 1)
	local baseBrakeFactor = 1 / (1 + (angleDiff * turnBrakeSensitivity))
	local brakeFactor = baseBrakeFactor * (1 - (speedFactor * angleDiff * 0.15))
	return math.clamp(brakeFactor, 0.05, 1)
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

-- Constrain a requested high-tier state down to whatever the current
-- physical speed actually supports. Prevents teleporting from Idle straight
-- into Sprint animation when the character has not had time to accelerate.
function MovementMath.ConstrainState(
	desiredState: string,
	currentSpeed: number,
	walkSpeed: number,
	trotSpeed: number,
	threshold: number?
): string
	local t = threshold or 1.5
	local canRunOrSprint = currentSpeed >= (trotSpeed + t)
	local canTrot        = currentSpeed >= (walkSpeed + t)

	if desiredState == "Sprint" or desiredState == "Run" then
		if canRunOrSprint then
			return desiredState
		end
	end

	if desiredState == "Trot" or desiredState == "Sprint" or desiredState == "Run" then
		if canTrot then
			return "Trot"
		end
	end

	return "Walk"
end

return MovementMath
