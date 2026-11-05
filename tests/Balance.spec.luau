-- Shared/Balance against rows from LootRush_Balancing.xlsx (sheets "Enemies", "Player", "Loot")
local Balance = require("ReplicatedStorage.Shared.Balance")

local function near(a: number, b: number)
	expect(math.abs(a - b) / b).toBeLessThan(0.001)
end

describe("Balance", function()
	it("computes enemies, gold and XP per depth from Balance.P", function()
		local P = Balance.P
		near(Balance.enemyHealth(1), P.hp_base)
		near(Balance.enemyHealth(20), P.hp_base * P.hp_growth ^ 19)
		near(Balance.enemyHealth(30), P.hp_base * P.hp_growth ^ 29 * P.deep_growth ^ 10) -- deep curve
		near(Balance.enemyDamage(1), P.dmg_base)
		near(Balance.enemyDamage(30), P.dmg_base * P.dmg_growth ^ 29)
		near(Balance.gold(30), 69.2316778006046)
		near(Balance.xp(30), 1110.12771864779)
		near(Balance.enemyHealth(20) * P.boss_hp, P.hp_base * P.hp_growth ^ 19 * P.boss_hp)
	end)

	it("computes player level, life and weapon like the table", function()
		expect(Balance.xpForLevel(1)).toBe(100)
		expect(Balance.xpForLevel(2)).toBe(math.floor(100 * 2 ^ Balance.P.xp_level_exp))
		expect(Balance.life(30)).toBe(448)
		near(Balance.weaponDamage(Balance.itemPower(30)), 783.535699604679)
		expect(Balance.weaponFactor(10)).toBe(1)
	end)

	it("shifts rarity like the table", function()
		near(Balance.rarityShift(30), 1.6)
		-- the table also has Unique/Legendary; the ratio of the four tiers stays the same
		local odds = Balance.rarityOdds(Balance.rarityShift(30))
		near(odds.magic / odds.normal, 0.305378292015439 / 0.517334437896856)
		-- Rare/Epic grow faster than the table since the loot rebalance (docs/specs/LOOT.md P5)
		near(odds.epic / odds.rare, (2 * 1.6 ^ 2) / (9.5 * 1.6 ^ 1.3))
	end)
end)
