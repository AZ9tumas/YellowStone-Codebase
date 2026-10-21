--[[
	BodyArticulation

	Procedural body language for a skinned quadruped: the head leads into a
	turn, the spine bends through it, and the hindquarters and tail lag behind
	and settle. Pure forward kinematics on Bone.Transform — no IK, no physics
	change, no network traffic. Every client runs this for every creature it
	can see, from state that already replicates (facing, velocity).

	How it works
	  * The rig is chest-rooted: Chest > Back.001 > Back.002 > Lowe Back >
	    {pelvis, hind legs, tail}. Yawing a spine bone swings everything behind
	    it. Chest is never yawed — it only banks. (The neck is NOT under
	    Chest: Chest and Neck.001 are siblings under Chest.IK, so the bank
	    tilts the body and the legs without cocking the head.)
	  * Each chain (Spine / Neck / Tail) owns a spring-damper tracking a yaw
	    signal. The chain's visible bend is the DIFFERENCE between its filtered
	    yaw and the yaw it is measured against:
	        Spine : tracks body yaw and lags it        -> rear falls behind
	        Neck  : tracks the DEMANDED heading, leads -> head anticipates
	        Tail  : tracks the spine's output, lags more -> whip
	    When the turn ends every filter converges on its reference, the bend
	    goes to zero and the rig relaxes onto the animated pose. The layer is
	    self-zeroing by construction and cannot drift.
	  * The bend is shared down the chain's bones by weight and applied about
	    the BODY'S up axis (the root's UpVector — the axis the body actually
	    turns about on a slope) expressed in each bone's LOCAL frame via
	    fromAxisAngle, so the lag never leaks into roll or pitch on a pitched
	    or rolled body, and no per-rig axis constants are needed.
	  * Bank: roll about the body's own forward axis, phi = atan(v*omega/g),
	    on the chest so the whole body inherits it.

	Engine contract (verified against docs + DevForum; see the wiki):
	  * Bone.Transform is written in RunService.PreSimulation — after the
	    Animator has written this frame's animation pose — and COMPOSED on top
	    of it.
	  * The Animator only rewrites Transform on bones the playing clip actually
	    keyframes (on the wolf, Idle keyframes Back.002 but NOT Back.001), and
	    skips distant rigs entirely when it throttles, so offsets must never be
	    composed blindly. BoneWriter owns that bookkeeping, and sharing one
	    writer is also what lets LegIK and HeadLook write the same bones as
	    this layer without the two stripping each other.
	  * Bone.Transform does not replicate. This must run on every client.

	Sign conventions (MEASURED on the rig, not derived):
	  * yaw = atan2(Facing.X, Facing.Z) increases on a LEFT turn.
	  * +theta about the body's up (equal to world-up on the flat, where this
	    was measured) swings a chain's far end to the body's RIGHT, so a
	    lagging rear (filtered yaw < body yaw during a left turn) applies
	    theta = filtered - body < 0 directly. No per-chain sign is needed.
	  * +phi about body-forward on Chest lifts the LEFT shoulder (lean right),
	    so banking INTO a left turn (omega > 0) is phi = -atan(v*omega/g).
]]

local MovementMath = require(script.Parent.Parent.Stats.MovementMath)
local BoneWriter = require(script.Parent.BoneWriter)

local BodyArticulation = {}
BodyArticulation.__index = BodyArticulation

local DT_MAX = 0.1 -- hitch guard on the integration step
local OMEGA_MAX = 20 -- rad/s, clamps the yaw-rate estimate after teleports
local SPEED_RESPONSE = 8 -- 1/s, smoothing of the raw speed signal (one owner: here)
local SCALE_RESPONSE = 8 -- 1/s, easing for the speed / suppression gain
local SCALE_EPS = 1e-3 -- below this a suppressed creature stops writing bones
local HEADING_EPS = 1e-6 -- |xz|^2 below this = no usable heading (vector is vertical)

export type ChainConfig = {
	Name: string,
	Bones: { string },
	Weights: { number }?, -- per-bone share of the bend; omitted = even split
	MaxYaw: number, -- deg, hard clamp on the chain's total bend
	Frequency: number, -- Hz, how fast the chain responds
	Damping: number, -- ratio; < 1 overshoots and settles
	TracksTarget: boolean?, -- chase the demanded heading (lead) instead of body yaw
	Follows: string?, -- chase another chain's filtered yaw (must be declared earlier)
}

export type BankConfig = {
	Bone: string,
	MaxRoll: number, -- deg
	Frequency: number,
	Damping: number,
}

export type Config = {
	SpeedRef: string, -- creature speed key the effect scales in against
	IdleScale: number, -- gain when stationary, 0..1
	Chains: { ChainConfig }?, -- may be omitted for a bank-only creature (neither Chains nor Bank is rejected)
	Bank: BankConfig?,
}

export type Signals = {
	-- PHYSICAL root orientation (HumanoidRootPart.LookVector) — the frame the
	-- bones actually ride on. Never a desired/target heading: anything the
	-- body is still chasing would make the spine read as leading instead of
	-- lagging while the body catches up. Yaw uses the X/Z components; the
	-- full vector (with its pitch on slopes) is the bank axis.
	Facing: Vector3,
	-- The root's UpVector: the axis the body turns about. World-up is wrong on
	-- a slope (half of a spine bend would leak into roll on a climb).
	Up: Vector3,
	TargetDir: Vector3?, -- demanded heading; nil = Facing
	-- Raw horizontal speed, studs/s, capped at the replicated WalkSpeed by the
	-- caller. Smoothed HERE so every driver produces the same gain and bank.
	Speed: number,
	Suppressed: boolean?, -- resting / frozen / far away: gain eases to 0
	-- +1 left / -1 right, ONLY while the controller is actually steering;
	-- nil otherwise. Decides which way round a near-reversal demand is taken.
	TurnSign: number?,
}

export type Debug = {
	Chains: { [string]: number }, -- each chain's bend by name, degrees
	Bank: number?, -- chest roll, degrees
	Gain: number, -- 0..1
	Omega: number, -- physical yaw rate, rad/s
}

type Chain = {
	name: string,
	bones: { Bone },
	weights: { number },
	maxYaw: number,
	stiffness: number,
	damping: number,
	tracksTarget: boolean,
	follows: Chain?,
	yaw: number,
	vel: number,
	goalPrev: number,
	bend: number,
}

type Bank = {
	bone: Bone,
	maxRoll: number,
	stiffness: number,
	damping: number,
	angle: number,
	vel: number,
}

export type BodyArticulation = typeof(setmetatable(
	{} :: {
		speedRef: number,
		idleScale: number,
		chains: { Chain },
		bank: Bank?,
		seeded: boolean,
		bodyYaw: number,
		omega: number,
		speed: number,
		scale: number,
		writer: BoneWriter.BoneWriter,
	},
	BodyArticulation
))

-- ===== helpers ===============================================================

-- Signed shortest angle in (-pi, pi].
local function wrapPi(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Continue an unwrapped angle series with a new wrapped sample.
local function unwrap(prev: number, raw: number): number
	return prev + wrapPi(raw - prev)
end

-- Every bone name a config touches. Used by the drivers to wait for a rig
-- that is still replicating before constructing.
function BodyArticulation.RequiredBones(config: Config): { string }
	local names = {}
	for _, chain in ipairs(config.Chains or {}) do
		for _, n in chain.Bones do
			names[#names + 1] = n
		end
	end
	if config.Bank then
		names[#names + 1] = config.Bank.Bone
	end
	return names
end

-- Configured bone names not (yet) present on the character. Empty = ready.
function BodyArticulation.MissingBones(character: Model, config: Config): { string }
	return BoneWriter.Missing(character, BodyArticulation.RequiredBones(config))
end

-- ===== construction ==========================================================

-- Resolve a creature's optional BodyArticulation block: nil when the creature
-- has none (feature off), otherwise a live instance. The one place SpeedRef
-- is looked up and validated, whoever the caller is.
function BodyArticulation.fromInfo(
	character: Model,
	info: { [string]: any },
	writer: BoneWriter.BoneWriter
): BodyArticulation?
	local config = info.BodyArticulation
	if not config then
		return nil
	end
	local speedRef = info[config.SpeedRef]
	assert(
		type(speedRef) == "number" and speedRef > 0,
		`BodyArticulation: SpeedRef "{tostring(config.SpeedRef)}" is not a positive speed stat on this creature`
	)
	return BodyArticulation.new(character, config, speedRef, writer)
end

function BodyArticulation.new(
	character: Model,
	config: Config,
	speedRef: number,
	writer: BoneWriter.BoneWriter
): BodyArticulation
	assert(type(config) == "table", "BodyArticulation: config missing")
	assert(writer, "BodyArticulation: a BoneWriter is required")
	assert(type(speedRef) == "number" and speedRef > 0, "BodyArticulation: speedRef must be a positive number")
	assert(
		type(config.IdleScale) == "number" and config.IdleScale >= 0 and config.IdleScale <= 1,
		"BodyArticulation: IdleScale must be in 0..1"
	)
	local chainConfigs = config.Chains or {}
	assert(type(chainConfigs) == "table", "BodyArticulation: Chains must be an array")
	assert(#chainConfigs > 0 or config.Bank, "BodyArticulation: config declares neither Chains nor Bank")

	-- Within this layer every bone has exactly one owner: two chains (or a
	-- chain and Bank) sharing one would silently strip each other every frame.
	-- Sharing a bone with a DIFFERENT layer is fine — that is what the writer
	-- is for.
	local claim = BoneWriter.Claimer(character, "BodyArticulation")

	local self = setmetatable({}, BodyArticulation)
	self.speedRef = speedRef
	self.idleScale = config.IdleScale
	self.chains = {}
	self.seeded = false
	self.bodyYaw = 0
	self.omega = 0
	self.speed = 0
	self.scale = 0
	self.writer = writer

	local chainByName: { [string]: Chain } = {}
	for _, cc in ipairs(chainConfigs) do
		local where = `chain "{tostring(cc.Name)}"`
		assert(type(cc.Name) == "string", "BodyArticulation: every chain needs a Name")
		assert(not chainByName[cc.Name], `BodyArticulation: duplicate chain "{cc.Name}"`)
		assert(type(cc.Bones) == "table" and #cc.Bones > 0, `BodyArticulation: {where} has no Bones`)
		assert(type(cc.MaxYaw) == "number" and cc.MaxYaw >= 0, `BodyArticulation: {where} MaxYaw must be a number >= 0`)
		assert(
			type(cc.Frequency) == "number" and type(cc.Damping) == "number",
			`BodyArticulation: {where} needs numeric Frequency and Damping`
		)
		assert(not (cc.Follows and cc.TracksTarget), `BodyArticulation: {where} cannot both Follow and TracksTarget`)

		local bones = {}
		for _, bn in cc.Bones do
			bones[#bones + 1] = claim(bn, where)
		end

		local weights = cc.Weights
		if weights then
			assert(#weights == #bones, `BodyArticulation: {where} has {#bones} bones but {#weights} weights`)
			local sum = 0
			for _, w in weights do
				assert(w >= 0, `BodyArticulation: {where} has a negative weight`)
				sum += w
			end
			assert(math.abs(sum - 1) < 1e-3, `BodyArticulation: {where} weights sum to {sum}, expected 1`)
		else
			weights = table.create(#bones, 1 / #bones)
		end

		local follows: Chain? = nil
		if cc.Follows then
			follows = chainByName[cc.Follows]
			assert(follows, `BodyArticulation: {where} follows "{cc.Follows}", which must be declared before it`)
		end

		local stiffness, damping = MovementMath.SpringParams(cc.Frequency, cc.Damping)
		local chain: Chain = {
			name = cc.Name,
			bones = bones,
			weights = weights,
			maxYaw = math.rad(cc.MaxYaw),
			stiffness = stiffness,
			damping = damping,
			tracksTarget = cc.TracksTarget == true,
			follows = follows,
			yaw = 0,
			vel = 0,
			goalPrev = 0,
			bend = 0,
		}
		self.chains[#self.chains + 1] = chain
		chainByName[cc.Name] = chain
	end

	if config.Bank then
		local b = config.Bank
		assert(type(b.MaxRoll) == "number" and b.MaxRoll >= 0, "BodyArticulation: Bank.MaxRoll must be a number >= 0")
		assert(
			type(b.Frequency) == "number" and type(b.Damping) == "number",
			"BodyArticulation: Bank needs numeric Frequency and Damping"
		)
		local stiffness, damping = MovementMath.SpringParams(b.Frequency, b.Damping)
		self.bank = {
			bone = claim(b.Bone, "Bank"),
			maxRoll = math.rad(b.MaxRoll),
			stiffness = stiffness,
			damping = damping,
			angle = 0,
			vel = 0,
		}
	end

	return self
end

-- ===== per-frame =============================================================

function BodyArticulation:Update(signals: Signals, dt: number)
	local f, up = signals.Facing, signals.Up
	-- No usable heading (vertical root, or a non-finite sample): skip the frame
	-- rather than feed a NaN into springs that would never recover.
	if f.X * f.X + f.Z * f.Z < HEADING_EPS or f.X ~= f.X or signals.Speed ~= signals.Speed then
		return
	end
	if up.Magnitude < 1e-4 then
		return
	end
	local raw = math.atan2(f.X, f.Z)

	-- First frame: seed every filter on the current heading and write nothing.
	if not self.seeded then
		self.seeded = true
		self.bodyYaw = raw
		for _, chain in ipairs(self.chains) do
			chain.yaw = raw
			chain.vel = 0
			chain.goalPrev = raw
		end
		return
	end

	-- Yaw rate from the REAL elapsed time; the integration step is clamped
	-- separately so a hitch neither inflates omega nor overshoots the springs.
	local realDt = math.max(dt, 1e-4)
	dt = math.min(realDt, DT_MAX)
	local bodyYaw = unwrap(self.bodyYaw, raw)
	self.omega = math.clamp((bodyYaw - self.bodyYaw) / realDt, -OMEGA_MAX, OMEGA_MAX)
	self.bodyYaw = bodyYaw

	-- Demanded heading in the same unwrapped space. The offset is measured
	-- from the PHYSICAL heading, but the controller chose its turn direction
	-- against the desired one, which the body trails by up to a few tens of
	-- degrees — so a near-reversal demand can land on the other side of 180°
	-- from the way the body is actually going. While the controller is
	-- steering it tells us which way, and any demand in the reversal
	-- half-plane is taken round that side; the bend is clamped, so a 200°
	-- goal is harmless and the head never flips sides mid-turn. Without a
	-- sign only an exact tie needs breaking, by the measured yaw rate.
	local targetYaw = bodyYaw
	local t = signals.TargetDir
	if t and t.X * t.X + t.Z * t.Z > HEADING_EPS then
		local off = wrapPi(math.atan2(t.X, t.Z) - raw)
		local sign = signals.TurnSign
		if sign then
			if math.abs(off) > math.pi * 0.5 and math.sign(off) ~= sign then
				off -= 2 * math.pi * math.sign(off)
			end
		elseif math.abs(off) > math.pi - 1e-3 then
			off = math.pi * (if self.omega ~= 0 then math.sign(self.omega) else math.sign(off))
		end
		targetYaw = bodyYaw + off
	end

	-- Speed is smoothed here, and only here, so every driver — local or
	-- remote — produces the same gain and bank for the same creature.
	self.speed += (signals.Speed - self.speed) * (1 - math.exp(-SPEED_RESPONSE * dt))
	local speed = self.speed

	-- Gain: fades in with speed, eases to 0 when suppressed. Applied to the
	-- bend, not the goal, so filter state stays continuous.
	local goalScale = if signals.Suppressed
		then 0
		else self.idleScale + (1 - self.idleScale) * math.clamp(speed / self.speedRef, 0, 1)
	self.scale += (goalScale - self.scale) * (1 - math.exp(-SCALE_RESPONSE * dt))
	local scale = self.scale

	-- The springs always integrate, so a suppressed creature's filters keep
	-- tracking its heading and there is nothing to swing through when the gain
	-- comes back. Only the bone writes are skipped once the gain has died; the
	-- writer hands those bones back to the animation at EndFrame.
	local writing = not (signals.Suppressed and scale < SCALE_EPS)
	local writer = self.writer

	-- Bank first: Chest is the ancestor of every chain, and each bone's yaw
	-- axis is read from its live world pose after its parents are written.
	local bank = self.bank
	if bank then
		local gravity = workspace.Gravity
		local goal = if gravity > 0
			then math.clamp(-math.atan(speed * self.omega / gravity), -bank.maxRoll, bank.maxRoll) * scale
			else 0
		bank.angle, bank.vel = MovementMath.SpringDamperExact(bank.angle, bank.vel, goal, bank.stiffness, bank.damping, dt)
		if writing then
			writer:Prepare(bank.bone)
			local axis = bank.bone.TransformedWorldCFrame:VectorToObjectSpace(f.Unit)
			writer:Add(bank.bone, CFrame.fromAxisAngle(axis, bank.angle))
		end
	end

	for _, chain in ipairs(self.chains) do
		local goal, ref
		if chain.follows then
			goal = chain.follows.yaw
			ref = goal
		elseif chain.tracksTarget then
			goal = targetYaw
			ref = bodyYaw
		else
			goal = bodyYaw
			ref = bodyYaw
		end
		-- The goal is a ramp during a turn but the exact spring solves for a
		-- goal held constant over the step. Integrating toward the midpoint of
		-- the previous and current goal removes the frame-rate dependence that
		-- holding the end-of-frame value would leave in the steady-state lag.
		local goalMid = 0.5 * (chain.goalPrev + goal)
		chain.goalPrev = goal
		chain.yaw, chain.vel =
			MovementMath.SpringDamperExact(chain.yaw, chain.vel, goalMid, chain.stiffness, chain.damping, dt)
		local bend = math.clamp((chain.yaw - ref) * scale, -chain.maxYaw, chain.maxYaw)
		chain.bend = bend

		if writing then
			for i, bone in ipairs(chain.bones) do
				writer:Prepare(bone)
				local axis = bone.TransformedWorldCFrame:VectorToObjectSpace(up)
				writer:Add(bone, CFrame.fromAxisAngle(axis, bend * chain.weights[i]))
			end
		end
	end
end

-- ===== introspection =========================================================

function BodyArticulation:HasBank(): boolean
	return self.bank ~= nil
end

-- Live values for the debug HUD. Chains live under their own key so a chain
-- may be named anything without colliding with the fixed fields.
function BodyArticulation:GetDebug(): Debug
	local chains = {}
	for _, chain in ipairs(self.chains) do
		chains[chain.name] = math.deg(chain.bend)
	end
	return {
		Chains = chains,
		Bank = if self.bank then math.deg(self.bank.angle) else nil,
		Gain = self.scale,
		Omega = self.omega,
	}
end

return BodyArticulation
