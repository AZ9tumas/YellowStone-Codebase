local ByteNet = require(script.Parent.ByteNet)

return ByteNet.defineNamespace("namespace1", function()
	return {
		spawn = ByteNet.definePacket({
			value = ByteNet.struct({
				charName = ByteNet.string,
				gender = ByteNet.string,
			}),
		}),
		
		sprint = ByteNet.definePacket({
			value = ByteNet.struct({
				sprintType = ByteNet.string,
			})
		}),
		
		attack = ByteNet.definePacket({
			value = ByteNet.nothing,
		}),
		
		attackReturn = ByteNet.definePacket({
			value = ByteNet.float32, -- damage value
		}),

		initClientScripts = ByteNet.definePacket({
			value = ByteNet.nothing,
		}),
	}
end)