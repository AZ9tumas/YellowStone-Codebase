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
	    server-driven, replicated WalkSpeed via Stats.GaitFromSpeed — pure speed
	    bands, no buffer. It drives the ANIMATION, so it climbs the ladder while
	    accelerating and descends it while coasting to a stop (the walk/run frames
	    you see on release) at zero network cost.
	  * The INTENT gait (from input) is the only locomotion value networked.
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
local AnimationController = require(ReplicatedStorage.Modules.AnimationController)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MovementController = Knit.CreateController({ Name = "MovementController" })

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
	return {
		moveVector = moveVector,
		hasMoveInput = moveVector.Magnitude > 0,
		shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift),
		walkStyle = object.walkStyle,
		runStyle = object.runStyle,
		currentSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude,
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

-- VISUAL gait band from the server-driven WalkSpeed (the animation source).
-- WalkSpeed replicates here for free, so reading the band each frame makes the
-- animation climb the ladder while accelerating AND descend it while coasting
-- to a stop. A freezing action shows Idle.
local function resolveVisualGait(object, sm)
	if sm:FreezesMovement() then
		return "Idle"
	end

	-- Use assembly linear velocity instead of walkspeed
	-- to have more realistic animations based on movement state.
	
	local sp = object.HRP.AssemblyLinearVelocity or Vector3.zero
	sp = math.floor(sp.Magnitude)
	
	return Stats.GaitFromSpeed(
		sp, -- object.Humanoid.WalkSpeed,
		object.info.WalkSpeed,
		object.info.TrotSpeed,
		object.info.RunSpeed
	)
end

local function updateState(self, object, ctx)
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

	-- Animation: the visual gait tracks the actual (server-driven) speed. One
	-- call, the animation id follows from the gait name (StateMachine.GaitChanged
	-- -> AnimationController:PlayGait).
	sm:SetGait(resolveVisualGait(object, sm))

	-- Networking: report the input intent, only on a real change.
	local intent = resolveIntent(sm, ctx)
	if intent ~= object.lastIntent then
		object.lastIntent = intent
		self.MovementService.SetState:Fire(intent)
	end
end

-- Turning + velocity. Turning is free (capped per gait); the speed penalty is
-- paid from the rate of orientation change. All client-side.
local function updateMovement(self, object, ctx, dt)
	local sm = object.StateMachine

	-- Target direction (camera-relative input, flattened) or hold facing.
	local targetDir = object.Facing
	if ctx.hasMoveInput then
		local d = camera.CFrame:VectorToWorldSpace(ctx.moveVector)
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.001 then
			targetDir = d.Unit
		end
	end

	-- Turning is FREE: always turn toward the target at the max rate the current
	-- gait allows (the per-state TurnRate; BaseTurnRate is the guaranteed fallback
	-- for gaits that don't define their own). Speed no longer throttles the turn.
	local gait = sm:GetGait()
	local maxTurnRate = object.info[gait .. "TurnRate"] or object.info.BaseTurnRate

	local currentDir = object.Facing
	local dot = math.clamp(currentDir:Dot(targetDir), -1, 1)
	local angleDiff = math.acos(dot)
	object.TurnAngleDeg = math.deg(angleDiff) -- stored for debug display

	-- While resting, controls are fully disabled: no turning here, and the
	-- velocity is zeroed below via FreezesMovement(). Movement input is consumed
	-- only to pop rest levels (see updateState).
	local appliedTurn = 0
	if ctx.hasMoveInput and angleDiff > 0.001 and not sm:IsResting() then
		local maxStep = maxTurnRate * dt -- the gait's max turn-angle this frame
		appliedTurn = math.min(angleDiff, maxStep)
		local turnSign = math.sign(currentDir:Cross(targetDir).Y)
		if turnSign == 0 then
			turnSign = 1
		end
		object.Facing = (CFrame.Angles(0, appliedTurn * turnSign, 0) * currentDir).Unit
	end

	-- Speed is INVERSELY proportional to the rate of orientation change: the
	-- faster we reorient (relative to the gait's max turn rate) the more speed we
	-- shed, so a sharp turn bleeds a lot and a straight line none. Eased so we
	-- decelerate into the turn and accelerate back out, and it recovers once the
	-- heading stabilises. This stays 100% client-side — the server keeps ramping
	-- WalkSpeed toward the gait intent and never learns about the turn, so the
	-- networking is untouched.
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

	-- Speed penalty is based on the DEMANDED turn ANGLE (framerate-independent),
	-- not the per-frame rate, then eased for a smooth decelerate-into / accelerate-
	-- out of the turn. 100% client-side; the server never learns about the turn.
	local targetBrake = Stats.GetTurnSpeedFactor(angleDiff, object.info.TurnBrakeSensitivity)
	object.TurnBrake = object.TurnBrake + (targetBrake - object.TurnBrake) * math.min(dt * TURN_BRAKE_RESPONSE, 1)

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

	local targetTiltRad = math.clamp(turnRateNow * info.TiltSensitivity, -math.rad(info.MaxTiltAngle), math.rad(info.MaxTiltAngle))
	object.Tilt = object.Tilt + (targetTiltRad - object.Tilt) * math.min(dt * info.TiltSpeed, 1)

	-- Placeholder resting lean: ease toward the pose for the current rest depth
	-- (0 when standing). Cosmetic only — remove with REST_PITCH when animated.
	local restDepth = object.StateMachine:GetRestDepth()
	local targetRestPitch = if restDepth > 0 then REST_PITCH[restDepth] else 0
	object.RestPitch = object.RestPitch + (targetRestPitch - object.RestPitch) * math.min(dt * REST_PITCH_SPEED, 1)

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

	local alpha = math.clamp(dt * info.TerrainAlignmentSpeed, 0, 1)
	object.TerrainNormal = object.TerrainNormal:Lerp(targetNormal, alpha)

	local rightVec = object.Facing:Cross(object.TerrainNormal)
	if rightVec.Magnitude < 0.001 then
		rightVec = Vector3.xAxis
	end

	local targetCF = CFrame.fromMatrix(Vector3.zero, rightVec, object.TerrainNormal)
	object.CFrame = targetCF * CFrame.Angles(object.RestPitch, 0, object.Tilt)
	ao.CFrame = object.CFrame
end

local function updateAnimationSpeed(object)
	local gait = object.StateMachine:GetGait()
	if gait == "Idle" then
		object.AnimationController:SetAnimationSpeed("Idle", 1)
		return
	end
	local targetSpeed = object.info[gait .. "Speed"]
	if targetSpeed and targetSpeed > 0 then
		local vel = object.HRP.AssemblyLinearVelocity
		local currentSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local ratio = math.clamp(currentSpeed / targetSpeed, 0.5, 1.2)
		object.AnimationController:SetAnimationSpeed(gait, ratio)
	end
end

local function update(self, object, dt)
	local char = object.Character
	if not char or object.Humanoid.Parent ~= char or object.HRP.Parent ~= char then
		return
	end
	local ctx = buildContext(self, object)
	updateState(self, object, ctx)
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

	local object = {
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
