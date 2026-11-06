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

	it("take no Forge actions and only drop from depth 10", function()
		local u = Items.makeUnique(Items.Uniques[1], 10, Random.new(1))
		local ok, why = Forge.check("seal", u, 2, { candy = 99, shards = 99, dust = 99 })
		expect(ok).toBe(false)
		expect(why).toBe("Uniques only take Fuse and Attune")
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
		expect(#name > #"Slime").toBe(true) -- modifier names in front (Shared/EliteMods)
	end)

	it("salvages loot on pickup up to the chosen rarity", function()
		sim:runAs("client", function(req)
			-- keep upgrades off: this hero's empty slots would make the rolled item an upgrade
			req("ReplicatedStorage.Shared.Net").AutoSalvage:FireServer("magic", false)
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

describe("Elite modifiers", function()
	local EliteMods = require("ReplicatedStorage.Shared.EliteMods")

	it("roll one modifier on Normal and one more per World Tier, never twice", function()
		expect(EliteMods.count(1)).toBe(1)
		expect(EliteMods.count(3)).toBe(3)
		expect(EliteMods.count(99)).toBe(#EliteMods.List)
		local rng = Random.new(7)
		for tier = 1, 4 do
			local ids = EliteMods.roll(rng, EliteMods.count(tier))
			expect(#ids).toBe(tier)
			local seen = {}
			for _, id in ids do
				expect(seen[id]).toBeNil()
				expect(EliteMods.ById[id]).never.toBeNil()
				seen[id] = true
			end
		end
		expect(EliteMods.title({ "fast", "shielded" }, "Slime")).toBe("Fast Shielded Slime")
	end)

	local function spawnElite(req, player, mods)
		local Enemies = req("ServerScriptService.Server.Systems.Enemies")
		local root = player.Character.HumanoidRootPart
		local model = Enemies.spawn(
			"slime",
			root.Position + Vector3.new(0, 0, -14),
			1,
			{ center = root.Position, run = 66, elite = true, mods = mods }
		)
		model:SetAttribute("SlowUntil", os.clock() + 60)
		model:SetAttribute("SlowFactor", 0)
		return model
	end

	it("names the elite after its modifiers and shields it", function()
		local name, shield, max, hpAfter, shieldAfter = server(function(req, player)
			local m = spawnElite(req, player, { "shielded" })
			local s = m:GetAttribute("Shield")
			local hp = m:GetAttribute("Health")
			req("ServerScriptService.Server.Systems.Combat").damageEnemy(m, 1, player, nil, true)
			return m.Name, s, hp, m:GetAttribute("Health"), m:GetAttribute("Shield")
		end)
		expect(string.sub(name, 1, 9)).toBe("Shielded ")
		expect(shield).toBe(math.floor(max * EliteMods.SHIELD))
		expect(hpAfter).toBe(max) -- the shield took the hit
		expect(shieldAfter < shield).toBe(true)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(66)
		end)
	end)

	it("leaves a telegraphed blast when an exploding elite dies", function()
		local before = server(function(_, player)
			return player.Character.Humanoid.Health
		end)
		server(function(req, player)
			local m = spawnElite(req, player, { "exploding" })
			m:PivotTo(player.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -3))
			req("ServerScriptService.Server.Systems.Combat").slay(player, m)
		end)
		sim:run(EliteMods.BLAST_DELAY + 0.3)
		local after = server(function(_, player)
			return player.Character.Humanoid.Health
		end)
		expect(after < before).toBe(true)
		server(function(_, player)
			local h = player.Character.Humanoid
			h.Health = h.MaxHealth
		end)
	end)

	it("slows players inside a frozen aura", function()
		local base = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed
		end)
		server(function(req, player)
			local m = spawnElite(req, player, { "frozen_aura" })
			m:PivotTo(player.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -4))
		end)
		sim:run(0.6)
		local slowed, chilled = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed, player:GetAttribute("Chilled")
		end)
		expect(slowed < base).toBe(true)
		expect(chilled).toBe(true)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(66)
		end)
		sim:run(1.5)
		local back = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed
		end)
		expect(back).toBe(base)
	end)
end)
