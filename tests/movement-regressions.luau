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
local swimming = loadModule(modules .. "Movement/Swimming.luau")
local stamina = loadModule(modules .. "Stats/StaminaMath.luau")

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

-- Stable clip geometry for timing tests; animal tuning can change independently.
local config = { MinAngle = 60, Brake = 0.05, Turns = {
	{ Angle = 90, Left = "Turn90Left", Right = "Turn90Right" },
	{ Angle = 180, Left = "Turn180Left", Right = "Turn180Right" },
} }
fixture(creatures.Wolf.Male.TurnInPlace) -- still validate the current animal config
local function withTurnSpeeds(ninety, oneEighty)
	local tuned = table.clone(config)
	tuned.Turns = {}
	for _, row in config.Turns do
		local copy = table.clone(row)
		copy.SpeedMultiplier = if row.Angle == 90 then ninety else oneEighty
		table.insert(tuned.Turns, copy)
	end
	return tuned
end

-- Baseline timing checks use authored speed, independently of current animal tuning.
config = withTurnSpeeds(1, 1)

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

-- The multiplier retimes both sides of each turn independently. Check body
-- phase against the authored smoothstep, and completion against clip time.
for _, fps in { 30, 60, 144 } do
	for _, multiplier in { 0.5, 1.3, 2 } do
		for _, angle in { 90, 180 } do
			local tuned = withTurnSpeeds(if angle == 90 then multiplier else 1, if angle == 180 then multiplier else 1)
			for _, sign in { -1, 1 } do
				local turner, ac, s = fixture(tuned)
				s.Sign = sign
				local initial = s.Facing
				local target = CFrame.Angles(0, math.rad(angle) * sign, 0) * initial
				local name = `Turn{angle}{if sign > 0 then "Left" else "Right"}`
				local track = ac.animationTracks[name]
				local duration = track.Length / multiplier
				local elapsed = 0
				for _, phase in { 0.25, 0.5, 1 } do
					while elapsed < duration * phase - 1e-9 do
						local dt = math.min(1 / fps, duration * phase - elapsed)
						s.Gap = math.acos(math.clamp(s.Facing:Dot(target), -1, 1))
						local facing, cap = turner:Update(s, dt)
						if facing then
							s.Facing = facing
							check(cap == s.MaxTurnRate * multiplier, "rotation frame reports its effective cap")
						end
						elapsed += dt
					end
					local expected = CFrame.Angles(0, math.rad(angle) * sign * phase * phase * (3 - 2 * phase), 0) * initial
					check(s.Facing:Dot(expected) > 0.99999, `{name}: body phase {phase} at {multiplier}x, {fps} FPS`)
					if phase < 1 then
						check(track.Speed == multiplier, `{name}: playback matches rotation multiplier`)
					end
				end
				check(track.plays == 1 and ac.currentTurn == nil, "alignment ends the scaled turn without an extra cycle")
			end
		end

		-- A tight gait cap must scale too, and repeated fractional cycles must
		-- keep their timeline without replaying the track at each boundary.
		local turner, ac, s = fixture(withTurnSpeeds(1, multiplier))
		s.Sign, s.MaxTurnRate = -1, 1
		local largestStep = 0
		for _ = 1, fps * 20 do
			local before = s.Facing
			local facing, cap = turner:Update(s, 1 / fps)
			s.Facing = facing
			local delta = math.atan2(math.abs(before:Cross(facing).Y), before:Dot(facing))
			check(cap == multiplier and delta <= cap / fps + 1e-5, "scaled turn respects its effective cap")
			largestStep = math.max(largestStep, delta)
		end
		check(largestStep * fps > multiplier * 0.99, "turn can reach the scaled allowance")
		local track = ac.animationTracks.Turn180Right
		local duration = track.Length / multiplier
		check(math.abs(turner.turn.elapsed % duration - 20 % duration) < 1e-6, "scaled right-turn cycles retain fractional time")
		check(track.plays == 1 and track.stops == 0 and track.Speed == multiplier, "scaled loops stay uninterrupted")
		s.Sign = 1
		local before = s.Facing
		s.Facing = turner:Update(s, 1 / fps)
		check(before:Cross(s.Facing).Y > 0 and ac.animationTracks.Turn180Left.Speed == multiplier, "scaled reversal is immediate")
		s.Steering = false
		local facing, cap = turner:Update(s, 1 / fps)
		check(facing == nil and cap == nil and ac.currentTurn == nil, "release yields ordinary steering with no scaled cap")
		s.Steering = true
		facing, cap = turner:Update(s, 1 / fps)
		check(facing ~= nil and cap == multiplier and ac.animationTracks.Turn180Left.Speed == multiplier, "resume restores scaled playback")
	end
end

do
	-- Force alignment within a rotation frame rather than at the next frame's
	-- tolerance check. Diagnostics still need that frame's scaled cap.
	local turner, _, s = fixture(withTurnSpeeds(1, 1.3))
	s.Facing = turner:Update(s, 0.2)
	s.Gap = 0.01
	local facing, cap = turner:Update(s, 0.1)
	check(facing ~= nil and turner:GetLabel() == nil and cap == 13, "completion frame retains its effective cap")
end

do
	local implicit, implicitAC, s = fixture(withTurnSpeeds(nil, nil))
	local explicit, explicitAC = fixture(withTurnSpeeds(1, 1))
	for frame = 1, 180 do
		s.Sign = if frame < 90 then 1 else -1
		local a, capA = implicit:Update(s, 1 / 60)
		local b, capB = explicit:Update(s, 1 / 60)
		check((a - b).Magnitude < 1e-6 and capA == capB, "omitted multiplier matches explicit 1")
		s.Facing = a
	end
	check(implicitAC.animationTracks.Turn180Right.Speed == 1 and explicitAC.animationTracks.Turn180Right.Speed == 1,
		"default playback remains authored speed")

	local track = explicitAC.animationTracks.Turn180Right
	track.TimePosition = 0.37
	explicitAC:PlayTurn("Turn180Right", 0.1, 1.3)
	check(track.TimePosition == 0.37 and track.plays == 1 and track.Speed == 1.3, "retiming a playing clip preserves its phase")
	explicitAC:PlayTurn("Turn180Right", 0.1)
	check(track.TimePosition == 0.37 and track.Speed == 1, "PlayTurn without a multiplier defaults to 1")
end

for _, invalid in { 0, -1, math.huge, -math.huge, 0 / 0, "fast", false } do
	local ok, err = pcall(fixture, withTurnSpeeds(1, invalid))
	check(not ok and string.find(tostring(err), "SpeedMultiplier", 1, true) ~= nil, "invalid multiplier rejected at config load")
end

do
	local turner, _, s = fixture({ MinAngle = 60, Turns = { { Angle = 180, Duration = 1.6, SpeedMultiplier = 2 } } })
	local initial = s.Facing
	local facing, cap = turner:Update(s, 0.4)
	check(turner:IsStepping() and math.abs(initial:Dot(facing)) < 1e-6 and cap == 20,
		"procedural duration and rotation cap use the multiplier too")
end

for _, signal in { "Blocked", "Grounded" } do
	local turner, ac, s = fixture(withTurnSpeeds(1.3, 1.3))
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

do
	local turner, ac, s = fixture(config)
	check(turner:GetBrake() == 1, "no cap before a turn runs")
	turner:Update(s, 0.1)
	check(turner:GetBrake() == config.Brake and config.Brake < 0.2, "running turn caps the brake below the curve floor")
	s.Steering = false
	turner:Update(s, 0.1)
	check(turner:GetBrake() == 1, "cancelled turn releases the cap")
	local uncapped = turns.new({ MinAngle = 60, Turns = config.Turns }, creatures.Wolf.Male.Animations, ac)
	check(uncapped:GetBrake() == 1, "omitted Brake means curve only")
	check(not pcall(turns.new, { MinAngle = 60, Brake = 0, Turns = config.Turns }, creatures.Wolf.Male.Animations, ac),
		"Brake of 0 is rejected")
end

-- Swimming: every land intent has a swim gait, and every swimmer has the
-- rows the server and controller look up by gait name.
for _, gait in states.GaitOrder do
	check(states.IsSwimming(states.SwimGaitFor[gait]), `{gait} maps onto the swim ladder`)
end
for species, genders in creatures do
	local info = genders.Male
	if info.Swimming then
		swimming.CheckConfig(info.Swimming)
		for _, gait in states.SwimOrder do
			check(type(info[gait .. "Speed"]) == "number", `{species}: {gait}Speed`)
			check(type(info[gait .. "TurnRate"]) == "number", `{species}: {gait}TurnRate`)
			check(type(info.Animations[gait]) == "string", `{species}: {gait} animation`)
			check(info[gait .. "StaminaDrain"] ~= nil or info[gait .. "StaminaGain"] ~= nil, `{species}: {gait} stamina row`)
		end
	end
end

do
	local info = creatures.Wolf.Male
	local swim = info.SwimSpeed
	-- Cruising at each swim speed settles on its rung from any history.
	for _, initial in { "Idle", "Sprint", "SwimIdle", "Swim", "SwimFast" } do
		for _, target in states.SwimOrder do
			check(mathModule.ResolveSwimGaitFromVelocity(info[target .. "Speed"], initial, swim) == target,
				`swim {initial} -> {target} at cruise`)
		end
	end
	-- Leaving the water at speed lands straight on the right land band.
	check(mathModule.ResolveGaitFromVelocity(info.SwimFastSpeed, "SwimFast", info.WalkSpeed, info.TrotSpeed, info.RunSpeed)
		== mathModule.ResolveGaitFromVelocity(info.SwimFastSpeed, "Idle", info.WalkSpeed, info.TrotSpeed, info.RunSpeed),
		"leaving the water restarts the land ladder")

	-- Hysteresis around the swim depth, in units of the root height.
	local cfg, h = info.Swimming, 3
	local swimDepth = h * (1 + cfg.FloatDepth)
	check(not swimming.Decide(false, nil, nil, 0, h, cfg), "no water, no swimming")
	check(not swimming.Decide(false, 10, 10 - swimDepth * 0.95, 10, h, cfg), "wades in water just too shallow")
	check(swimming.Decide(false, 10, 10 - swimDepth, 10, h, cfg), "swims once deep enough")
	check(swimming.Decide(true, 10, 10 - swimDepth * 0.9, 10, h, cfg), "keeps swimming inside the band")
	check(not swimming.Decide(true, 10, 10 - swimDepth * 0.8, 10, h, cfg), "wades out below the band")
	check(not swimming.Decide(false, 10, -100, 10 + h, h, cfg), "still falling toward the surface")

	-- The lift settles on the float height from above and below, bounded.
	local target = 10 - h * cfg.FloatDepth
	check(math.abs(swimming.LiftVelocity(target, 10, h, cfg)) < 1e-9, "no lift at the float height")
	check(swimming.LiftVelocity(target - 1, 10, h, cfg) > 0, "rises when too deep")
	check(swimming.LiftVelocity(target + 1, 10, h, cfg) < 0, "sinks when too high")
	check(swimming.LiftVelocity(-1000, 10, h, cfg) <= 10 and swimming.LiftVelocity(1000, 10, h, cfg) >= -20,
		"lift is bounded")
	for _, fps in { 30, 60, 144 } do
		local y = target - 2
		for _ = 1, fps * 3 do
			y += swimming.LiftVelocity(y, 10, h, cfg) / fps
		end
		check(math.abs(y - target) < 0.01, `float settles at {fps} FPS`)
	end

	-- Stamina: an exhausted fast swim slows to the slow swim, never below it.
	local t = info.StaminaPenaltyThreshold
	check(stamina.GetStaminaPenalizedSwimSpeed(info.SwimFastSpeed, swim, 1, t) == info.SwimFastSpeed, "full stamina, full fast swim")
	check(stamina.GetStaminaPenalizedSwimSpeed(info.SwimFastSpeed, swim, 0, t) == swim, "exhausted fast swim = slow swim")
	check(stamina.GetStaminaPenalizedSwimSpeed(swim, swim, 0, t) == swim, "slow swim is never penalised")
end

-- Turn-braked speed: braking into a turn stays fast, the recovery is capped
-- at Acceleration (it used to spike to ~700 studs/s^2), and the command never
-- exceeds WalkSpeed. Same result at any frame rate.
do
	local info = creatures.Wolf.Male
	local walk, accel, floor = info.SprintSpeed, info.Acceleration, info.TurnInPlace.Brake
	for _, fps in { 30, 60, 144 } do
		local dt = 1 / fps
		local speed = walk
		for _ = 1, fps do
			speed = mathModule.StepTurnBrakedSpeed(speed, walk, floor, dt, accel, 10, true, info.Deceleration)
		end
		check(speed < walk * floor * 1.1, `brakes into a turn within a second at {fps} FPS`)

		local elapsed, worst = 0, 0
		while speed < walk - 1e-6 do
			local before = speed
			speed = mathModule.StepTurnBrakedSpeed(speed, walk, 1, dt, accel, 10, true, info.Deceleration)
			worst = math.max(worst, (speed - before) / dt)
			elapsed += dt
			check(speed <= walk, "recovery never exceeds WalkSpeed")
		end
		check(worst <= accel + 1e-6, `recovery capped at Acceleration at {fps} FPS`)
		local expected = (walk - walk * floor) / accel
		check(math.abs(elapsed - expected) <= dt + 0.05, `recovery takes (gap / Acceleration) s at {fps} FPS`)

		-- A lower server ceiling (gait drop, stamina) is followed at once.
		check(mathModule.StepTurnBrakedSpeed(walk, 40, 1, dt, accel, 10, true, info.Deceleration) == 40,
			"follows a falling WalkSpeed")
	end
end

-- Releasing a pivot must never recover toward the unused server speed. Test
-- actual turn cancellation after short and sustained input, then re-pressing.
do
	local info = creatures.Wolf.Male
	for _, fps in { 30, 60, 144 } do
		local dt = 1 / fps
		for _, heldFor in { 0.2, 1, 4 } do
			local turner, ac, signals = fixture(info.TurnInPlace)
			local speed, walk = 0, 0
			for _ = 1, math.ceil(heldFor * fps) do
				walk = mathModule.Accelerate(walk, info.SprintSpeed, dt, info.Acceleration, info.Deceleration)
				signals.Facing = turner:Update(signals, dt)
				speed = mathModule.StepTurnBrakedSpeed(speed, walk, turner:GetBrake(), dt, info.Acceleration, 10, true, info.Deceleration)
			end
			check(walk > speed, "pivot leaves unused server speed")
			signals.Steering = false
			check(turner:Update(signals, dt) == nil and ac.currentTurn == nil, "release cancels the pivot immediately")
			local before = speed
			speed = mathModule.StepTurnBrakedSpeed(speed, walk, turner:GetBrake(), dt, info.Acceleration, 10, false, info.Deceleration)
			check(speed < before and speed >= 0, `release sheds pivot speed after {heldFor}s at {fps} FPS`)
			check(math.abs(speed - math.max(0, before - info.Deceleration * dt)) < 1e-6,
				"pivot release decelerates from current speed, not unused server speed")
			local resumed = mathModule.StepTurnBrakedSpeed(speed, walk, 1, dt, info.Acceleration, 10, true, info.Deceleration)
			check(resumed > speed and resumed - speed <= info.Acceleration * dt + 1e-6,
				"re-pressing resumes acceleration from the remaining speed")
		end
	end
end

-- Ordinary coasting retains each creature's Deceleration. A delayed server
-- release cannot add thrust; a server already decelerating cannot double it.
for species, genders in creatures do
	local info = genders.Male
	for _, fps in { 30, 60, 144 } do
		local dt = 1 / fps
		for _, initial in { 0, 0.6, info.WalkSpeed, info.RunSpeed, info.SprintSpeed } do
			for _, delay in { 0, 0.3, math.huge } do
				local speed, walk = initial, info.SprintSpeed
				local frames = math.ceil((initial / info.Deceleration + 0.5) * fps)
				for frame = 1, frames do
					if (frame - 1) * dt >= delay then
						walk = mathModule.Accelerate(walk, 0, dt, info.Acceleration, info.Deceleration)
					end
					local before = speed
					speed = mathModule.StepTurnBrakedSpeed(speed, walk, 1, dt, info.Acceleration, 10, false, info.Deceleration)
					check(speed >= 0 and speed <= before and speed <= walk, "released speed only falls, within server authority")
					-- Accelerate may snap the server's last <0.1 studs/s to zero.
					local expected = math.min(walk, math.max(0, initial - info.Deceleration * frame * dt))
					check(math.abs(speed - expected) < 1e-6, `{species}: normal stopping rate at {fps} FPS`)
				end
				check(speed == 0, "release reaches zero and stays stopped even with a high server ceiling")
			end
		end
	end
end

check(mathModule.StepTurnBrakedSpeed(20, 2, 1, 0.01, 60, 10, false, 60) == 2,
	"release still obeys a suddenly lower server ceiling")
check(mathModule.StepTurnBrakedSpeed(20, 73, 1, 1, 60, 10, false, 60) == 0,
	"a long release frame stops without reversing")

print(`PASS: {checks} movement regression checks`)
