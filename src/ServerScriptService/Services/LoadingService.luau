--[[
	LoadingService

	Server half of the join handshake. The client (LoadingController) preloads
	its assets, then calls ClientLoaded. The server then loads that player's
	persistent data (datastores / profile / inventory — STUBBED for now) and only
	returns once it is done. That return is the signal the client waits on before
	it lets the player pick a creature.

	Flow:
	  client  -> LoadingService.Client:ClientLoaded()
	  server  -> :LoadPlayer(player)   (load data — TODO, currently a no-op)
	  server  -> returns true          (resolves the client's promise = "server done")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LoadingService = Knit.CreateService({
	Name = "LoadingService",
	Client = {},
})

-- Per-player guard so a client can't trigger the data load twice.
local loaded: { [Player]: boolean } = {}

-- Load this player's persistent data. LEFT BLANK ON PURPOSE — implement
-- datastore / profile / saved-creature loading here later. It must return true
-- once the player is fully ready on the server (the client blocks on this).
function LoadingService:LoadPlayer(player: Player): boolean
	if loaded[player] then
		return true
	end

	-- TODO: load player data here (datastores, inventory, saved creature, ...).

	loaded[player] = true
	return true
end

-- Called by the client once it has finished preloading its own assets. Yields
-- on the client until the server has finished loading the player's data.
function LoadingService.Client:ClientLoaded(player: Player): boolean
	return self.Server:LoadPlayer(player)
end

function LoadingService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		loaded[player] = nil
	end)
end

return LoadingService
