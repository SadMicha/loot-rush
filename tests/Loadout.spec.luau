-- Skill loadout (4 of 8 on the bar) and auto-cast: rules (pure) and the server via real remotes.
local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")

describe("Loadout rules", function()
	it("has 8 skills, each with a bloom, and a valid starting bar", function()
		expect(#Skills.list).toBe(8)
		for _, s in Skills.list do
			expect(Skills.Blooms[s.id]).never.toBeNil()
		end
		expect(#Progression.fresh().bar).toBe(Skills.SLOTS)
	end)

	it("cleans up saved bars", function()
		local data = Progression.reconcile({
			bar = { "meteor", "meteor", "bogus", 7 },
			auto = { meteor = true, nope = true, spark_ball = "yes" },
		})
		expect(data.bar[1]).toBe("meteor")
		local seen = {}
		for slot = 1, Skills.SLOTS do
			local id = data.bar[slot]
			expect(Skills.ById[id]).never.toBeNil()
			expect(seen[id]).toBeNil()
			seen[id] = true
		end
		expect(data.auto.meteor).toBe(true)
		expect(data.auto.nope).toBeNil()
		expect(data.auto.spark_ball).toBeNil()
	end)

	it("swaps skills and respects the unlock level", function()
		local data = Progression.fresh()
		expect(Progression.equip(data, 1, "meteor", 7)).toBe(false)
		expect(Progression.equip(data, 1, "meteor", 8)).toBe(true)
		expect(data.bar[1]).toBe("meteor")
		-- moving an equipped skill swaps the two slots
		expect(Progression.equip(data, 3, "meteor", 8)).toBe(true)
		expect(data.bar[3]).toBe("meteor")
		expect(data.bar[1]).toBe(Skills.DefaultBar[3])
		expect(Progression.equip(data, 5, "spark_ball", 99)).toBe(false)
		expect(Progression.equip(data, 1.5, "spark_ball", 99)).toBe(false)
	end)

	it("allows auto-cast from skill level 5 or after a Rebirth", function()
		local data = Progression.fresh()
		expect(Progression.canAuto(data, "spark_ball", 0)).toBe(false)
		expect(Progression.canAuto(data, "spark_ball", 1)).toBe(true)
		Progression.skillMut(data, "spark_ball").level = Skills.AUTO_LEVEL
		expect(Progression.canAuto(data, "spark_ball", 0)).toBe(true)
	end)

	it("adds bloom burn on top of a skill's own burn", function()
		local data = Progression.fresh()
		Progression.skillMut(data, "meteor").bloom.trunk3 = 2
		local eff = Progression.effectiveSkill(Skills.ById.meteor, data)
		expect(eff.burn).toBeCloseTo(0.3 + 0.2, 1e-6)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function client(fn)
	sim:runAs("client", function(req)
		fn(req, req("ReplicatedStorage.Shared.Net"))
	end)
	sim:run(0.5)
end

local function sent(name: string): number
	local n = 0
	for _, e in sim.netLog do
		if e.name == name and e.dir == "S→C" then
			n += 1
		end
	end
	return n
end

describe("Loadout in game", function()
	it("equips only unlocked skills", function()
		sim:boot({ seconds = 2 })
		client(function(_, Net)
			Net.Loadout:FireServer("equip", 2, "venom_arc") -- level 20 needed
			Net.Loadout:FireServer("equip", "x", "meteor")
		end)
		server(function(_, player)
			player:SetAttribute("Level", 8)
		end)
		client(function(_, Net)
			Net.Loadout:FireServer("equip", 2, "meteor")
		end)
		local bar = server(function(req, player)
			return table.concat(
				req("ServerScriptService.Server.Systems.Data").get(player).progress.bar,
				","
			)
		end)
		expect(bar).toBe("thunderstorm,meteor,chain_lightning,frost_nova")
	end)

	it("auto-casts an equipped skill at enemies in reach", function()
		client(function(_, Net)
			Net.Loadout:FireServer("auto", "thunderstorm", true) -- skill level 1: refused
		end)
		local refused = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).progress.auto.thunderstorm
		end)
		expect(refused).toBeNil()
		server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			Progression.skillMut(p.progress, "thunderstorm").level = Skills.AUTO_LEVEL
		end)
		client(function(_, Net)
			Net.Loadout:FireServer("auto", "thunderstorm", true)
		end)
		local before = sent("SkillCast")
		local hpBefore = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character.HumanoidRootPart.Position
			local e = Enemies.spawn("slime", root + Vector3.new(4, 0, 0), 40, { run = 777 })
			return e:GetAttribute("Health")
		end)
		sim:run(1)
		expect(sent("SkillCast")).toBeGreaterThan(before)
		local hpAfter = server(function(req)
			local total = 0
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				total += e:GetAttribute("Health") or 0
			end
			req("ServerScriptService.Server.Systems.Enemies").clear(777)
			return total
		end)
		expect(hpAfter).toBeLessThan(hpBefore)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
