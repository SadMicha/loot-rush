-- Path Cards (docs/specs/ENDGAME.md E1) and the Altered World boss rotation (E3): pure rules,
-- then a real run in the Altered World: cards after the boss, a picked card sets the next
-- depth's affixes and reward, a bad index is refused, every affix at once runs clean.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local PathCards = require("ReplicatedStorage.Shared.PathCards")
local RiftAffixes = require("ReplicatedStorage.Shared.RiftAffixes")

describe("Path Card rules", function()
	it("keeps the first depths plain", function()
		local rng = Random.new(3)
		for depth = 1, PathCards.FROM_DEPTH - 1 do
			expect(#PathCards.roll(rng, depth)).toBe(0)
		end
		expect(#PathCards.roll(rng, PathCards.FROM_DEPTH)).toBe(PathCards.COUNT)
	end)

	it("offers a safe card, a one-affix card and a riskier third card", function()
		local rng = Random.new(5)
		for _ = 1, 300 do
			local early = PathCards.roll(rng, 5)
			expect(#early[1].affixes).toBe(0)
			expect(early[1].reward).toBe("gold")
			expect(early[1].amount).toBe(PathCards.SAFE_GOLD)
			expect(#early[2].affixes).toBe(1)
			expect(#early[3].affixes).toBe(1) -- one affix at most before TWO_FROM
			local late = PathCards.roll(rng, PathCards.TWO_FROM)
			expect(#late[3].affixes).toBe(2)
			expect(late[3].affixes[1] ~= late[3].affixes[2]).toBe(true)
		end
	end)

	it("pays more for harder cards and offers every affix", function()
		local rng = Random.new(8)
		local seen = {}
		for _ = 1, 500 do
			for _, card in PathCards.roll(rng, 30) do
				for _, id in card.affixes do
					seen[id] = true
				end
				expect(card.weight).toBe(RiftAffixes.weight(card.affixes))
				if card.reward == "items" then
					expect(card.amount).toBeCloseTo(card.weight * PathCards.ITEMS_PER_WEIGHT, 5)
				elseif card.reward == "cache" then
					expect(card.weight >= PathCards.CACHE_FROM).toBe(true)
					expect(card.amount).toBe(card.weight - 1)
				elseif #card.affixes > 0 then
					expect(card.amount).toBeCloseTo(card.weight * PathCards.GOLD_PER_WEIGHT, 5)
				end
			end
		end
		for _, a in RiftAffixes.List do
			expect(seen[a.id]).toBe(true)
		end
	end)

	it("picks the safe card for nil and refuses bad indices", function()
		local cards = PathCards.roll(Random.new(1), 12)
		expect(PathCards.pick(cards, nil)).toBe(cards[1])
		expect(PathCards.pick(cards, 3)).toBe(cards[3])
		expect(PathCards.pick(cards, 0)).toBeNil()
		expect(PathCards.pick(cards, 4)).toBeNil()
		expect(PathCards.pick(cards, 1.5)).toBeNil()
		expect(PathCards.pick(cards, 0 / 0)).toBeNil()
		expect(PathCards.pick(cards, "2")).toBeNil()
		expect(PathCards.pick({}, 1)).toBeNil()
	end)

	it("describes rewards and survives the network round trip", function()
		expect(PathCards.describe({ affixes = {}, reward = "gold", amount = 0.1, weight = 0 })).toBe(
			"+10% gold"
		)
		expect(
			PathCards.describe({
				affixes = { "swarm" },
				reward = "items",
				amount = 0.15,
				weight = 1,
			})
		).toBe("+15% items")
		expect(PathCards.describe({ affixes = {}, reward = "cache", amount = 3, weight = 4 })).toBe(
			"Rare+ cache x3"
		)
		local card = PathCards.sanitize({
			affixes = { "swarm", "nope", "swarm", 5 },
			reward = "items",
			amount = 0.15,
		})
		expect(card).never.toBeNil()
		expect(#(card :: any).affixes).toBe(1)
		expect(PathCards.sanitize({ affixes = {}, reward = "souls", amount = 1 })).toBeNil()
		expect(PathCards.sanitize("x")).toBeNil()
	end)

	it("decodes affix attributes safely", function()
		expect(#RiftAffixes.decode("")).toBe(0)
		expect(#RiftAffixes.decode(nil)).toBe(0)
		local ids = RiftAffixes.decode("swarm,bogus,goblin,swarm")
		expect(#ids).toBe(2)
		expect(RiftAffixes.encode(ids)).toBe("swarm,goblin")
	end)
end)

describe("Altered World boss rotation", function()
	local altered = Atlas.ById.altered_world

	it("meets every boss once per block and never the same boss twice in a row", function()
		local pool = altered.bossPool :: { string }
		expect(#pool).toBe(6)
		local prev = nil
		for block = 0, 40 do
			local seen = {}
			for i = 0, #pool - 1 do
				local depth = altered.depth + block * #pool + i
				local kind, rotating = Atlas.bossFor(altered, depth)
				expect(rotating).toBe(true)
				expect(seen[kind]).toBeNil()
				seen[kind] = true
				expect(kind ~= prev).toBe(true)
				prev = kind
			end
		end
	end)

	it("is the same for everyone (seeded by depth) and leaves other regions alone", function()
		expect(Atlas.bossFor(altered, 40)).toBe((Atlas.bossFor(altered, 40)))
		local kind, rotating = Atlas.bossFor(Atlas.ById.fire_desert, 20)
		expect(kind).toBe("furnace_lord")
		expect(rotating).toBe(false)
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
	sim:run(1.2) -- also refills the Rift remote's rate limit (1/s)
end

local function phase(): string
	return sim.player:GetAttribute("RiftPhase") or ""
end

local bosses: { string } = {}

-- Kills everything until the phase is `want`; notes every boss name it meets
local function until_(want: string)
	for _ = 1, 60 do
		if phase() == want then
			return
		end
		server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				if e:GetAttribute("Boss") == true and not table.find(bosses, e.Name) then
					table.insert(bosses, e.Name)
				end
				Combat.slay(player, e)
			end
		end)
		sim:run(1)
	end
end

local function lastClear(): { [string]: any }?
	for i = #sim.netLog, 1, -1 do
		local entry = sim.netLog[i]
		if entry.name == "RiftResult" and entry.args[1].kind == "clear" then
			return entry.args[1]
		end
	end
	return nil
end

describe("Path Cards in a run", function()
	local cards = nil

	it("offers three cards after the first Altered World boss", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Debug:FireServer("atlas") -- opens the Altered World
		end)
		sim:run(1)
		rift("enter", "altered_world", Atlas.ById.altered_world.depth)
		expect(phase()).toBe("wave")
		expect(sim.player:GetAttribute("RiftAffixes")).toBe("") -- the first depth is plain
		until_("clear")
		expect(phase()).toBe("clear")
		local summary = lastClear()
		expect(summary).never.toBeNil()
		cards = (summary :: any).cards
		expect(#cards).toBe(PathCards.COUNT)
		expect(#cards[1].affixes).toBe(0)
		-- the boss of depth 26 is the rotation's pick
		local kind = Atlas.bossFor(Atlas.ById.altered_world, Atlas.ById.altered_world.depth)
		expect(#bosses).toBe(1)
		if kind ~= "the_rift" then
			expect(string.sub(bosses[1], 1, 8)).toBe("Altered ")
		end
	end)

	it("refuses a card index that does not exist", function()
		rift("deeper", 7)
		expect(phase()).toBe("clear")
		expect(sim.player:GetAttribute("RiftDepth")).toBe(26)
	end)

	it("goes deeper with the picked card's affixes and reward", function()
		rift("deeper", 3)
		sim:run(1)
		expect(phase()).toBe("wave")
		expect(sim.player:GetAttribute("RiftDepth")).toBe(27)
		expect(sim.player:GetAttribute("RiftAffixes")).toBe(RiftAffixes.encode(cards[3].affixes))
		expect(sim.player:GetAttribute("RiftReward")).toBe(PathCards.describe(cards[3]))
		until_("clear")
		expect(phase()).toBe("clear")
		expect(#bosses).toBe(2)
		expect(bosses[1] ~= bosses[2]).toBe(true) -- a different boss every depth
	end)

	it("takes the safe card when no index is sent", function()
		rift("deeper")
		sim:run(1)
		expect(sim.player:GetAttribute("RiftDepth")).toBe(28)
		expect(sim.player:GetAttribute("RiftAffixes")).toBe("")
		expect(sim.player:GetAttribute("RiftReward")).toBe("+10% gold")
		local bonus = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Loot").runBonus(player)
		end)
		expect(bonus.gold).toBe(PathCards.SAFE_GOLD)
		rift("leave")
		expect(phase()).toBe("")
		expect(sim.player:GetAttribute("RiftAffixes")).toBeNil()
		local after = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Loot").runBonus(player)
		end)
		expect(after).toBeNil()
	end)

	it("plays a depth with every affix at once", function()
		local all = {}
		for _, a in RiftAffixes.List do
			table.insert(all, a.id)
		end
		server(function(req)
			req("ServerScriptService.Server.Systems.Rift").forceAffixes = all
		end)
		sim:run(3) -- past the re-enter delay
		rift("enter", "altered_world", Atlas.ById.altered_world.depth)
		expect(phase()).toBe("wave")
		expect(sim.player:GetAttribute("RiftDamageBonus")).toBe(RiftAffixes.GLASS_DAMAGE)
		expect(sim.player:GetAttribute("RiftRushFill")).toBe(RiftAffixes.RUSH_FILL)
		local shielded = server(function()
			local n = 0
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				if (e:GetAttribute("Shield") or 0) > 0 then
					n += 1
				end
			end
			return n
		end)
		expect(shielded > 0).toBe(true)
		sim:run(RiftAffixes.RAIN_EVERY * 2) -- brick rain volleys fall
		until_("clear")
		expect(phase()).toBe("clear")
		server(function(req)
			req("ServerScriptService.Server.Systems.Rift").forceAffixes = nil
		end)
		rift("leave")
		expect(sim.player:GetAttribute("RiftDamageBonus")).toBeNil()
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
