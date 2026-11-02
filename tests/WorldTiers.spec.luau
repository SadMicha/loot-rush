-- World Tiers (replace Rebirth): rules, save field, enemies, loot and the server flow.
local Profile = require("ReplicatedStorage.Shared.Profile")
local WorldTiers = require("ReplicatedStorage.Shared.WorldTiers")

describe("World Tier rules", function()
	it("gets tougher and more rewarding with every tier", function()
		for i = 2, WorldTiers.MAX do
			local a, b = WorldTiers.List[i - 1], WorldTiers.List[i]
			expect(b.health).toBeGreaterThan(a.health)
			expect(b.damage).toBeGreaterThan(a.damage)
			expect(b.reward).toBeGreaterThan(a.reward)
			expect(b.ilvl).toBeGreaterThan(a.ilvl)
		end
		expect(WorldTiers.get(99).id).toBe(WorldTiers.MAX)
		expect(WorldTiers.get(0 / 0).id).toBe(1)
	end)

	it("unlocks the next tier only from the highest tier at depth 20", function()
		local d = WorldTiers.fresh()
		expect(WorldTiers.unlockAfter(d, 1, 19)).toBeNil()
		expect(WorldTiers.unlockAfter(d, 1, 20)).toBe(2)
		expect(WorldTiers.unlockAfter(d, 1, 25)).toBeNil() -- tier 1 is no longer the highest
		expect(d.unlocked).toBe(2)
	end)

	it("cleans the save and drops the old rebirth field", function()
		local data = Profile.reconcile({ rebirths = 3, tier = { unlocked = 9, selected = 3 } })
		expect(data.tier.unlocked).toBe(WorldTiers.MAX)
		expect(data.tier.selected).toBe(3)
		expect((data :: any).rebirths).toBeNil()
		expect(Profile.reconcile({ tier = { unlocked = 2, selected = 4 } }).tier.selected).toBe(2)
		expect(Profile.fresh().tier.unlocked).toBe(1)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function rift(...)
	local args = table.pack(...)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer(table.unpack(args, 1, args.n))
	end)
	sim:run(1.2)
end

describe("World Tiers in game", function()
	it("scales enemies and loot with the tier", function()
		sim:boot({ seconds = 2 })
		local hp1, hp2, ilvl1, ilvl2 = server(function(req)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Loot = req("ServerScriptService.Server.Systems.Loot")
			local kind = Enemies.kindNames()[1]
			return Enemies.stats(kind, 10, 1).health,
				Enemies.stats(kind, 10, 2).health,
				Loot.forDepth(10, nil, false, 1).ilvl,
				Loot.forDepth(10, nil, false, 2).ilvl
		end)
		expect(math.abs(hp2 - hp1 * WorldTiers.List[2].health)).toBeLessThan(hp1 * 0.02)
		expect(ilvl2).toBe(ilvl1 + WorldTiers.List[2].ilvl)
	end)

	it("only selects unlocked tiers", function()
		rift("tier", 2)
		expect(server(function(_, player)
			return player:GetAttribute("WorldTier")
		end)).toBe(1)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Data").get(player).tier.unlocked = 2
		end)
		rift("tier", 2)
		rift("tier", 2.5)
		expect(server(function(_, player)
			return player:GetAttribute("WorldTier")
		end)).toBe(2)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
