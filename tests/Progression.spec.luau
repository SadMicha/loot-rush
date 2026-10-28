local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")
local StarNet = require("ReplicatedStorage.Shared.StarNet")

describe("Progression.reconcile", function()
	it("säubert kaputte Spielstände", function()
		local data = Progression.reconcile({
			skills = {
				funkenball = {
					level = 999,
					xp = -5,
					bloom = { trunk1 = 99, quatsch = 3, left9 = 1 },
				},
				gibtsnicht = { level = 3 },
			},
			stars = { k1 = true, herz = true, unbekannt = true, k2 = "ja" },
		})
		local sp = data.skills.funkenball
		expect(sp.level).toBe(Skills.MaxLevel)
		expect(sp.xp).toBe(0)
		expect(sp.bloom.trunk1).toBe(Skills.BloomMax)
		expect(sp.bloom.quatsch).toBeNil()
		expect(sp.bloom.left9).toBeNil()
		expect(data.skills.gibtsnicht).toBeNil()
		expect(data.stars.k1).toBe(true)
		expect(data.stars.herz).toBeNil()
		expect(data.stars.unbekannt).toBeNil()
		expect(data.stars.k2).toBeNil()
	end)

	it("liefert für Unsinn einen leeren Stand", function()
		local data = Progression.reconcile("kaputt")
		expect(next(data.skills)).toBeNil()
		local m = Progression.reconcileMaterials({ candy = 0 / 0, shards = math.huge, dust = 2.7 })
		expect(m.candy).toBe(0)
		expect(m.shards).toBe(0)
		expect(m.dust).toBe(2)
	end)
end)

describe("Skill-Stufen und Blüte", function()
	it("steigt mit XP auf und deckelt bei der Höchststufe", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "funkenball")
		expect(Progression.addSkillXp(sp, Progression.skillXpFor(1))).toBe(1)
		expect(sp.level).toBe(2)
		Progression.addSkillXp(sp, 1e9)
		expect(sp.level).toBe(Skills.MaxLevel)
		expect(sp.xp).toBe(0)
	end)

	it("vergibt Blüten-Punkte nur nach den Regeln", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "kettenblitz")
		expect((Progression.canBloom(sp, "kettenblitz", "trunk1"))).toBe(false) -- keine Punkte
		sp.level = 3
		expect((Progression.canBloom(sp, "kettenblitz", "trunk2"))).toBe(false) -- Knoten davor fehlt
		expect((Progression.canBloom(sp, "kettenblitz", "left2"))).toBe(false) -- Knoten davor fehlt
		expect((Progression.canBloom(sp, "kettenblitz", "trunk1"))).toBe(true)
		sp.bloom.trunk1 = 1
		expect((Progression.canBloom(sp, "kettenblitz", "trunk2"))).toBe(true)
		sp.bloom.trunk2 = 1
		expect(Progression.bloomPoints(sp)).toBe(0)
		expect((Progression.canBloom(sp, "kettenblitz", "trunk2"))).toBe(false)
	end)

	it("verrechnet Stufe, Blüte und Sterne in den Skill", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "kettenblitz")
		sp.level = 5
		sp.bloom = { trunk1 = 2, trunk2 = 1, right1 = 1 }
		data.stars = { w1 = true, resonanz = true, sturmgeist = true }
		local base = Skills.bar[Skills.BarIndex.kettenblitz]
		local eff = Progression.effectiveSkill(base, data)
		-- 1 + 4 × 5 % (Stufe) + 3 % (Skill-Schaden) + 2 × 10 % (Hochspannung)
		expect(eff.damage).toBeCloseTo(base.damage * 1.43, 1e-6)
		expect(eff.chains).toBe((base.chains :: number) + 1 + 2)
		expect(eff.cooldown).toBeCloseTo((base.cooldown - 0.3) * 0.9, 1e-6)
		expect(base.damage).toBe(20) -- Original bleibt unverändert
	end)

	it("jeder Blüten-Knoten wirkt mit bekanntem Wert", function()
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

	it("Sonderknoten landen im Skill", function()
		local data = Progression.fresh()
		local sp = Progression.skillMut(data, "funkenball")
		sp.level = 20
		sp.bloom = { trunk3 = 1, left1 = 2, left2 = 5, right2 = 1 }
		local eff = Progression.effectiveSkill(Skills.bar[Skills.BarIndex.funkenball], data)
		expect(eff.burn).toBeCloseTo(0.1, 1e-6)
		expect(eff.sparks).toBe(2)
		expect(eff.twin).toBeCloseTo(0.4, 1e-6)
		expect(eff.pierce).toBeCloseTo(0.2, 1e-6)
		expect(eff.fork).toBeNil()
	end)

	it("Grundangriff nutzt Angriffstempo statt Skill-Werte", function()
		local data = Progression.fresh()
		data.stars = { g1 = true, w1 = true }
		local eff = Progression.effectiveSkill(Skills.basic, data)
		expect(eff.damage).toBe(Skills.basic.damage)
		expect(eff.cooldown).toBeCloseTo(Skills.basic.cooldown / 1.03, 1e-6)
	end)
end)

describe("Sternennetz", function()
	it("weist nur verbundene Sterne mit genug Punkten zu", function()
		local data = Progression.fresh()
		expect((Progression.canAllocate(data, "k1", 1))).toBe(false) -- Level 1 = 0 Punkte
		expect((Progression.canAllocate(data, "k1", 2))).toBe(true)
		expect((Progression.canAllocate(data, "k2", 5))).toBe(false) -- nicht verbunden
		expect((Progression.canAllocate(data, "herz", 5))).toBe(false)
		data.stars.k1 = true
		data.stars.k2 = true
		expect(Progression.starPoints(data, 4)).toBe(1)
		expect((Progression.canAllocate(data, "eisenhaut", 4))).toBe(false) -- großer Stern kostet 2
		expect((Progression.canAllocate(data, "eisenhaut", 5))).toBe(true)
		expect((Progression.canRemove(data, "k1"))).toBe(false) -- k2 hängt dran
		expect((Progression.canRemove(data, "k2"))).toBe(true)
	end)

	it("Schutz-Sterne geben Rüstung, Block, Splitter und Schild", function()
		local data = Progression.fresh()
		data.stars =
			{ eisenhaut = true, schildwall = true, kristallklinge = true, arkanerschild = true }
		local m = Progression.starMods(data)
		expect(m.armor).toBe(20)
		expect(m.block).toBe(25)
		expect(m.critShard).toBe(30)
		expect(m.arcaneShield).toBe(5)
		for _, s in StarNet.Stars do
			for _, line in s.stats do
				expect(string.find(line, "(folgt)", 1, true)).toBeNil()
			end
		end
	end)

	it("hat gültige Wirkungs-Schlüssel", function()
		for _, s in StarNet.Stars do
			for key in s.mods or {} do
				local id, stat = string.match(key, "^(%w+)%.(%w+)$")
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
