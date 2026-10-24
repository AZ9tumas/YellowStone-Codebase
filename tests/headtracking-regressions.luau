-- Run locally: lune run tests/headtracking-regressions.luau
-- Production solver + BoneWriter on a small hierarchical rig, and the actual
-- server handler with fake Knit signals. No Studio or asset downloads needed.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function loadModule(path, environment)
	return luau.load(fs.readFile(path), { debugName = path, environment = environment, injectGlobals = true })()
end
local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
end
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback) table.insert(callbacks, callback) end,
		Fire = function(_, ...) for _, callback in callbacks do callback(...) end end,
	}
end
local players = { PlayerRemoving = signal(), list = {}, sweeps = 0 }
function players:GetPlayers() self.sweeps += 1; return self.list end
local writerModule = loadModule("src/ReplicatedStorage/Modules/Movement/BoneWriter.luau", { CFrame = CFrame })
local headModule = loadModule("src/ReplicatedStorage/Modules/Movement/HeadLook.luau", {
	game = { GetService = function() return players end },
	script = { Parent = { BoneWriter = writerModule } },
	require = function(module) return module end,
	CFrame = CFrame, Vector3 = Vector3,
})

local function direction(yaw, pitch)
	yaw, pitch = math.rad(yaw), math.rad(pitch)
	return Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end
local function angles(d)
	return math.deg(math.atan2(d.X, -d.Z)), math.deg(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)))
end

local boneMeta = { __index = function(bone, key)
	if key == "WorldCFrame" then
		return (bone.Parent.WorldCFrame or bone.Parent.CFrame) * bone.CFrame
	end
	if key == "TransformedWorldCFrame" then
		local parentFrame = bone.Parent.TransformedWorldCFrame or bone.Parent.CFrame
		return parentFrame * bone.CFrame * bone.Transform
	end
	return nil
end }
local function bone(name, parent, frame)
	return setmetatable({
		Name = name, Parent = parent, CFrame = frame, Transform = CFrame.identity,
		IsA = function(_, class) return class == "Bone" end,
	}, boneMeta)
end
local function fixture(cameraTracking)
	local character = { Parent = true }
	local root = { CFrame = CFrame.identity, Position = Vector3.zero }
	local neck = bone("Neck", root, CFrame.Angles(0, 0, 0.3))
	local head = bone("Head", neck, CFrame.new(0, 0, -1) * CFrame.Angles(0, 0, -0.2))
	local nose = bone("Nose", head, CFrame.new(0, 0, -1))
	function character:GetDescendants() return { neck, head, nose } end
	function character:FindFirstChild(name) return if name == "HumanoidRootPart" then root else nil end
	local writer = writerModule.new()
	local look = headModule.new(character, {
		Bones = { "Neck", "Head" }, Weights = { 0.4, 0.6 }, Aim = "Nose",
		MaxYaw = 55, MaxPitch = 35, Response = 6, CameraTracking = cameraTracking,
	}, writer)
	local function step(d, dt, suppressed, lead, target)
		writer:BeginFrame()
		if lead then writer:Add(neck, CFrame.Angles(0, lead, 0)) end
		look:Update({
			Facing = root.CFrame.LookVector, Up = root.CFrame.UpVector,
			Direction = d, Target = target, Suppressed = suppressed,
		}, dt)
		writer:EndFrame()
		return (nose.TransformedWorldCFrame.Position - head.TransformedWorldCFrame.Position).Unit
	end
	return look, step, root, neck, head, writer
end

for _, fps in { 30, 60, 144 } do
	for _, requested in { { 40, 20 }, { -40, -20 }, { 120, 70 }, { -120, -70 }, { 0, 0 } } do
		local look, step, root, neck, head = fixture(true)
		local d = direction(requested[1], requested[2])
		local aim
		for _ = 1, fps * 3 do aim = step(d, 1 / fps) end
		local yaw, pitch = angles(aim)
		check(math.abs(yaw - math.clamp(requested[1], -55, 55)) < 0.1, `camera yaw at {fps} FPS`)
		check(math.abs(pitch - math.clamp(requested[2], -35, 35)) < 0.1, `camera pitch at {fps} FPS`)
		check(look:GetDebug().HasTarget, "camera direction is reported as an active target")
		check(root.CFrame == CFrame.identity, "head aiming never changes the root")
		if requested[1] ~= 0 then
			check(neck.Transform ~= CFrame.identity and head.Transform ~= CFrame.identity,
				"both neck and head share the camera rotation")
		end
		for _ = 1, fps * 3 do aim = step(d, 1 / fps, true) end
		check(aim:Dot(Vector3.new(0, 0, -1)) > 0.99999 and not look:GetDebug().HasTarget, "suppression blends back to the base pose")
	end
end
check(players.sweeps == 0, "camera tracking never selects a nearby creature instead")

do
	local look, step, root = fixture(true)
	for _ = 1, 180 do step(direction(40, 20), 1 / 60, false, math.rad(15)) end
	local aim = step(direction(40, 20), 1 / 60, false, math.rad(15))
	local yaw, pitch = angles(aim)
	check(math.abs(yaw - 40) < 0.1 and math.abs(pitch - 20) < 0.1, "camera aim corrects the existing neck turn lead")
	root.CFrame = CFrame.Angles(math.rad(20), math.rad(-100), math.rad(15))
	step(direction(40, 20), 1 / 60)
	yaw, pitch = angles(root.CFrame:VectorToObjectSpace(look.dir))
	check(math.abs(yaw) <= 55.01 and math.abs(pitch) <= 35.01, "smoothed aim stays within limits after a sharp body turn on a slope")
	for _ = 1, 180 do aim = step(nil, 1 / 60) end
	check(aim:Dot(root.CFrame.LookVector) > 0.99999 and not look:GetDebug().HasTarget, "missing camera direction fades out without auto-acquiring")
end

do
	local look, step = fixture(true)
	local previousYaw = 0
	for frame = 1, 240 do
		local wanted = if frame <= 120 then direction(50, 20) else direction(-50, -20)
		local aim = step(wanted, 1 / 60)
		local yaw, pitch = angles(aim)
		check(math.abs(yaw) <= 55.01 and math.abs(pitch) <= 35.01, "rapid camera reversal stays bounded")
		check(math.abs(yaw - previousYaw) < 12, "camera reversal blends instead of snapping")
		previousYaw = yaw
	end
end

do
	local _, step, root = fixture(true)
	for _ = 1, 180 do step(direction(40, 20), 1 / 60) end
	root.CFrame = CFrame.Angles(0, math.rad(150), 0)
	local aim = step(nil, 1 / 60, true)
	local yaw, pitch = angles(root.CFrame:VectorToObjectSpace(aim))
	check(math.abs(yaw) <= 55.01 and math.abs(pitch) <= 35.01, "a body turn during fade-out cannot overtwist the head")
end

do
	local nearby = { FindFirstChild = function() return { Position = direction(-30, 0) * 30 } end }
	players.list = { { Character = nearby } }
	local look, step = fixture(false)
	step(nil, 1 / 60)
	check(look:GetDebug().HasTarget and players.sweeps > 0, "automatic nearby-creature attention remains available")
	local cameraLook, cameraStep = fixture(true)
	for _ = 1, 180 do cameraStep(direction(30, 0), 1 / 60, false, nil, direction(-30, 0) * 30) end
	check(cameraLook:GetDebug().Yaw > 29, "direction takes precedence over a world target")
	local scriptedLook, scriptedStep = fixture(true)
	scriptedStep(nil, 1 / 60, false, nil, direction(20, 0) * 30)
	check(scriptedLook:GetDebug().HasTarget, "explicit world targets remain supported")
end

-- The imported wolf's nose is below its head joint. Pointing that joint-to-
-- joint line at a level camera incorrectly lifts the skull by about 31 deg.
local wolfRest = require("./fixtures/wolf-head-rest")
local function wolfFixture(animatedAtSpawn)
	local root = { CFrame = CFrame.identity }
	local parts, descendants = { Root = root }, {}
	for _, row in wolfRest do
		local joint = bone(row.name, parts[row.parent], CFrame.new(table.unpack(row.frame)))
		parts[row.name] = joint
		table.insert(descendants, joint)
	end
	local character = { Parent = true }
	function character:GetDescendants() return descendants end
	function character:FindFirstChild(name) return if name == "HumanoidRootPart" then root else nil end
	local neck1, neck2, head, nose = parts["Neck.001"], parts["Neck.002"], parts.Head, parts.Nose
	local restHead = head.WorldCFrame.Rotation
	if animatedAtSpawn then head.Transform = CFrame.Angles(0.2, 0.1, -0.15) end
	local writer = writerModule.new()
	local look = headModule.new(character, {
		Bones = { "Neck.002", "Head" }, Weights = { 0.4, 0.6 }, Aim = "Nose",
		MaxYaw = 55, MaxPitch = 35, Response = 6, CameraTracking = true,
	}, writer)
	local function step(d, dt, lead, animate, suppressed)
		-- Simulate a clip keyframing these bones before PreSimulation. Other
		-- frames leave the previous write alone, as throttled/unkeyed bones do.
		if animate then
			neck1.Transform = CFrame.Angles(0.1, -0.08, 0.15)
			head.Transform = CFrame.Angles(-0.12, 0.1, -0.2)
		end
		writer:BeginFrame()
		for i, joint in { neck1, neck2 } do
			writer:Prepare(joint)
			local axis = joint.TransformedWorldCFrame:VectorToObjectSpace(root.CFrame.UpVector)
			writer:Add(joint, CFrame.fromAxisAngle(axis, (lead or 0) * (if i == 1 then 0.45 else 0.55)))
		end
		look:Update({ Facing = root.CFrame.LookVector, Up = root.CFrame.UpVector, Direction = d, Suppressed = suppressed }, dt)
		writer:EndFrame()
		return head.TransformedWorldCFrame.Rotation * restHead:Inverse()
	end
	return look, step, root, head, nose, restHead
end

local function rotationError(a, b)
	local _, angle = (a:Inverse() * b):ToAxisAngle()
	return math.deg(math.min(math.abs(angle), math.abs(2 * math.pi - angle)))
end

local function lookFrame(d, up)
	local right = d:Cross(up or Vector3.yAxis).Unit
	return CFrame.fromMatrix(Vector3.zero, right, right:Cross(d), -d)
end

for _, fps in { 30, 60, 144 } do
	do
		local _, step, _, head, nose, rest = wolfFixture()
		for _ = 1, fps * 3 do step(direction(0, 0), 1 / fps) end
		check(rotationError(head.TransformedWorldCFrame.Rotation, rest) < 0.1,
			`level camera preserves the wolf's neutral skull pose at {fps} FPS`)
		local _, nosePitch = angles((nose.TransformedWorldCFrame.Position - head.TransformedWorldCFrame.Position).Unit)
		check(nosePitch < -30 and nosePitch > -32, "neutral wolf retains its naturally downward head-to-nose line")
	end
	for _, requested in { { 40, 20 }, { -40, -20 }, { 120, 70 }, { -120, -70 }, { 0, 0 } } do
		local look, step, root = wolfFixture(true)
		local d = direction(requested[1], requested[2])
		local actual
		for _ = 1, fps * 3 do actual = step(d, 1 / fps, math.rad(35), true) end
		local expected = lookFrame(direction(math.clamp(requested[1], -55, 55), math.clamp(requested[2], -35, 35)))
		check(rotationError(actual, expected) < 0.1, `wolf aims without roll despite animated/turning neck at {fps} FPS`)
		for frame = 1, fps * 3 do
			local t = frame / fps
			root.CFrame = CFrame.Angles(math.rad(20), t * 2, math.rad(15))
			actual = step(d, 1 / fps, math.rad(35) * math.sin(t * 4), frame % 2 == 0)
			expected = lookFrame(look.dir, root.CFrame.UpVector)
			check(rotationError(actual, expected) < 0.1, "body turns and clip writes cannot override the calibrated camera pose")
			local yaw, pitch = angles(root.CFrame:VectorToObjectSpace(actual.LookVector))
			check(math.abs(yaw) <= 55.01 and math.abs(pitch) <= 35.01, "actual wolf pose stays inside yaw/pitch limits on slopes")
		end
	end
	do
		local _, step, root, head, _, rest = wolfFixture(true)
		for _ = 1, fps * 3 do step(direction(50, 30), 1 / fps, math.rad(35), true) end
		for _ = 1, fps * 3 do step(nil, 1 / fps, 0, true, true) end
		check(rotationError(head.Transform, CFrame.Angles(-0.12, 0.1, -0.2)) < 0.1,
			"wolf suppression returns the head to its current animated pose")
		local actual
		for _ = 1, fps * 3 do actual = step(direction(-40, -20), 1 / fps, math.rad(-35), true) end
		check(rotationError(actual, lookFrame(direction(-40, -20))) < 0.1,
			"camera tracking reacquires cleanly after an action releases the head")
		check(root.CFrame == CFrame.identity and head.WorldCFrame.Rotation == rest,
			"camera correction leaves root and bind geometry unchanged")
	end
end

for _, invalid in { false, "forward", {}, Vector3.zero, Vector3.new(0 / 0, 0, 1), Vector3.new(0, math.huge, 1) } do
	check(headModule.UnitDirection(invalid) == nil, "invalid direction rejected")
end
check(math.abs(headModule.UnitDirection(Vector3.new(3, 4, 0)).Magnitude - 1) < 1e-6, "valid directions are normalised")

-- Exercise the real remote handler: ownership, malformed packets, rate
-- limiting, clears, death, and a new character replacing an old one.
do
	local time = 0
	local common = {
		IsSpawned = function(player) return player.spawned end,
		GetPlayerInfo = function(player) return player.info end,
	}
	local knit = { CreateSignal = signal, CreateService = function(service) return service end }
	local replicatedStorage = { Packages = { Knit = knit }, Modules = { Common = common, Movement = { HeadLook = headModule } } }
	local service = loadModule("src/ServerScriptService/Services/HeadLookService.luau", {
		game = { GetService = function(_, name) return if name == "Players" then players else replicatedStorage end },
		require = function(module) return module end,
		os = { clock = function() return time end },
	})
	service:KnitStart()
	local function character()
		local char = { Parent = true, attributes = {}, writes = 0, humanoid = { Health = 100 } }
		function char:SetAttribute(name, value) self.attributes[name] = value; self.writes += 1 end
		function char:FindFirstChildOfClass() return self.humanoid end
		return char
	end
	local char, other = character(), character()
	local player = { Character = char, spawned = true, info = { HeadLook = { CameraTracking = true } } }
	local function send(model, d, advance)
		time += advance or 0.1
		service.Client.SetDirection:Fire(player, model, d)
	end
	local attribute = headModule.DIRECTION_ATTRIBUTE
	send(other, direction(30, 20))
	check(other.writes == 0 and char.writes == 0, "cannot change another creature's look")
	send(char, direction(30, 20) * 5)
	check(char.attributes[attribute]:Dot(direction(30, 20)) > 0.99999, "owner direction is stored for observers, normalised")
	local writes = char.writes
	send(char, direction(-30, -20), 0.001)
	check(char.writes == writes, "excess updates are rate-limited")
	for _, invalid in { false, "forward", {}, Vector3.zero, Vector3.new(math.huge, 0, 0), Vector3.new(0, 0 / 0, 0) } do
		send(char, invalid)
		check(char.writes == writes, "malformed remote input does not overwrite a valid pose")
	end
	send(char, nil)
	check(char.attributes[attribute] == nil, "suppression clears the replicated direction")
	player.info.HeadLook.CameraTracking = false
	writes = char.writes
	send(char, direction(30, 0))
	check(char.writes == writes, "disabled camera tracking rejects updates")
	player.info.HeadLook.CameraTracking = true
	player.spawned = false
	send(char, direction(30, 0))
	check(char.writes == writes, "unspawned players cannot publish a pose")
	player.spawned = true
	send(char, direction(30, 0))
	char.humanoid.Health = 0
	send(char, direction(40, 0))
	check(char.attributes[attribute] == nil, "dead creatures release their pose")
	player.Character = other
	send(other, direction(-20, 10), 0.001)
	check(other.attributes[attribute] ~= nil, "new character can publish immediately")
	writes = char.writes
	send(char, direction(40, 0))
	check(char.writes == writes, "late messages from an old life are ignored")
	players.PlayerRemoving:Fire(player)
end

print(`PASS: {checks} head-tracking regression checks`)
