--[[
	AnimationController

	Per-character animation playback, split to match the two-layer state model:

	  * GAIT layer   — exactly one locomotion track playing at a time, crossfaded
	                   on change, at Movement priority. Driven by PlayGait.
	  * ACTION layer — zero or more action tracks (Eat/Drink/Fight) played at
	                   Action priority so they LAYER on top of the gait instead
	                   of replacing it (Roblox blends by priority). Driven by
	                   PlayAction / StopAction.

	The old single-slot `currentAnimation` model could only ever play one track,
	which is wrong for an action that should overlay locomotion (Fight while
	running). This version keeps the same loading infrastructure but separates
	the two layers.

	Animations are loaded by name from the player's `Animations` folder, which
	the server populates during morph (SpawnService.SetupAnimations).
]]

local AnimationController = {}
AnimationController.__index = AnimationController

local DEFAULT_FADE_TIME = 0.2
-- Locomotion crossfades get a slightly longer blend than actions: gait swaps
-- happen mid-stride between full-body cycles, where a short fade reads as a
-- snap (most visible on Sprint -> Trot).
local GAIT_FADE_TIME = 0.3
local GAIT_PRIORITY = Enum.AnimationPriority.Movement
local ACTION_PRIORITY = Enum.AnimationPriority.Action

export type AnimationController = {
	player: Player?,
	animator: Animator?,
	animationsFolder: Folder?,
	animationTracks: { [string]: AnimationTrack },
	currentGait: string?,
	activeActions: { [string]: boolean },
	fadeTime: number,

	Init: (self: AnimationController) -> (),
	LoadAnimationsFromFolder: (self: AnimationController) -> (),
	LoadAnimation: (self: AnimationController, name: string, animation: Animation) -> AnimationTrack?,
	PlayGait: (self: AnimationController, name: string, fadeTime: number?, looped: boolean?) -> (),
	PlayAction: (self: AnimationController, name: string, fadeTime: number?, looped: boolean?) -> (),
	StopAction: (self: AnimationController, name: string, fadeTime: number?) -> (),
	StopAllActions: (self: AnimationController, fadeTime: number?) -> (),
	SetAnimationSpeed: (self: AnimationController, name: string, speed: number) -> (),
	GetTrack: (self: AnimationController, name: string) -> AnimationTrack?,
	HasAnimation: (self: AnimationController, name: string) -> boolean,
	IsActionPlaying: (self: AnimationController, name: string) -> boolean,
	RefreshAnimator: (self: AnimationController) -> (),
	IsValid: (self: AnimationController) -> boolean,
	Destroy: (self: AnimationController) -> (),
}

function AnimationController.new(player: Player): AnimationController
	local self = setmetatable({}, AnimationController)

	self.player = player
	self.animator = nil
	self.animationsFolder = nil
	self.animationTracks = {}
	self.currentGait = nil
	self.activeActions = {}
	self.fadeTime = DEFAULT_FADE_TIME

	self:Init()

	return self
end

function AnimationController:Init()
	local char = self.player.Character
	if not char then
		warn("AnimationController: No character found for player")
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("AnimationController: No humanoid found in character")
		return
	end

	self.animator = humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = humanoid
	end

	-- The Animations folder is created by the server during morph. Wait briefly
	-- for it (async creation) but warn loudly if it never arrives — that is a
	-- setup bug, not something to paper over.
	self.animationsFolder = self.player:WaitForChild("Animations", 5)
	if not self.animationsFolder then
		warn("AnimationController: Animations folder not found under player after waiting")
		return
	end

	self:LoadAnimationsFromFolder()
end

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

function AnimationController:LoadAnimation(name: string, animation: Animation): AnimationTrack?
	if not self.animator then
		warn("AnimationController: No animator available")
		return nil
	end

	if self.animationTracks[name] then
		return self.animationTracks[name]
	end

	local success, track = pcall(function()
		return self.animator:LoadAnimation(animation)
	end)

	if success and track then
		self.animationTracks[name] = track
		return track
	else
		warn("AnimationController: Failed to load animation: " .. name)
		return nil
	end
end

-- Resolve a track by name, loading it lazily from the folder if needed.
function AnimationController:_resolveTrack(name: string): AnimationTrack?
	local track = self.animationTracks[name]
	if track then
		return track
	end
	if self.animationsFolder then
		local animInstance = self.animationsFolder:FindFirstChild(name)
		if animInstance and animInstance:IsA("Animation") then
			return self:LoadAnimation(name, animInstance)
		end
	end
	warn("AnimationController: Animation not found: " .. tostring(name))
	return nil
end

-- GAIT layer: crossfade to a new locomotion track. No-op if already playing it.
-- `looped` defaults to true (gait cycles); turn-in-place one-shots pass false.
--
-- The crossfade is PHASE-SYNCED between looping cycles: the incoming track
-- starts at the same normalized cycle time as the outgoing one, so the legs
-- keep their stride phase through the blend instead of popping to a different
-- foot position — that pop was the visible "snap" on gait changes, which no
-- fade length alone can hide. The outgoing track is stopped only after the
-- incoming one starts, so the animator weight-blends the overlap.
function AnimationController:PlayGait(name: string, fadeTime: number?, looped: boolean?)
	if self.currentGait == name then
		return
	end

	local fade = fadeTime or GAIT_FADE_TIME

	local prev: AnimationTrack? = nil
	if self.currentGait then
		prev = self.animationTracks[self.currentGait]
	end

	local track = self:_resolveTrack(name)
	self.currentGait = name
	if not track then
		if prev and prev.IsPlaying then
			prev:Stop(fade)
		end
		return
	end

	track.Priority = GAIT_PRIORITY
	track.Looped = looped ~= false
	if not track.IsPlaying then
		track:Play(fade)
		if track.Looped then
			-- Match the outgoing cycle's phase. Length is 0 until the asset
			-- loads; skip the sync then (the blend still happens, just unphased).
			if track.Length > 0 and prev and prev.IsPlaying and prev.Looped and prev.Length > 0 then
				local phase = (prev.TimePosition % prev.Length) / prev.Length
				track.TimePosition = phase * track.Length
			end
		elseif track.Length > 0 and track.TimePosition >= track.Length then
			-- Replayed one-shot: a finished track parks at its end; without this
			-- it would re-finish instantly instead of playing again.
			track.TimePosition = 0
		end
	end

	if prev and prev.IsPlaying then
		prev:Stop(fade)
	end
end

-- ACTION layer: play an action track on top of the gait.
function AnimationController:PlayAction(name: string, fadeTime: number?, looped: boolean?)
	local track = self:_resolveTrack(name)
	if not track then
		return
	end

	track.Priority = ACTION_PRIORITY
	if looped ~= nil then
		track.Looped = looped
	end
	if not track.IsPlaying then
		track:Play(fadeTime or self.fadeTime)
	end
	self.activeActions[name] = true
end

function AnimationController:StopAction(name: string, fadeTime: number?)
	local track = self.animationTracks[name]
	if track and track.IsPlaying then
		track:Stop(fadeTime or self.fadeTime)
	end
	self.activeActions[name] = nil
end

function AnimationController:StopAllActions(fadeTime: number?)
	for name in pairs(self.activeActions) do
		self:StopAction(name, fadeTime)
	end
end

function AnimationController:SetAnimationSpeed(name: string, speed: number)
	local track = self.animationTracks[name]
	if track then
		track:AdjustSpeed(speed)
	end
end

function AnimationController:GetTrack(name: string): AnimationTrack?
	return self.animationTracks[name]
end

-- Is an animation by this name available (already loaded, or present in the
-- player's Animations folder)? Quiet — used to decide whether to auto-play an
-- action track. Does not warn on absence (unlike _resolveTrack).
function AnimationController:HasAnimation(name: string): boolean
	if self.animationTracks[name] then
		return true
	end
	if self.animationsFolder then
		local inst = self.animationsFolder:FindFirstChild(name)
		return inst ~= nil and inst:IsA("Animation")
	end
	return false
end

function AnimationController:IsActionPlaying(name: string): boolean
	local track = self.animationTracks[name]
	return track ~= nil and track.IsPlaying
end

-- Rebuild track references after a respawn (tracks bound to an old Animator are
-- invalid).
function AnimationController:RefreshAnimator()
	local char = self.player.Character
	if not char then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	self.animator = humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = humanoid
	end

	self.animationTracks = {}
	self.currentGait = nil
	self.activeActions = {}

	self:LoadAnimationsFromFolder()
end

function AnimationController:IsValid(): boolean
	return self.animator ~= nil and self.animator.Parent ~= nil
end

function AnimationController:Destroy()
	for _, track in pairs(self.animationTracks) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
	self.animationTracks = {}
	self.currentGait = nil
	self.activeActions = {}
	self.animator = nil
	self.animationsFolder = nil
	self.player = nil
end

return AnimationController
