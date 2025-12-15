--[[
	AnimationController Module
	
	A customized animation module to handle playing animations separately.
	Manages animation playback based on state changes and provides
	smooth transitions between animations.
]]

local AnimationController = {}
AnimationController.__index = AnimationController

export type AnimationControllerType = {
	player: Player,
	animator: Animator?,
	animationsFolder: Folder?,
	animationTracks: {[string]: AnimationTrack},
	currentAnimation: string?,
	fadeTime: number,
}

-- Default fade time for animation transitions
local DEFAULT_FADE_TIME = 0.2

function AnimationController.new(player: Player)
	local self = setmetatable({}, AnimationController)
	
	self.player = player
	self.animator = nil
	self.animationsFolder = nil
	self.animationTracks = {}
	self.currentAnimation = nil
	self.fadeTime = DEFAULT_FADE_TIME
	self.loadedAnimations = {}
	
	self:Init()
	
	return self
end

function AnimationController:Init()
	local char = self.player.Character
	if not char then
		warn("AnimationController: No character found for player")
		return
	end
	
	-- Get or wait for humanoid
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("AnimationController: No humanoid found in character")
		return
	end
	
	-- Get or create animator
	self.animator = humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = humanoid
	end
	
	-- Find animations folder under player
	self.animationsFolder = self.player:FindFirstChild("Animations")
	if not self.animationsFolder then
		warn("AnimationController: No Animations folder found under player")
		return
	end
	
	-- Load all animations from the folder
	self:LoadAnimationsFromFolder()
end

-- Load all Animation instances from the player's Animations folder
function AnimationController:LoadAnimationsFromFolder()
	if not self.animationsFolder or not self.animator then
		return
	end
	
	for _, animInstance in ipairs(self.animationsFolder:GetChildren()) do
		if animInstance:IsA("Animation") then
			self:LoadAnimation(animInstance.Name, animInstance)
		end
	end
end

-- Load a specific animation by name
function AnimationController:LoadAnimation(name: string, animation: Animation): AnimationTrack?
	if not self.animator then
		warn("AnimationController: No animator available")
		return nil
	end
	
	-- Check if already loaded
	if self.animationTracks[name] then
		return self.animationTracks[name]
	end
	
	local success, track = pcall(function()
		return self.animator:LoadAnimation(animation)
	end)
	
	if success and track then
		self.animationTracks[name] = track
		self.loadedAnimations[name] = animation
		return track
	else
		warn("AnimationController: Failed to load animation: " .. name)
		return nil
	end
end

-- Load animation by ID
function AnimationController:LoadAnimationFromId(name: string, animationId: string): AnimationTrack?
	if not self.animator then
		warn("AnimationController: No animator available")
		return nil
	end
	
	-- Check if already loaded
	if self.animationTracks[name] then
		return self.animationTracks[name]
	end
	
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	animation.Name = name
	
	-- Store in animations folder if it exists
	if self.animationsFolder then
		animation.Parent = self.animationsFolder
	end
	
	return self:LoadAnimation(name, animation)
end

-- Play an animation by name with optional fade time
function AnimationController:PlayAnimation(name: string, fadeTime: number?, priority: Enum.AnimationPriority?): AnimationTrack?
	local track = self.animationTracks[name]
	
	if not track then
		-- Try to find and load from folder
		if self.animationsFolder then
			local animInstance = self.animationsFolder:FindFirstChild(name)
			if animInstance and animInstance:IsA("Animation") then
				track = self:LoadAnimation(name, animInstance)
			end
		end
	end
	
	if not track then
		warn("AnimationController: Animation not found: " .. name)
		return nil
	end
	
	-- Set priority if provided
	if priority then
		track.Priority = priority
	end
	
	-- Stop current animation with fade
	if self.currentAnimation and self.currentAnimation ~= name then
		self:StopAnimation(self.currentAnimation, fadeTime)
	end
	
	-- Play new animation
	local fade = fadeTime or self.fadeTime
	if not track.IsPlaying then
		track:Play(fade)
	end
	
	self.currentAnimation = name
	return track
end

-- Stop an animation by name with optional fade time
function AnimationController:StopAnimation(name: string, fadeTime: number?)
	local track = self.animationTracks[name]
	if track and track.IsPlaying then
		track:Stop(fadeTime or self.fadeTime)
	end
	
	if self.currentAnimation == name then
		self.currentAnimation = nil
	end
end

-- Stop all currently playing animations
function AnimationController:StopAllAnimations(fadeTime: number?)
	for name, track in pairs(self.animationTracks) do
		if track.IsPlaying then
			track:Stop(fadeTime or self.fadeTime)
		end
	end
	self.currentAnimation = nil
end

-- Get currently playing animation name
function AnimationController:GetCurrentAnimation(): string?
	return self.currentAnimation
end

-- Check if an animation is currently playing
function AnimationController:IsPlaying(name: string): boolean
	local track = self.animationTracks[name]
	return track and track.IsPlaying or false
end

-- Get animation track by name
function AnimationController:GetTrack(name: string): AnimationTrack?
	return self.animationTracks[name]
end

-- Set the default fade time for transitions
function AnimationController:SetFadeTime(fadeTime: number)
	self.fadeTime = fadeTime
end

-- Adjust animation speed
function AnimationController:SetAnimationSpeed(name: string, speed: number)
	local track = self.animationTracks[name]
	if track then
		track:AdjustSpeed(speed)
	end
end

-- Set animation looped status
function AnimationController:SetAnimationLooped(name: string, looped: boolean)
	local track = self.animationTracks[name]
	if track then
		track.Looped = looped
	end
end

-- Update animation based on state (called by movement controller)
function AnimationController:UpdateForState(stateName: string, fadeTime: number?): AnimationTrack?
	-- Try to play the animation matching the state name
	return self:PlayAnimation(stateName, fadeTime)
end

-- Refresh the animator reference (useful when character respawns)
function AnimationController:RefreshAnimator()
	local char = self.player.Character
	if not char then return end
	
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	self.animator = humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = humanoid
	end
	
	-- Clear old tracks since they're invalid now
	self.animationTracks = {}
	self.currentAnimation = nil
	
	-- Reload animations
	self:LoadAnimationsFromFolder()
end

-- Check if animator is valid
function AnimationController:IsValid(): boolean
	return self.animator ~= nil and self.animator.Parent ~= nil
end

-- Cleanup
function AnimationController:Destroy()
	self:StopAllAnimations(0)
	self.animationTracks = {}
	self.loadedAnimations = {}
	self.animator = nil
	self.animationsFolder = nil
	self.player = nil
end

return AnimationController
