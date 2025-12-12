local UserInputService = game:GetService("UserInputService")

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(player, camera, packets)
	local self = setmetatable({}, MovementController)
	
	self.Player = player
	self.Camera = camera
	self.Packets = packets
	
	self.Params = {
		CurrentWalkingStyle = "Walk",
		CurrentRunningStyle = "Sprint",
		CurrentState = "Idle",
		CurrentFacingDirection = Vector3.new(0, 0, 0),

		RotationY = 0,
		AngularVelocity = 0,
		MoveDirection = 0,

		MomentumActive = false,
		MomentumStartTime = 0,
		MomentumDuration = 0.5,
		MomentumStrength = 2,
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
	
	self:Init()
	
	return self
end

function MovementController:Init()
	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	
	self.Params.RotationY = math.deg(math.atan2(-hrp.CFrame.LookVector.X, -hrp.CFrame.LookVector.Z))
	
	self.BodyMovers.AlignOrientation = hrp:WaitForChild("AlignOrientation", 5)
	self.BodyMovers.LinearVelocity = hrp:WaitForChild("LinearVelocity", 5)
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

function MovementController:UpdateMovement()
	local char = self.Player.Character
	if not char then return end
	local hum: Humanoid = char:FindFirstChild("Humanoid")
	if not hum then return end
	
	local params = self.Params
	local moveVector = params.MoveDirection
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

	if hum.MoveDirection.Magnitude ~= 0 then
		params.CurrentState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and params.CurrentRunningStyle or params.CurrentWalkingStyle
		if char:FindFirstChild("HumanoidRootPart") then
			params.CurrentFacingDirection = char.HumanoidRootPart.CFrame.LookVector
		end
	else
		params.CurrentState = "Idle"
	end

	if laststate ~= params.CurrentState then
		if hum.WalkSpeed > 1 and params.CurrentState == "Idle" then
			params.MomentumActive = true
			params.MomentumStartTime = os.clock()
		end
		self.Packets.sprint.send({sprintType = params.CurrentState})
	end
end

function MovementController:UpdatePhysicsControllers(dt)
	local char = self.Player.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	local hmr = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hmr then return end

	-- Refresh body movers if missing (e.g. after respawn if not handled elsewhere, though Init should handle it)
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
	
	params.RotationY += params.AngularVelocity * dt * 150
	params.RotationY = params.RotationY % 360

	local movedir = Vector2.new(lookvec.X, lookvec.Z) * params.MoveDirection

	ao.CFrame = CFrame.fromEulerAnglesYXZ(0, math.rad(params.RotationY), 0)
	lv.PlaneVelocity = movedir * hum.WalkSpeed
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
