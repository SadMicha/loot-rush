--!strict
-- Light per place (pure data): Hub "Lumenhaven" and every Rift region. It is only applied on the
-- client (Controllers/LightController) - so every player sees the light of the place they are
-- currently in, even while someone else fights in a Rift. Missing fields = values from
-- default.project.json (Lighting/Atmosphere at start).

export type Light = {
	clock: number?,
	brightness: number?,
	ambient: Color3?,
	outdoor: Color3?,
	fog: Color3?, -- Atmosphere.Color
	decay: Color3?, -- Atmosphere.Decay
	density: number?,
	haze: number?,
	tint: Color3?, -- color correction
	clouds: number?, -- Terrain Clouds.Cover (0 = clear sky)
	ambience: string?, -- key in Shared/Sounds.Ambience for the looped ambience (AmbienceController)
}

local Looks = {}

-- Hub: base light from default.project.json (sunny, warm)
Looks.Hub = table.freeze({ clouds = 0.55, ambience = "hub" } :: Light)

-- Rift regions (key = Atlas ID)
Looks.Regions = table.freeze({
	green_plains = { clouds = 0.55, ambience = "meadow" },
	crystal_caves = {
		clock = 20.6,
		brightness = 1.2,
		ambient = Color3.fromHex("#40527F"),
		outdoor = Color3.fromHex("#4A6699"),
		fog = Color3.fromHex("#6FA8D8"),
		decay = Color3.fromHex("#2A3B6A"),
		density = 0.45,
		haze = 2,
		tint = Color3.fromHex("#D6F2FF"),
		clouds = 0.85,
		ambience = "cave",
	},
	mushroom_swamp = {
		clock = 18.2,
		brightness = 1.8,
		ambient = Color3.fromHex("#5A476B"),
		outdoor = Color3.fromHex("#806699"),
		fog = Color3.fromHex("#B79BD8"),
		decay = Color3.fromHex("#5C3F7A"),
		density = 0.5,
		haze = 2.5,
		tint = Color3.fromHex("#F2E0FF"),
		clouds = 0.75,
		ambience = "swamp",
	},
	fire_desert = {
		clock = 18.4,
		brightness = 2.2,
		ambient = Color3.fromHex("#733F33"),
		outdoor = Color3.fromHex("#B3734D"),
		fog = Color3.fromHex("#FFB27A"),
		decay = Color3.fromHex("#8A3A1E"),
		density = 0.4,
		haze = 2.2,
		tint = Color3.fromHex("#FFE2C8"),
		clouds = 0.2,
		ambience = "lava",
	},
	sky_islands = {
		clock = 15.5,
		brightness = 1.6,
		ambient = Color3.fromHex("#4E5A70"),
		outdoor = Color3.fromHex("#8290AC"),
		fog = Color3.fromHex("#BFD8EE"),
		decay = Color3.fromHex("#7FA6D8"),
		density = 0.34,
		haze = 1.4,
		tint = Color3.fromHex("#E4EAF2"),
		clouds = 0.45,
		ambience = "wind",
	},
	altered_world = {
		clock = 0.5,
		brightness = 1.2,
		ambient = Color3.fromHex("#59336F"),
		outdoor = Color3.fromHex("#66337F"),
		fog = Color3.fromHex("#6A3A9A"),
		decay = Color3.fromHex("#FF5AD0"),
		density = 0.5,
		haze = 2,
		tint = Color3.fromHex("#FFD0F4"),
		clouds = 0.9,
		ambience = "rift",
	},
} :: { [string]: Light })

-- Horizontal distance (studs) from the Hub center within which a player counts as "in the Hub"
Looks.HUB_RADIUS = 300

return table.freeze(Looks)
