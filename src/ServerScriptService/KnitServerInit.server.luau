--[[
	KnitServerInit

	Boots Knit on the server. Every ModuleScript under ServerScriptService.Services
	is registered as a service; Knit then wires up their client-facing remotes and
	runs the KnitInit -> KnitStart lifecycle.

	Replaces the old ByteNet bootstrap (remotes.server.luau): there is no central
	packet namespace anymore — each service owns its own remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.AddServices(ServerScriptService.Services)

Knit.Start()
	:andThen(function()
		print("[Knit] Server started")
	end)
	:catch(function(err)
		warn("[Knit] Server failed to start -", err)
	end)
