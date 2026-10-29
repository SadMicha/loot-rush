--!strict
-- Wiedergeburt (Rebirth): freiwillig, nie erzwungen. Reine Regeln für Server (Systems/Rebirth) und UI.
--   • Möglich, sobald die beste Tiefe (über alle Gebiete) die weiche Wand erreicht hat:
--     Tiefe 20 beim ersten Mal, danach je Wiedergeburt 5 Tiefen mehr.
--   • Zurückgesetzt: Level, XP, Gold, Atlas-Fortschritt (Gebiete) und das Sternennetz
--     (Sternpunkte kommen aus dem Level). Behalten: Ausrüstung, Inventar, Material, Skill-Stufen
--     und Blüten, Tränke, Seelensterne, Haustiere.
--   • Jede Wiedergeburt gibt dauerhaft mehr Schaden, Leben, Gold und XP und schiebt die weiche
--     Wand (Shared/Balance, wand_ab) 5 Tiefen nach hinten. Dazu einmalig Seelensterne.
-- Werte sind eigene Annahmen (nicht im Balancing-Blatt), siehe docs/WIEDERGEBURT.md.

local Balance = require(script.Parent.Balance)

local Rebirth = {}

Rebirth.WALL_STEP = 5 -- Tiefen, um die jede Wiedergeburt die weiche Wand verschiebt
Rebirth.MAX = 50 -- Obergrenze (Schutz vor Unsinn im Spielstand)

-- Bonus je Wiedergeburt in Prozent (addiert sich: 3 Wiedergeburten = +75 % Schaden)
Rebirth.PerRebirth = table.freeze({
	damage = 25,
	life = 10,
	gold = 20,
	xp = 20,
} :: { [string]: number })

-- Seelensterne für die n-te Wiedergeburt
function Rebirth.reward(n: number): number
	return 25 + 25 * n
end

-- Beste Tiefe, die für die nächste Wiedergeburt nötig ist (rebirths = bisherige Anzahl)
function Rebirth.required(rebirths: number): number
	return Balance.P.wand_ab + Rebirth.WALL_STEP * rebirths
end

-- Um so viele Tiefen liegt die weiche Wand weiter hinten
function Rebirth.wallShift(rebirths: number): number
	return Rebirth.WALL_STEP * rebirths
end

-- Bonus-Prozente nach `rebirths` Wiedergeburten (Schlüssel wie Rebirth.PerRebirth)
function Rebirth.bonus(rebirths: number): { [string]: number }
	local out: { [string]: number } = {}
	for stat, pct in Rebirth.PerRebirth do
		out[stat] = pct * rebirths
	end
	return out
end

-- Höchste geschaffte Tiefe über alle Gebiete (profile.atlas)
function Rebirth.bestDepth(atlas: { [string]: number }): number
	local best = 0
	for _, depth in atlas do
		if depth > best then
			best = depth
		end
	end
	return best
end

-- Darf der Spieler wiedergeboren werden? (Grund für den gesperrten Knopf)
function Rebirth.check(rebirths: number, best: number): (boolean, string?)
	if rebirths >= Rebirth.MAX then
		return false, "Höchste Wiedergeburt erreicht"
	end
	local need = Rebirth.required(rebirths)
	if best < need then
		return false, string.format("Erst Tiefe %d schaffen", need)
	end
	return true, nil
end

return table.freeze(Rebirth)
