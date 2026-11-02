-- Elites, uniques and auto-salvage: rules (pure) and the server paths in the sandbox.
local Balance = require("ReplicatedStorage.Shared.Balance")
local Forge = require("ReplicatedStorage.Shared.Forge")
local Items = require("ReplicatedStorage.Shared.Items")
local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Uniques", function()
	it("never roll without the uniques flag", function()
		local rng = Random.new(3)
		for _ = 1, 400 do
			local item = Items.roll(20, rng, 50, { shift = 3 })
			expect(item.rarity == "unique").toBe(false)
		end
	end)

	it("roll with the flag and carry their fixed package", function()
		local rng = Random.new(5)
		local found = nil
		for _ = 1, 4000 do
			local item = Items.roll(20, rng, 50, { shift = 3, uniques = true })
			if item.rarity == "unique" then
				found = item
				break
			end
		end
		expect(found).never.toBeNil()
		local u = Items.UniqueById[found.unique]
		expect(u).never.toBeNil()
		expect(found.slot).toBe(u.slot)
		expect(found.name).toBe(u.name)
		expect(#found.affixes).toBe(1 + #u.stats)
		expect(found.charges).toBe(0)
	end)

	it("cannot be forged and only drop from depth 10", function()
		local u = Items.makeUnique(Items.Uniques[1], 10, Random.new(1))
		local ok, why = Forge.check("seal", u, 2, { candy = 99, shards = 99, dust = 99 })
		expect(ok).toBe(false)
		expect(why).toBe("Uniques cannot be forged")
		expect(Balance.rarityOdds(1.2).unique).toBeNil()
		expect(Balance.rarityOdds(1.2, true).unique).toBeGreaterThan(0)
	end)

	it("keeps the auto-salvage setting valid", function()
		expect(Profile.reconcile({ autoSalvage = "magic" }).autoSalvage).toBe("magic")
		expect(Profile.reconcile({ autoSalvage = "unique" }).autoSalvage).toBe("")
		expect(Profile.reconcile({ autoSalvage = "bogus" }).autoSalvage).toBe("")
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Elites and auto-salvage in game", function()
	it("spawns elites with the spreadsheet factors", function()
		sim:boot({ seconds = 2 })
		local hp, eliteHp, isElite, name = server(function(req)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local kind = Enemies.kindNames()[1]
			local a = Enemies.spawn(kind, Vector3.new(0, 0, -20), 5, { run = 999 })
			local b = Enemies.spawn(kind, Vector3.new(4, 0, -20), 5, { run = 999, elite = true })
			local out = table.pack(
				a:GetAttribute("MaxHealth"),
				b:GetAttribute("MaxHealth"),
				b:GetAttribute("Elite"),
				b.Name
			)
			Enemies.clear(999)
			return table.unpack(out, 1, out.n)
		end)
		expect(eliteHp).toBe(math.floor(hp * Balance.P.elite_hp))
		expect(isElite).toBe(true)
		expect(string.sub(name, 1, 6)).toBe("Elite ")
	end)

	it("salvages loot on pickup up to the chosen rarity", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").AutoSalvage:FireServer("magic")
		end)
		sim:run(0.5)
		local stored, salvaged, bag, gold, setting = server(function(req, player)
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			local before = #p.inventory
			local item = req("ReplicatedStorage.Shared.Items").roll(
				5,
				Random.new(1),
				nil,
				{ min = "normal" }
			)
			item.rarity = "magic"
			local goldBefore = p.gold
			local a, b = Inventory.add(player, item, true)
			return a, b, #p.inventory - before, p.gold - goldBefore, p.autoSalvage
		end)
		expect(setting).toBe("magic")
		expect(stored).toBe(true)
		expect(salvaged).toBe(true)
		expect(bag).toBe(0)
		expect(gold).toBeGreaterThan(0)
	end)

	it("never auto-salvages uniques and ignores bad settings", function()
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.AutoSalvage:FireServer("unique")
			Net.AutoSalvage:FireServer(42)
		end)
		sim:run(0.5)
		local setting = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).autoSalvage
		end)
		expect(setting).toBe("magic")
	end)
end)
