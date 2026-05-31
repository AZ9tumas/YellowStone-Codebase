--[[
	StaminaMath

	Stamina and health-penalty math. Pure helpers — they take primitives
	(or a Humanoid for the health helper) and return the new value, never
	mutating game state directly.
]]

local StaminaMath = {}

-- Multiplier applied to target speed when the humanoid's health falls
-- below `thresholdRatio * MaxHealth`. Returns 1 above the threshold; ramps
-- down linearly to `1 - speedReduction` at zero health.
function StaminaMath.HealthBasedSpeedMultiplier(
	humanoid: Humanoid?,
	speedReduction: number?,
	thresholdRatio: number?
): number
	if not humanoid or not speedReduction or speedReduction <= 0 then
		return 1
	end

	local threshold = humanoid.MaxHealth * (thresholdRatio or 0.5)
	if threshold <= 0 then
		return 1
	end

	local health = humanoid.Health
	if health >= threshold then
		return 1
	end

	local ratio = math.clamp(health / threshold, 0, 1)
	return 1 - speedReduction * (1 - ratio)
end

-- Apply `drainAmount` stamina points to `currentStamina` (0..1 normalised).
-- Returns the new 0..1 stamina value, clamped at zero.
function StaminaMath.ApplyStaminaDrain(currentStamina: number, maxStamina: number, drainAmount: number): number
	local currentPoints = currentStamina * maxStamina
	local newPoints = math.max(currentPoints - drainAmount, 0)
	return newPoints / maxStamina
end

-- Apply `gainAmount` stamina points to `currentStamina` (0..1 normalised).
-- Returns the new 0..1 stamina value, clamped at 1.
function StaminaMath.ApplyStaminaGain(currentStamina: number, maxStamina: number, gainAmount: number): number
	local currentPoints = currentStamina * maxStamina
	local newPoints = math.min(currentPoints + gainAmount, maxStamina)
	return newPoints / maxStamina
end

-- Compute the speed allowed by the current stamina level for Run / Sprint
-- states. Above the penalty threshold the full `targetSpeed` is allowed;
-- below it the speed lerps toward `trotSpeed`, with a small Sprint-only
-- bonus driven by the Sprint/Run speed ratio.
function StaminaMath.GetStaminaPenalizedSpeed(
	targetSpeed: number,
	trotSpeed: number,
	runSpeed: number,
	sprintSpeed: number,
	currentStamina: number,
	threshold: number,
	stateType: string
): number
	if currentStamina >= threshold then
		return targetSpeed
	end

	local pdiff = (sprintSpeed - runSpeed) / runSpeed
	local finalSpeed = trotSpeed + (targetSpeed - trotSpeed) * (currentStamina / threshold)
	if stateType == "Sprint" then
		finalSpeed += trotSpeed * pdiff * (if currentStamina > 0 then 1 else 0)
	end
	return finalSpeed
end

-- Attack cost helper: sums penalty cost from low health + low stamina and
-- returns the final post-cost attack damage.
function StaminaMath.GetAttackDamage(
	baseDamage: number,
	humanoid: Humanoid,
	currentStamina: number,
	healthAttackCost: number,
	staminaAttackCost: number,
	healthPenaltyThreshold: number,
	staminaPenaltyThreshold: number
): number
	local totalCost = 0

	local healthThreshold = healthPenaltyThreshold * humanoid.MaxHealth
	if humanoid.Health <= healthThreshold and healthThreshold > 0 then
		totalCost += healthAttackCost * (1 - humanoid.Health / healthThreshold)
	end

	if currentStamina <= staminaPenaltyThreshold and staminaPenaltyThreshold > 0 then
		totalCost += staminaAttackCost * (1 - currentStamina / staminaPenaltyThreshold)
	end

	return baseDamage * (1 - totalCost)
end

return StaminaMath
