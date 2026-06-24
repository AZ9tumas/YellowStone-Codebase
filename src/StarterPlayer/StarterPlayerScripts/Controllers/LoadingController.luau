--[[
	LoadingController

	Client half of the join handshake and the gate everything else waits behind:

	  1. Preload every GUI element under PlayerGui (kept as a table from
	     PlayerGui:GetChildren()).
	  2. Tell the server we're loaded (LoadingService:ClientLoaded()).
	  3. The server loads our data and only then resolves the call.
	  4. Flip IsLoaded() true and fire Loaded.

	The spawn menu (ui) stays locked until Loaded fires, so a player can't request
	a morph before both sides are ready. Movement / mechanics build off
	SpawnService.Spawned, which only fires after a successful morph — so they
	never touch creature config before the player actually exists.
]]

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local player = Players.LocalPlayer

local LoadingController = Knit.CreateController({ Name = "LoadingController" })

function LoadingController:IsLoaded(): boolean
	return self._loaded
end

-- Run `callback` once loading is complete (immediately if already done).
function LoadingController:OnLoaded(callback: () -> ())
	if self._loaded then
		task.spawn(callback)
	else
		self.Loaded:Connect(callback)
	end
end

function LoadingController:KnitInit()
	self._loaded = false
	self.Loaded = Signal.new()
	self.guiElements = {}
end

function LoadingController:KnitStart()
	local LoadingService = Knit.GetService("LoadingService")
	local playerGui = player:WaitForChild("PlayerGui")

	-- 1. Gather every GUI element to preload (kept around for reference/debug).
	self.guiElements = playerGui:GetChildren()

	-- Preload assets. A preload failure shouldn't hard-block the player.
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(self.guiElements)
	end)
	if not ok then
		warn("LoadingController: PreloadAsync failed -", err)
	end

	-- 2-4. Tell the server we're done, wait for it to finish loading our data.
	LoadingService:ClientLoaded()
		:andThen(function()
			self._loaded = true
			self.Loaded:Fire()
			print("[Loading] Client + server load complete")
		end)
		:catch(function(e)
			warn("LoadingController: server load failed -", e)
		end)
end

return LoadingController
