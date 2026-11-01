local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")
local StarNet = require("ReplicatedStorage.Shared.StarNet")

describe("Progression.reconcile", function()
	it("cleans up broken saves", function()
		local data = Progression.reconcile({
			skills = {
				spark_ball = {
					level = 999,
					xp = -5,
					bloom = { trunk1 = 99, bogus = 3, left9 = 1 },
				},
				does_not_exist = { level = 3 },
			},
			stars = { m1 = true, heart = true, unknown = true, m2 = "yes" },
		})
		local sp = data.skills.spark_ball
		expect(sp.level).toBe(Skills.MaxLevel)
		expect(sp.xp).toBe(0)
		expect(sp.bloom.trunk1).toBe(Skills.BloomMax)
		expect(sp.bloom.bogus).toBeNil()
		expect(sp.bloom.left9).toBeNil()
		expect(data.skills.does_not_exist).toBeNil()
		expect(data.stars.m1).toBe(true)
		expect(data.stars.heart).toBeNil()
		expect(data.stars.unknown).toBeNil()
		expect(data.stars.m2).toBeNil()
	end)

	it("returns an empty state for nonsense", function()
		local data = Progression.reconcile("broken")
		expect(next(data.skills)).toBeNil()
		local m = Progression.reconcileMaterials({ candy = 0 / 0, shards = math.huge, dust = 2.7 })
		expect(m.candy).toBe(0)
		expect(m.shards).toBe(0)
		expect(m.dust).toBe(2)
	end)
end)

describe("Skill levels and Bloom", function()
	it("levels up with XP and caps at max level", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "spark_ball")
		expect(Progression.addSkillXp(sp, Progression.skillXpFor(1))).toBe(1)
		expect(sp.level).toBe(2)
		Progression.addSkillXp(sp, 1e9)
		expect(sp.level).toBe(Skills.MaxLevel)
		expect(sp.xp).toBe(0)
	end)

	it("grants Bloom Points only by the rules", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "chain_lightning")
		expect((Progression.canBloom(sp, "chain_lightning", "trunk1"))).toBe(false) -- no points
		sp.level = 3
		expect((Progression.canBloom(sp, "chain_lightning", "trunk2"))).toBe(false) -- previous node missing
		expect((Progression.canBloom(sp, "chain_lightning", "left2"))).toBe(false) -- previous node missing
		expect((Progression.canBloom(sp, "chain_lightning", "trunk1"))).toBe(true)
		sp.bloom.trunk1 = 1
		expect((Progression.canBloom(sp, "chain_lightning", "trunk2"))).toBe(true)
		sp.bloom.trunk2 = 1
		expect(Progression.bloomPoints(sp)).toBe(0)
		expect((Progression.canBloom(sp, "chain_lightning", "trunk2"))).toBe(false)
	end)

	it("applies level, Bloom and stars to the skill", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "chain_lightning")
		sp.level = 5
		sp.bloom = { trunk1 = 2, trunk2 = 1, right1 = 1 }
		data.stars = { w1 = true, resonance = true, storm_spirit = true }
		local base = Skills.bar[Skills.BarIndex.chain_lightning]
		local eff = Progression.effectiveSkill(base, data)
		-- 1 + 4 × 5% (level) + 3% (skill damage) + 2 × 10% (High Voltage)
		expect(eff.damage).toBeCloseTo(base.damage * 1.43, 1e-6)
		expect(eff.chains).toBe((base.chains :: number) + 1 + 2)
		expect(eff.cooldown).toBeCloseTo((base.cooldown - 0.3) * 0.9, 1e-6)
		expect(base.damage).toBe(20) -- the original stays unchanged
	end)

	it("every Bloom node works with a known stat", function()
		local known = {
			damage = true,
			radius = true,
			cooldown = true,
			chains = true,
			speed = true,
			slowTime = true,
		}
		for _, s in Progression.SpecialStats do
			known[s] = true
		end
		for id, b in Skills.Blooms do
			for _, branch in Skills.BloomBranches do
				for _, node in b[branch].nodes do
					expect(node.effect).never.toBeNil()
					expect(known[node.effect.stat]).toBe(true)
				end
			end
		end
	end)

	it("special nodes end up in the skill", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "spark_ball")
		sp.level = 20
		sp.bloom = { trunk3 = 1, left1 = 2, left2 = 5, right2 = 1 }
		local eff = Progression.effectiveSkill(Skills.bar[Skills.BarIndex.spark_ball], data)
		expect(eff.burn).toBeCloseTo(0.1, 1e-6)
		expect(eff.sparks).toBe(2)
		expect(eff.twin).toBeCloseTo(0.4, 1e-6)
		expect(eff.pierce).toBeCloseTo(0.2, 1e-6)
		expect(eff.fork).toBeNil()
	end)

	it("basic attack uses attack speed instead of skill values", function()
		local data = Progression.fresh()
		data.stars = { f1 = true, w1 = true }
		local eff = Progression.effectiveSkill(Skills.basic, data)
		expect(eff.damage).toBe(Skills.basic.damage)
		expect(eff.cooldown).toBeCloseTo(Skills.basic.cooldown / 1.03, 1e-6)
	end)
end)

describe("Star Net", function()
	it("only allocates connected stars with enough points", function()
		local data = Progression.fresh()
		expect((Progression.canAllocate(data, "m1", 1))).toBe(false) -- level 1 = 0 points
		expect((Progression.canAllocate(data, "m1", 2))).toBe(true)
		expect((Progression.canAllocate(data, "m2", 5))).toBe(false) -- not connected
		expect((Progression.canAllocate(data, "heart", 5))).toBe(false)
		data.stars.m1 = true
		data.stars.m2 = true
		expect(Progression.starPoints(data, 4)).toBe(1)
		expect((Progression.canAllocate(data, "iron_skin", 4))).toBe(false) -- big star costs 2
		expect((Progression.canAllocate(data, "iron_skin", 5))).toBe(true)
		expect((Progression.canRemove(data, "m1"))).toBe(false) -- m2 hangs on it
		expect((Progression.canRemove(data, "m2"))).toBe(true)
	end)

	it("protection stars give armor, block, shards and shield", function()
		local data = Progression.fresh()
		data.stars =
			{ iron_skin = true, shield_wall = true, crystal_blade = true, arcane_shield = true }
		local m = Progression.starMods(data)
		expect(m.armor).toBe(20)
		expect(m.block).toBe(25)
		expect(m.critShard).toBe(30)
		expect(m.arcaneShield).toBe(5)
		for _, s in StarNet.Stars do
			for _, line in s.stats do
				expect(string.find(line, "(coming)", 1, true)).toBeNil()
			end
		end
	end)

	it("has valid effect keys", function()
		for _, s in StarNet.Stars do
			for key in s.mods or {} do
				local id, stat = string.match(key, "^([%w_]+)%.(%w+)$")
				if id then
					expect(Skills.BarIndex[id]).never.toBeNil()
					expect(stat).toBeA("string")
				else
					expect(Progression.StarStats[key]).never.toBeNil()
				end
			end
		end
	end)
end)
