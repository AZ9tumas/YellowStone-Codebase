-- Run from the repository root: lune run tests/movement-regressions.luau
-- Loads the production modules with Roblox value types and fake animation
-- tracks; no Studio instance, game edits or downloaded assets are needed.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function loadModule(path, dependencies)
	return luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			script = { Parent = { Parent = dependencies or {} } },
			require = function(module) return module end,
			Enum = roblox.Enum,
			Vector3 = Vector3,
			CFrame = CFrame,
		},
		injectGlobals = true,
	})()
end

local modules = "src/ReplicatedStorage/Modules/"
local states = loadModule(modules .. "Movement/MovementStates.luau")
local mathModule = loadModule(modules .. "Stats/MovementMath.luau", { Movement = { MovementStates = states } })
local creatures = loadModule(modules .. "Stats/CreatureStats.luau")
local animations = loadModule(modules .. "AnimationController.luau")
local turns = loadModule(modules .. "Movement/TurnInPlace.luau", { AnimationController = animations })

local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
end

-- Cruising at ANY gait must converge to that gait regardless of history.
-- The old resolver fails Sprint -> Trot, Run -> Walk and Sprint -> Run here.
for species, genders in creatures do
	local info = genders.Male
	for _, initial in states.GaitOrder do
		for _, target in states.GaitOrder do
			local speed = info[target .. "Speed"]
			check(mathModule.ResolveGaitFromVelocity(speed, initial, info.WalkSpeed, info.TrotSpeed, info.RunSpeed) == target,
				`{species}: {initial} -> {target} at cruise`)
		end
	end
	for _, fps in { 30, 60, 144 } do
		for _, target in { "Walk", "Trot", "Run" } do
			local measured, smoothed, gait = info.SprintSpeed, info.SprintSpeed, "Sprint"
			local dt = 1 / fps
			for _ = 1, fps * 12 do
				measured = mathModule.Accelerate(measured, info[target .. "Speed"], dt, info.Acceleration, info.Deceleration)
				smoothed += (measured - smoothed) * (1 - math.exp(-8 * dt))
				gait = mathModule.ResolveGaitFromVelocity(smoothed, gait, info.WalkSpeed, info.TrotSpeed, info.RunSpeed)
			end
			check(gait == target, `{species}: deceleration to {target} at {fps} FPS`)
			-- Terrain noise at cruise must not promote the gait again.
			for frame = 1, fps do
				local noisy = info[target .. "Speed"] * (1 + 0.025 * math.sin(frame))
				gait = mathModule.ResolveGaitFromVelocity(noisy, gait, info.WalkSpeed, info.TrotSpeed, info.RunSpeed)
				check(gait == target, `{species}: cruise jitter at {fps} FPS`)
			end
		end
	end
end

local function fixture(config)
	local ac = setmetatable({ animationTracks = {}, currentTurn = nil, fadeTime = 0.2 }, animations)
	for name in turns.ClipNames(config) do
		-- Measured from the wolf's loaded Studio tracks: left 180 = 1 s,
		-- right 180 = 25/24 s (deliberately not a whole 30/60/144 FPS frame).
		local track = { Length = if name == "Turn180Right" then 25 / 24 else 1, IsPlaying = false, plays = 0, stops = 0 }
		function track:Play(_, _, speed) self.IsPlaying = true; self.plays += 1; self.Speed = speed end
		function track:Stop() self.IsPlaying = false; self.stops += 1 end
		function track:AdjustSpeed(speed) self.Speed = speed end
		ac.animationTracks[name] = track
	end
	local turner = turns.new(config, creatures.Wolf.Male.Animations, ac)
	local signals = {
		Facing = Vector3.new(0, 0, -1), Gap = math.pi, Sign = 1,
		Steering = true, Grounded = true, Blocked = false, MaxTurnRate = 10,
	}
	return turner, ac, signals
end

local config = creatures.Wolf.Male.TurnInPlace
for _, fps in { 30, 60, 144 } do
	local dt = 1 / fps
	local turner, ac, s = fixture(config)
	local target = -s.Facing
	for _ = 1, fps do
		s.Gap = math.acos(math.clamp(s.Facing:Dot(target), -1, 1))
		local facing = turner:Update(s, dt)
		if facing then s.Facing = facing end
	end
	check(s.Facing:Dot(target) > 0.99999, `full 180 completes at {fps} FPS`)
	check(ac.animationTracks.Turn180Left.plays == 1, "authored 180 used once")
	check(not turner:IsStepping(), "180 does not use procedural stepping")

	-- Cancel halfway: no more heading changes, no wait for the clip to finish.
	turner, ac, s = fixture(config)
	for _ = 1, math.floor(0.5 * fps) do
		s.Facing = turner:Update(s, dt)
	end
	s.Steering = false
	check(turner:Update(s, dt) == nil and turner:GetLabel() == nil, "release cancels on the same frame")
	check(ac.currentTurn == nil and ac.animationTracks.Turn180Left.Speed == 0, "released clip stops stepping")
	check(turner:Update(s, dt) == nil, "released turn stays cancelled")

	-- Keep a large gap ahead of the moving heading for several full cycles.
	turner, ac, s = fixture(config)
	s.Gap = math.rad(160)
	s.MaxTurnRate = 4
	for _ = 1, fps * 6 do
		local before = s.Facing
		s.Facing = turner:Update(s, dt)
		check(s.Facing ~= nil and turner:GetLabel() == "Turn180Left", "sustained demand keeps turning")
		local delta = math.acos(math.clamp(before:Dot(s.Facing), -1, 1))
		check(delta <= 4 * dt + 1e-4, "turn respects the gait's rate cap")
	end
	check(ac.animationTracks.Turn180Left.plays == 1, "repeated turns loop without replay resets")
	check(ac.animationTracks.Turn180Left.stops == 0, "no fade gaps between repeated turns")

	-- Opposite demand is acted on immediately, not after the previous cycle.
	s.Sign = -1
	local before = s.Facing
	s.Facing = turner:Update(s, dt)
	check(before:Cross(s.Facing).Y < 0 and turner:GetLabel() == "Turn180Right", "reversal switches direction immediately")
	check(ac.animationTracks.Turn180Left.stops == 1, "old direction's clip stopped")
	for _ = 1, fps * 20 - 1 do
		s.Facing = turner:Update(s, dt)
	end
	local length = ac.animationTracks.Turn180Right.Length
	check(math.abs(turner.turn.elapsed % length - 20 % length) < 1e-6,
		"repeated body cycles stay in time with the right turn clip")
	s.Gap = 0
	check(turner:Update(s, dt) == nil and ac.currentTurn == nil, "steering straight cancels immediately")
end

for _, signal in { "Blocked", "Grounded" } do
	local turner, ac, s = fixture(config)
	turner:Update(s, 0.1)
	s[signal] = signal == "Blocked"
	check(turner:Update(s, 0.1) == nil and ac.currentTurn == nil, signal .. " cancels")
end

do
	local turner, ac, s = fixture(config)
	ac.animationTracks.Turn180Left.Length = 0
	check(turner:Update(s, 0.1) == nil, "unloaded clip yields to ordinary steering")
	check(ac.currentTurn == nil, "unloaded clip cannot lock the turn")
end

do
	local procedural = { MinAngle = 60, Turns = { { Angle = 180, Duration = 1.6 } } }
	local turner, _, s = fixture(procedural)
	check(turner:Update(s, 0.1) ~= nil and turner:IsStepping(), "procedural option retained")
	s.Steering = false
	check(turner:Update(s, 0.1) == nil and not turner:IsStepping(), "procedural option is interruptible too")
end

do
	local mixed = { MinAngle = 60, Turns = {
		{ Angle = 90, Left = "Turn90Left", Right = "Turn90Right" },
		{ Angle = 180, Duration = 1.6 },
	} }
	local turner, ac, s = fixture(mixed)
	s.Gap = math.pi / 2
	for _ = 1, 60 do
		s.Facing = turner:Update(s, 1 / 60)
	end
	check(ac.currentTurn == "Turn90Left", "mixed config starts its authored quarter-turn")
	s.Gap = math.pi
	turner:Update(s, 0.1)
	check(turner:IsStepping() and ac.currentTurn == nil, "procedural continuation releases the previous clip")
end

print(`PASS: {checks} movement regression checks`)
