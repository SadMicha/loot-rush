-- Shared/Balance gegen Zeilen aus LootRush_Balancing.xlsx (Blätter „Gegner“, „Spieler“, „Loot“)
local Balance = require("ReplicatedStorage.Shared.Balance")

local function near(a: number, b: number)
	expect(math.abs(a - b) / b).toBeLessThan(0.001)
end

describe("Balance", function()
	it("rechnet Gegner, Gold und XP je Tiefe wie die Tabelle", function()
		near(Balance.enemyHealth(1), 40)
		near(Balance.enemyHealth(20), 928.577444210371) -- bis zur weichen Wand genau die Tabelle
		near(Balance.enemyHealth(30), 4860.02164196364 * Balance.P.wand_wachstum ^ 10)
		near(Balance.enemyDamage(30), 160.499582790595)
		near(Balance.gold(30), 69.2316778006046)
		near(Balance.xp(30), 1110.12771864779)
		near(Balance.enemyHealth(20) * Balance.P.boss_hp, 37143.0977684148)
	end)

	it("rechnet Spieler-Level, Leben und Waffe wie die Tabelle", function()
		expect(Balance.xpForLevel(1)).toBe(100)
		expect(Balance.xpForLevel(2)).toBe(303)
		expect(Balance.life(30)).toBe(448)
		near(Balance.weaponDamage(Balance.itemPower(30)), 783.535699604679)
		expect(Balance.weaponFactor(10)).toBe(1)
	end)

	it("verschiebt die Seltenheit wie die Tabelle", function()
		near(Balance.rarityShift(30), 1.6)
		-- Tabelle hat zusätzlich Einzigartig/Legendär; Verhältnis der vier Stufen bleibt gleich
		local odds = Balance.rarityOdds(Balance.rarityShift(30))
		near(odds.magic / odds.normal, 0.305378292015439 / 0.517334437896856)
		near(odds.epic / odds.rare, 0.0349003762303359 / 0.131058057600537)
	end)
end)
