-- Shared/Balance against rows from LootRush_Balancing.xlsx (sheets "Enemies", "Player", "Loot")
local Balance = require("ReplicatedStorage.Shared.Balance")

local function near(a: number, b: number)
	expect(math.abs(a - b) / b).toBeLessThan(0.001)
end

describe("Balance", function()
	it("computes enemies, gold and XP per depth like the table", function()
		near(Balance.enemyHealth(1), 40)
		near(Balance.enemyHealth(20), 928.577444210371)
		near(Balance.enemyHealth(30), 4860.02164196364 * Balance.P.deep_growth ^ 10) -- deep curve
		near(Balance.enemyDamage(30), 160.499582790595)
		near(Balance.gold(30), 69.2316778006046)
		near(Balance.xp(30), 1110.12771864779)
		near(Balance.enemyHealth(20) * Balance.P.boss_hp, 37143.0977684148)
	end)

	it("computes player level, life and weapon like the table", function()
		expect(Balance.xpForLevel(1)).toBe(100)
		expect(Balance.xpForLevel(2)).toBe(303)
		expect(Balance.life(30)).toBe(448)
		near(Balance.weaponDamage(Balance.itemPower(30)), 783.535699604679)
		expect(Balance.weaponFactor(10)).toBe(1)
	end)

	it("shifts rarity like the table", function()
		near(Balance.rarityShift(30), 1.6)
		-- the table also has Unique/Legendary; the ratio of the four tiers stays the same
		local odds = Balance.rarityOdds(Balance.rarityShift(30))
		near(odds.magic / odds.normal, 0.305378292015439 / 0.517334437896856)
		near(odds.epic / odds.rare, 0.0349003762303359 / 0.131058057600537)
	end)
end)
