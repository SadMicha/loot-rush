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
}

local Looks = {}

-- Hub: base light from default.project.json (sunny, warm)
Looks.Hub = table.freeze({} :: Light)

-- Rift regions (key = Atlas ID)
Looks.Regions = table.freeze({
	green_plains = {},
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
	},
	sky_islands = {
		clock = 13,
		brightness = 3,
		ambient = Color3.fromHex("#66738C"),
		outdoor = Color3.fromHex("#B3BFD9"),
		fog = Color3.fromHex("#DDF4FF"),
		decay = Color3.fromHex("#9CC8FF"),
		density = 0.28,
		haze = 1,
		tint = Color3.fromHex("#F4FBFF"),
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
	},
} :: { [string]: Light })

-- Horizontal distance (studs) from the Hub center within which a player counts as "in the Hub"
Looks.HUB_RADIUS = 300

return table.freeze(Looks)
