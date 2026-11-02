-- Skill loadout (4 of 8 on the bar) rules (pure) and the server via real remotes.
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
		})
		expect(data.bar[1]).toBe("meteor")
		local seen = {}
		for slot = 1, Skills.SLOTS do
			local id = data.bar[slot]
			expect(Skills.ById[id]).never.toBeNil()
			expect(seen[id]).toBeNil()
			seen[id] = true
		end
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

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
