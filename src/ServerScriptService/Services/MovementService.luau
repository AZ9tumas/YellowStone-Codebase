--[[
	MovementService

	Server-side authority over locomotion SPEED. This is the anti-exploit
	backbone: the client owns facing/direction, but the magnitude it may travel
	at is `Humanoid.WalkSpeed`, which only this service sets.

	Each Heartbeat, for every spawned player:
	  * read the reported gait (the `State` attribute, set via SetState)
	  * compute the target speed for that gait, modulated by stamina + health
	  * ramp `Humanoid.WalkSpeed` toward it via Stats.Accelerate (up from 0 on
	    start; down to 0 on Idle)

	Because the client keeps applying `facing.Unit * WalkSpeed`, ramping
	WalkSpeed down produces a smooth deceleration to a stop on input release,
	and ramping up produces acceleration from rest — no instant Roblox stop.

	Replaces the ByteNet `sprint` packet (-> SetState) and the old
	remotes.server PlayerAdded + Heartbeat + Modules/Remotes.UpdateStamina.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local Common = require(ReplicatedStorage.Modules.Common)
local MovementStates = require(ReplicatedStorage.Modules.Movement.MovementStates)

local MovementService = Knit.CreateService({
	Name = "MovementService",
	Client = {
		-- One-way gait report (fire-and-forget). A RemoteSignal, not a method,
		-- because it is fired frequently from the client render loop and needs
		-- no return value / round trip.
		SetState = Knit.CreateSignal(),
	},
})

-- ===== Per-player setup ======================================================

local function initStats(player: Player)
	if player:FindFirstChild("PlayerStats") then
		return
	end
	local statsFolder = Instance.new("Folder")
	statsFolder.Name = "PlayerStats"

	local stamina = Instance.new("NumberValue")
	stamina.Name = "Stamina"
	stamina.Value = 1 -- normalised 0..1
	stamina.Parent = statsFolder

	statsFolder.Parent = player
end

local function onPlayerAdded(player: Player)
	-- The custom controller drives input, so Roblox's default movement is off.
	player.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable
	initStats(player)
end

-- ===== Speed integration =====================================================

local function updateSpeed(player: Player, dt: number)
	-- Only spawned players have a creature config + State attribute.
	if not Common.IsSpawned(player) then
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local statsFolder = player:FindFirstChild("PlayerStats")
	local stamina = statsFolder and statsFolder:FindFirstChild("Stamina")
	if not humanoid or not stamina then
		return
	end

	local state = player:GetAttribute("State")
	if not state then
		return
	end

	local info = Common.GetPlayerInfo(player)

	-- Target speed for the reported gait. `state` is always a valid gait (set
	-- by SetState / morph), so a missing speed key is an internal data bug.
	local reqSpeed = info[state .. "Speed"]
	assert(reqSpeed, `MovementService: no "{state}Speed" configured`)

	local healthScale = Stats.HealthBasedSpeedMultiplier(
		humanoid,
		info.MaxHealthSpeedPenalty,
		info.HealthPenaltyThreshold
	)

	local finalSpeed = reqSpeed
	local drain = info[state .. "StaminaDrain"]
	if drain then
		stamina.Value = Stats.ApplyStaminaDrain(stamina.Value, info.MaxStamina, drain * dt)
		finalSpeed = Stats.GetStaminaPenalizedSpeed(
			reqSpeed,
			info.TrotSpeed,
			info.RunSpeed,
			info.SprintSpeed,
			stamina.Value,
			info.StaminaPenaltyThreshold,
			state
		)
	else
		-- A gait with no drain must define a gain (even if 0) — fail loud if not.
		local gain = info[state .. "StaminaGain"]
		assert(gain, `MovementService: state "{state}" has neither StaminaDrain nor StaminaGain`)
		stamina.Value = Stats.ApplyStaminaGain(stamina.Value, info.MaxStamina, gain * dt)
	end

	humanoid.WalkSpeed = Stats.Accelerate(
		humanoid.WalkSpeed,
		finalSpeed * healthScale,
		dt,
		info.Acceleration,
		info.Deceleration
	)
end

-- Report the current locomotion gait. Untrusted: silently reject anything that
-- isn't a known gait (Idle/Walk/Trot/Run/Sprint).
local function onSetState(player: Player, stateName: string)
	if type(stateName) ~= "string" then
		return
	end
	local def = MovementStates.Definitions[stateName]
	if not def or def.category ~= MovementStates.Category.Gait then
		return
	end
	player:SetAttribute("State", stateName)
end

-- ===== Lifecycle =============================================================

function MovementService:KnitStart()
	self.Client.SetState:Connect(onSetState)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, player in Players:GetPlayers() do
			updateSpeed(player, dt)
		end
	end)
end

return MovementService
