--[[
	MovementController (Knit controller, client)

	Owns the local creature's locomotion. Singleton — there is only ever one
	local character — but all per-life state lives in a rebuilt-each-spawn
	"MovementObject" so respawns are clean.

	Authority model:
	  * The client owns FACING and DIRECTION (the turning simulation here).
	  * The server owns SPEED MAGNITUDE: every frame the LinearVelocity is set to
	      facing.Unit * (Humanoid.WalkSpeed * brake)
	    where Humanoid.WalkSpeed is driven only by MovementService. The client
	    cannot exceed the server's speed.
	  * The client sends only its INPUT INTENT (the gait the player is asking
	    for) and only when it changes; the server ramps WalkSpeed toward it.
	    Releasing input reports "Idle" -> WalkSpeed ramps to 0 -> the magnitude
	    above shrinks to 0 -> the creature DECELERATES to a stop instead of the
	    instant Roblox halt. Acceleration from rest is the reverse.

	State / animation:
	  * The VISUAL gait (Idle/Walk/Trot/Run/Sprint) is read every frame from the
	    creature's MEASURED horizontal velocity — smoothed, then banded with
	    hysteresis (Stats.ResolveGaitFromVelocity). It drives the ANIMATION, so
	    it climbs the ladder while accelerating and descends it while coasting
	    to a stop, and it reflects client-side speed loss (turn braking) the
	    server-driven WalkSpeed never sees. The smoothing + hysteresis + the
	    horizontal-only measurement are what stop slope climbs / reorientation
	    jitter from flapping the gait (Idle->Walk, Walk->Trot) frame to frame.
	  * The INTENT gait (from input) is the only locomotion value networked.
	  * TURN-IN-PLACE (The-Isle-style): while near-stationary, a large gap
	    between the input direction and the current facing plays a dedicated
	    Turn90/Turn180 left/right state on the gait layer. The root rotation is
	    paced by the animation's remaining time (feet stay planted in sync) and
	    the turn brake holds the speed at 0 until the gap closes; the per-
	    creature TurnBrakeCurve decides how hard moving turns bleed speed.
	  * Actions (Eat/Drink/Fight/Rest) are requested via RequestAction; a freezing
	    action (Eat/Drink/Rest) forces intent + visual gait to Idle and stops
	    driving forward velocity. The StateMachine enforces all restrictions (e.g.
	    no Eat while Sprinting).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Stats = require(ReplicatedStorage.Modules.Stats)
local Common = require(ReplicatedStorage.Modules.Common)
local StateMachine = require(ReplicatedStorage.Modules.Movement.StateMachine)
local MovementStates = require(ReplicatedStorage.Modules.Movement.MovementStates)
local AnimationController = require(ReplicatedStorage.Modules.AnimationController)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MovementController = Knit.CreateController({ Name = "MovementController" })

-- types
export type obj = {
	Character: Model,
	Humanoid: Humanoid,
	HRP: BasePart,
	info: Common.CreatureInfo,
	BodyMovers: {
		LinearVelocity: LinearVelocity?,
		AlignOrientation: AlignOrientation?,
	},
	StateMachine: StateMachine.StateMachine,
	AnimationController: AnimationController.AnimationController,
	trove: Trove.Trove,

	Facing: Vector3,
	LastFacing: Vector3,
	Tilt: number,
	RestPitch: number,
	TurnBrake: number,
	CFrame: CFrame,
	TerrainNormal: Vector3,
	Grounded: boolean,
	ForwardSlope: number,

	walkStyle: string,
	runStyle: string,
	lastIntent: string?,
	lastMoveInput: boolean,

	SmoothedSpeed: number,
	VisualGait: string,
	TurnInPlace: string?,
	TurnInPlacePlaying: boolean,
	TurnInPlaceAge: number,
	TurnInPlaceRetryAt: number,

	TurnAngleDeg: number?,
	TurnRateFraction: number?,
	TurnRateRPS: number?,
	MaxTurnRate: number?,
	LastCamLook: Vector3?,
	CamYawRate: number?,
}

-- Placeholder resting pose until Rest1/Rest2 animations exist: a gentle nose-
-- down lean that deepens per rest level, applied through the normal orientation
-- pipeline (orientation only, no physics change). Purely cosmetic so the state
-- is visible now — delete these two lines once real rest animations land.
local REST_PITCH = { -math.rad(15), -math.rad(32) } -- index === rest depth (1 = Rest1, 2 = Rest2)
local REST_PITCH_SPEED = 6

-- How quickly the turn-speed penalty eases in and out (per second). Higher =
-- snappier decelerate-into / accelerate-out-of a turn; lower = floatier. Purely
-- a client-side feel knob.
local TURN_BRAKE_RESPONSE = 10

-- Exponential smoothing rate (per second) for the measured horizontal speed
-- that feeds the visual gait. High enough to track real acceleration, low
-- enough to swallow single-frame physics jitter (slope climbs, reorientation).
local SPEED_SMOOTH_RESPONSE = 8

-- Turn-in-place safety rails: cap the animation-paced rotation rate (rad/s);
-- abort a turn whose animation never becomes usable (failed/blocked asset load
-- keeps the track at Length 0) so the creature can never get stuck waiting on
-- a track; and back off re-triggering after such an abort so a broken asset
-- degrades to plain fast turning instead of a freeze/retry flicker loop.
local TURN_IN_PLACE_MAX_RATE = math.rad(360)
local TURN_IN_PLACE_START_TIMEOUT = 0.5
local TURN_IN_PLACE_RETRY_COOLDOWN = 3

-- ===== Ground probe ==========================================================
-- Four downward rays in a facing-aligned square around the HRP; averaged /
-- plane-fit normal + signed forward slope. (Ported unchanged — it was sound.)
local function detectGround(object, facingDir: Vector3): (Vector3, boolean, number)
	local char = object.Character
	local hrp = object.HRP
	if not char or not hrp or hrp.Parent ~= char then
		return Vector3.yAxis, false, 0
	end

	local probeDist = object.info.TerrainRaycastDistance

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }

	local size = hrp.Size
	local halfX = math.max(size.X * 0.5, 0.5)
	local halfZ = math.max(size.Z * 0.5, 0.5)
	local halfY = size.Y * 0.5

	local fwd = Vector3.new(facingDir.X, 0, facingDir.Z)
	if fwd.Magnitude < 1e-3 then
		fwd = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	end
	fwd = fwd.Unit
	local right = Vector3.new(fwd.Z, 0, -fwd.X)

	local center = hrp.Position
	local offsets = {
		fwd * halfZ + right * halfX,
		fwd * halfZ + right * -halfX,
		fwd * -halfZ + right * halfX,
		fwd * -halfZ + right * -halfX,
	}

	local castDir = Vector3.new(0, -(halfY + probeDist), 0)
	local hitPoints = table.create(4)
	local normalSum = Vector3.zero

	for _, off in ipairs(offsets) do
		local origin = center + off + Vector3.new(0, halfY * 0.5, 0)
		local r = workspace:Raycast(origin, castDir, rp)
		if r then
			hitPoints[#hitPoints + 1] = r.Position
			normalSum += r.Normal
		end
	end

	local grounded = #hitPoints >= 2
	if not grounded then
		return Vector3.yAxis, false, 0
	end

	local planeNormal
	if #hitPoints >= 3 then
		local n = Vector3.zero
		local samples = 0
		for i = 1, #hitPoints - 2 do
			for j = i + 1, #hitPoints - 1 do
				for k = j + 1, #hitPoints do
					local e1 = hitPoints[j] - hitPoints[i]
					local e2 = hitPoints[k] - hitPoints[i]
					local c = e1:Cross(e2)
					if c.Magnitude > 1e-4 then
						if c.Y < 0 then
							c = -c
						end
						n += c.Unit
						samples += 1
					end
				end
			end
		end
		planeNormal = (samples > 0 and n.Magnitude > 1e-3) and n.Unit or (normalSum / #hitPoints).Unit
	else
		planeNormal = (normalSum / #hitPoints).Unit
	end

	local projected = fwd - planeNormal * fwd:Dot(planeNormal)
	local forwardSlopeDeg = 0
	if projected.Magnitude > 1e-3 then
		projected = projected.Unit
		forwardSlopeDeg = math.deg(math.asin(math.clamp(projected.Y, -1, 1)))
	end

	return planeNormal, true, forwardSlopeDeg
end

-- ===== Per-frame phases ======================================================

local function buildContext(self, object)
	local moveVector = self.ControlModule:GetMoveVector()
	local vel = object.HRP.AssemblyLinearVelocity
	local hasMoveInput = moveVector.Magnitude > 0

	-- Desired heading (camera-relative input, flattened) and its gap from the
	-- current facing. With no input the target IS the facing => zero gap, so
	-- the brake always recovers to 1 when the sticks are released.
	local targetDir = object.Facing
	if hasMoveInput then
		local d = camera.CFrame:VectorToWorldSpace(moveVector)
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.001 then
			targetDir = d.Unit
		end
	end
	local dot = math.clamp(object.Facing:Dot(targetDir), -1, 1)
	local angleGap = math.acos(dot)
	-- +1 = target is to the LEFT of the facing (counter-clockwise from above).
	local turnSign = math.sign(object.Facing:Cross(targetDir).Y)
	if turnSign == 0 then
		turnSign = 1
	end

	return {
		moveVector = moveVector,
		hasMoveInput = hasMoveInput,
		shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift),
		walkStyle = object.walkStyle,
		runStyle = object.runStyle,
		-- Horizontal only: climbing a slope adds vertical velocity that must not
		-- count toward the locomotion speed (it pushed the 3D magnitude into the
		-- next gait band and caused the Walk->Trot flicker on hills).
		currentSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude,
		targetDir = targetDir,
		angleGap = angleGap,
		turnSign = turnSign,
	}
end

-- Locomotion INTENT from raw input: the gait the player is asking for, which is
-- the target the server ramps WalkSpeed toward. A freezing action (Eat / Drink
-- / Rest) overrides it to Idle so the server decelerates to a stop. This is the
-- ONLY locomotion value sent over the network, and only when it changes.
local function resolveIntent(sm, ctx)
	if sm:FreezesMovement() or not ctx.hasMoveInput then
		return "Idle"
	end
	return if ctx.shiftHeld then ctx.runStyle else ctx.walkStyle
end

-- VISUAL gait band from the creature's measured horizontal velocity, smoothed
-- (exponential, framerate-independent) and resolved with hysteresis so slope
-- climbs / reorientation jitter can't flap the animation between bands. The
-- smoothed speed lives on the object; `object.VisualGait` is always one of the
-- five locomotion gaits (turn-in-place overrides happen at the SetGait site,
-- never here, so the hysteresis always has a valid previous band to work from).
local function resolveVisualGait(object, sm, ctx, dt)
	-- Cap the measured speed at the server-driven WalkSpeed: locomotion can
	-- never legitimately exceed the server's authority, so anything above it is
	-- a physics artifact (measured ~2x WalkSpeed while the AlignOrientation
	-- whips the body toward a new heading), which would spike the gait a band
	-- too high. Every real dynamic (turn braking, collisions, deceleration)
	-- happens BELOW WalkSpeed and passes through untouched.
	local raw = if sm:FreezesMovement() then 0 else math.min(ctx.currentSpeed, object.Humanoid.WalkSpeed)
	object.SmoothedSpeed += (raw - object.SmoothedSpeed) * (1 - math.exp(-SPEED_SMOOTH_RESPONSE * dt))

	object.VisualGait = if sm:FreezesMovement()
		then "Idle"
		else Stats.ResolveGaitFromVelocity(
			object.SmoothedSpeed,
			object.VisualGait,
			object.info.WalkSpeed,
			object.info.TrotSpeed,
			object.info.RunSpeed
		)
	return object.VisualGait
end

-- Turn-in-place resolution (The-Isle-style). Returns the turn state to show on
-- the gait layer, or nil for normal speed-derived gait. A turn STARTS when the
-- creature is grounded, near-stationary and the demanded heading is at least
-- MinAngle off the facing; it ENDS when the gap closes below ExitAngle, input
-- is released, a freezing action starts, or the one-shot track finishes. The
-- chosen animation (90 vs 180, left vs right) is locked for the whole turn so
-- camera wiggle can't flicker between tracks mid-turn.
local function resolveTurnInPlace(object, ctx, dt): string?
	local sm = object.StateMachine
	local cfg = object.info.TurnInPlace
	if not cfg then
		return nil -- creature has no turn-in-place animations
	end

	local active = object.TurnInPlace
	if active then
		object.TurnInPlaceAge += dt
		local track = object.AnimationController:GetTrack(active)
		-- Healthy = playing with real content. A blocked/failed asset can report
		-- IsPlaying with Length 0 (no keyframes), which must count as stalled,
		-- not as running — never wait on such a track.
		local healthy = track ~= nil and track.IsPlaying and track.Length > 0
		if healthy then
			object.TurnInPlacePlaying = true
		end
		local finished = object.TurnInPlacePlaying and not (track and track.IsPlaying)
		local stalled = not healthy and object.TurnInPlaceAge > TURN_IN_PLACE_START_TIMEOUT

		if stalled then
			-- Track never became usable: back off so the retry loop can't freeze
			-- the creature; normal (non-animated) turning covers the gap.
			object.TurnInPlaceRetryAt = os.clock() + TURN_IN_PLACE_RETRY_COOLDOWN
			warn(`MovementController: turn-in-place track "{active}" never became playable (asset failed to load?)`)
		end

		if not ctx.hasMoveInput or sm:FreezesMovement() or ctx.angleGap < math.rad(cfg.ExitAngle) or finished or stalled then
			object.TurnInPlace = nil
			return nil
		end
		return active
	end

	if os.clock() < object.TurnInPlaceRetryAt then
		return nil
	end
	if not ctx.hasMoveInput or sm:IsResting() or sm:FreezesMovement() or not object.Grounded then
		return nil
	end
	if ctx.currentSpeed > cfg.MaxSpeed or ctx.angleGap < math.rad(cfg.MinAngle) then
		return nil
	end

	local arc = if math.deg(ctx.angleGap) >= cfg.Angle180 then "Turn180" else "Turn90"
	local side = if ctx.turnSign > 0 then "Left" else "Right"
	local state = arc .. side
	if not object.AnimationController:HasAnimation(state) then
		-- TurnInPlace config promises these tracks; a missing one is a setup bug.
		warn(`MovementController: TurnInPlace is configured but animation "{state}" is missing`)
		return nil
	end

	-- Only engage with a track that actually has content. All tracks are
	-- preloaded at spawn, so Length == 0 here means the asset hasn't finished
	-- loading (or failed/blocked) — engaging now would blank the gait layer
	-- with an empty one-shot. Retry again shortly; normal turning covers the
	-- gap meanwhile, so this degrades invisibly.
	local track = object.AnimationController:GetTrack(state)
	if not track or track.Length <= 0 then
		object.TurnInPlaceRetryAt = os.clock() + 1
		return nil
	end

	object.TurnInPlace = state
	object.TurnInPlaceAge = 0
	object.TurnInPlacePlaying = false
	return state
end

local function updateState(self, object, ctx, dt)
	local sm = object.StateMachine

	-- Resting consumes movement input as a "stand up one posture" command rather
	-- than locomotion. Step on the RISING edge of move input so one press = one
	-- level (Rest2 -> Rest1 -> standing).
	if sm:IsResting() then
		if ctx.hasMoveInput and not object.lastMoveInput then
			sm:ShallowRest()
		end
	else
		sm:AbortActionsIfNeeded(ctx)
	end
	object.lastMoveInput = ctx.hasMoveInput

	-- Animation: a running turn-in-place owns the gait layer; otherwise the
	-- visual gait tracks the measured speed. One call, the animation follows
	-- from the state name (StateMachine.GaitChanged -> PlayGait).
	local visualGait = resolveVisualGait(object, sm, ctx, dt)
	local turnState = resolveTurnInPlace(object, ctx, dt)
	sm:SetGait(turnState or visualGait)

	-- Networking: report the input intent, only on a real change. Turn states
	-- are never reported — while turning in place the intent stays the input
	-- gait, so the server pre-ramps WalkSpeed and the creature accelerates out
	-- of the turn the moment the brake releases.
	local intent = resolveIntent(sm, ctx)
	if intent ~= object.lastIntent then
		object.lastIntent = intent
		self.MovementService.SetState:Fire(intent)
	end
end

-- Turning + velocity. Turning is free (capped per gait); the speed penalty is
-- paid from the rate of orientation change. All client-side.
local function updateMovement(self, object: obj, ctx, dt)
	local sm = object.StateMachine

	-- Desired heading gap computed once per frame in buildContext (shared with
	-- the turn-in-place resolution in updateState).
	local angleDiff = ctx.angleGap
	object.TurnAngleDeg = math.deg(angleDiff) -- stored for debug display

	-- Turning is FREE: always turn toward the target at the max rate the current
	-- gait allows (the per-state TurnRate; BaseTurnRate is the guaranteed fallback
	-- for gaits that don't define their own). Speed no longer throttles the turn.
	local gait = sm:GetGait()
	local maxTurnRate = object.info[gait .. "TurnRate"] or object.info.BaseTurnRate

	local currentDir = object.Facing

	-- While resting, controls are fully disabled: no turning here, and the
	-- velocity is zeroed below via FreezesMovement(). Movement input is consumed
	-- only to pop rest levels (see updateState).
	local appliedTurn = 0
	if object.TurnInPlace then
		-- Animation-paced rotation: close the remaining gap over the remaining
		-- track time, so the root finishes rotating exactly when the one-shot
		-- ends and the planted feet stay in sync with the body (Isle-style).
		-- Until the track actually starts (<= 1 frame, bounded by the stall
		-- timeout in resolveTurnInPlace) the creature holds still.
		local track = object.AnimationController:GetTrack(object.TurnInPlace)
		if track and track.IsPlaying and track.Length > 0 and angleDiff > 0.001 then
			local remaining = math.max(track.Length - track.TimePosition, 1 / 30)
			local rate = math.min(angleDiff / remaining, TURN_IN_PLACE_MAX_RATE)
			appliedTurn = math.min(angleDiff, rate * dt)
			object.Facing = (CFrame.Angles(0, appliedTurn * ctx.turnSign, 0) * currentDir).Unit
		end
	elseif ctx.hasMoveInput and angleDiff > 0.001 and not sm:IsResting() then
		local maxStep = maxTurnRate * dt -- the gait's max turn-angle this frame
		appliedTurn = math.min(angleDiff, maxStep)
		object.Facing = (CFrame.Angles(0, appliedTurn * ctx.turnSign, 0) * currentDir).Unit
	end

	local turnRateNow = appliedTurn / dt
	-- Raw turn rate as a fraction of the gait's max (debug read-out). Deliberately
	-- NOT clamped so a value > 1 would reveal the per-frame turn cap being blown.
	object.TurnRateFraction = turnRateNow / maxTurnRate
	object.TurnRateRPS = turnRateNow
	object.MaxTurnRate = maxTurnRate

	-- Diagnostic: camera yaw angular velocity (rad/s). Reveals whether the camera
	-- itself is rotating while the player holds a straight line (feeds CamRate).
	local camLook = camera.CFrame.LookVector
	camLook = Vector3.new(camLook.X, 0, camLook.Z)
	if camLook.Magnitude > 1e-4 then
		camLook = camLook.Unit
		local prevCam = object.LastCamLook or camLook
		object.CamYawRate = math.acos(math.clamp(prevCam:Dot(camLook), -1, 1)) / dt
		object.LastCamLook = camLook
	end

	-- Speed penalty from the DEMANDED turn ANGLE (framerate-independent), read
	-- off the creature's own TurnBrakeCurve, then eased (exponential, framerate-
	-- independent) for a smooth decelerate-into / accelerate-out of the turn.
	-- A running turn-in-place targets 0 outright: the creature plants until the
	-- turn resolves, then the same easing accelerates it out. 100% client-side;
	-- the server never learns about the turn.
	local targetBrake
	if object.TurnInPlace then
		targetBrake = 0
	else
		targetBrake = Stats.EvaluateTurnBrakeCurve(angleDiff, object.info.TurnBrakeCurve)
	end
	object.TurnBrake += (targetBrake - object.TurnBrake) * (1 - math.exp(-TURN_BRAKE_RESPONSE * dt))

	-- Velocity: always facing.Unit * (WalkSpeed * TurnBrake). Magnitude is owned
	-- by the server (WalkSpeed); we only shave it locally for turns. We do NOT
	-- zero it on input release — the server ramps WalkSpeed to 0 and the magnitude
	-- follows, producing deceleration.
	local lv = object.BodyMovers.LinearVelocity
	if not lv or not lv.Parent then
		return
	end

	local freezing = sm:FreezesMovement()
	local blockedClimb = (object.ForwardSlope or 0) > object.info.MaxClimbAngle
	if freezing or blockedClimb then
		lv.PlaneVelocity = Vector2.zero
	else
		local v = object.Facing * (object.Humanoid.WalkSpeed * object.TurnBrake)
		lv.PlaneVelocity = Vector2.new(v.X, v.Z)
	end
end

-- Tilt (banking) + terrain alignment -> AlignOrientation.CFrame. (Ported.)
local function updateOrientation(self, object, dt)
	local ao = object.BodyMovers.AlignOrientation
	if not ao or not ao.Parent then
		return
	end
	local info = object.info

	local lastFacing = object.LastFacing or object.Facing
	local cross = lastFacing:Cross(object.Facing)
	local turnRateNow = math.asin(math.clamp(cross.Y, -1, 1)) / dt
	object.LastFacing = object.Facing

	-- No banking while turning in place — the creature is stationary, pivoting
	-- on its feet; a lean only makes sense with forward momentum.
	local targetTiltRad = if object.TurnInPlace
		then 0
		else math.clamp(turnRateNow * info.TiltSensitivity, -math.rad(info.MaxTiltAngle), math.rad(info.MaxTiltAngle))
	-- All orientation easing below uses the exponential form 1 - exp(-k*dt):
	-- unlike min(dt*k, 1) it converges identically at any framerate.
	object.Tilt += (targetTiltRad - object.Tilt) * (1 - math.exp(-info.TiltSpeed * dt))

	-- Placeholder resting lean: ease toward the pose for the current rest depth
	-- (0 when standing). Cosmetic only — remove with REST_PITCH when animated.
	local restDepth = object.StateMachine:GetRestDepth()
	local targetRestPitch = if restDepth > 0 then REST_PITCH[restDepth] else 0
	object.RestPitch += (targetRestPitch - object.RestPitch) * (1 - math.exp(-REST_PITCH_SPEED * dt))

	local targetNormal = Vector3.yAxis
	if info.TerrainAlignmentEnabled then
		local normal, grounded, slope = detectGround(object, object.Facing)
		object.Grounded = grounded
		object.ForwardSlope = slope
		if grounded then
			local maxAngle = math.rad(info.MaxTerrainAngle)
			local currentAngle = math.acos(math.clamp(normal:Dot(Vector3.yAxis), -1, 1))
			if currentAngle > maxAngle then
				local axis = Vector3.yAxis:Cross(normal)
				if axis.Magnitude > 0.001 then
					normal = CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(Vector3.yAxis)
				end
			end
			targetNormal = normal
		end
	end

	-- Ease toward the target normal, then RE-NORMALIZE: lerping two unit vectors
	-- yields a shorter one, and feeding a non-unit up-vector into fromMatrix
	-- below would shear the orientation the AlignOrientation chases.
	local alpha = 1 - math.exp(-info.TerrainAlignmentSpeed * dt)
	local blended = object.TerrainNormal:Lerp(targetNormal, alpha)
	object.TerrainNormal = if blended.Magnitude > 1e-4 then blended.Unit else targetNormal

	-- Orthonormal basis: rightVec = facing x up is perpendicular to the (unit)
	-- normal by construction, so after normalizing it, fromMatrix(_, right, up)
	-- produces a clean rotation with the facing projected onto the ground plane.
	local rightVec = object.Facing:Cross(object.TerrainNormal)
	rightVec = if rightVec.Magnitude > 0.001 then rightVec.Unit else Vector3.xAxis

	local targetCF = CFrame.fromMatrix(Vector3.zero, rightVec, object.TerrainNormal)
	object.CFrame = targetCF * CFrame.Angles(object.RestPitch, 0, object.Tilt)
	ao.CFrame = object.CFrame
end

-- Scale the playing gait cycle to the measured speed (feet track the ground).
-- Uses the SMOOTHED speed so the playback rate doesn't shiver with physics
-- jitter. Turn-in-place states have no "<state>Speed" config and are skipped —
-- their one-shots always play at authored speed (rotation is paced to them,
-- not the other way around).
local function updateAnimationSpeed(object)
	local gait = object.StateMachine:GetGait()
	if gait == "Idle" then
		object.AnimationController:SetAnimationSpeed("Idle", 1)
		return
	end
	local targetSpeed = object.info[gait .. "Speed"]
	if targetSpeed and targetSpeed > 0 then
		local ratio = math.clamp(object.SmoothedSpeed / targetSpeed, 0.5, 1.2)
		object.AnimationController:SetAnimationSpeed(gait, ratio)
	end
end

local function update(self, object, dt)
	local char = object.Character
	if not char or object.Humanoid.Parent ~= char or object.HRP.Parent ~= char then
		return
	end
	local ctx = buildContext(self, object)
	updateState(self, object, ctx, dt)
	updateMovement(self, object, ctx, dt)
	updateOrientation(self, object, dt)
	updateAnimationSpeed(object)
end

-- ===== Spawn / object lifecycle =============================================

function MovementController:_destroyObject()
	if self.object then
		self.object.trove:Destroy()
		self.object = nil
	end
end

function MovementController:_buildObject()
	self:_destroyObject()

	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not hrp then
		warn("MovementController: character missing Humanoid/HumanoidRootPart")
		return
	end

	local info = Common.GetPlayerInfo(player)
	assert(info.BaseTurnRate, "MovementController: creature config missing BaseTurnRate")

	humanoid.AutoRotate = false

	local trove = Trove.new()
	local sm = trove:Add(StateMachine.new())
	local animController = trove:Add(AnimationController.new(player))

	local object: obj = {
		Character = char,
		Humanoid = humanoid,
		HRP = hrp,
		info = info,
		BodyMovers = {
			LinearVelocity = hrp:WaitForChild("LinearVelocity", 5),
			AlignOrientation = hrp:WaitForChild("AlignOrientation", 5),
		},
		StateMachine = sm,
		AnimationController = animController,
		trove = trove,

		Facing = hrp.CFrame.LookVector,
		LastFacing = hrp.CFrame.LookVector,
		Tilt = 0,
		RestPitch = 0,
		TurnBrake = 1,
		CFrame = hrp.CFrame,
		TerrainNormal = Vector3.yAxis,
		Grounded = true,
		ForwardSlope = 0,

		walkStyle = "Walk",
		runStyle = "Sprint",
		lastIntent = nil,
		lastMoveInput = false,

		SmoothedSpeed = 0,
		VisualGait = "Idle",
		TurnInPlace = nil,
		TurnInPlacePlaying = false,
		TurnInPlaceAge = 0,
		TurnInPlaceRetryAt = 0,
	}

	-- Animations follow StateMachine signals (single source of truth). Turn
	-- states declare looped = false (one-shots); gaits loop.
	trove:Connect(sm.GaitChanged, function(newGait)
		local def = MovementStates.Get(newGait)
		animController:PlayGait(newGait, nil, def.looped ~= false)
	end)
	trove:Connect(sm.ActionChanged, function(newAction, oldAction)
		-- Stop the outgoing track first so action -> action swaps (e.g.
		-- Rest1 -> Rest2) don't leave the old pose layered underneath.
		if oldAction then
			animController:StopAction(oldAction)
		end
		if newAction and animController:HasAnimation(newAction) then
			animController:PlayAction(newAction)
		end
		-- Publish the resting posture (0 = standing, 1 = Rest1, 2 = Rest2) as a
		-- single value for UI / future rest animations to react to.
		humanoid:SetAttribute("RestState", sm:GetRestDepth())
	end)

	-- Reset any leftover velocity, prime the idle gait animation.
	if object.BodyMovers.LinearVelocity then
		object.BodyMovers.LinearVelocity.PlaneVelocity = Vector2.zero
	end
	animController:PlayGait("Idle")

	self.object = object

	trove:Connect(RunService.RenderStepped, function(dt)
		if self.object == object then
			update(self, object, dt)
		end
	end)

	-- Tear down when this character goes away.
	trove:Connect(player.CharacterRemoving, function(removing)
		if removing == char then
			self:_destroyObject()
		end
	end)
end

-- ===== Public API (for the survival/UI host) =================================

function MovementController:GetWalkingStyle(): string
	return self.object and self.object.walkStyle or "Walk"
end

function MovementController:GetRunningStyle(): string
	return self.object and self.object.runStyle or "Sprint"
end

function MovementController:ToggleWalkingStyle(): string
	if not self.object then
		return "Walk"
	end
	self.object.walkStyle = if self.object.walkStyle == "Walk" then "Trot" else "Walk"
	self.StylesChanged:Fire(self.object.walkStyle, self.object.runStyle)
	return self.object.walkStyle
end

function MovementController:ToggleRunningStyle(): string
	if not self.object then
		return "Sprint"
	end
	self.object.runStyle = if self.object.runStyle == "Sprint" then "Run" else "Sprint"
	self.StylesChanged:Fire(self.object.walkStyle, self.object.runStyle)
	return self.object.runStyle
end

-- Request an action (Eat/Drink/Fight). Returns ok, reason. Restrictions (e.g.
-- "no Eat while Sprinting") are enforced by the StateMachine.
function MovementController:RequestAction(name: string): (boolean, string?)
	if not self.object then
		return false, "no character"
	end
	local ctx = buildContext(self, self.object)
	return self.object.StateMachine:RequestAction(name, ctx)
end

function MovementController:ClearAction()
	if self.object then
		self.object.StateMachine:ClearAction()
	end
end

function MovementController:GetAction(): string?
	return self.object and self.object.StateMachine:GetAction() or nil
end

function MovementController:IsActionActive(name: string): boolean
	return self.object ~= nil and self.object.StateMachine:GetAction() == name
end

-- True while the creature is in any resting posture (Rest1/Rest2). Controls are
-- suppressed during rest; movement input rises one posture instead of moving.
function MovementController:IsResting(): boolean
	return self.object ~= nil and self.object.StateMachine:IsResting()
end

-- Current eased speed-penalty from turning (1 = no penalty, 0.1 = hard turn).
-- Exposed for debug display; will be 1 when no character is loaded.
function MovementController:GetTurnBrake(): number
	return self.object and self.object.TurnBrake or 1
end

-- Current angle between facing and input-target direction (degrees).
-- 0 = heading straight toward input; 180 = full reversal. Debug display.
function MovementController:GetTurnAngle(): number
	return self.object and self.object.TurnAngleDeg or 0
end

-- Raw turn rate as a fraction of the gait's max turn rate. UNCLAMPED, so a debug
-- read-out can reveal if it ever exceeds 1 (turning faster than the gait allows).
function MovementController:GetTurnRateFraction(): number
	return self.object and self.object.TurnRateFraction or 0
end

-- Diagnostic getters (debug HUD): raw turn rate (rad/s), the gait's max turn
-- rate, and the camera's yaw angular velocity (rad/s).
function MovementController:GetTurnRateRPS(): number
	return self.object and self.object.TurnRateRPS or 0
end

function MovementController:GetMaxTurnRate(): number
	return self.object and self.object.MaxTurnRate or 0
end

function MovementController:GetCamYawRate(): number
	return self.object and self.object.CamYawRate or 0
end

-- Live locomotion/action state for debug display: the visual gait, plus the
-- active action (Eat/Drink/Fight/Rest1/Rest2) when one is running.
function MovementController:GetState(): string
	local obj = self.object
	if not obj then
		return "—"
	end
	local sm = obj.StateMachine
	local action = sm:GetAction()
	if action then
		return sm:GetGait() .. " / " .. action
	end
	return sm:GetGait()
end

-- ===== Lifecycle =============================================================

function MovementController:KnitInit()
	self.object = nil
	self.StylesChanged = Signal.new() -- (walkStyle, runStyle)
	self.ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
end

function MovementController:KnitStart()
	self.MovementService = Knit.GetService("MovementService")

	local SpawnService = Knit.GetService("SpawnService")
	SpawnService.Spawned:Connect(function()
		self:_buildObject()
	end)

	-- Movement-affecting input: Z/X cycle the active gait tiers; R drives the
	-- resting posture (enter / sink deeper — movement input rises back out).
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.object then
			return
		end
		if input.KeyCode == Enum.KeyCode.Z then
			self:ToggleWalkingStyle()
		elseif input.KeyCode == Enum.KeyCode.X then
			self:ToggleRunningStyle()
		elseif input.KeyCode == Enum.KeyCode.R then
			self.object.StateMachine:DeepenRest()
		end
	end)

	-- If the controller starts after the player already spawned, build now.
	if Common.IsSpawned(player) and player.Character then
		self:_buildObject()
	end
end

return MovementController
