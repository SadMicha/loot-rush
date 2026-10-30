--!strict
-- Alle Robux-IDs an einem Ort: Developer Products (Seelensterne) und Gamepässe.
-- IDs kommen aus dem Creator Hub (Spiel → Monetization → Developer Products / Passes).
-- 0 = noch nicht angelegt: der Kaufknopf bleibt aus, der Server nimmt nichts an.
-- Robux-Preise hier sind nur Anzeige – maßgeblich ist der Preis im Creator Hub.
-- Server: Systems/Monetization (ProcessReceipt, Gamepass-Besitz). Anleitung: docs/MONETARISIERUNG.md

local Monetization = {}

-- Developer Products (mehrfach kaufbar). Schlüssel = Shop.OFFERS[].product
Monetization.ProductIds = table.freeze({
	soulstars_s = 0,
	soulstars_m = 0,
	soulstars_l = 0,
} :: { [string]: number })

export type Pass = {
	key: string,
	id: number, -- Gamepass-ID; 0 = Platzhalter
	name: string,
	text: string,
	robux: number,
	icon: string,
	bonus: { [string]: number }, -- Dauer-Boni wie Systems/Boosts (Prozent, magnet = Studs)
	attr: string?, -- zusätzliches Player-Attribut = true (z. B. PassPetSlot für Systems/Pets)
}

local PASSES: { Pass } = {
	{
		key = "vip",
		id = 0,
		name = "VIP",
		text = "+25 % Gold und +25 % Erfahrung für immer.",
		robux = 299,
		icon = "krone",
		bonus = { gold = 25, xp = 25 },
	},
	{
		key = "pet_slot",
		id = 0,
		name = "Haustier-Platz",
		text = "Ein zweites Haustier begleitet dich.",
		robux = 199,
		icon = "herz",
		bonus = {},
		attr = "PassPetSlot",
	},
	{
		key = "magnet",
		id = 0,
		name = "Beutemagnet",
		text = "+8 Studs Aufheberadius und +10 % Item-Chance.",
		robux = 149,
		icon = "truhe",
		bonus = { magnet = 8, items = 10 },
	},
}

local byKey: { [string]: Pass } = {}
for _, p in PASSES do
	table.freeze(p.bonus)
	byKey[p.key] = table.freeze(p)
end
Monetization.Passes = table.freeze(PASSES)
Monetization.PassByKey = table.freeze(byKey)

-- Attribut am Spieler, wenn er den Pass besitzt (Server setzt es)
function Monetization.passAttr(key: string): string
	return "Pass_" .. key
end

function Monetization.passById(id: number): Pass?
	if id <= 0 then
		return nil
	end
	for _, p in PASSES do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Summe der Boni aller Pässe, für die owned(key) true ist
function Monetization.bonus(owned: (string) -> boolean): { [string]: number }
	local sum: { [string]: number } = {}
	for _, p in PASSES do
		if owned(p.key) then
			for stat, v in p.bonus do
				sum[stat] = (sum[stat] or 0) + v
			end
		end
	end
	return sum
end

return table.freeze(Monetization)
