-- Gear stats → player attributes: move speed and crit chance are capped (Config.STAT_*_CAP),
-- damage and life are not. The worst case is a full nine-slot set with the best rolls (tier 1 =
-- ×2.4 on the top of RANGE: speed 4, crit 3) as an explicit affix on every piece plus implicits.
local Config = require("ReplicatedStorage.Shared.Config")
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

describe("Stats caps", function()
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

	it("caps the best possible set on speed and crit", function()
		local best = Items.TierMult[1]
		local a = refreshWith(gearSet(4 * best, 3 * best))
		-- uncapped this would be 9 × 9.6 + 12 = 98.4 speed and 9 × 7.2 + 12 = 76.8 crit
		expect(a.StatSpeed).toBe(Config.STAT_SPEED_CAP)
		expect(a.StatCrit).toBe(Config.STAT_CRIT_CAP)
	end)

	it("keeps damage and life uncapped", function()
		local a = refreshWith(gearSet(nil, nil))
		expect(a.StatLife).toBe(60) -- helmet, armor, belt
		expect(a.StatDamage).toBe(12) -- weapon, offhand
		expect(a.StatSpeed).toBe(12)
	end)

	it("applies the capped speed to the walk speed", function()
		refreshWith(gearSet(4 * Items.TierMult[1], nil))
		sim:run(0.5)
		local humanoid = sim.player.Character
			and sim.player.Character:FindFirstChildOfClass("Humanoid")
		expect(humanoid).never.toBeNil()
		expect(humanoid.WalkSpeed).toBeCloseTo(
			Config.WALK_SPEED * (1 + Config.STAT_SPEED_CAP / 100),
			3
		)
	end)
end)
