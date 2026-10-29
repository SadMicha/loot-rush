-- Haustiere: Regeln (rein) und Schlüpfen/Ausrüsten über Net.Pet in der Sandbox.
local Pets = require("ReplicatedStorage.Shared.Pets")
local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Haustier-Regeln", function()
	it("hat für jede Ei-Seltenheit mindestens ein Haustier", function()
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

	it("würfelt, steigert Stufen und summiert nur belegte Plätze", function()
		local rng = Random.new(7)
		for _ = 1, 50 do
			expect(Pets.ById[Pets.roll(Pets.EggById.sternen_ei, rng).id]).never.toBeNil()
		end
		local data = Pets.fresh()
		expect(Pets.hatchResult(data, "moosfrosch")).toBe(1)
		data.owned.moosfrosch = Pets.MAX_LEVEL
		local lvl, shards = Pets.hatchResult(data, "moosfrosch")
		expect(lvl).toBe(Pets.MAX_LEVEL)
		expect(shards).toBe(Pets.DUPE_SHARDS)
		data.owned.gluehwuermchen = 2
		data.equipped = { "gluehwuermchen", "moosfrosch" }
		expect(Pets.total(data, 1).gold).toBe(15)
		expect(Pets.total(data, 1).xp).toBeNil()
		expect(Pets.total(data, 2).xp).toBe(30)
	end)

	it("säubert gespeicherte Haustiere", function()
		local p = Profile.reconcile({
			pets = {
				owned = { moosfrosch = 99, quatsch = 1 },
				equipped = { "quatsch", "moosfrosch", "moosfrosch" },
			},
		})
		expect(p.pets.owned.moosfrosch).toBe(Pets.MAX_LEVEL)
		expect(p.pets.owned.quatsch).toBeNil()
		expect(#p.pets.equipped).toBe(1)
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

local function state()
	return server(function(req, player)
		local p = req("ServerScriptService.Server.Systems.Data").get(player)
		local owned = 0
		for _ in p.pets.owned do
			owned += 1
		end
		return {
			owned = owned,
			equipped = table.clone(p.pets.equipped),
			gold = p.gold,
			stars = p.soulstars,
			attr = player:GetAttribute("Pets"),
			slots = player:GetAttribute("PetSlots"),
		}
	end)
end

describe("Haustiere im Spiel", function()
	it("schlüpft nur mit genug Gold und rüstet das erste Haustier aus", function()
		sim:boot({ seconds = 2 })
		send("hatch", "wiesen_ei")
		expect(state().owned).toBe(0)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Inventory").addGold(player, 1000)
		end)
		send("hatch", "wiesen_ei")
		local s = state()
		expect(s.owned).toBe(1)
		expect(s.gold).toBe(400)
		expect(#s.equipped).toBe(1)
		expect(s.attr).toBe(s.equipped[1])
		expect(s.slots).toBe(1)
		-- Bonus kommt an
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

	it("legt ab, ignoriert Fremdes und Unsinn", function()
		local id = state().equipped[1]
		send("equip", "runendrache") -- nicht im Besitz
		send("hatch", "gibtsnicht")
		send(42, {})
		expect(#state().equipped).toBe(1)
		send("unequip", id)
		local s = state()
		expect(#s.equipped).toBe(0)
		expect(s.attr).toBe("")
		send("equip", id)
		expect(state().equipped[1]).toBe(id)
	end)
end)
