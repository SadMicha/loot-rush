--!strict
-- Light per place (pure data): Hub "Lumenhaven" and every Rift region. It is only applied on the
-- client (Controllers/LightController) - so every player sees the light of the place they are
-- currently in, even while someone else fights in a Rift. Missing fields = values from
-- default.project.json (Lighting/Atmosphere at start).

export type Light = {
	clock: number?,
	brightness: number?,
	ambient: Color3?, -- shadow fill: kept cooler/darker than the sun side for contrast
	outdoor: Color3?,
	fog: Color3?, -- Atmosphere.Color
	decay: Color3?, -- Atmosphere.Decay
	density: number?,
	haze: number?,
	tint: Color3?, -- color correction
	saturation: number?, -- on top of the base ColorCorrection (default.project.json)
	contrast: number?, -- on top of the base ColorCorrection
	bloom: number?, -- BloomEffect.Intensity (glow of Neon crystals, lava, loot beams)
	clouds: number?, -- Terrain Clouds.Cover (0 = clear sky)
	ambience: string?, -- key in Shared/Sounds.Ambience for the looped ambience (AmbienceController)
}

local Looks = {}

-- Palette rule (docs/specs/WORLD-MAPS.md §7): each place has one dominant hue, a contrasting
-- shadow/fog hue and a cyan-blue or gold accent. Ground stays darker or less saturated than
-- enemies, loot and red danger zones so combat reads on phones.

-- Hub "Lumenhaven": warm late-afternoon sun, sky-blue fog, cool violet shadows
Looks.Hub = table.freeze({
	clock = 16.4,
	brightness = 2.8,
	ambient = Color3.fromHex("#4A4C78"),
	outdoor = Color3.fromHex("#9A8CBA"),
	fog = Color3.fromHex("#9CCEFF"),
	decay = Color3.fromHex("#FFB46A"),
	density = 0.28,
	haze = 1.3,
	tint = Color3.fromHex("#FFF8EC"),
	saturation = 0.12,
	contrast = 0.06,
	bloom = 0.8,
	clouds = 0.5,
	ambience = "hub",
} :: Light)

-- Rift regions (key = Atlas ID)
Looks.Regions = table.freeze({
	-- bright midday meadow, deep blue sky
	green_plains = {
		clock = 14.6,
		brightness = 3,
		ambient = Color3.fromHex("#46567E"),
		outdoor = Color3.fromHex("#8E9CC4"),
		fog = Color3.fromHex("#8CCBFF"),
		decay = Color3.fromHex("#FFD488"),
		density = 0.26,
		haze = 1.1,
		tint = Color3.fromHex("#FFFBEE"),
		saturation = 0.14,
		contrast = 0.08,
		bloom = 0.8,
		clouds = 0.5,
		ambience = "meadow",
	},
	-- deep indigo night, glowing cyan crystals
	crystal_caves = {
		clock = 20.6,
		brightness = 1.4,
		ambient = Color3.fromHex("#3A58A8"),
		outdoor = Color3.fromHex("#4E7AD0"),
		fog = Color3.fromHex("#3FB4F0"),
		decay = Color3.fromHex("#1A2A80"),
		density = 0.42,
		haze = 1.8,
		tint = Color3.fromHex("#D4F2FF"),
		saturation = 0.16,
		contrast = 0.14,
		bloom = 1.1,
		clouds = 0.85,
		ambience = "cave",
	},
	-- lush green bog under a violet dusk
	mushroom_swamp = {
		clock = 18.2,
		brightness = 2,
		ambient = Color3.fromHex("#5C3C88"),
		outdoor = Color3.fromHex("#8C5CC0"),
		fog = Color3.fromHex("#B888F4"),
		decay = Color3.fromHex("#5A2A90"),
		density = 0.46,
		haze = 2.2,
		tint = Color3.fromHex("#F2E2FF"),
		saturation = 0.2,
		contrast = 0.1,
		bloom = 1,
		clouds = 0.75,
		ambience = "swamp",
	},
	-- golden sand, red rock, orange sunset
	fire_desert = {
		clock = 18.4,
		brightness = 2.6,
		ambient = Color3.fromHex("#7A3A40"),
		outdoor = Color3.fromHex("#C8743F"),
		fog = Color3.fromHex("#FF9C58"),
		decay = Color3.fromHex("#A02E18"),
		density = 0.38,
		haze = 2,
		tint = Color3.fromHex("#FFE4C4"),
		saturation = 0.18,
		contrast = 0.12,
		bloom = 1,
		clouds = 0.2,
		ambience = "lava",
	},
	-- white-gold stone over a saturated blue sky
	sky_islands = {
		clock = 15.5,
		brightness = 2,
		ambient = Color3.fromHex("#506894"),
		outdoor = Color3.fromHex("#8CA8E0"),
		fog = Color3.fromHex("#94CCFF"),
		decay = Color3.fromHex("#5A98F2"),
		density = 0.3,
		haze = 1.2,
		tint = Color3.fromHex("#EEF4FF"),
		saturation = 0.15,
		contrast = 0.1,
		bloom = 0.9,
		clouds = 0.45,
		ambience = "wind",
	},
	-- violet void, magenta rifts
	altered_world = {
		clock = 0.5,
		brightness = 1.4,
		ambient = Color3.fromHex("#5A2C88"),
		outdoor = Color3.fromHex("#7A36A8"),
		fog = Color3.fromHex("#7A36C8"),
		decay = Color3.fromHex("#FF4AD0"),
		density = 0.46,
		haze = 1.8,
		tint = Color3.fromHex("#FFD8F6"),
		saturation = 0.24,
		contrast = 0.15,
		bloom = 1.2,
		clouds = 0.9,
		ambience = "rift",
	},
} :: { [string]: Light })

-- Horizontal distance (studs) from the Hub center within which a player counts as "in the Hub"
Looks.HUB_RADIUS = 300

return table.freeze(Looks)
