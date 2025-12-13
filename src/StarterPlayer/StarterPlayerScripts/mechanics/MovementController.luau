local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(player, camera, packets)
	local self = setmetatable({}, MovementController)

	self.Player = player
	self.Camera = camera
	self.Packets = packets
	self.ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

	self.Params = {
		-- Movement States
		CurrentWalkingStyle = "Walk",
		CurrentRunningStyle = "Sprint",
		CurrentState = "Idle",
		CurrentFacingDirection = Vector3.new(0, 0, 0),

		-- Physics Params
		RotationY = 0,
		AngularVelocity = 0,
		MoveDirection = 0,

		-- Momentum Params
		MomentumActive = false,
		MomentumStartTime = 0,
		MomentumDuration = 0.5,
		MomentumStrength = 2,
		
		-- Tilt Configuration
		UsePhysicsTilt = true, -- Set to TRUE to use AlignOrientation, FALSE for Motor6D
		MaxTiltAngle = 25,     
		TiltSpeed = 6,         
		CurrentTilt = 0,       -- Calculated tilt in radians
	}

	self.InputStateMap = {
		Forward = false,
		Backward = false,
		Left = false,
		Right = false
	}

	self.BodyMovers = {
		AlignOrientation = nil,
		LinearVelocity = nil
	}
	
	-- Motor6D References (Preserved for "Visual" mode)
	self.RootJoint = nil
	self.OriginalRootC0 = nil

	self:Init()

	return self
end

function MovementController:Init()
	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")

	-- Initial Rotation calculation
	self.Params.RotationY = math.deg(math.atan2(-hrp.CFrame.LookVector.X, -hrp.CFrame.LookVector.Z))

	-- Physics Objects Setup
	self.BodyMovers.AlignOrientation = hrp:WaitForChild("AlignOrientation", 5)
	self.BodyMovers.LinearVelocity = hrp:WaitForChild("LinearVelocity", 5)
	
	-- Motor6D Setup (Preserved)
	-- We grab this even if using Physics Tilt, in case we switch modes dynamically
	--self.RootJoint = hrp:FindFirstChild("RootJoint") or char:WaitForChild("LowerTorso"):FindFirstChild("Root")
	self.RootJoint = nil
	if self.RootJoint then
		self.OriginalRootC0 = self.RootJoint.C0
	end
end

-- Input handling
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

function MovementController:HandleRotation(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		if actionName == "RotateLeft" then self.InputStateMap.Left = true end
		if actionName == "RotateRight" then self.InputStateMap.Right = true end
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if actionName == "RotateLeft" then self.InputStateMap.Left = false end
		if actionName == "RotateRight" then self.InputStateMap.Right = false end
	end

	local left = self.InputStateMap.Left and 1 or 0
	local right = self.InputStateMap.Right and 1 or 0
	self.Params.AngularVelocity = (left - right)
end

-- Core Movement Logic (State & Momentum)
function MovementController:UpdateMovement()
	local char = self.Player.Character
	if not char then return end
	local hum: Humanoid = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return end

	local params = self.Params
	local moveVector = self.ControlModule:GetMoveVector()
	local laststate = params.CurrentState

	-- Momentum
	if params.MomentumActive then
		local elapsed = os.clock() - params.MomentumStartTime
		local progress = math.min(elapsed / params.MomentumDuration, 1)
		local momentumFactor = (1 - progress) * params.MomentumStrength

		if momentumFactor > 0.01 then
			local momentumDirection = params.CurrentFacingDirection
			if momentumDirection.Magnitude > 0 then
				hum:Move(momentumDirection * momentumFactor)
			end
		else
			params.MomentumActive = false
		end
	end

	if moveVector.Magnitude ~= 0 then
		params.CurrentState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and params.CurrentRunningStyle or params.CurrentWalkingStyle
		params.CurrentFacingDirection = hum.MoveDirection.Unit
		params.MomentumActive = false
	else
		params.CurrentState = "Idle"
		params.CurrentFacingDirection = hrp.CFrame.LookVector
	end

	if laststate ~= params.CurrentState then
		if hum.WalkSpeed > 0 and params.CurrentState == "Idle" then
			params.MomentumActive = true
			params.MomentumStartTime = os.clock()
		end
		self.Packets.sprint.send({sprintType = params.CurrentState})
	end
end

-- [[ TILT CALCULATION ]] --
-- Calculates the target tilt based on input, independent of how we apply it
function MovementController:CalculateTilt(dt)
	local moveVector = self.ControlModule:GetMoveVector()
	local hrp = self.Player.Character and self.Player.Character:FindFirstChild("HumanoidRootPart")
	
	if not hrp then return end
	
	local targetTilt = 0
	
	-- Only tilt if moving
	if moveVector.Magnitude > 0.1 then
		-- Convert global move vector to local space
		local relativeMove = hrp.CFrame:VectorToObjectSpace(moveVector)
		
		-- Relative X determines turn direction: -X is Left, +X is Right
		-- Banking logic: Turn Left (+Roll), Turn Right (-Roll)
		local direction = -relativeMove.X 
		targetTilt = direction * math.rad(self.Params.MaxTiltAngle)
	end
	
	-- Smoothly interpolate current tilt
	self.Params.CurrentTilt = self.Params.CurrentTilt + (targetTilt - self.Params.CurrentTilt) * math.min(dt * self.Params.TiltSpeed, 1)
end

-- [[ METHOD 1: PHYSICS TILT (AlignOrientation) ]] --
function MovementController:UpdatePhysicsControllers(dt)
	local char = self.Player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	local hmr = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hmr then return end

	-- Ensure movers exist
	if not self.BodyMovers.AlignOrientation or not self.BodyMovers.AlignOrientation.Parent then
		self.BodyMovers.AlignOrientation = hmr:FindFirstChildWhichIsA("AlignOrientation")
	end
	if not self.BodyMovers.LinearVelocity or not self.BodyMovers.LinearVelocity.Parent then
		self.BodyMovers.LinearVelocity = hmr:FindFirstChildWhichIsA("LinearVelocity")
	end

	local ao = self.BodyMovers.AlignOrientation
	local lv = self.BodyMovers.LinearVelocity
	if not ao or not lv then return end

	local params = self.Params
	local lookvec = hmr.CFrame.LookVector.Unit

	-- Handle Y Rotation (Turning)
	params.RotationY += params.AngularVelocity * dt * 150
	params.RotationY = params.RotationY % 360

	local movedir = Vector2.new(lookvec.X, lookvec.Z) * params.MoveDirection

	-- APPLY TILT HERE:
	-- We construct a CFrame that has:
	-- 1. The Y-Axis Rotation (Direction we are facing)
	-- 2. The Z-Axis Rotation (The banking/tilt angle)
	-- Order: YXZ applies Yaw first, then Roll.
	ao.CFrame = CFrame.fromEulerAnglesYXZ(0, math.rad(params.RotationY), params.CurrentTilt)
	
	lv.PlaneVelocity = movedir * hum.WalkSpeed
end

-- [[ METHOD 2: VISUAL TILT (Motor6D) ]] --
-- Keep this function available as requested
function MovementController:ApplyMotorTilt()
	if not self.RootJoint or not self.OriginalRootC0 then return end
	-- Simply apply the pre-calculated CurrentTilt to the C0
	self.RootJoint.C0 = self.OriginalRootC0 * CFrame.Angles(0, 0, self.Params.CurrentTilt)
end

function MovementController:Update(dt)
	-- 1. Determine Movement State
	self:UpdateMovement()
	
	-- 2. Calculate current tilt value (Math only)
	self:CalculateTilt(dt)
	
	-- 3. Apply Controls based on preference
	if self.Params.UsePhysicsTilt then
		-- Apply rotation + tilt via AlignOrientation
		self:UpdatePhysicsControllers(dt)
		
		-- Reset Motor6D if it was previously changed to avoid double tilting
		if self.RootJoint and self.RootJoint.C0 ~= self.OriginalRootC0 then
			self.RootJoint.C0 = self.OriginalRootC0
		end
	else
		-- Use Motor6D for tilt
		self:ApplyMotorTilt()
		-- You might still want UpdatePhysicsControllers here for movement, 
		-- just pass 0 as the tilt angle inside that function if you mix them.
	end
end

function MovementController:ToggleWalkingStyle()
	local params = self.Params
	local oldState = params.CurrentWalkingStyle
	params.CurrentWalkingStyle = if params.CurrentWalkingStyle == "Walk" then "Trot" else "Walk"

	if oldState ~= params.CurrentRunningStyle then
		self.Packets.sprint.send({
			sprintType = params.CurrentWalkingStyle
		})
	end
	return params.CurrentWalkingStyle
end

function MovementController:ToggleRunningStyle()
	local params = self.Params
	if params.CurrentState == params.CurrentRunningStyle then
		self.Packets.sprint.send({
			sprintType = params.CurrentRunningStyle
		})
	end

	params.CurrentRunningStyle = if params.CurrentRunningStyle == "Sprint" then "Run" else "Sprint"
	return params.CurrentRunningStyle
end

return MovementController