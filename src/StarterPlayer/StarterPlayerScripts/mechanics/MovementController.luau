local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(modules:WaitForChild("Common"))
local Stats = require(modules:WaitForChild("Stats"))
local StateManager = require(modules:WaitForChild("StateManager"))
local AnimationController = require(modules:WaitForChild("AnimationController"))

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(player, camera, packets)
	local self = setmetatable({}, MovementController)

	local plrInfo = commonM.GetPlayerInfo(player)

	self.Player = player
	self.PlrInfo = plrInfo
	self.Camera = camera
	self.Packets = packets

	self.ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

	self.Humanoid = self.Player.Character and self.Player.Character:WaitForChild("Humanoid")
	self.HumanoidRootPart = self.Player.Character and self.Player.Character:WaitForChild("HumanoidRootPart")

	self.StateManager = StateManager.new(player, "Idle")

	self.AnimationController = AnimationController.new(player)

	self.Params = {
		-- Movement Stages: Idle, Walk, Trot, Run, Sprint
		CurrentWalkingStyle = "Walk",
		CurrentRunningStyle = "Sprint",
		CurrentState = "Idle",

		-- Facing / Physics
		CurrentFacingDirection = self.HumanoidRootPart and self.HumanoidRootPart.CFrame.LookVector or Vector3.new(0, 0, -1),
		TargetSpeed = 0,

		MoveDirection = 0,

		-- Turn
		BaseTurnRate = plrInfo.BaseTurnRate or 4,
		TurnSpeedDecay = plrInfo.TurnSpeedDecay or 0.08,
		TurnBrakeSensitivity = plrInfo.TurnBrakeSensitivity or 2.5,

		-- Tilt Conf
		MaxTiltAngle = plrInfo.MaxTiltAngle or 25,
		TiltSpeed = plrInfo.TiltSpeed or 2,
		CurrentTilt = 0,
		TiltSensitivity = plrInfo.TiltSensitivity or 0.8,

		-- Terrain Alignment
		TerrainAlignmentEnabled = plrInfo.TerrainAlignmentEnabled ~= false,
		TerrainAlignmentSpeed = plrInfo.TerrainAlignmentSpeed or 3,
		MaxTerrainPitch = plrInfo.MaxTerrainPitch or 45,
		MaxTerrainRoll = plrInfo.MaxTerrainRoll or 30,
		MaxTerrainAngle = plrInfo.MaxTerrainAngle or 40,
		MaxClimbAngle = plrInfo.MaxClimbAngle or 35,
		TerrainRaycastDistance = plrInfo.TerrainRaycastDistance or 10,
		CurrentTerrainPitch = 0,
		CurrentTerrainRoll = 0,
		CurrentTerrainNormal = Vector3.yAxis,
		LastTerrainCheckPosition = nil, -- Will be set on first terrain check
		TerrainCheckThreshold = 2, -- Studs to move before rechecking terrain

		LastHumanoidRootPartCFrame = self.HumanoidRootPart and self.HumanoidRootPart.CFrame or CFrame.new(),

		LastDesiredState = "Idle"
	}

	self.InputStateMap = {
		Forward = false,
		Backward = false
	}

	self.BodyMovers = {
		AlignOrientation = nil,
		LinearVelocity = nil,
	}

	self:SetupStateCallbacks()
	self:Init()

	return self
end

function MovementController:SetupStateCallbacks()
	self.StateManager:OnStateChanged(function(newState, oldState, stateConfig)
		if self.AnimationController then
			self.AnimationController:UpdateForState(newState)
		end
	end)
end

function MovementController:Init()
	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	local hum = char:WaitForChild("Humanoid")

	hum.AutoRotate = false

	self.BodyMovers.AlignOrientation = hrp:WaitForChild("AlignOrientation", 5)
	self.BodyMovers.LinearVelocity = hrp:WaitForChild("LinearVelocity", 5)

	self.Params.CurrentFacingDirection = hrp.CFrame.LookVector
end

-- Drive the LinearVelocity body mover on the X / Z plane.
--
-- The mover is configured server-side with VelocityConstraintMode = Plane
-- and PrimaryTangentAxis / SecondaryTangentAxis on world X / Z, so it can
-- ONLY apply force on the horizontal plane. Y is owned entirely by gravity
-- and the Humanoid's HipHeight + collisions. There is no position feedback
-- (unlike AlignPosition.Position = hrp.Position) so there's no possibility
-- of a vertical ratchet.
function MovementController:Move(direction: Vector3, _dt: number)
	local lv = self.BodyMovers.LinearVelocity
	if not lv or not lv.Parent then
		self.BodyMovers.LinearVelocity = self.HumanoidRootPart
			and self.HumanoidRootPart:FindFirstChildWhichIsA("LinearVelocity")
		lv = self.BodyMovers.LinearVelocity
	end
	if not lv then return end

	local hum = self.Humanoid
	if not hum then return end

	local targetSpeed = hum.WalkSpeed

	if direction.Magnitude > 0 and targetSpeed > 0 then
		local flatDir = Vector3.new(direction.X, 0, direction.Z)
		if flatDir.Magnitude > 0 then
			-- Preserve direction magnitude so callers can pass a brake
			-- factor (|dir| < 1) without renormalising.
			local speedScale = flatDir.Magnitude
			flatDir = flatDir.Unit
			local v = flatDir * (targetSpeed * speedScale)
			lv.PlaneVelocity = Vector2.new(v.X, v.Z)
			return
		end
	end

	lv.PlaneVelocity = Vector2.zero
end

-- Returns the current movement direction vector (for external scripts to check if moving)
function MovementController:GetMoveDirection(): Vector3
	local moveVector = self.ControlModule:GetMoveVector()
	if moveVector.Magnitude > 0 then
		local camCF = self.Camera.CFrame
		local targetDir = camCF:VectorToWorldSpace(moveVector)
		return Vector3.new(targetDir.X, 0, targetDir.Z).Unit
	end
	return Vector3.zero
end

function MovementController:UpdateMoveDir(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		if actionName == "MoveForward" then self.InputStateMap.Forward = true end
		if actionName == "MoveBackward" then self.InputStateMap.Backward = true end
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if actionName == "MoveForward" then self.InputStateMap.Forward = false end
		if actionName == "MoveBackward" then self.InputStateMap.Backward = false end
	end

	local forward = self.InputStateMap.Forward and 1 or 0
	local backward = self.InputStateMap.Backward and 1 or 0
	self.Params.MoveDirection = forward - backward
end

function MovementController:ConstrainState(desiredState)
	local hrp = self.HumanoidRootPart
	if not hrp then return desiredState end

	local vel = hrp.AssemblyLinearVelocity
	local currentSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local info = self.PlrInfo or {}
	return Stats.ConstrainState(
		desiredState,
		currentSpeed,
		info.WalkSpeed or 15,
		info.TrotSpeed or 28
	)
end

function MovementController:UpdateMovement(dt)
	-- Handles turning + movement. Drives the AlignPosition body mover via
	-- :Move() so position is fully owned by the client controller (no
	-- humanoid sliding). All math constants come from Stats.Movement.
	local char = self.Player.Character
	if not char then return end
	local hum: Humanoid = self.Humanoid
	local hrp = self.HumanoidRootPart

	if not hum or not hrp or hum.Parent ~= char or hrp.Parent ~= char then return end

	local params = self.Params
	local moveVector = self.ControlModule:GetMoveVector()
	local targetDir

	if moveVector.Magnitude > 0 then
		local camCF = self.Camera.CFrame
		targetDir = camCF:VectorToWorldSpace(moveVector)
		targetDir = Vector3.new(targetDir.X, 0, targetDir.Z)
		if targetDir.Magnitude > 0.001 then
			targetDir = targetDir.Unit
		end
	else
		targetDir = params.CurrentFacingDirection
	end

	-- use self.StateManager.currentState to get the correct base turnRate
	local currentTurnRateID = self.StateManager.currentState .. "TurnRate"
	local currentTurnRate = params[currentTurnRateID] or params.BaseTurnRate

	local currentSpeed = hrp.AssemblyLinearVelocity.Magnitude
	local maxTurnRate = Stats.GetMaxTurnRate(currentTurnRate, currentSpeed, params.TurnSpeedDecay)

	local currentDir: Vector3 = params.CurrentFacingDirection
	local dot = math.clamp(currentDir:Dot(targetDir), -1, 1)
	local angleDiff = math.acos(dot)

	local brakeFactor = Stats.GetBrakeFactor(angleDiff, currentSpeed, params.TurnBrakeSensitivity)

	if moveVector.Magnitude > 0 and angleDiff > 0.001 then
		-- Sharper desired angle -> faster turn so the character finishes
		-- aligning quickly (reduces the time spent moving in the wrong dir).
		local boostedTurnRate = maxTurnRate * Stats.GetTurnBoost(angleDiff)
		local maxStep = boostedTurnRate * dt

		local cross = currentDir:Cross(targetDir)
		local turnDirection = math.sign(cross.Y)
		if turnDirection == 0 then turnDirection = 1 end

		local alpha = math.min(angleDiff, maxStep)
		local rotationCF = CFrame.Angles(0, alpha * turnDirection, 0)
		params.CurrentFacingDirection = (rotationCF * currentDir).Unit
	end

	if moveVector.Magnitude > 0 then
		-- Climb gate: if the slope along facing exceeds MaxClimbAngle the
		-- creature can't ascend it. This stops the character from walking
		-- straight up cliffs (the previous behaviour) while still allowing
		-- side-hill traversal and downhill movement, which keep their
		-- normal speed.
		local slope = self.Params.ForwardSlope or 0
		if slope > (self.Params.MaxClimbAngle or 35) then
			self:Move(Vector3.zero, dt)
		else
			self:Move(params.CurrentFacingDirection * brakeFactor, dt)
		end
	else
		self:Move(Vector3.zero, dt)
	end
end

function MovementController:UpdateStates(dt)
	-- Movement stages, slowest to fastest: Idle, Walk, Trot, Run, Sprint.
	-- Releasing input immediately transitions to Idle — the legacy momentum
	-- carry-over has been removed. The server still ramps WalkSpeed down
	-- smoothly via Stats.Accelerate, so the character decelerates naturally.
	local char = self.Player.Character
	if not char then return end
	local hum = self.Humanoid
	if not hum or hum.Parent ~= char then return end

	local params = self.Params
	local laststate = params.CurrentState

	local desiredState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		and params.CurrentRunningStyle or params.CurrentWalkingStyle
	local moveVector = self.ControlModule:GetMoveVector()

	if moveVector.Magnitude <= 0 then
		desiredState = "Idle"
	end

	if params.LastDesiredState ~= desiredState then
		params.LastDesiredState = desiredState
		if self.Packets then
			self.Packets.sprint.send({ sprintType = desiredState })
		end
	end

	local targetState = desiredState
	if desiredState ~= "Idle" then
		targetState = self:ConstrainState(desiredState)
	end

	if laststate ~= targetState then
		params.CurrentState = targetState
		self.StateManager:TransitionTo(params.CurrentState)
	end
end

-- Multi-sample ground probe.
--
-- We cast four downward rays from points arranged in a square around the
-- HumanoidRootPart (front-right, front-left, back-right, back-left) at
-- roughly hip height. The averaged normal of all hits is the plane fit
-- for the ground under the character. This is the same technique used
-- by Unity's CharacterController-based locomotion samples, Malbers
-- Animal Controller, and most third-person AAA games — a single
-- raycast picks up noise from polygon edges and small props, which is
-- what produces the random "shoot up" snaps with rigid orientation.
--
-- Returns:
--   normal          - averaged surface normal (world space)
--   grounded        - true if at least 2 sample rays hit
--   forwardSlopeDeg - signed slope angle along facing direction
--                       (positive = uphill, negative = downhill)
function MovementController:DetectGround(facingDir: Vector3)
	local char = self.Player.Character
	local hrp = self.HumanoidRootPart
	if not char or not hrp or hrp.Parent ~= char then
		return Vector3.yAxis, false, 0
	end

	local params = self.Params
	local probeDist = params.TerrainRaycastDistance or 10

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }

	local size = hrp.Size
	local halfX = math.max(size.X * 0.5, 0.5)
	local halfZ = math.max(size.Z * 0.5, 0.5)
	local halfY = size.Y * 0.5

	-- Build facing-aligned axes so the probe square rotates with the
	-- character (front-back / left-right are meaningful even when the
	-- HRP CFrame is being driven by AlignOrientation).
	local fwd = Vector3.new(facingDir.X, 0, facingDir.Z)
	if fwd.Magnitude < 1e-3 then
		fwd = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	end
	fwd = fwd.Unit
	local right = Vector3.new(fwd.Z, 0, -fwd.X)

	local center = hrp.Position
	local offsets = {
		fwd *  halfZ + right *  halfX, -- FR
		fwd *  halfZ + right * -halfX, -- FL
		fwd * -halfZ + right *  halfX, -- BR
		fwd * -halfZ + right * -halfX, -- BL
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

	-- Plane fit: when we have 3+ hits, build a normal from cross products
	-- of edges between hit points (averaged across all triangle pairs).
	-- This is more stable than the raycast Normal at polygon edges.
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
						if c.Y < 0 then c = -c end
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

	-- Forward slope: project facing onto the terrain plane and compare
	-- to the world horizontal. Positive Y component => climbing.
	local projected = fwd - planeNormal * fwd:Dot(planeNormal)
	local forwardSlopeDeg = 0
	if projected.Magnitude > 1e-3 then
		projected = projected.Unit
		local sinPitch = math.clamp(projected.Y, -1, 1)
		forwardSlopeDeg = math.deg(math.asin(sinPitch))
	end

	return planeNormal, true, forwardSlopeDeg
end

-- Legacy helper kept for callers that just want the surface normal.
function MovementController:DetectTerrainSlope()
	local n = self:DetectGround(self.Params.CurrentFacingDirection)
	return n
end

function MovementController:UpdatePhysicsControllers(dt)
	local char = self.Player.Character
	if not char then return end
	local hrp = self.HumanoidRootPart

	if not hrp or hrp.Parent ~= char then return end

	if not self.BodyMovers.AlignOrientation or not self.BodyMovers.AlignOrientation.Parent then
		self.BodyMovers.AlignOrientation = hrp:FindFirstChildWhichIsA("AlignOrientation")
	end

	local ao = self.BodyMovers.AlignOrientation
	if not ao then return end

	local params = self.Params

	-- Calculate Turn Rate for Visual Tilt
	local lastFacing = params.LastFacingVector or params.CurrentFacingDirection
	local currentFacing = params.CurrentFacingDirection

	local cross = lastFacing:Cross(currentFacing)
	local angleChange = math.asin(math.clamp(cross.Y, -1, 1)) -- rad
	local turnRate = angleChange / dt

	params.LastFacingVector = currentFacing

	-- Calculate Tilt
	local targetTiltRad = turnRate * params.TiltSensitivity
	local maxTiltRad = math.rad(params.MaxTiltAngle)
	targetTiltRad = math.clamp(targetTiltRad, -maxTiltRad, maxTiltRad)

	params.CurrentTilt = params.CurrentTilt + (targetTiltRad - params.CurrentTilt) * math.min(dt * params.TiltSpeed, 1)

	-- Terrain Alignment (quad-probe plane fit + airborne fallback).
	local targetNormal = Vector3.yAxis
	local grounded = false
	local forwardSlope = 0

	if params.TerrainAlignmentEnabled then
		targetNormal, grounded, forwardSlope = self:DetectGround(params.CurrentFacingDirection)
		params.LastGroundNormal = targetNormal
		params.IsGrounded = grounded
		params.ForwardSlope = forwardSlope

		if grounded then
			-- Hard cap: clamp the tilt between world Up and the terrain
			-- normal to MaxTerrainAngle degrees (single stat that bounds
			-- how dramatically the character can pitch / roll regardless
			-- of axis).
			local maxAngle = math.rad(params.MaxTerrainAngle or 40)
			local currentAngle = math.acos(math.clamp(targetNormal:Dot(Vector3.yAxis), -1, 1))

			if currentAngle > maxAngle then
				local axis = Vector3.yAxis:Cross(targetNormal)
				if axis.Magnitude > 0.001 then
					targetNormal = CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(Vector3.yAxis)
				end
			end
		else
			-- Airborne: no ground samples, lerp back to world Up so the
			-- character doesn't keep the last hillside pose mid-jump /
			-- mid-fall.
			targetNormal = Vector3.yAxis
		end
	end

	-- Smoothing: Reduce intensity of changes (Lerp)
	local alpha = math.clamp(dt * (params.TerrainAlignmentSpeed or 3), 0, 1)
	params.CurrentTerrainNormal = params.CurrentTerrainNormal:Lerp(targetNormal, alpha)

	local usedNormal = params.CurrentTerrainNormal

	-- actual math
	local rightVec = params.CurrentFacingDirection:Cross(usedNormal)
	if rightVec.Magnitude < 0.001 then
		rightVec = Vector3.xAxis -- Fallback
	end

	local targetCF = CFrame.fromMatrix(Vector3.zero, rightVec, usedNormal)
	local tiltCF = CFrame.Angles(0, 0, params.CurrentTilt)

	self.BodyMovers.AlignOrientation.CFrame = targetCF * tiltCF
end

function MovementController:UpdateAnimationSpeed(dt)
	local char = self.Player.Character
	if not char then return end
	local hrp : BasePart = self.HumanoidRootPart
	if not hrp then return end

	local vel = hrp.AssemblyLinearVelocity
	local currentSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local currentState = self.Params.CurrentState
	if currentState == "Idle" then
		if self.AnimationController then
			self.AnimationController:SetAnimationSpeed("Idle", 1)
		end
		return
	end

	local info = self.PlrInfo or {}
	local targetSpeed = info[currentState .. "Speed"]

	if targetSpeed and targetSpeed > 0 then
		local ratio = currentSpeed / targetSpeed
		ratio = math.clamp(ratio, 0.5, 1.2)

		if self.AnimationController then
			self.AnimationController:SetAnimationSpeed(currentState, ratio)
		end
	end
end

function MovementController:Update(dt)
	self:UpdateMovement(dt)
	self:UpdateStates(dt)
	self:UpdatePhysicsControllers(dt)
	self:UpdateAnimationSpeed(dt)
end

function MovementController:ToggleWalkingStyle()
	local params = self.Params
	local oldWalkingStyle = params.CurrentWalkingStyle
	params.CurrentWalkingStyle = if params.CurrentWalkingStyle == "Walk" then "Trot" else "Walk"

	if params.CurrentState == oldWalkingStyle then
		self.StateManager:TransitionTo(params.CurrentWalkingStyle, true)
		params.CurrentState = params.CurrentWalkingStyle
	end

	return params.CurrentWalkingStyle
end

function MovementController:ToggleRunningStyle()
	local params = self.Params
	local oldRunningStyle = params.CurrentRunningStyle
	params.CurrentRunningStyle = if params.CurrentRunningStyle == "Sprint" then "Run" else "Sprint"

	if params.CurrentState == oldRunningStyle then
		self.StateManager:TransitionTo(params.CurrentRunningStyle, true)
		params.CurrentState = params.CurrentRunningStyle
	end

	return params.CurrentRunningStyle
end

function MovementController:GetStateManager()
	return self.StateManager
end

function MovementController:GetAnimationController()
	return self.AnimationController
end

function MovementController:Destroy()
	if self.StateManager then
		self.StateManager:Destroy()
	end
	if self.AnimationController then
		self.AnimationController:Destroy()
	end

	--script:Destroy()

	print("cleanup.")
end

return MovementController