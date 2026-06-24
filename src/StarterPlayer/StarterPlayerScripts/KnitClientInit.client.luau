--[[
	KnitClientInit

	Boots Knit on the client. Every ModuleScript under
	StarterPlayerScripts.Controllers is registered as a controller; Knit then
	exposes the server services (via Knit.GetService) and runs the
	KnitInit -> KnitStart lifecycle.

	Replaces the old ByteNet client bootstrap + the ClientHandler/initClientScripts
	"enable the mechanics script" dance — controllers self-manage off the
	SpawnService.Spawned signal and CharacterAdded.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

print("[Knit] Client starting...")
script.Parent:WaitForChild("Controllers")

Knit.AddControllers(script.Parent.Controllers)

Knit.Start()
	:andThen(function()
		print("[Knit] Client started")
	end)
	:catch(function(err)
		warn("[Knit] Client failed to start -", err)
	end)
