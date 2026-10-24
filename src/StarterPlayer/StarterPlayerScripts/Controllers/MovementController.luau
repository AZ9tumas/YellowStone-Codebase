--[[
	MovementController (Knit controller, client)

	Owns the local creature's locomotion. Singleton, but all per-life state
	lives in a rebuilt-each-spawn "MovementObject" so respawns are clean.

	Authority split:
	  * CLIENT owns facing + direction (the turning simulation here).
	  * SERVER owns speed magnitude. Each frame the LinearVelocity is set to
	      facing.Unit * commandedSpeed,   commandedSpeed <= Humanoid.WalkSpeed
	    where commandedSpeed is WalkSpeed shaved by the turn brake (regained
	    no faster than Acceleration, while input is held). Only MovementService
	    drives WalkSpeed, so the client can never exceed it.
	  * The client sends only its INPUT INTENT (the gait the player is asking
	    for), and only when it changes. Releasing input reports "Idle", the
	    server ramps WalkSpeed to 0, and the client decelerates its current
	    command toward 0 at Deceleration without recovering any turn-braked speed.

	Gaits:
	  * The VISUAL gait (Idle/Walk/Trot/Run/Sprint) is derived every frame from
	    the MEASURED horizontal speed — smoothed, then banded with hysteresis
	    (Stats.ResolveGaitFromVelocity). It drives the animation, so it climbs
	    the ladder while accelerating and descends it while coasting to a stop,
	    and it reflects client-side speed loss (turn braking) that the
	    server-driven WalkSpeed never sees.
	  * The INTENT gait (from input) is the only locomotion value networked.
	  * Actions (Eat/Drink/Fight/Rest) go through RequestAction; a freezing
	    action forces intent + visual gait to Idle and stops driving velocity.
	    The StateMachine owns all the restrictions.

	Turning:
	  * On the move, the facing turns toward the input at the gait's max rate
	    and the speed pays for it through the turn brake.
	  * A sharp demand can play an authored turn overlay (see TurnInPlace).
	    It tracks live input, loops while needed and cancels on release or
	    alignment. Translation and gait intent remain available throughout.

	Swimming (optional per creature, see Movement/Swimming):
	  * In Terrain water deep enough to float, SwimLift holds the root at the
	    surface and the visual gait comes from the swim ladder instead. The
	    server maps the intent to swim speeds on its own probe; this side only
	    floats the body, animates it and keeps the paws off the lake bed.

	Body language (all optional per creature, all purely visual — the physics
	facing is unchanged, and none of it replicates, so ArticulationController
	re-derives the same thing for everyone else's creature):
	  * BodyArticulation bends the spine/neck/tail and banks the chest from the
	    facing + demanded heading this controller already computes.
	  * LegIK plants the paws on the terrain under them.
	  * HeadLook follows the camera, or attends to nearby creatures by config.
	They share one BoneWriter and run in that order on a single PreSimulation
	connection, after the Animator — the RenderStepped sim loop above never
	touches bones. Order matters: the legs and head correct the pose the spine
	produced, and the hind legs hang off the very bones it bends.
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
local BodyArticulation = require(ReplicatedStorage.Modules.Movement.BodyArticulation)
local BoneWriter = require(ReplicatedStorage.Modules.Movement.BoneWriter)
local LegIK = require(ReplicatedStorage.Modules.Movement.LegIK)
local HeadLook = require(ReplicatedStorage.Modules.Movement.HeadLook)
local TurnInPlace = require(ReplicatedStorage.Modules.Movement.TurnInPlace)
local Swimming = require(ReplicatedStorage.Modules.Movement.Swimming)
local AnimationController = require(ReplicatedStorage.Modules.AnimationController)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MovementController = Knit.CreateController({ Name = "MovementController" })

export type obj = {
	Character: Model,
	Humanoid: Humanoid,
	HRP: BasePart,
	info: Common.CreatureInfo,
	BodyMovers: {
		LinearVelocity: LinearVelocity?,
		AlignOrientation: AlignOrientation?,
		SwimLift: LinearVelocity?, -- only for creatures that can swim
	},
	StateMachine: StateMachine.StateMachine,
	AnimationController: AnimationController.AnimationController,
	Articulation: BodyArticulation.BodyArticulation?,
	LegIK: LegIK.LegIK?,
	HeadLook: HeadLook.HeadLook?,
	TurnInPlace: TurnInPlace.TurnInPlace?,
	trove: Trove.Trove,

	Facing: Vector3,
	Turning: boolean, -- a turn overlay supplied the facing this frame
	TurnApplied: number, -- rad applied by the overlay, for the steering diagnostics
	TurnRateCap: number?, -- effective overlay cap this frame; nil for ordinary steering
	TargetDir: Vector3, -- demanded heading this frame (== Facing with no input)
	TurnSign: number?, -- +1 left / -1 right while actually steering; nil otherwise
	LastFacing: Vector3,
	Tilt: number,
	RestPitch: number,
	TurnBrake: number, -- CommandedSpeed / WalkSpeed (the curve's target while WalkSpeed is 0)
	CommandedSpeed: number, -- horizontal speed handed to the LinearVelocity this frame
	CFrame: CFrame,
	TerrainNormal: Vector3,
	Grounded: boolean,
	ForwardSlope: number,
	Swimming: boolean,
	SurfaceY: number?, -- water surface over the root, while swimming

	walkStyle: string,
	runStyle: string,
	lastIntent: string?,
	lastMoveInput: boolean,

	SmoothedSpeed: number,
	VisualGait: string,

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

-- How quickly speed is shed INTO a turn (per second). Higher = the creature
-- plants harder. Coming back OUT of a turn is capped by the creature's
-- Acceleration instead (Stats.StepTurnBrakedSpeed). Purely a client-side
-- feel knob.
local TURN_BRAKE_RESPONSE = 10

-- Exponential smoothing rate (per second) for the measured horizontal speed
-- that feeds the visual gait. High enough to track real acceleration, low
-- enough to swallow single-frame physics jitter (slope climbs, reorientation).
local SPEED_SMOOTH_RESPONSE = 8

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
	-- current facing. With no input the gap is zero; the speed step then
	-- decelerates toward zero rather than recovering the removed turn brake.
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
	local crossY = object.Facing:Cross(targetDir).Y
	-- Directly behind is ambiguous. Keep the previous side through floating
	-- point noise instead of swapping left/right clips every frame.
	local turnSign = if math.abs(crossY) < 1e-4 then (object.TurnSign or 1) else math.sign(crossY)

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
-- / Rest) overrides it to Idle so the server decelerates to a stop. Turn
-- animations never change intent. This is the ONLY locomotion value sent over
-- the network, and only when it changes.
local function resolveIntent(sm, ctx)
	if sm:FreezesMovement() or not ctx.hasMoveInput then
		return "Idle"
	end
	return if ctx.shiftHeld then ctx.runStyle else ctx.walkStyle
end

-- VISUAL gait band from the measured horizontal speed: smoothed, then banded
-- with hysteresis so slope climbs / reorientation jitter can't flap the
-- animation between bands.
local function resolveVisualGait(object, sm, ctx, dt)
	-- Cap at the server-driven WalkSpeed. Locomotion can never legitimately
	-- exceed the server's authority, so anything above it is a physics artifact
	-- (the AlignOrientation whipping the body measures ~2x WalkSpeed) that
	-- would spike the gait a band too high. Every real dynamic — turn braking,
	-- collisions, deceleration — happens below WalkSpeed and passes through.
	local raw = if sm:FreezesMovement() then 0 else math.min(ctx.currentSpeed, object.Humanoid.WalkSpeed)
	object.SmoothedSpeed += (raw - object.SmoothedSpeed) * (1 - math.exp(-SPEED_SMOOTH_RESPONSE * dt))

	object.VisualGait = if sm:FreezesMovement()
		then "Idle"
		elseif object.Swimming then Stats.ResolveSwimGaitFromVelocity(object.SmoothedSpeed, object.VisualGait, object.info.SwimSpeed)
		else Stats.ResolveGaitFromVelocity(
			object.SmoothedSpeed,
			object.VisualGait,
			object.info.WalkSpeed,
			object.info.TrotSpeed,
			object.info.RunSpeed
		)
	return object.VisualGait
end

-- Max turn rate (rad/s) for a gait: the per-gait override when the creature
-- defines one, else BaseTurnRate (asserted present at spawn).
local function turnRateForGait(info: Common.CreatureInfo, gait: string): number
	return info[gait .. "TurnRate"] or info.BaseTurnRate
end

-- The turn overlay supplies a live, interruptible rotation step. Run after
-- updateState so actions and the current gait's rate cap apply this frame.
local function updateTurnInPlace(object: obj, ctx, dt: number)
	local turner = object.TurnInPlace
	object.Turning = false
	object.TurnApplied = 0
	object.TurnRateCap = nil
	if not turner then
		return
	end
	local sm = object.StateMachine
	local facing, rateCap = turner:Update({
		Facing = object.Facing,
		Gap = ctx.angleGap,
		Sign = ctx.turnSign,
		Steering = ctx.hasMoveInput,
		-- The turn clips are footwork; there is nothing to step on in water.
		Grounded = not object.Swimming and object.Humanoid.FloorMaterial ~= Enum.Material.Air,
		Blocked = sm:HasAction(),
		MaxTurnRate = turnRateForGait(object.info, sm:GetGait()),
	}, dt)
	object.Turning = facing ~= nil
	if facing then
		object.TurnRateCap = rateCap
		object.TurnApplied = math.atan2(math.abs(object.Facing:Cross(facing).Y), object.Facing:Dot(facing))
		object.Facing = facing
	end
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

	-- Animation: the visual gait tracks the measured speed. One call — the
	-- animation follows from the state name (GaitChanged -> PlayGait).
	sm:SetGait(resolveVisualGait(object, sm, ctx, dt))

	-- Networking: report the input intent, only on a real change.
	local intent = resolveIntent(sm, ctx)
	if intent ~= object.lastIntent then
		object.lastIntent = intent
		self.MovementService.SetState:Fire(intent)
	end
end

-- Turning + velocity. Turning is free (capped per gait); the speed penalty is
-- paid from the demanded angle. All client-side.
local function updateMovement(self, object: obj, ctx, dt)
	local sm = object.StateMachine

	local angleDiff = ctx.angleGap
	object.TurnAngleDeg = math.deg(angleDiff) -- stored for debug display

	-- Turning is FREE: always turn toward the target at the max rate the gait
	-- allows. Speed does not throttle the turn; the brake below prices it.
	-- Resting disables the controls entirely (velocity is zeroed via
	-- FreezesMovement); movement input then only pops rest levels. A
	-- turn overlay may already have supplied this frame's rotation step.
	local maxTurnRate = object.TurnRateCap or turnRateForGait(object.info, sm:GetGait())
	local appliedTurn = object.TurnApplied
	if ctx.hasMoveInput and angleDiff > 0.001 and not sm:IsResting() and not object.Turning then
		appliedTurn = math.min(angleDiff, maxTurnRate * dt)
		object.Facing = (CFrame.Angles(0, appliedTurn * ctx.turnSign, 0) * object.Facing).Unit
	end

	local turnRateNow = appliedTurn / dt
	-- Raw turn rate as a fraction of this frame's cap (debug read-out), including
	-- a turn overlay's SpeedMultiplier. Deliberately
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
	-- off the creature's TurnBrakeCurve. Client-side only. A running turn
	-- clip plants the paws, so it may cap the brake lower still (TurnInPlace
	-- Brake) or the body would slide through the footwork.
	local targetBrake = Stats.EvaluateTurnBrakeCurve(angleDiff, object.info.TurnBrakeCurve)
	if object.Turning and object.TurnInPlace then
		targetBrake = math.min(targetBrake, object.TurnInPlace:GetBrake())
	end

	-- Velocity: always facing.Unit * CommandedSpeed. Magnitude is owned by the
	-- server (WalkSpeed); we only shave it locally for turns — shed fast going
	-- in, regained at Acceleration while input is held. On release, the current
	-- command falls toward zero at Deceleration, still capped by WalkSpeed.
	-- Unused server speed from a pivot must never become a forward burst.
	local lv = object.BodyMovers.LinearVelocity
	if not lv or not lv.Parent then
		return
	end

	-- Float at the surface. Vertical only, so it composes with the plane
	-- velocity below; on land it is off and gravity + the Humanoid own Y.
	local lift = object.BodyMovers.SwimLift
	if lift then
		lift.Enabled = object.Swimming
		if object.Swimming and object.SurfaceY then
			lift.LineVelocity = Swimming.LiftVelocity(
				object.HRP.Position.Y,
				object.SurfaceY,
				Swimming.RootHeight(object.Humanoid, object.HRP),
				object.info.Swimming
			)
		end
	end

	local walkSpeed = object.Humanoid.WalkSpeed
	local freezing = sm:FreezesMovement()
	local blockedClimb = (object.ForwardSlope or 0) > object.info.MaxClimbAngle
	if freezing or blockedClimb then
		-- Really stopped, so it accelerates away again from 0.
		object.CommandedSpeed = 0
		lv.PlaneVelocity = Vector2.zero
	else
		object.CommandedSpeed = Stats.StepTurnBrakedSpeed(
			object.CommandedSpeed,
			walkSpeed,
			targetBrake,
			dt,
			object.info.Acceleration,
			TURN_BRAKE_RESPONSE,
			ctx.hasMoveInput,
			object.info.Deceleration
		)
		local v = object.Facing * object.CommandedSpeed
		lv.PlaneVelocity = Vector2.new(v.X, v.Z)
	end
	object.TurnBrake = if walkSpeed > 1e-3 then object.CommandedSpeed / walkSpeed else targetBrake
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

	-- Bank into the turn, proportional to how fast the facing is changing.
	-- When BodyArticulation banks the chest bone instead, this whole-body
	-- tilt stays at 0 so the lean is never applied twice.
	-- All easing below uses 1 - exp(-k*dt): unlike min(dt*k, 1) it converges
	-- identically at any framerate.
	local targetTiltRad = 0
	if not (object.Articulation and object.Articulation:HasBank()) then
		targetTiltRad =
			math.clamp(turnRateNow * info.TiltSensitivity, -math.rad(info.MaxTiltAngle), math.rad(info.MaxTiltAngle))
	end
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
-- Uses the SMOOTHED speed so playback doesn't shiver with physics jitter.
local function updateAnimationSpeed(object)
	local gait = object.StateMachine:GetGait()
	if gait == "Idle" then
		object.AnimationController:SetAnimationSpeed("Idle", 1)
		return
	end
	-- The gait slot only ever holds locomotion gaits, so the speed key must
	-- exist — a missing one is a stats bug (the same contract MovementService
	-- asserts server-side). A configured 0 means "no scaling" (authored rate).
	local targetSpeed = object.info[gait .. "Speed"]
	assert(targetSpeed, `MovementController: no "{gait}Speed" configured`)
	if targetSpeed > 0 then
		local ratio = math.clamp(object.SmoothedSpeed / targetSpeed, 0.5, 1.2)
		object.AnimationController:SetAnimationSpeed(gait, ratio)
	end
end

-- Same rules as the server's probe (Movement/Swimming), decided locally so
-- the float and the animation react on the frame the root reaches the water.
local function updateSwimming(object: obj)
	local config = object.info.Swimming
	if not config then
		return
	end
	local root = object.HRP
	local surfaceY, bedY = Swimming.Probe(root.Position)
	object.Swimming = Swimming.Decide(
		object.Swimming,
		surfaceY,
		bedY,
		root.Position.Y,
		Swimming.RootHeight(object.Humanoid, root),
		config
	)
	object.SurfaceY = if object.Swimming then surfaceY else nil
end

local function update(self, object, dt)
	local char = object.Character
	if not char or object.Humanoid.Parent ~= char or object.HRP.Parent ~= char then
		return
	end
	updateSwimming(object)
	local ctx = buildContext(self, object)
	object.TargetDir = ctx.targetDir
	-- buildContext defaults the sign to +1 when there is nothing to turn
	-- toward; only a sign the controller is acting on may steer the neck.
	object.TurnSign = if ctx.hasMoveInput and ctx.angleGap > 0.001 then ctx.turnSign else nil
	updateState(self, object, ctx, dt)
	updateTurnInPlace(object, ctx, dt)
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

-- `spawnedChar` is the model SpawnService just created, or nil when it has
-- not replicated yet (it streams atomically and can trail the Spawned
-- remote). player.Character is NOT a substitute: at that moment it can still
-- resolve to the previous character, which has no creature rig at all.
function MovementController:_buildObject(spawnedChar: Model?)
	self:_destroyObject()
	-- This function yields several times. A second Spawned arriving mid-build
	-- starts a newer build; the older one must abandon rather than install a
	-- stale life over the new one.
	self.buildGen = (self.buildGen or 0) + 1
	local gen = self.buildGen

	local char = spawnedChar
	while not (char and char.Parent) do
		char = player.CharacterAdded:Wait()
	end
	local humanoid = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if self.buildGen ~= gen then
		return
	end
	if not humanoid or not hrp then
		warn("MovementController: character missing Humanoid/HumanoidRootPart")
		return
	end

	local info = Common.GetPlayerInfo(player)
	assert(info.BaseTurnRate, "MovementController: creature config missing BaseTurnRate")
	if info.Swimming then
		Swimming.CheckConfig(info.Swimming)
		assert(info.SwimSpeed, "MovementController: a creature that swims needs SwimSpeed")
	end

	-- The skinned mesh that carries the bones can replicate after the root.
	-- Wait for every bone EVERY layer needs, the same way the remote driver does.
	local required = {}
	local function need(names: { string })
		table.move(names, 1, #names, #required + 1, required)
	end
	if info.BodyArticulation then
		need(BodyArticulation.RequiredBones(info.BodyArticulation))
	end
	if info.LegIK then
		need(LegIK.RequiredBones(info.LegIK))
	end
	if info.HeadLook then
		need(HeadLook.RequiredBones(info.HeadLook))
	end
	if #required > 0 then
		local deadline = os.clock() + 10
		while #BoneWriter.Missing(char, required) > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		if self.buildGen ~= gen then
			return
		end
	end

	humanoid.AutoRotate = false
	-- SwimLift floats the body; the Humanoid's own swim physics would fight it.
	-- The owning client runs the Humanoid's states, so this is the place.
	if info.Swimming then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	end

	local trove = Trove.new()
	local sm = trove:Add(StateMachine.new())
	local animController = trove:Add(AnimationController.new(player))
	-- Optional: interruptible overlays with the creature's turn clips.
	local turner = TurnInPlace.fromInfo(info, animController)

	-- Optional procedural body language; each is nil when the creature has no
	-- config for it. A rig that never completed replication fails loud here,
	-- by design. One writer per character, shared by all three layers so they
	-- can write the same bone without stripping each other — it owns the
	-- release, so the layers themselves need no teardown.
	local writer = trove:Add(BoneWriter.new())
	local articulation = BodyArticulation.fromInfo(char, info, writer)
	local legIK = LegIK.fromInfo(char, info, writer)
	local headLook = HeadLook.fromInfo(char, info, writer)

	local object: obj = {
		Character = char,
		Humanoid = humanoid,
		HRP = hrp,
		info = info,
		BodyMovers = {
			LinearVelocity = hrp:WaitForChild("LinearVelocity", 5),
			AlignOrientation = hrp:WaitForChild("AlignOrientation", 5),
			SwimLift = if info.Swimming then hrp:WaitForChild("SwimLift", 5) else nil,
		},
		StateMachine = sm,
		AnimationController = animController,
		Articulation = articulation,
		LegIK = legIK,
		HeadLook = headLook,
		TurnInPlace = turner,
		trove = trove,

		Facing = hrp.CFrame.LookVector,
		Turning = false,
		TurnApplied = 0,
		TurnRateCap = nil,
		TargetDir = hrp.CFrame.LookVector,
		TurnSign = 1,
		LastFacing = hrp.CFrame.LookVector,
		Tilt = 0,
		RestPitch = 0,
		TurnBrake = 1,
		CommandedSpeed = 0,
		CFrame = hrp.CFrame,
		TerrainNormal = Vector3.yAxis,
		Grounded = true,
		ForwardSlope = 0,
		Swimming = false,
		SurfaceY = nil,

		walkStyle = "Walk",
		runStyle = "Sprint",
		lastIntent = nil,
		lastMoveInput = false,

		SmoothedSpeed = 0,
		VisualGait = "Idle",
	}

	-- Animations follow StateMachine signals (single source of truth).
	trove:Connect(sm.GaitChanged, function(newGait)
		animController:PlayGait(newGait)
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

	-- The mover waits above yielded too; bail if a newer build has started.
	if self.buildGen ~= gen then
		trove:Destroy()
		return
	end

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

	-- Bone writes must land AFTER the Animator has written this frame's pose,
	-- which is PreSimulation — not RenderStepped, where they would be stomped.
	--
	-- Facing here is the PHYSICAL root orientation, not object.Facing. The
	-- bones ride on the physical body, and the force-based AlignOrientation
	-- lets that body trail object.Facing by a few frames; measuring lag
	-- against the desired heading instead made the spine read as leading
	-- while the body was still catching up. object.TargetDir (the raw input
	-- intent) is what the neck anticipates toward.
	if articulation or legIK or headLook then
		-- Per-life publication state; the Trove owns this callback and its data.
		local lookSendClock = HeadLook.KEEPALIVE_INTERVAL
		local lastLookDirection: Vector3? = nil
		-- PreSimulation passes the physics step's delta time as its only argument.
		trove:Connect(RunService.PreSimulation, function(dt: number)
			if self.object ~= object then
				return
			end
			local rootCF = hrp.CFrame
			local up = rootCF.UpVector
			local suppressed = object.StateMachine:FreezesMovement()

			writer:BeginFrame()
			if articulation then
				-- The physical look is the facing projected onto the terrain
				-- plane, so on a side slope its X/Z yaw differs from the flat
				-- demanded heading. Project the demand the same way, or the
				-- neck holds a permanent "looking uphill" cock with the stick
				-- dead straight.
				local demand = object.TargetDir
				demand -= up * up:Dot(demand)
				local vel = hrp.AssemblyLinearVelocity
				articulation:Update({
					Facing = rootCF.LookVector,
					Up = up,
					TargetDir = demand,
					TurnSign = object.TurnSign,
					Speed = math.min(Vector3.new(vel.X, 0, vel.Z).Magnitude, humanoid.WalkSpeed),
					Suppressed = suppressed,
				}, dt)
			end
			-- After the spine: these correct the pose it produced, and the
			-- hind legs hang off the bones it just bent. A foot with no ground
			-- under it relaxes itself, so there is no airborne signal to pass.
			-- A stepped (clip-less) standstill turn hands the paws to the
			-- stepper for as long as it runs.
			if legIK then
				local turner = object.TurnInPlace
				-- Swimming paws hang free instead of reaching for the lake bed.
				legIK:Update({
					Up = up,
					Suppressed = suppressed or object.Swimming,
					Pivoting = turner ~= nil and turner:IsStepping(),
				}, dt)
			end
			if headLook then
				local lookDirection: Vector3? = nil
				local lookSuppressed = suppressed or humanoid.Health <= 0
				if headLook.cameraTracking then
					-- Direction, not camera position: zooming should not pull the
					-- head toward the viewer or change its aim through parallax.
					local currentCamera = workspace.CurrentCamera
					if currentCamera and not lookSuppressed then
						lookDirection = currentCamera.CFrame.LookVector
					end
					lookSendClock += dt
					local changed = (lookDirection == nil) ~= (lastLookDirection == nil)
						or (lookDirection ~= nil and lastLookDirection ~= nil and lookDirection:Dot(lastLookDirection) < HeadLook.CHANGE_COS)
					if lookSendClock >= HeadLook.SEND_INTERVAL and (changed or lookSendClock >= HeadLook.KEEPALIVE_INTERVAL) then
						self.HeadLookService.SetDirection:Fire(char, lookDirection)
						lastLookDirection = lookDirection
						lookSendClock = 0
					end
				end
				headLook:Update({
					Facing = rootCF.LookVector,
					Up = up,
					Direction = lookDirection,
					Suppressed = lookSuppressed,
				}, dt)
			end
			writer:EndFrame()
		end)
	end

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

-- Fraction of WalkSpeed currently commanded (1 = no penalty, 0.1 = hard turn,
-- or still climbing back out of one). Debug display; 1 with no character.
function MovementController:GetTurnBrake(): number
	return self.object and self.object.TurnBrake or 1
end

-- Horizontal speed the controller handed to the LinearVelocity last frame
-- (server WalkSpeed x turn brake, or 0 while frozen). Debug display: compare
-- it with the measured speed to see whether the physics is keeping up.
function MovementController:GetCommandedSpeed(): number
	return self.object and self.object.CommandedSpeed or 0
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

-- Live articulation values for the debug HUD (see BodyArticulation.Debug), or
-- nil when the creature has no BodyArticulation config.
function MovementController:GetArticulationDebug(): BodyArticulation.Debug?
	local obj = self.object
	return if obj and obj.Articulation then obj.Articulation:GetDebug() else nil
end

-- Live foot-planting values for the debug HUD, or nil with no LegIK config.
function MovementController:GetLegIKDebug(): LegIK.Debug?
	local obj = self.object
	return if obj and obj.LegIK then obj.LegIK:GetDebug() else nil
end

-- Live head-aim values for the debug HUD, or nil with no HeadLook config.
function MovementController:GetHeadLookDebug(): HeadLook.Debug?
	local obj = self.object
	return if obj and obj.HeadLook then obj.HeadLook:GetDebug() else nil
end

function MovementController:GetMaxTurnRate(): number
	return self.object and self.object.MaxTurnRate or 0
end

function MovementController:GetCamYawRate(): number
	return self.object and self.object.CamYawRate or 0
end

-- Live locomotion/action state for debug display: the visual gait, plus the
-- active action (Eat/Drink/Fight/Rest1/Rest2) or standstill turn (its clip, or
-- Step<angle><side>) when one is running.
function MovementController:GetState(): string
	local obj = self.object
	if not obj then
		return "—"
	end
	local sm = obj.StateMachine
	local action = sm:GetAction() or (obj.TurnInPlace and obj.TurnInPlace:GetLabel())
	return if action then sm:GetGait() .. " / " .. action else sm:GetGait()
end

-- ===== Lifecycle =============================================================

function MovementController:KnitInit()
	self.object = nil
	self.StylesChanged = Signal.new() -- (walkStyle, runStyle)
	self.ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
end

function MovementController:KnitStart()
	self.MovementService = Knit.GetService("MovementService")
	self.HeadLookService = Knit.GetService("HeadLookService")

	local SpawnService = Knit.GetService("SpawnService")
	SpawnService.Spawned:Connect(function(char: Model?)
		self:_buildObject(char)
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
		self:_buildObject(player.Character)
	end
end

return MovementController
