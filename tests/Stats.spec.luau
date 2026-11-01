-- Gear stats → player attributes (no caps) and the overcrit tiers (Shared/Crit). The worst case is
-- a full nine-slot set with the best rolls (tier 1 = ×2.4 on the top of RANGE: speed 4, crit 3) as
-- an explicit affix on every piece plus implicits.
local Config = require("ReplicatedStorage.Shared.Config")
local Crit = require("ReplicatedStorage.Shared.Crit")
local Items = require("ReplicatedStorage.Shared.Items")

local DATA = "ServerScriptService.Server.Systems.Data"
local STATS = "ServerScriptService.Server.Systems.Stats"

local IMPLICIT = {
	helmet = "life",
	armor = "life",
	weapon = "damage",
	amulet = "crit",
	ring = "speed",
	boots = "speed",
	gloves = "crit",
	belt = "life",
	offhand = "damage",
}

-- speed/crit: value of the explicit speed and crit affix on every piece (nil = none)
local function gearSet(speed: number?, crit: number?)
	local set = {}
	for _, slot in Items.Slots do
		local affixes = {
			{
				stat = IMPLICIT[slot],
				value = if IMPLICIT[slot] == "life" then 20 else 6,
				implicit = true,
			},
		}
		if speed then
			table.insert(affixes, { stat = "speed", value = speed, tier = 1 })
		end
		if crit then
			table.insert(affixes, { stat = "crit", value = crit, tier = 1 })
		end
		set[slot] = { slot = slot, ilvl = 10, rarity = "epic", affixes = affixes }
	end
	return set
end

local function refreshWith(set)
	local out = {}
	sim:runAs("server", function(require)
		require(DATA).get(sim.player).equipped = set
		require(STATS).refresh(sim.player, false)
		for _, attr in { "StatSpeed", "StatCrit", "StatDamage", "StatLife" } do
			out[attr] = sim.player:GetAttribute(attr)
		end
	end)
	return out
end

local function tiers(chance: number, n: number, seed: number): { [number]: number }
	local rng = Random.new(seed)
	local roll = function()
		return rng:NextNumber()
	end
	local count = {}
	for _ = 1, n do
		local t = Crit.rollTier(chance, roll)
		count[t] = (count[t] or 0) + 1
	end
	return count
end

describe("Stats (uncapped)", function()
	it("boots", function()
		sim:boot({ seconds = 3 })
		expect(sim.player:GetAttribute("StatSpeed")).never.toBeNil()
	end)

	it("leaves a normal set untouched", function()
		local a = refreshWith(gearSet(2, 1.5))
		-- ring + boots implicit 6 each, plus 9 × 2
		expect(a.StatSpeed).toBe(30)
		-- amulet + gloves implicit 6 each, plus 9 × 1.5
		expect(a.StatCrit).toBeCloseTo(25.5, 5)
	end)

	it("passes the best possible set through uncapped", function()
		local best = Items.TierMult[1]
		local a = refreshWith(gearSet(4 * best, 3 * best))
		expect(a.StatSpeed).toBeCloseTo(9 * 4 * best + 12, 5)
		expect(a.StatCrit).toBeCloseTo(9 * 3 * best + 12, 5)
	end)

	it("keeps damage and life uncapped", function()
		local a = refreshWith(gearSet(nil, nil))
		expect(a.StatLife).toBe(60) -- helmet, armor, belt
		expect(a.StatDamage).toBe(12) -- weapon, offhand
		expect(a.StatSpeed).toBe(12)
	end)

	it("applies the uncapped speed to the walk speed", function()
		local a = refreshWith(gearSet(4 * Items.TierMult[1], nil))
		sim:run(0.5)
		local humanoid = sim.player.Character
			and sim.player.Character:FindFirstChildOfClass("Humanoid")
		expect(humanoid).never.toBeNil()
		expect(humanoid.WalkSpeed).toBeCloseTo(Config.WALK_SPEED * (1 + a.StatSpeed / 100), 3)
	end)
end)

describe("Crit tiers", function()
	it("rolls no crit at 0% or less and never on NaN", function()
		expect(tiers(0, 1000, 1)[0]).toBe(1000)
		expect(tiers(-0.5, 1000, 1)[0]).toBe(1000)
		expect(tiers(0 / 0, 100, 1)[0]).toBe(100)
	end)

	it("crits exactly at the chance below 100%", function()
		local c = tiers(0.99, 20000, 7)
		expect(c[2]).toBeNil()
		expect(c[1] / 20000).toBeCloseTo(0.99, 1)
	end)

	it("always crits once at 100%", function()
		local c = tiers(1, 5000, 3)
		expect(c[1]).toBe(5000)
		expect(c[0]).toBeNil()
		expect(c[2]).toBeNil()
	end)

	it("130% = always tier 1 plus 30% tier 2", function()
		local c = tiers(1.3, 20000, 11)
		expect(c[0]).toBeNil()
		expect(c[3]).toBeNil()
		expect(c[2] / 20000).toBeGreaterThan(0.28)
		expect(c[2] / 20000).toBeLessThan(0.32)
	end)

	it("201% = guaranteed tier 2 plus 1% tier 3", function()
		local c = tiers(2.01, 20000, 5)
		expect(c[1]).toBeNil()
		expect(c[2] + (c[3] or 0)).toBe(20000)
		expect((c[3] or 0) / 20000).toBeLessThan(0.02)
		expect((c[3] or 0) / 20000).toBeGreaterThan(0.003)
	end)

	it("300% = always tier 3", function()
		local c = tiers(3, 2000, 2)
		expect(c[3]).toBe(2000)
	end)

	it("damage multiplies per tier", function()
		expect(Crit.damage(100, 0, 2)).toBe(100)
		expect(Crit.damage(100, 1, 2)).toBe(200)
		expect(Crit.damage(100, 2, 2.5)).toBeCloseTo(625, 5)
		expect(Crit.damage(100, 3, 2)).toBe(800)
	end)

	it("expected factor matches the average of the rolls", function()
		expect(Crit.expectedMult(0, 2)).toBe(1)
		expect(Crit.expectedMult(0.5, 2)).toBeCloseTo(1.5, 5)
		expect(Crit.expectedMult(1.3, 2)).toBeCloseTo(2 * (0.7 + 0.3 * 2), 5)
		expect(Crit.expectedMult(2.5, 2)).toBeCloseTo(6, 5)
	end)

	it("a hit at 250% crit chance deals critMult^2 or ^3 half of the time each", function()
		local out = {}
		sim:runAs("server", function(require)
			local Combat = require("ServerScriptService.Server.Systems.Combat")
			local Enemies = require("ServerScriptService.Server.Systems.Enemies")
			local player = sim.player
			local root = player.Character.HumanoidRootPart.Position
			local enemy = Enemies.spawn("slime", root + Vector3.new(40, 0, 0), 1)
			local function hit(): number
				enemy:SetAttribute("Health", 1e6)
				Combat.damageEnemy(enemy, 1000, player, nil, false)
				return 1e6 - (enemy:GetAttribute("Health") :: number)
			end
			player:SetAttribute("StatWeapon", 1)
			player:SetAttribute("StatDamage", 0)
			player:SetAttribute("StatLowLife", 0)
			player:SetAttribute("StatCritDamage", 0)
			player:SetAttribute("Level", 1)
			player:SetAttribute("StatCrit", -Config.CRIT_CHANCE * 100)
			out.base = hit()
			player:SetAttribute("StatCrit", 240) -- 10% + 240% = 250%
			out.tier2, out.tier3, out.other = 0, 0, 0
			for _ = 1, 400 do
				local d = hit()
				if d == out.base * Config.CRIT_MULT ^ 2 then
					out.tier2 += 1
				elseif d == out.base * Config.CRIT_MULT ^ 3 then
					out.tier3 += 1
				else
					out.other += 1
				end
			end
			player:SetAttribute("StatCrit", 0)
			enemy:Destroy()
		end)
		expect(out.base).toBeGreaterThan(0)
		expect(out.other).toBe(0)
		expect(out.tier2 / 400).toBeGreaterThan(0.35)
		expect(out.tier2 / 400).toBeLessThan(0.65)
	end)
end)
