--!strict
-- Spielwerte aus LootRush_Balancing.xlsx (Blatt „Parameter“), Namen wie in der Tabelle.
-- Ändert sich die Tabelle, hier nachziehen; tests/Balancing.spec.luau rechnet Tiefe 1–30 durch.
-- Abweichungen und eigene Annahmen stehen in docs/balancing.md.

local Balance = {}

Balance.P = table.freeze({
	-- Gegner (normaler Gegner, Archetyp-Faktor 1)
	hp_basis = 40,
	hp_wachstum = 1.18,
	dmg_basis = 6,
	dmg_wachstum = 1.12,
	boss_hp = 40,
	-- Weiche Wand (eigene Annahme, Michas Vorgabe): ab dieser Tiefe wächst das Gegner-Leben schneller.
	-- Ohne Wiedergeburt bleibt es schaffbar, braucht aber Farmen, Schmiede und Sterne.
	wand_ab = 20,
	wand_wachstum = 1.1,
	-- Belohnung
	gold_basis = 2,
	gold_wachstum = 1.13,
	xp_basis = 15,
	xp_wachstum = 1.16,
	boss_beute = 25,
	-- Spieler
	xp_level_basis = 100,
	xp_level_exp = 1.6,
	level_max = 100,
	leben_basis = 100,
	leben_pro_level = 12,
	waffe_basis = 12,
	waffe_wachstum = 1.155,
	-- Loot
	drop_normal = 0.12,
	drops_boss = 3,
	loot_tiefe = 50,
	ip_pro_tiefe = 10,
})

-- Seltenheits-Gewichte auf Tiefe 1 und Exponent der Verschiebung (Blatt „Loot“).
-- Einzigartig/Legendär (0,45 / 0,05) gibt es im Spiel noch nicht.
Balance.Rarity = table.freeze({
	{ id = "normal", weight = 60, exp = 0 },
	{ id = "magic", weight = 28, exp = 0.5 },
	{ id = "rare", weight = 9.5, exp = 1 },
	{ id = "epic", weight = 2, exp = 1.5 },
})

-- IP-Bonus je Seltenheit (Blatt „Loot · Affixe & Verwerten“)
Balance.IpBonus =
	table.freeze({ normal = 0, magic = 5, rare = 10, epic = 20 } :: { [string]: number })

local P = Balance.P

local function steps(depth: number): number
	return math.max(0, math.floor(depth) - 1)
end

-- Je Tiefe (normaler Gegner, vor Archetyp- und Boss-Faktor)
function Balance.enemyHealth(depth: number): number
	local wall = math.max(0, math.floor(depth) - P.wand_ab)
	return P.hp_basis * P.hp_wachstum ^ steps(depth) * P.wand_wachstum ^ wall
end

function Balance.enemyDamage(depth: number): number
	return P.dmg_basis * P.dmg_wachstum ^ steps(depth)
end

function Balance.gold(depth: number): number
	return P.gold_basis * P.gold_wachstum ^ steps(depth)
end

function Balance.xp(depth: number): number
	return P.xp_basis * P.xp_wachstum ^ steps(depth)
end

-- Item-Power der Beute auf dieser Tiefe (Gegenstandsstufe = IP / 10)
function Balance.itemPower(depth: number): number
	return math.max(1, math.floor(depth)) * P.ip_pro_tiefe
end

-- Spieler: XP von Level L auf L + 1 und Grundleben
function Balance.xpForLevel(level: number): number
	return math.floor(P.xp_level_basis * level ^ P.xp_level_exp)
end

function Balance.life(level: number): number
	return P.leben_basis + (level - 1) * P.leben_pro_level
end

-- Waffen-Grundschaden bei dieser Item-Power (12 bei IP 10, ×1,155 je 10 IP)
function Balance.weaponDamage(ip: number): number
	return P.waffe_basis * P.waffe_wachstum ^ (math.max(10, ip) / 10 - 1)
end

-- Faktor auf allen Spieler-Schaden: Waffen-Grundschaden relativ zu IP 10
function Balance.weaponFactor(ip: number): number
	return Balance.weaponDamage(ip) / P.waffe_basis
end

-- Verschiebung der Seltenheit: 1 + Tiefe / loot_tiefe
function Balance.rarityShift(depth: number): number
	return 1 + math.max(1, math.floor(depth)) / P.loot_tiefe
end

-- Wahrscheinlichkeiten je Seltenheit auf dieser Verschiebung (Summe 1)
function Balance.rarityOdds(shift: number): { [string]: number }
	local out: { [string]: number } = {}
	local total = 0
	for _, r in Balance.Rarity do
		local w = r.weight * shift ^ r.exp
		out[r.id] = w
		total += w
	end
	for id, w in out do
		out[id] = w / total
	end
	return out
end

return table.freeze(Balance)
