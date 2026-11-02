-- Onboarding quests: rules (pure) and the chain in the sandbox (rewards, unlocks, Net.Quest).
local Quests = require("ReplicatedStorage.Shared.Quests")
local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Quest rules", function()
	it("has unique ids, positive targets and only known unlocks", function()
		local seen = {}
		for _, q in Quests.Chain do
			expect(seen[q.id]).toBeNil()
			seen[q.id] = true
			expect(q.target).toBeGreaterThan(0)
			expect(q.gold).toBeGreaterThan(0)
			if q.unlocks then
				expect(Quests.Unlocks[q.unlocks]).never.toBeNil()
			end
		end
		for id in Quests.Unlocks do
			expect(Quests.Names[id]).never.toBeNil()
		end
	end)

	it("counts only the active goal and finishes quests in order", function()
		local d = Quests.fresh()
		expect(#Quests.advance(d, "kill", 5, 1, 0)).toBe(0) -- active quest is "rift"
		expect(d.count).toBe(0)
		local done = Quests.advance(d, "rift", 1, 1, 0)
		expect(#done).toBe(1)
		expect(done[1].id).toBe("enter_rift")
		expect(d.step).toBe(2)
		Quests.advance(d, "kill", 4, 1, 0)
		expect(d.count).toBe(4)
		expect(#Quests.advance(d, "kill", 6, 1, 0)).toBe(1)
		expect(d.count).toBe(0)
	end)

	it("skips state goals that are already reached", function()
		local d = Quests.fresh()
		d.step = 5 -- "Clear depth 3", then "Reach level 5"
		local done = Quests.advance(d, nil, 0, 7, 4)
		expect(#done).toBe(2)
		expect(Quests.active(d).id).toBe("first_star")
		expect(d.unlocks.star_net).toBe(true)
	end)

	it("unlocks by level or depth and never locks again", function()
		local d = Quests.fresh()
		expect(Quests.isOpen(d, "inventory", 1, 0)).toBe(true)
		expect(Quests.isOpen(d, "forge", 1, 4)).toBe(false)
		local new = Quests.refreshUnlocks(d, 5, 8)
		expect(table.concat(new, ",")).toBe("forge,pets,star_net")
		expect(Quests.isOpen(d, "forge", 1, 0)).toBe(true) -- after a Rebirth
	end)

	it("repairs broken saves", function()
		local d =
			Quests.reconcile({ step = 0 / 0, count = -3, unlocks = { forge = true, bogus = true } })
		expect(d.step).toBe(1)
		expect(d.count).toBe(0)
		expect(d.unlocks.forge).toBe(true)
		expect(d.unlocks.bogus).toBeNil()
		expect(Quests.reconcile({ step = 999 }).step).toBe(#Quests.Chain + 1)
		expect(Profile.fresh().quests.step).toBe(1)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function lastQuest()
	for i = #sim.netLog, 1, -1 do
		local e = sim.netLog[i]
		if e.name == "Quest" and e.dir == "S→C" then
			return e.args[1]
		end
	end
	return nil
end

describe("Quests in game", function()
	it("sends the first quest on join", function()
		sim:boot({ seconds = 3 })
		local q = lastQuest()
		expect(q).never.toBeNil()
		expect(q.step).toBe(1)
		expect(q.text).toBe("Enter the Rift")
	end)

	it("pays gold for a finished quest and moves on", function()
		local before = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).gold
		end)
		server(function(req, player)
			req("ServerScriptService.Server.Util.Actions").fire(player, "rift")
		end)
		sim:run(0.5)
		local after, step = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			return p.gold, p.quests.step
		end)
		expect(after - before).toBe(Quests.Chain[1].gold)
		expect(step).toBe(2)
		local q = lastQuest()
		expect(q.step).toBe(2)
		expect(q.done[1]).toBe("Enter the Rift")
	end)

	it("unlocks windows when the level rises", function()
		server(function(_, player)
			player:SetAttribute("Level", 6)
		end)
		sim:run(0.5)
		local unlocked = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).quests.unlocks.star_net
		end)
		expect(unlocked).toBe(true)
		local q = lastQuest()
		expect(table.find(q.unlocks, "star_net")).never.toBeNil()
	end)
end)
