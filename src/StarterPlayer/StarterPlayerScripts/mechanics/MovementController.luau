local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local commonM = require(modules:WaitForChild("Common"))
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
        -- Movement States
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

        -- Momentum Params
        MomentumActive = false,
        MomentumStartTime = 0,
        MomentumDuration = 0.6,
        MomentumStrength = 3,

        -- Tilt Conf
        MaxTiltAngle = plrInfo.MaxTiltAngle or 25,
        TiltSpeed = plrInfo.TiltSpeed or 2,
        CurrentTilt = 0,
        TiltSensitivity = plrInfo.TiltSensitivity or 0.8,

        LastHumanoidRootPartCFrame = self.HumanoidRootPart and self.HumanoidRootPart.CFrame or CFrame.new(),
        
        LastDesiredState = "Idle"
    }

    self.InputStateMap = {
        Forward = false,
        Backward = false
    }

    self.BodyMovers = {
        AlignOrientation = nil,
        LinearVelocity = nil
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
	local walkSpeed = info.WalkSpeed or 15
	local trotSpeed = info.TrotSpeed or 28
	
	local threshold = 1.5

	-- Determine max allowed state based on speed thresholds
	-- Hierarchy: Walk -> Trot -> Run/Sprint
	
	local canRunOrSprint = currentSpeed >= (trotSpeed + threshold)
	local canTrot = currentSpeed >= (walkSpeed + threshold)

	if desiredState == "Sprint" then
		if canRunOrSprint then
			return "Sprint"
		end
	elseif desiredState == "Run" then
		if canRunOrSprint then
			return "Run"
		end
	end
	
	if desiredState == "Trot" or desiredState == "Sprint" or desiredState == "Run" then
		if canTrot then
			return "Trot"
		end
	end

	return "Walk"
end

function MovementController:UpdateMovement(dt)
    -- This only does the turning. Nothing else. Here, the major
    -- "setter" is Humanoid:Move(dir) and the rest is just calculating
    local char = self.Player.Character
    if not char then return end
    local hum: Humanoid = self.Humanoid
    local hrp = self.HumanoidRootPart
    
    if not hum or not hrp or hum.Parent ~= char or hrp.Parent ~= char then return end

    local params = self.Params
    local moveVector = self.ControlModule:GetMoveVector()
    local targetDir = Vector3.new()
    
    if moveVector.Magnitude > 0 then
        -- get the absolute target direction (relative to world)
        local camCF = self.Camera.CFrame
        targetDir = camCF:VectorToWorldSpace(moveVector)
        targetDir = Vector3.new(targetDir.X, 0, targetDir.Z) -- Flatten Y
        if targetDir.Magnitude > 0.001 then
            targetDir = targetDir.Unit
        end
    else
        targetDir = params.CurrentFacingDirection
    end

    local currentSpeed = hrp.AssemblyLinearVelocity.Magnitude
    local maxTurnRate = params.BaseTurnRate / (1 + (currentSpeed * params.TurnSpeedDecay))

    local currentDir: Vector3 = params.CurrentFacingDirection
    local dot = math.clamp(currentDir:Dot(targetDir), -1, 1)
    -- Here, angleDiff is the final angle difference between current
    -- direction and the final target direction.
    local angleDiff = math.acos(dot)
    local brakeFactor = 1 / (1 + (angleDiff * params.TurnBrakeSensitivity))

    if moveVector.Magnitude > 0 and angleDiff > 0.001 then
        local maxStep = maxTurnRate * dt

        local cross = currentDir:Cross(targetDir)
        local turnDirection = math.sign(cross.Y)
        if turnDirection == 0 then turnDirection = 1 end

        local alpha = math.min(angleDiff, maxStep)
        local rotationCF = CFrame.Angles(0, alpha * turnDirection, 0)
        params.CurrentFacingDirection = (rotationCF * currentDir).Unit
    end

    if moveVector.Magnitude > 0 then
        hum:Move(params.CurrentFacingDirection)
        -- handle momentum
        --params.MomentumActive = false
    else
        hum:Move(Vector3.zero)
    end
end

function MovementController:UpdateStates(dt)
    local char = self.Player.Character
    if not char then return end
    local hum = self.Humanoid
    if not hum or hum.Parent ~= char then return end

    --[[
        Important information:
        -> Here, while you stop moving (moveVecter.Magnitude == 0), we do not immediately
           transition to "Idle". Instead, we enable a "momentum" effect that
           allows the character to keep moving slightly for a short duration.
           This is on paper obviously. In reality we choose to set "Idle" as the state
           and have an independent, non-state-dependent momentum system that
           applies Humanoid:Move to the vector pointing to the last known facing direction.

           Although this may seem unprofessional, it allows us to keep the state machine
           simple and clean, while still achieving the desired momentum effect.
           Not to mention, server has to set walkspeed to zero when stopping anyway.
    ]]
    -- on state change
    local params = self.Params
    local laststate = params.CurrentState
    
    -- 1. Determine Desired State (Input)
    local desiredState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        and params.CurrentRunningStyle or params.CurrentWalkingStyle
    local moveVector = self.ControlModule:GetMoveVector()

    if moveVector.Magnitude <= 0 then
        desiredState = "Idle"
    else
        params.MomentumActive = false
    end

    -- 2. Send Packet if Desired State Changed (Network)
    if params.LastDesiredState ~= desiredState then
        params.LastDesiredState = desiredState
        if self.Packets then
             self.Packets.sprint.send({sprintType = desiredState})
        end
    end

    -- 3. Determine Constrained State (Visual/Local)
    local targetState = desiredState
    if desiredState ~= "Idle" then
        targetState = self:ConstrainState(desiredState)
    end

    -- 4. Transition Logic
    if laststate ~= targetState then
        -- momentum enabled only when we are transitioning to idle, and we aren't already
        -- in momentum.
        if targetState == "Idle" and params.CurrentState ~= "Idle" then
            if not params.MomentumActive then
                params.MomentumActive = true
                params.MomentumStartTime = os.clock()

                params.CurrentState = "Walk"
                self.StateManager:TransitionTo("Walk")
            end
        elseif not params.MomentumActive then
            -- handle idle separately.
            params.CurrentState = targetState
            local success = self.StateManager:TransitionTo(params.CurrentState)
        end
    end

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
            if moveVector.Magnitude <= 0 then
                params.CurrentState = "Idle"
                self.StateManager:TransitionTo("Idle")
            end
        end
    end
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

    -- Apply Final CFrame to AlignOrientation
    local lookCF = CFrame.lookAt(Vector3.zero, params.CurrentFacingDirection)
    self.BodyMovers.AlignOrientation.CFrame = lookCF * CFrame.Angles(0, 0, params.CurrentTilt)
end

function MovementController:UpdateAnimationSpeed(dt)
	local char = self.Player.Character
	if not char then return end
	local hrp = self.HumanoidRootPart
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