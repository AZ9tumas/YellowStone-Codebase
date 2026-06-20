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
	  * Releasing input reports gait "Idle" -> server ramps WalkSpeed to 0 ->
	    the magnitude above shrinks to 0 -> the creature DECELERATES to a stop
	    instead of the instant Roblox halt. Acceleration from rest is the same in
	    reverse.

	State:
	  * Gait (Idle/Walk/Trot/Run/Sprint) is derived each frame by the StateMachine
	    and reported to the server on change.
	  * Actions (Eat/Drink/Fight) are requested via RequestAction; a freezing
	    action (Eat/Drink) reports Idle + stops driving forward velocity. The
	    StateMachine enforces all restrictions (e.g. no Eat while Sprinting).
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
		walkSpeed = object.info.WalkSpeed,
		trotSpeed = object.info.TrotSpeed,
	}
end

local function updateState(self, object, ctx)
	local sm = object.StateMachine
	sm:AbortActionsIfNeeded(ctx)
	sm:UpdateGait(ctx)

	-- A freezing action (Eat/Drink) reports Idle so the server decelerates the
	-- creature to a stop; otherwise report the live gait.
	local reported = if sm:FreezesMovement() then "Idle" else sm:GetGait()
	if reported ~= object.lastReported then
		object.lastReported = reported
		self.MovementService.SetState:Fire(reported)
	end
end

-- Turning + velocity. Returns the brake factor (used nowhere else but kept
-- explicit for clarity).
local function updateMovement(self, object, ctx, dt)
	local hrp = object.HRP
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

	-- Speed-dependent turn rate. Per-state turn rate (if the creature defines
	-- one) overrides the guaranteed BaseTurnRate — the allowed "specific over
	-- general" fallback, never a data-masking default.
	local gait = sm:GetGait()
	local turnRate = object.info[gait .. "TurnRate"] or object.info.BaseTurnRate
	local currentSpeed = hrp.AssemblyLinearVelocity.Magnitude
	local maxTurnRate = Stats.GetMaxTurnRate(turnRate, currentSpeed, object.info.TurnSpeedDecay)

	local currentDir = object.Facing
	local dot = math.clamp(currentDir:Dot(targetDir), -1, 1)
	local angleDiff = math.acos(dot)
	local brake = Stats.GetBrakeFactor(angleDiff, currentSpeed, object.info.TurnBrakeSensitivity)

	if ctx.hasMoveInput and angleDiff > 0.001 then
		local boosted = maxTurnRate * Stats.GetTurnBoost(angleDiff)
		local maxStep = boosted * dt
		local cross = currentDir:Cross(targetDir)
		local turnSign = math.sign(cross.Y)
		if turnSign == 0 then
			turnSign = 1
		end
		local alpha = math.min(angleDiff, maxStep)
		object.Facing = (CFrame.Angles(0, alpha * turnSign, 0) * currentDir).Unit
	end

	-- Velocity: always facing.Unit * (WalkSpeed * brake). Magnitude is owned by
	-- the server (WalkSpeed). We do NOT zero it on input release — the server
	-- ramps WalkSpeed to 0 and the magnitude follows, producing deceleration.
	local lv = object.BodyMovers.LinearVelocity
	if not lv or not lv.Parent then
		return
	end

	local freezing = sm:FreezesMovement()
	local blockedClimb = (object.ForwardSlope or 0) > object.info.MaxClimbAngle
	if freezing or blockedClimb then
		lv.PlaneVelocity = Vector2.zero
	else
		local v = object.Facing * (object.Humanoid.WalkSpeed * brake)
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
	object.CFrame = targetCF * CFrame.Angles(0, 0, object.Tilt)
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
		CFrame = hrp.CFrame,
		TerrainNormal = Vector3.yAxis,
		Grounded = true,
		ForwardSlope = 0,

		walkStyle = "Walk",
		runStyle = "Sprint",
		lastReported = nil,
	}

	-- Animations follow StateMachine signals (single source of truth).
	trove:Connect(sm.GaitChanged, function(newGait)
		animController:PlayGait(newGait)
	end)
	trove:Connect(sm.ActionChanged, function(newAction, oldAction)
		if newAction and animController:HasAnimation(newAction) then
			animController:PlayAction(newAction)
		elseif oldAction then
			animController:StopAction(oldAction)
		end
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

	-- Movement-affecting input: Z/X cycle the active gait tiers.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.object then
			return
		end
		if input.KeyCode == Enum.KeyCode.Z then
			self:ToggleWalkingStyle()
		elseif input.KeyCode == Enum.KeyCode.X then
			self:ToggleRunningStyle()
		end
	end)

	-- If the controller starts after the player already spawned, build now.
	if Common.IsSpawned(player) and player.Character then
		self:_buildObject()
	end
end

return MovementController
