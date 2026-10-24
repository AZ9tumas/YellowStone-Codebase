--[[
	HeadLookService

	Shares a player's camera look direction for cosmetic head/neck aiming.
	The owner renders immediately; observers read the latest direction from
	the character attribute, including after joining or streaming the rig in.
	Only the sender's current creature can be updated. Directions are validated
	and normalised here, and each observer applies the creature's joint limits.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Common = require(ReplicatedStorage.Modules.Common)
local HeadLook = require(ReplicatedStorage.Modules.Movement.HeadLook)

local HeadLookService = Knit.CreateService({
	Name = "HeadLookService",
	Client = { SetDirection = Knit.CreateSignal() },
})

-- Allow some network jitter around the owner's 10 Hz publication limit.
local MIN_INTERVAL = HeadLook.SEND_INTERVAL * 0.5
local lastUpdates: { [Player]: { character: Model, time: number } } = {}

local function onSetDirection(player: Player, character: Model, direction: Vector3?)
	if not character or character ~= player.Character or not character.Parent or not Common.IsSpawned(player) then
		return
	end
	local now = os.clock()
	local last = lastUpdates[player]
	if last and last.character == character and now - last.time < MIN_INTERVAL then
		return
	end
	local info = Common.GetPlayerInfo(player)
	if not info.HeadLook or not info.HeadLook.CameraTracking then
		return
	end
	if direction ~= nil then
		direction = HeadLook.UnitDirection(direction)
		if not direction then
			return
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		direction = nil
	end
	lastUpdates[player] = { character = character, time = now }
	character:SetAttribute(HeadLook.DIRECTION_ATTRIBUTE, direction)
end

function HeadLookService:KnitStart()
	self.Client.SetDirection:Connect(onSetDirection)
	Players.PlayerRemoving:Connect(function(player)
		lastUpdates[player] = nil
	end)
end

return HeadLookService
