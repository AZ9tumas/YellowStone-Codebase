--[[
	Swimming

	Surface swimming in Terrain water. Shared by the server (which owns swim
	SPEED, like every other gait) and the client (which floats the body and
	picks the swim animation). Both decide independently from the same rules,
	so neither has to trust the other's claim.

	Every distance is a fraction of the creature's standing root height
	(Humanoid.HipHeight + half the root part), read off the rig, so nothing
	needs re-tuning if a creature is rescaled:

	  * Floating, the root sits FloatDepth x that height under the surface.
	  * The creature swims once the water is deep enough to float there with
	    its legs hanging clear of the bed: depth >= height x (1 + FloatDepth).
	  * It wades out again below EXIT_RATIO of that depth. The gap keeps a
	    shoreline from flickering between swimming and walking.

	The probe only ever sees Terrain (the lakes are Terrain water), so trees,
	bridges and other creatures cannot hide the surface.
]]

local Swimming = {}

export type Config = {
	FloatDepth: number, -- fraction of standing root height under the surface while floating
	Buoyancy: number, -- 1/s: how fast the body settles to that height
}

local PROBE_UP = 40 -- studs above the root the surface ray starts
local PROBE_DOWN = 400 -- studs the bed ray may travel below the surface
local EXIT_RATIO = 0.85 -- wade out below this fraction of the swim depth
local ENTRY_ABOVE = 0.5 -- x root height: a root higher above the surface is still falling in
local MAX_RISE = 10 -- studs/s
local MAX_SINK = 20 -- studs/s

-- Validates a creature's optional Swimming block. Fails loud on a bad value.
function Swimming.CheckConfig(config: Config)
	assert(type(config) == "table", "Swimming: config missing")
	assert(
		type(config.FloatDepth) == "number" and config.FloatDepth >= 0 and config.FloatDepth <= 1,
		"Swimming: FloatDepth must be in 0..1"
	)
	assert(type(config.Buoyancy) == "number" and config.Buoyancy > 0, "Swimming: Buoyancy must be > 0")
end

-- Height of the root's centre above the ground when standing, in studs.
function Swimming.RootHeight(humanoid: Humanoid, root: BasePart): number
	return humanoid.HipHeight + root.Size.Y * 0.5
end

-- Water surface and bed heights in the column through `position`, or nil
-- when there is no water there.
function Swimming.Probe(position: Vector3): (number?, number?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false

	local surface = workspace:Raycast(position + Vector3.yAxis * PROBE_UP, Vector3.yAxis * -(PROBE_UP * 2), params)
	if not surface or surface.Material ~= Enum.Material.Water then
		return nil, nil
	end

	params.IgnoreWater = true
	local bed = workspace:Raycast(surface.Position, Vector3.yAxis * -PROBE_DOWN, params)
	return surface.Position.Y, if bed then bed.Position.Y else surface.Position.Y - PROBE_DOWN
end

-- Swimming this frame? Pure: `wasSwimming` carries the hysteresis.
function Swimming.Decide(
	wasSwimming: boolean,
	surfaceY: number?,
	bedY: number?,
	rootY: number,
	rootHeight: number,
	config: Config
): boolean
	if not surfaceY or not bedY then
		return false
	end
	local swimDepth = rootHeight * (1 + config.FloatDepth)
	local depth = surfaceY - bedY
	if wasSwimming then
		return depth >= swimDepth * EXIT_RATIO
	end
	return depth >= swimDepth and rootY <= surfaceY + rootHeight * ENTRY_ABOVE
end

-- Vertical velocity (studs/s) that floats the root at its swimming height.
function Swimming.LiftVelocity(rootY: number, surfaceY: number, rootHeight: number, config: Config): number
	local target = surfaceY - rootHeight * config.FloatDepth
	return math.clamp((target - rootY) * config.Buoyancy, -MAX_SINK, MAX_RISE)
end

return Swimming
