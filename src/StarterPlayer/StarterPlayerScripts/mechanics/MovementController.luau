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
    print(plrInfo)

    self.Player = player
    self.Camera = camera
    self.Packets = packets
    -- We use the ControlModule to get the camera-relative move vector
    self.ControlModule = require(player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

    self.Humanoid = self.Player.Character and self.Player.Character:WaitForChild("Humanoid")
    self.HumanoidRootPart = self.Player.Character and self.Player.Character:WaitForChild("HumanoidRootPart")
    
    -- Initialize state manager
    self.StateManager = StateManager.new(player, "Idle")
    
    -- Initialize animation controller
    self.AnimationController = AnimationController.new(player)

    self.Params = {
        -- Movement States
        CurrentWalkingStyle = "Walk",
        CurrentRunningStyle = "Sprint",
        CurrentState = "Idle",
        
        -- Facing / Physics
        CurrentFacingDirection = self.HumanoidRootPart and self.HumanoidRootPart.CFrame.LookVector or Vector3.new(0, 0, -1),
        TargetSpeed = 0,

        -- Physics Params (Cleaned)
        MoveDirection = 0,

        -- Turning Configuration (Adjustable per animal via plrInfo)
        -- NOW PULLED FROM THE INFO MODULE
        BaseTurnRate = plrInfo.BaseTurnRate or 4,
        TurnSpeedDecay = plrInfo.TurnSpeedDecay or 0.08,
        TurnBrakeSensitivity = plrInfo.TurnBrakeSensitivity or 2.5,

        -- Momentum Params
        MomentumActive = false,
        MomentumStartTime = 0,
        MomentumDuration = 0.5,
        MomentumStrength = 2,
        
        -- Tilt Configuration
        MaxTiltAngle = plrInfo.MaxTiltAngle or 25,
        TiltSpeed = plrInfo.TiltSpeed or 2,
        CurrentTilt = 0,
        TiltSensitivity = plrInfo.TiltSensitivity or 0.8,

        LastHumanoidRootPartCFrame = self.HumanoidRootPart and self.HumanoidRootPart.CFrame or CFrame.new()
    }

    self.InputStateMap = {
        Forward = false,
        Backward = false
    }

    self.BodyMovers = {
        AlignOrientation = nil,
        LinearVelocity = nil
    }
    
    -- Setup state change callback for animations
    self:SetupStateCallbacks()
    
    self:Init()

    return self
end

function MovementController:SetupStateCallbacks()
    -- Register callback to update animations when state changes
    self.StateManager:OnStateChanged(function(newState, oldState, stateConfig)
        -- Update animation based on new state
        if self.AnimationController then
            self.AnimationController:UpdateForState(newState)
        end
        
        -- Sync with server via packets
        if self.Packets then
            self.Packets.sprint.send({sprintType = newState})
        end
    end)
end

function MovementController:Init()
    local char = self.Player.Character or self.Player.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    local hum = char:WaitForChild("Humanoid")

    -- DISABLE DEFAULT ROBLOX ROTATION
    -- We are handling rotation manually with AlignOrientation
    hum.AutoRotate = false

    self.BodyMovers.AlignOrientation = hrp:WaitForChild("AlignOrientation", 5)
    self.BodyMovers.LinearVelocity = hrp:WaitForChild("LinearVelocity", 5)
    
    self.Params.CurrentFacingDirection = hrp.CFrame.LookVector
end

-- Only tracking Forward/Backward for momentum logic
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

function MovementController:UpdateMovement(dt)
    local char = self.Player.Character
    if not char then return end
    local hum: Humanoid = self.Humanoid
    local hrp = self.HumanoidRootPart
    local params = self.Params

    local moveVector = self.ControlModule:GetMoveVector()
    local laststate = params.CurrentState

    local targetDir = Vector3.new()
    local newState
    if moveVector.Magnitude > 0 then
        -- get the absolute target direction (relative to world)
        local camCF = self.Camera.CFrame
        targetDir = camCF:VectorToWorldSpace(moveVector)
        targetDir = Vector3.new(targetDir.X, 0, targetDir.Z) -- Flatten Y
        if targetDir.Magnitude > 0.001 then
            targetDir = targetDir.Unit
        end

        -- update stage
        newState = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and params.CurrentRunningStyle or params.CurrentWalkingStyle
        params.MomentumActive = true
    else
        targetDir = params.CurrentFacingDirection
        params.MomentumActive = false
        newState = "Idle"
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
    else
        hum:Move(Vector3.zero)
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
        end
    end

    -- on state change
    if laststate ~= newState then
        if hum.WalkSpeed > 0 and newState == "Idle" then
            params.MomentumActive = true
            params.MomentumStartTime = os.clock()
        else
            local success = self.StateManager:TransitionTo(newState)
            if success then print("Transitioned to state: " .. newState) end
        end
        
        params.CurrentState = newState
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
    
    -- Calculate Turn Rate for Visual Tilt
    local lastFacing = params.LastFacingVector or params.CurrentFacingDirection
    local currentFacing = params.CurrentFacingDirection
    
    local cross = lastFacing:Cross(currentFacing)
    local angleChange = math.asin(math.clamp(cross.Y, -1, 1))
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

function MovementController:Update(dt)
    self:UpdateMovement(dt)
    self:UpdatePhysicsControllers(dt)
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
end

return MovementController