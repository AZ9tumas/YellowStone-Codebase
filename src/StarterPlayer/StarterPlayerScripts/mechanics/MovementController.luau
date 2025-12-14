local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(player, camera, packets)
	local self = setmetatable({}, MovementController)

	self.Player = player
	self.Camera = camera
	self.Packets = packets
	-- We use the ControlModule to get the camera-relative move vector
	self.ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

	self.Humanoid = self.Player.Character and self.Player.Character:WaitForChild("Humanoid")
	self.HumanoidRootPart = self.Player.Character and self.Player.Character:WaitForChild("HumanoidRootPart")

	self.Params = {
		-- Movement States
		CurrentWalkingStyle = "Walk",
		CurrentRunningStyle = "Sprint",
		CurrentState = "Idle",
		CurrentFacingDirection = Vector3.new(0, 0, 0),

		-- Physics Params (Cleaned)
		MoveDirection = 0,

		-- Momentum Params
		MomentumActive = false,
		MomentumStartTime = 0,
		MomentumDuration = 0.5,
		MomentumStrength = 2,
		
		-- Tilt Configuration
		MaxTiltAngle = 25,
		TiltSpeed = 6,
		CurrentTilt = 0, -- Stored in radians
		TiltSensitivity = 0.8, -- How "heavy" the turn needs to be to cause max tilt

		LastHumanoidRootPartCFrame = self.HumanoidRootPart.CFrame
	}

	self.InputStateMap = {
		Forward = false,
		Backward = false
	}

	self.BodyMovers = {
		AlignOrientation = nil,
		LinearVelocity = nil
	}
	
	self:Init()

	return self
end

function MovementController:Init()
	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")

	self.BodyMovers.AlignOrientation = hrp:WaitForChild("AlignOrientation", 5)
	self.BodyMovers.LinearVelocity = hrp:WaitForChild("LinearVelocity", 5)
end

-- Only tracking Forward/Backward for momentum logic, 
-- Rotation inputs (A/D) are now handled natively by the ControlModule vector
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

function MovementController:UpdateMovement()
	local char = self.Player.Character
	if not char then return end
	local hum: Humanoid = self.Humanoid
	local hrp = self.HumanoidRootPart

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

function MovementController:UpdatePhysicsControllers(dt)
	local char = self.Player.Character
	if not char then return end
	local hrp = self.HumanoidRootPart

	if not self.BodyMovers.AlignOrientation or not self.BodyMovers.AlignOrientation.Parent then
		self.BodyMovers.AlignOrientation = hrp:FindFirstChildWhichIsA("AlignOrientation")
	end
	
	local ao = self.BodyMovers.AlignOrientation
	if not ao then return end

	local params = self.Params
	local currentCFrame: CFrame = hrp.CFrame
	local lastCFrame = params.LastHumanoidRootPartCFrame
	local deltaCFrame = lastCFrame:ToObjectSpace(currentCFrame)
	local _, rotY, _ = deltaCFrame:ToOrientation()
	params.LastHumanoidRootPartCFrame = currentCFrame

	local turnRate = rotY / dt
	local targetTiltRad = turnRate * params.TiltSensitivity
	
	local maxTiltRad = math.rad(params.MaxTiltAngle)
	targetTiltRad = math.clamp(targetTiltRad, -maxTiltRad, maxTiltRad)
	params.CurrentTilt = params.CurrentTilt + (targetTiltRad - params.CurrentTilt) * math.min(dt * params.TiltSpeed, 1)

	local finalRot = self.Params.CurrentFacingDirection * Vector3.new(1, 0, 1) * dt

	self.BodyMovers.AlignOrientation.CFrame = CFrame.lookAt(Vector3.zero, finalRot) * CFrame.Angles(0, 0, params.CurrentTilt)
end

function MovementController:Update(dt)
	self:UpdateMovement()
	self:UpdatePhysicsControllers(dt)
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