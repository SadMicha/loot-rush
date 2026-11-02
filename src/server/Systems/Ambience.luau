--!strict
-- World atmosphere that is the same for everyone and lives outside the map folders:
-- sky (sun, moon, stars), clouds, depth of field and the Terrain water look.
-- Base light/fog/bloom/sun rays/color correction come from default.project.json;
-- the per-place mood (time of day, fog color, cloud cover) is set on the client
-- (LightController with Shared/Looks), ambience sounds by AmbienceController.

local Lighting = game:GetService("Lighting")

local Ambience = {}

-- Tunable look values (rendering only, no gameplay)
local SKY = table.freeze({ stars = 3000, sun = 14, moon = 9 })
local CLOUDS = table.freeze({
	cover = 0.55,
	density = 0.6,
	color = Color3.fromHex("#FFF6EC"),
})
-- Far blur only: the playfield (camera ≈ 40-60 studs away) stays sharp, the backdrop softens.
local DOF = table.freeze({ focus = 55, radius = 60, far = 0.18, near = 0 })
local WATER = table.freeze({
	color = Color3.fromHex("#3FA9E0"),
	transparency = 0.55,
	reflectance = 0.35,
	waves = 0.12,
	speed = 8,
})

local function ensure<T>(parent: Instance, className: string, name: string): T
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == className then
		return found :: any
	end
	local inst = Instance.new(className :: any)
	inst.Name = name
	inst.Parent = parent
	return inst :: any
end

function Ambience.init()
	local sky = ensure(Lighting, "Sky", "Sky") :: Sky
	sky.StarCount = SKY.stars
	sky.SunAngularSize = SKY.sun
	sky.MoonAngularSize = SKY.moon
	sky.CelestialBodiesShown = true

	local dof = ensure(Lighting, "DepthOfFieldEffect", "DepthOfField") :: DepthOfFieldEffect
	dof.FocusDistance = DOF.focus
	dof.InFocusRadius = DOF.radius
	dof.FarIntensity = DOF.far
	dof.NearIntensity = DOF.near

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = ensure(terrain, "Clouds", "Clouds") :: Clouds
		clouds.Cover = CLOUDS.cover
		clouds.Density = CLOUDS.density
		clouds.Color = CLOUDS.color
		terrain.WaterColor = WATER.color
		terrain.WaterTransparency = WATER.transparency
		terrain.WaterReflectance = WATER.reflectance
		terrain.WaterWaveSize = WATER.waves
		terrain.WaterWaveSpeed = WATER.speed
	end
end

return Ambience
