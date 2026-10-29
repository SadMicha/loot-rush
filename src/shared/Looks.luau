--!strict
-- Licht je Ort (reine Daten): Hub „Lumenhafen“ und jedes Rift-Gebiet. Angewendet wird es nur im
-- Client (Controllers/LightController) – so sieht jeder Spieler das Licht des Ortes, an dem er
-- gerade steht, auch wenn ein anderer im Rift kämpft. Fehlende Felder = Werte aus
-- default.project.json (Lighting/Atmosphere beim Start).

export type Light = {
	clock: number?,
	brightness: number?,
	ambient: Color3?,
	outdoor: Color3?,
	fog: Color3?, -- Atmosphere.Color
	decay: Color3?, -- Atmosphere.Decay
	density: number?,
	haze: number?,
	tint: Color3?, -- Farbkorrektur
}

local Looks = {}

-- Hub: Grundlicht aus default.project.json (sonnig, warm)
Looks.Hub = table.freeze({} :: Light)

-- Rift-Gebiete (Schlüssel = Atlas-ID)
Looks.Regions = table.freeze({
	gruene_ebenen = {},
	kristallhoehlen = {
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
	pilzsumpf = {
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
	feuerwueste = {
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
	himmelsinseln = {
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
	veraenderte_welt = {
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

-- Abstand (Studs, waagerecht) zur Hub-Mitte, ab dem ein Spieler als „im Hub“ gilt
Looks.HUB_RADIUS = 300

return table.freeze(Looks)
