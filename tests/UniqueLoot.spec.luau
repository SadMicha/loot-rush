-- Loot rebalance (docs/specs/LOOT.md): signature uniques (budget, effects, ranks, Fuse, Attune),
-- targeted boss drops with pity, the drop table, and the effect hooks on the server.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local Balance = require("ReplicatedStorage.Shared.Balance")
local Forge = require("ReplicatedStorage.Shared.Forge")
local Items = require("ReplicatedStorage.Shared.Items")
local Profile = require("ReplicatedStorage.Shared.Profile")
local UniqueEffects = require("ReplicatedStorage.Shared.UniqueEffects")

local RICH = { candy = 99, shards = 9999, dust = 9 }

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function packageScore(item): number
	local s = 0
	for _, a in item.affixes do
		if not a.implicit then
			s += a.value
		end
	end
	return s
end

describe("Signature uniques", function()
	it("every unique has an effect with readable text and a real boss source", function()
		local kinds = {}
		for _, r in Atlas.Regions do
			kinds[r.bossKind] = 0
		end
		for _, u in Items.Uniques do
			expect(UniqueEffects.ById[u.id]).never.toBeNil()
			for rank = 1, UniqueEffects.MAX_RANK do
				local text = UniqueEffects.text(u.id, rank)
				expect(#text > 10).toBe(true)
				expect(string.find(text, "{", 1, true)).toBeNil()
			end
			expect(kinds[u.source]).never.toBeNil()
			kinds[u.source] += 1
			expect(#u.stats).toBe(3)
		end
		for _, n in kinds do
			expect(n).toBe(2) -- every boss kind owns two uniques
		end
		expect(#Items.uniquesFrom("spore_mother")).toBe(2)
		expect(#Items.uniquesFrom("nobody")).toBe(0)
	end)

	it("the headline stat beats any tier-1 affix, the total stays below a perfect Epic", function()
		for _, u in Items.Uniques do
			expect(u.stats[1].mult).toBeGreaterThan(Items.TierMult[1])
			local total = 1.5
			for _, s in u.stats do
				total += s.mult
			end
			local perfectEpic = 1.5 + 4 * Items.TierMult[1]
			expect(total).toBeLessThan(perfectEpic)
			-- rank V (+20 % on the package) stays below the perfect Epic too
			expect(1.5 + (total - 1.5) * (1 + 4 * Items.RANK_STEP)).toBeLessThan(perfectEpic)
		end
	end)

	it("effect values grow with the rank and counts round down", function()
		expect(UniqueEffects.value("stormcaller", "hit", 1)).toBe(60)
		expect(UniqueEffects.value("stormcaller", "hit", 5)).toBe(100)
		expect(UniqueEffects.count("stormcaller", "targets", 1)).toBe(3)
		expect(UniqueEffects.count("stormcaller", "targets", 2)).toBe(3)
		expect(UniqueEffects.count("stormcaller", "targets", 3)).toBe(4)
		expect(UniqueEffects.value("stormcaller", "hit", 99)).toBe(100) -- clamped to rank V
		expect(UniqueEffects.value("nope", "hit", 1)).toBe(0)
		expect(UniqueEffects.text("nope")).toBe("")
	end)

	it("a rank raises the package but not the implicit", function()
		local u = Items.UniqueById.stormcaller
		local r1 = Items.makeUnique(u, 20, Random.new(4))
		local r3 = Items.makeUnique(u, 20, Random.new(4), nil, 3)
		expect(Items.rankOf(r1)).toBe(1)
		expect(r1.rank).toBeNil()
		expect(Items.rankOf(r3)).toBe(3)
		expect(r3.affixes[1].value).toBe(r1.affixes[1].value)
		expect(packageScore(r3) / packageScore(r1)).toBeCloseTo(1.1, 1)
		expect(Items.rankOf({ rank = 0 / 0 } :: any)).toBe(1)
		expect(Items.rankOf({ rank = 9 } :: any)).toBe(5)
	end)

	it("rescales a unique to another item level, keeping its rolls", function()
		local u = Items.UniqueById.glibber_crown -- headline life grows with the level
		local low = Items.makeUnique(u, 10, Random.new(2))
		local high = Items.rescaleUnique(low, 30)
		expect(high.ilvl).toBe(30)
		expect(high.id).toBe(low.id)
		expect(high.affixes[2].stat).toBe("life")
		expect(high.affixes[2].value).toBeGreaterThan(low.affixes[2].value)
		expect(high.affixes[3].value).toBe(low.affixes[3].value) -- damage % does not grow
		expect(low.ilvl).toBe(10) -- the original stays
	end)

	it("fuses a duplicate: ranks add up, the higher level and the better rolls win", function()
		local u = Items.UniqueById.ember_band
		local a = Items.makeUnique(u, 12, Random.new(1))
		a.id = "a"
		local b = Items.makeUnique(u, 20, Random.new(99), nil, 2)
		b.id = "b"
		local f = Items.fuse(a, b) :: any
		expect(f).never.toBeNil()
		expect(f.id).toBe("a")
		expect(Items.rankOf(f)).toBe(3)
		expect(f.ilvl).toBe(20)
		for i, x in f.affixes do
			-- never worse than either copy brought to the new level and rank
			expect(x.value + 0.11).toBeGreaterThan(Items.rescaleUnique(a, 20, 3).affixes[i].value)
			expect(x.value + 0.11).toBeGreaterThan(Items.rescaleUnique(b, 20, 3).affixes[i].value)
		end
		local max = Items.makeUnique(u, 12, Random.new(3), nil, 4)
		expect(Items.rankOf(Items.fuse(max, b) :: any)).toBe(5)
		expect(Items.fuse(a, a)).toBeNil()
		expect(Items.fuse(a, Items.makeUnique(Items.UniqueById.stormcaller, 12, Random.new(1)))).toBeNil()
	end)
end)

describe("Forge on uniques", function()
	local u = Items.UniqueById.cloud_steps

	it("offers only Fuse and Attune on uniques and only the four actions elsewhere", function()
		local item = Items.makeUnique(u, 10, Random.new(1))
		expect(#Forge.actionsFor(item)).toBe(2)
		expect(Forge.actionsFor(item)[1].id).toBe("fuse")
		local epic = Items.roll(10, Random.new(1), nil, { min = "epic" })
		expect(#Forge.actionsFor(epic)).toBe(#Forge.Actions)
		local ok, why = Forge.check("fuse", epic, nil, RICH, { bag = {} })
		expect(ok).toBe(false)
		expect(why).toBe("Only for uniques")
		expect(Forge.canForge(item)).toBe(true)
	end)

	it("fuses with a duplicate from the bag and names what it uses up", function()
		local item = Items.makeUnique(u, 10, Random.new(1))
		item.id = "worn"
		local dup = Items.makeUnique(u, 14, Random.new(2))
		dup.id = "dup"
		local other = Items.makeUnique(Items.UniqueById.stormcaller, 30, Random.new(2))
		local ok, why = Forge.check("fuse", item, nil, RICH, { bag = { item, other } })
		expect(ok).toBe(false)
		expect(why).toBe("Needs a duplicate in the bag")
		local r = Forge.apply("fuse", item, nil, RICH, Random.new(1), { bag = { other, dup } })
		expect(r.ok).toBe(true)
		expect(r.consumed).toBe("dup")
		expect(r.cost).toBe(Forge.ById.fuse.cost)
		expect(Items.rankOf(r.item :: any)).toBe(2)
		local poor = { candy = 0, shards = 10, dust = 0 }
		expect((Forge.check("fuse", item, nil, poor, { bag = { dup } }))).toBe(false)
		local maxed = Items.makeUnique(u, 10, Random.new(1), nil, 5)
		expect(select(2, Forge.check("fuse", maxed, nil, RICH, { bag = { dup } }))).toBe(
			"Already at rank V"
		)
	end)

	it("attunes up to the best loot level for shards", function()
		local item = Items.makeUnique(u, 10, Random.new(1))
		local target = Forge.attuneLevel(30, 1)
		expect(target).toBe(Items.levelForDepth(30) + 1) -- boss loot level on Normal
		expect(Forge.attuneLevel(30, 2)).toBe(target + 10)
		local ctx = { attune = target }
		expect(Forge.cost(Forge.ById.attune, item, nil, ctx)).toBe(Forge.attuneCost(10, target))
		expect(Forge.attuneCost(10, 31)).toBeGreaterThan(Forge.attuneCost(10, 20))
		expect(Forge.attuneCost(20, 20)).toBe(0)
		local r = Forge.apply("attune", item, nil, RICH, Random.new(1), ctx)
		expect(r.ok).toBe(true)
		expect((r.item :: any).ilvl).toBe(target)
		local done = r.item :: any
		local ok, why = Forge.check("attune", done, nil, RICH, ctx)
		expect(ok).toBe(false)
		expect(why).toBe("Already at your best loot level")
		expect((Forge.check("attune", item, nil, RICH, nil))).toBe(false) -- never above what the hero can wear (level + grace)
		expect(Forge.attuneLevel(30, 4, 10)).toBe(10 + Balance.P.equip_level_grace)
		expect(Forge.attuneLevel(5, 1, 60)).toBe(Forge.attuneLevel(5, 1))
	end)

	it("fuses the lowest-rank duplicate first so no rank is wasted", function()
		local target = Items.makeUnique(u, 10, Random.new(1), nil, 4)
		target.id = "t"
		local r3 = Items.makeUnique(u, 10, Random.new(2), nil, 3)
		r3.id = "r3"
		local r1 = Items.makeUnique(u, 10, Random.new(3))
		r1.id = "r1"
		expect((Forge.duplicateOf(target, { r3, r1 }) :: any).id).toBe("r1")
	end)
end)

describe("Drop table", function()
	it("no Normal items from depth 10, rarer drops deeper, uniques only from bosses", function()
		local LootRules = nil
		sim:boot({ seconds = 2 })
		local early, deep, boss = server(function(req)
			LootRules = req("ServerScriptService.Server.Systems.Loot")
			return LootRules.forDepth(5, "green_plains", false),
				LootRules.forDepth(12, "mushroom_swamp", false),
				LootRules.forDepth(12, "mushroom_swamp", true)
		end)
		expect(early.min).toBeNil()
		expect(deep.min).toBe("magic")
		expect(boss.bossKind).toBe("spore_mother")
		expect(boss.uniques).toBe(true)
		local o1 = Balance.rarityOdds(Balance.rarityShift(1))
		local o30 = Balance.rarityOdds(Balance.rarityShift(30))
		expect(o30.epic / o1.epic).toBeGreaterThan(2)
		expect(o30.rare / o1.rare).toBeGreaterThan(1.4)
	end)

	it("boss unique chance grows with the World Tier and with every miss (pity)", function()
		local Loot = server(function(req)
			return req("ServerScriptService.Server.Systems.Loot")
		end)
		expect(Loot.uniqueChance(1, 0)).toBeCloseTo(0.08, 5)
		expect(Loot.uniqueChance(3, 0)).toBeCloseTo(0.12, 5)
		expect(Loot.uniqueChance(1, 10)).toBeCloseTo(0.18, 5)
		expect(Loot.uniqueChance(1, 1000)).toBe(1)
		local luck = Profile.reconcileLuck(nil)
		expect(Loot.rollBossUnique(luck, "spore_mother", 1, true, 0.5)).toBe(false)
		expect(luck.pity.spore_mother).toBe(1)
		expect(Loot.rollBossUnique(luck, "spore_mother", 1, true, 0.085)).toBe(true) -- 8 % + 1 %
		expect(luck.pity.spore_mother).toBe(0)
		expect(Loot.rollBossUnique(luck, "spore_mother", 1, false, 0)).toBe(false)
		-- first kill of a boss kind on Veteran: guaranteed, once
		expect(Loot.rollBossUnique(luck, "cloud_queen", 2, true, 0.99)).toBe(true)
		expect(luck.firsts.cloud_queen).toBe(true)
		expect(Loot.rollBossUnique(luck, "cloud_queen", 2, true, 0.99)).toBe(false)
		-- a hero always gets one within (1 − base) / pity + 1 kills
		local l2 = Profile.reconcileLuck(nil)
		local kills = 0
		repeat
			kills += 1
		until Loot.rollBossUnique(l2, "the_rift", 1, true, 0.999) or kills > 200
		expect(kills).toBeLessThan(100)
		expect(Loot.epicDue(5)).toBe(true)
		expect(Loot.epicDue(6)).toBe(false)
		expect(Loot.epicDue(0)).toBe(false)
	end)

	it("cleans the saved luck", function()
		local l = Profile.reconcileLuck({
			pity = { spore_mother = 3.7, bogus = 5, cloud_queen = -2 },
			firsts = { the_rift = true, x = true, cloud_queen = "yes" },
			bosses = 0 / 0,
		})
		expect(l.pity.spore_mother).toBe(3)
		expect(l.pity.bogus).toBeNil()
		expect(l.pity.cloud_queen).toBe(0)
		expect(l.firsts.the_rift).toBe(true)
		expect(l.firsts.x).toBeNil()
		expect(l.firsts.cloud_queen).toBeNil()
		expect(l.bosses).toBe(0)
		expect(Profile.fresh().luck.bosses).toBe(0)
	end)

	it("a boss kill on Veteran drops one of that boss's uniques and counts the kill", function()
		local found, bosses, pool = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local Loot = req("ServerScriptService.Server.Systems.Loot")
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			p.luck = Profile.reconcileLuck(nil)
			player:SetAttribute("WorldTier", 2)
			Loot.collect(player)
			local pos = player.Character.HumanoidRootPart.Position
			Combat.EnemyKilled:Fire(player, pos, 1, true, nil, 0, 12, "mushroom_swamp", 10, false)
			local _, items = Loot.collect(player)
			player:SetAttribute("WorldTier", 1)
			local ids = {}
			for _, it in items do
				if it.rarity == "unique" then
					table.insert(ids, it.unique)
				end
			end
			local names = {}
			for _, u in req("ReplicatedStorage.Shared.Items").uniquesFrom("spore_mother") do
				names[u.id] = true
			end
			return ids, p.luck.bosses, names
		end)
		expect(#found).toBe(1)
		expect(pool[found[1]]).toBe(true)
		expect(bosses).toBe(1)
	end)
end)

describe("Unique actions on the server", function()
	it("fuses a duplicate from the bag through the Forge remote", function()
		local id = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			local It = req("ReplicatedStorage.Shared.Items")
			local u = It.UniqueById.moonlit_tome
			for i = #p.inventory, 1, -1 do -- an earlier boss drop could be a copy too
				if p.inventory[i].unique == u.id then
					table.remove(p.inventory, i)
				end
			end
			local a = It.makeUnique(u, 5, Random.new(1), p.class)
			local b = It.makeUnique(u, 5, Random.new(2), p.class)
			table.insert(p.inventory, a)
			table.insert(p.inventory, b)
			p.materials.shards = 500
			return a.id
		end)
		local reply = nil
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.ForgeResult.OnClientEvent:Connect(function(data)
				reply = data
			end)
			Net.ForgeAct:FireServer("fuse", id)
		end)
		sim:run(0.5)
		expect(reply and reply.text).toBe("Fused - Rank II")
		local count, rank, shards = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			local n, r = 0, 0
			for _, it in p.inventory do
				if it.unique == "moonlit_tome" then
					n += 1
					r = it.rank or 1
				end
			end
			return n, r, p.materials.shards
		end)
		expect(count).toBe(1)
		expect(rank).toBe(2)
		expect(shards).toBe(500 - Forge.ById.fuse.cost)
	end)
end)

describe("Unique effects in combat", function()
	local function hit(req, player, enemy, skill): number
		local Combat = req("ServerScriptService.Server.Systems.Combat")
		enemy:SetAttribute("Health", 1e6)
		Combat.damageEnemy(enemy, 100, player, skill, false)
		return 1e6 - (enemy:GetAttribute("Health") :: number)
	end

	local function setup(player)
		player:SetAttribute("StatWeapon", 1)
		player:SetAttribute("StatDamage", 0)
		player:SetAttribute("StatLowLife", 0)
		player:SetAttribute("StatCritDamage", 0)
		player:SetAttribute("StatCritShard", 0)
		player:SetAttribute("Level", 1)
		player:SetAttribute("StatCrit", -1000) -- no crits
	end

	it(
		"Shard of the Stormkeeper turns move speed into damage, Ember Band hits burning enemies harder",
		function()
			local plain, fast, cold, hot = server(function(req, player)
				local Combat = req("ServerScriptService.Server.Systems.Combat")
				local Enemies = req("ServerScriptService.Server.Systems.Enemies")
				setup(player)
				local root = player.Character.HumanoidRootPart.Position
				local enemy = Enemies.spawn("slime", root + Vector3.new(40, 0, 0), 1)
				player:SetAttribute("StatSpeed", 20)
				Combat.setUniques(player, {})
				local a = hit(req, player, enemy, nil)
				Combat.setUniques(player, { storm_shard = 1 })
				local b = hit(req, player, enemy, nil)
				Combat.setUniques(player, { ember_band = 1 })
				local c = hit(req, player, enemy, nil)
				local burnSkill = { id = "test_burn", damage = 100, burn = 0.01 }
				hit(req, player, enemy, burnSkill :: any) -- sets it burning
				local d = hit(req, player, enemy, nil)
				Combat.setUniques(player, {})
				player:SetAttribute("StatSpeed", 0)
				enemy:Destroy()
				return a, b, c, d
			end)
			expect(fast / plain).toBeCloseTo(1.2, 1)
			expect(cold).toBe(plain)
			expect(hot / plain).toBeCloseTo(1.15, 1)
		end
	)

	it("Stormcaller chains lightning on every 4th basic hit", function()
		local others = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Skills = req("ReplicatedStorage.Shared.Skills")
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			setup(player)
			local root = player.Character.HumanoidRootPart.Position
			local main = Enemies.spawn("slime", root + Vector3.new(40, 0, 0), 1)
			local near = Enemies.spawn("slime", root + Vector3.new(44, 0, 0), 1)
			near:SetAttribute("Health", 1e6)
			Combat.setUniques(player, { stormcaller = 1 })
			local basic = Skills.forClass(p.class).basic
			for _ = 1, 4 do
				hit(req, player, main, basic)
			end
			return { main = main, near = near }
		end)
		sim:run(0.5)
		local lost = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local out = 1e6 - (others.near:GetAttribute("Health") :: number)
			Combat.setUniques(player, {})
			others.main:Destroy()
			others.near:Destroy()
			return out
		end)
		expect(lost).toBeGreaterThan(0)
	end)

	it("Warden's Girdle heals once when life drops low", function()
		local after, again = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			Combat.setUniques(player, { warden_girdle = 1 })
			humanoid.Health = humanoid.MaxHealth
			Combat.hurtPlayer(player, humanoid.MaxHealth * 0.7)
			local a = humanoid.Health / humanoid.MaxHealth
			Combat.hurtPlayer(player, humanoid.MaxHealth * 0.05)
			local b = humanoid.Health / humanoid.MaxHealth
			Combat.setUniques(player, {})
			humanoid.Health = humanoid.MaxHealth
			return a, b
		end)
		expect(after).toBeGreaterThan(0.45) -- 30 % left + 20 % heal (less with armor rounding)
		expect(again).toBeLessThan(after) -- the rescue waits for its cooldown
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
