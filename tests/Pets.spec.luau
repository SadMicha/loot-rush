-- Pets: rules (pure) and hatching/equipping via Net.Pet in the sandbox.
local Pets = require("ReplicatedStorage.Shared.Pets")
local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Pet rules", function()
	it("has at least one pet for every egg rarity", function()
		local rarities = {}
		for _, p in Pets.List do
			rarities[p.rarity] = true
		end
		for _, egg in Pets.Eggs do
			for r, w in egg.weights do
				if w > 0 then
					expect(rarities[r]).toBe(true)
				end
			end
		end
	end)

	it("prices eggs: gold grows with the best depth, Soulstars stay fixed", function()
		local Balance = require("ReplicatedStorage.Shared.Balance")
		local meadow, star = Pets.EggById.meadow_egg, Pets.EggById.star_egg
		expect(Pets.eggPrice(meadow, 0)).toBe(
			math.floor(meadow.price.amount * Balance.shopFactor(0) + 0.5)
		)
		expect(Pets.eggPrice(meadow, 40)).toBeGreaterThanOrEqual(Pets.eggPrice(meadow, 0))
		expect(Pets.eggPrice(star, 0)).toBe(star.price.amount)
		expect(Pets.eggPrice(star, 40)).toBe(star.price.amount)
		expect(Pets.eggPrice(meadow, 40, 0)).toBe(0) -- first pet is free
		expect(Pets.eggPrice(star, 0, 0)).toBe(star.price.amount) -- Soulstar eggs never
		expect(Pets.eggPrice(meadow, 0, 1)).toBe(Pets.eggPrice(meadow, 0))
	end)

	it("rolls, raises levels and only sums occupied slots", function()
		local rng = Random.new(7)
		for _ = 1, 50 do
			expect(Pets.ById[Pets.roll(Pets.EggById.star_egg, rng).id]).never.toBeNil()
		end
		local data = Pets.fresh()
		expect(Pets.hatchResult(data, "moss_frog")).toBe(1)
		data.owned.moss_frog = Pets.MAX_LEVEL
		local lvl, shards = Pets.hatchResult(data, "moss_frog")
		expect(lvl).toBe(Pets.MAX_LEVEL)
		expect(shards).toBe(Pets.DUPE_SHARDS)
		data.owned.firefly = 2
		data.equipped = { "firefly", "moss_frog" }
		expect(Pets.total(data, 1).gold).toBe(15)
		expect(Pets.total(data, 1).xp).toBeNil()
		expect(Pets.total(data, 2).xp).toBe(30)
	end)

	it("cleans up saved pets", function()
		local p = Profile.reconcileAccount({
			pets = {
				owned = { moss_frog = 99, bogus = 1 },
				equipped = { "bogus", "moss_frog", "moss_frog" },
			},
		})
		expect(p.pets.owned.moss_frog).toBe(Pets.MAX_LEVEL)
		expect(#p.pets.equipped).toBe(1)
		expect(p.pets.equipped[1]).toBe("moss_frog")
	end)

	it("keeps unknown pets and game passes (newer server) but does not count them", function()
		local p = Profile.reconcileAccount({
			pets = {
				owned = {
					moss_frog = 2,
					future_pet = 99,
					broken = "x",
					nan = 0 / 0,
					[string.rep("a", 65)] = 1,
				},
				equipped = { "future_pet", "moss_frog" },
			},
			passes = { vip = true, future_pass = true, wrong = "yes" },
		})
		expect(p.pets.owned.future_pet).toBe(Pets.MAX_LEVEL)
		expect(p.pets.owned.broken).toBeNil()
		expect(p.pets.owned.nan).toBeNil()
		expect(p.pets.owned[string.rep("a", 65)]).toBeNil()
		-- only known pets stay equipped, display and bonuses ignore unknown ones
		expect(#p.pets.equipped).toBe(1)
		expect(p.pets.equipped[1]).toBe("moss_frog")
		expect(Pets.knownOwned(p.pets).future_pet).toBeNil()
		expect(Pets.knownOwned(p.pets).moss_frog).toBe(2)
		p.pets.equipped = { "future_pet", "moss_frog" }
		expect(Pets.total(p.pets, 1).xp).toBe(15)
		expect(p.passes.future_pass).toBe(true)
		expect(p.passes.vip).toBe(true)
		expect(p.passes.wrong).toBeNil()
		-- survives a second load (save on an old server, load again)
		local again = Profile.reconcileAccount(Profile.copy(p))
		expect(again.pets.owned.future_pet).toBe(Pets.MAX_LEVEL)
		expect(again.passes.future_pass).toBe(true)
	end)

	it("caps unknown entries", function()
		local owned = {}
		local passes = {}
		for i = 1, Pets.MAX_UNKNOWN + 10 do
			owned["tier" .. i] = 1
			passes["pass" .. i] = true
		end
		owned.moss_frog = 1
		local p = Profile.reconcileAccount({ pets = { owned = owned }, passes = passes })
		local n = 0
		for _ in p.pets.owned do
			n += 1
		end
		expect(n).toBe(Pets.MAX_UNKNOWN + 1)
		expect(p.pets.owned.moss_frog).toBe(1)
		local np = 0
		for _ in p.passes do
			np += 1
		end
		expect(np).toBe(Profile.MAX_UNKNOWN_PASSES)
	end)
end)

describe("Egg odds", function()
	local function rank(r)
		return table.find(Pets.RarityOrder, r)
	end

	it("uses only weight keys from the rarity order", function()
		for _, egg in Pets.Eggs do
			for r, w in egg.weights do
				expect(rank(r)).never.toBeNil()
				expect(w).toBeGreaterThanOrEqual(0)
			end
		end
	end)

	it("sums to 100, follows the rarity order and omits zero weights", function()
		for _, egg in Pets.Eggs do
			local odds = Pets.odds(egg)
			local sum = 0
			local last = 0
			local listed = {}
			for _, o in odds do
				sum += o.percent
				expect(o.percent).toBeGreaterThan(0)
				expect(rank(o.rarity)).toBeGreaterThan(last)
				last = rank(o.rarity)
				listed[o.rarity] = true
			end
			expect(sum).toBeCloseTo(100, 1e-9)
			for r, w in egg.weights do
				expect(listed[r] == true).toBe(w > 0)
			end
		end
		-- zero weights are left out, also in the roll
		local egg = {
			id = "test",
			name = "",
			text = "",
			price = { kind = "gold", amount = 1 },
			weights = { normal = 0, magic = 1, epic = 3 },
		}
		local odds = Pets.odds(egg)
		expect(#odds).toBe(2)
		expect(odds[1].rarity).toBe("magic")
		expect(odds[1].percent).toBeCloseTo(25)
		expect(odds[2].rarity).toBe("epic")
		expect(odds[2].percent).toBeCloseTo(75)
		local rng = Random.new(3)
		for _ = 1, 200 do
			local r = Pets.roll(egg, rng).rarity
			expect(r == "magic" or r == "epic").toBe(true)
		end
	end)

	it("matches the frequencies of Pets.roll (seeded)", function()
		local N = 20000
		for _, egg in Pets.Eggs do
			local rng = Random.new(42)
			local seen = {}
			for _ = 1, N do
				local r = Pets.roll(egg, rng).rarity
				seen[r] = (seen[r] or 0) + 1
			end
			local listed = {}
			for _, o in Pets.odds(egg) do
				listed[o.rarity] = true
				-- 20000 rolls: standard error at most ~0.35 percentage points, 1.5 is generous
				expect((seen[o.rarity] or 0) / N * 100).toBeCloseTo(o.percent, 1.5)
			end
			for r in seen do
				expect(listed[r]).toBe(true)
			end
		end
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function send(action, id)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Pet:FireServer(action, id)
	end)
	sim:run(1)
end

-- Latest Net.PetResult payload the server sent
local function lastResult()
	for i = #sim.netLog, 1, -1 do
		local e = sim.netLog[i]
		if e.name == "PetResult" and e.dir == "S→C" then
			return e.args[1]
		end
	end
	return nil
end

local function state()
	return server(function(req, player)
		local Data = req("ServerScriptService.Server.Systems.Data")
		local p = Data.get(player)
		local a = Data.account(player)
		local owned = 0
		for _ in a.pets.owned do
			owned += 1
		end
		return {
			owned = owned,
			equipped = table.clone(a.pets.equipped),
			gold = p.gold,
			stars = a.soulstars,
			attr = player:GetAttribute("Pets"),
			slots = player:GetAttribute("PetSlots"),
		}
	end)
end

describe("Pets in game", function()
	it("hatches the first gold egg for free, then only with enough gold", function()
		sim:boot({ seconds = 2 })
		local gold0 = state().gold
		send("hatch", "meadow_egg") -- first pet: free
		local s = state()
		expect(s.owned).toBe(1)
		expect(s.gold).toBe(gold0)
		local before = s.owned
		send("hatch", "meadow_egg") -- not enough gold now
		expect(state().gold).toBe(gold0)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Inventory").addGold(player, 1000 - gold0)
		end)
		send("hatch", "meadow_egg")
		s = state()
		expect(s.gold).toBe(400)
		expect(s.owned).toBeGreaterThanOrEqual(before) -- a duplicate levels up instead
		expect(#s.equipped).toBe(1)
		expect(s.attr).toBe(s.equipped[1])
		expect(s.slots).toBe(1)
		local last = lastResult()
		expect(last.kind).toBe("hatch")
		expect(last.ok).toBe(true)
		expect(last.pet).never.toBeNil() -- the second hatch (the first stays equipped)
		-- the bonus arrives
		local bonus = server(function(_, player)
			local total = 0
			for _, a in
				{ "BonusGold", "BonusXP", "BonusLife", "BonusDamage", "BonusItems", "BonusMagnet" }
			do
				total += player:GetAttribute(a) or 0
			end
			return total
		end)
		expect(bonus).toBeGreaterThan(0)
	end)

	it("unequips, ignores foreign and nonsense input", function()
		local id = state().equipped[1]
		send("equip", "rune_dragon") -- not owned
		-- unknown pet owned (from a newer server): not equippable, no error
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Data").account(player).pets.owned.future_pet = 3
		end)
		send("equip", "future_pet")
		send("hatch", "does_not_exist")
		send(42, {})
		expect(#state().equipped).toBe(1)
		send("unequip", id)
		local s = state()
		expect(#s.equipped).toBe(0)
		expect(s.attr).toBe("")
		expect(lastResult().kind).toBe("unequip")
		send("equip", id)
		expect(state().equipped[1]).toBe(id)
		expect(lastResult().kind).toBe("equip")
		expect(lastResult().pet).toBe(id)
	end)
end)
