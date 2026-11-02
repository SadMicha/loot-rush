-- Village: rules against the spreadsheet (sheet "Dorf") and upgrades/production in the sandbox.
local Village = require("ReplicatedStorage.Shared.Village")
local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Village rules", function()
	it("matches the spreadsheet costs and production", function()
		local bakery = Village.ById.bakery
		expect(Village.cost(bakery, 0)).toBe(100)
		expect(Village.cost(bakery, 1)).toBe(115)
		expect(Village.cost(bakery, 3)).toBe(152) -- 152.09
		expect(Village.output(bakery, 1)).toBeCloseTo(0.1)
		expect(Village.output(bakery, 9)).toBeCloseTo(0.9)
		expect(Village.output(bakery, 10)).toBeCloseTo(2) -- milestone 10: ×2
		expect(Village.output(bakery, 25)).toBeCloseTo(10) -- ×4
		expect(Village.output(bakery, 0)).toBe(0)
	end)

	it("caps offline time and halves it", function()
		expect(Village.offlineSeconds(0, 1000, false)).toBe(0) -- never seen
		expect(Village.offlineSeconds(1000, 1600, false)).toBe(300)
		local day = 24 * 3600
		expect(Village.offlineSeconds(1, 1 + day, false)).toBe(8 * 3600 * 0.5)
		expect(Village.offlineSeconds(1, 1 + day, true)).toBe(16 * 3600 * 0.5)
	end)

	it("pays whole units and keeps the rest", function()
		local d = Village.fresh()
		d.levels.bakery = 1 -- 0.1 gold / s
		local pay = Village.produce(d, 25)
		expect(pay.gold).toBe(2)
		expect(d.carry.gold).toBeCloseTo(0.5)
		pay = Village.produce(d, 5)
		expect(pay.gold).toBe(1)
	end)

	it("repairs broken saves", function()
		local d = Village.reconcile({
			levels = { bakery = 0 / 0, crystal_mine = 3.7, bogus = 5, observatory = 1e9 },
			carry = { gold = 2, shards = 0.4 },
			seen = -5,
		})
		expect(d.levels.bakery).toBeNil()
		expect(d.levels.crystal_mine).toBe(3)
		expect(d.levels.bogus).toBeNil()
		expect(d.levels.observatory).toBe(Village.MAX_LEVEL)
		expect(d.carry.gold).toBeNil()
		expect(d.carry.shards).toBeCloseTo(0.4)
		expect(d.seen).toBe(0)
		expect(Profile.fresh().village.seen).toBe(0)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function upgrade(id)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Village:FireServer("upgrade", id)
	end)
	sim:run(0.5)
end

describe("Village in game", function()
	it("only upgrades with enough gold and ignores bad requests", function()
		sim:boot({ seconds = 2 })
		upgrade("bakery")
		local level = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).village.levels.bakery
		end)
		expect(level).toBeNil()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Inventory").addGold(player, 250)
		end)
		upgrade("bakery")
		upgrade("does_not_exist")
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Village:FireServer("upgrade", { "bakery" })
			Net.Village:FireServer(42)
		end)
		sim:run(0.5)
		local lvl, gold = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			return p.village.levels.bakery, p.gold
		end)
		expect(lvl).toBe(1)
		expect(gold).toBe(150)
	end)

	it("produces gold while online", function()
		local before = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).gold
		end)
		sim:run(30)
		local after = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).gold
		end)
		expect(after).toBeGreaterThan(before)
	end)
end)
