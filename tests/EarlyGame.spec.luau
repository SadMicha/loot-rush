-- Early-game pass (2026-11-06, docs/GAMEPLAY.md "Early game"): early bosses bring a real upgrade
-- (Balance.EarlyUpgrades), the Star Web opens at level 4, and the first depth 1 clear offers
-- tutorial Path Cards (PathCards.tutorial).
local Balance = require("ReplicatedStorage.Shared.Balance")
local Items = require("ReplicatedStorage.Shared.Items")
local PathCards = require("ReplicatedStorage.Shared.PathCards")
local Quests = require("ReplicatedStorage.Shared.Quests")
local RiftAffixes = require("ReplicatedStorage.Shared.RiftAffixes")
local StarNet = require("ReplicatedStorage.Shared.StarNet")
local Upgrade = require("ReplicatedStorage.Shared.Upgrade")

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

local function until_(want: string)
	for _ = 1, 60 do
		if phase() == want then
			return
		end
		server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
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

describe("Tutorial Path Cards rules", function()
	it("offers the safe card, Swarm for items and the Gold Goblin for gold", function()
		local cards = PathCards.tutorial()
		expect(#cards).toBe(PathCards.COUNT)
		expect(#cards[1].affixes).toBe(0)
		expect(cards[1].amount).toBe(PathCards.SAFE_GOLD)
		expect(cards[2].affixes[1]).toBe("swarm")
		expect(cards[2].reward).toBe("items")
		expect(cards[3].affixes[1]).toBe("goblin")
		expect(cards[3].reward).toBe("gold")
		for _, card in cards do
			expect(card.weight).toBe(RiftAffixes.weight(card.affixes))
			-- survives the network round trip like rolled cards
			expect(PathCards.sanitize(card)).never.toBeNil()
		end
	end)

	it("is due only on the first clear of depth 1", function()
		expect(PathCards.tutorialDue(1, 0)).toBe(true)
		expect(PathCards.tutorialDue(1, 1)).toBe(false)
		expect(PathCards.tutorialDue(2, 0)).toBe(false)
	end)
end)

describe("Star Web unlock", function()
	it("opens at level 4, not at level 3", function()
		local d = Quests.fresh()
		expect(Quests.isOpen(d, "star_net", 3, 0)).toBe(false)
		expect(Quests.isOpen(d, "star_net", 4, 0)).toBe(true)
	end)
end)

describe("Early upgrades rule", function()
	it("counts the first bosses as early ones", function()
		local Loot = server(function(req)
			return req("ServerScriptService.Server.Systems.Loot")
		end)
		expect(Loot.earlyDue(0)).toBe(true)
		expect(Loot.earlyDue(Balance.EarlyUpgrades.bosses - 1)).toBe(true)
		expect(Loot.earlyDue(Balance.EarlyUpgrades.bosses)).toBe(false)
	end)

	it("fills an empty slot first", function()
		local Loot = server(function(req)
			return req("ServerScriptService.Server.Systems.Loot")
		end)
		local rng = Random.new(4)
		local equipped = {}
		for _, slot in Items.Slots do
			if slot ~= "boots" then
				equipped[slot] = Items.roll(1, rng, nil, { slot = slot, class = "ranger" })
			end
		end
		local hero = Upgrade.hero(equipped, 5, "ranger")
		for _ = 1, 20 do
			local item = Loot.earlyUpgrade(hero, rng, function(slot)
				return Items.roll(3, rng, nil, { min = "rare", slot = slot, class = "ranger" })
			end)
			expect(item.slot).toBe("boots")
		end
	end)

	it("beats the worn piece when every slot is taken", function()
		local Loot = server(function(req)
			return req("ServerScriptService.Server.Systems.Loot")
		end)
		local rng = Random.new(9)
		local equipped = {}
		for _, slot in Items.Slots do
			equipped[slot] = Items.roll(1, rng, nil, { slot = slot, class = "mage" })
		end
		local hero = Upgrade.hero(equipped, 8, "mage")
		for _ = 1, 30 do
			local item = Loot.earlyUpgrade(hero, rng, function(slot)
				return Items.roll(4, rng, nil, { min = "rare", slot = slot, class = "mage" })
			end)
			expect(Upgrade.isUpgrade(hero, item)).toBe(true)
			expect(Items.canWear(item, hero.level, hero.class)).toBe(true)
		end
	end)
end)

describe("Early game in a run", function()
	it("offers the tutorial cards after the first depth 1 boss", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer(
				"setup",
				"Early Hero",
				"warrior"
			)
		end)
		sim:run(1)
		rift("enter", "green_plains", 1)
		expect(phase()).toBe("wave")
		until_("clear")
		expect(phase()).toBe("clear")
		local summary = lastClear()
		expect(summary).never.toBeNil()
		local cards = (summary :: any).cards
		expect(#cards).toBe(PathCards.COUNT)
		expect(cards[2].affixes[1]).toBe("swarm")
	end)

	it("plays the picked card and keeps later depths plain", function()
		rift("deeper", 2)
		sim:run(1)
		expect(sim.player:GetAttribute("RiftDepth")).toBe(2)
		expect(sim.player:GetAttribute("RiftAffixes")).toBe(RiftAffixes.encode({ "swarm" }))
		until_("clear")
		expect(phase()).toBe("clear")
		expect((lastClear() :: any).depth).toBe(2)
		expect((lastClear() :: any).cards).toBeNil()
		rift("leave")
		expect(phase()).toBe("")
	end)

	it("an early boss kill brings a wearable upgrade", function()
		local fits = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local Loot = req("ServerScriptService.Server.Systems.Loot")
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			p.luck.bosses = 0
			local hero = req("ServerScriptService.Server.Systems.Stats").hero(player)
			Loot.collect(player)
			local pos = player.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 200)
			Combat.EnemyKilled:Fire(player, pos, 1, true, nil, 0, 2, "green_plains", 10, false)
			local _, items = Loot.collect(player)
			for _, it in items do
				if Upgrade.isUpgrade(hero, it) and Items.canWear(it, hero.level, hero.class) then
					return true
				end
			end
			return false
		end)
		expect(fits).toBe(true)
	end)

	it("counts a star placed before the star quest came up", function()
		local before, after = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			local idx = 0
			for i, q in Quests.Chain do
				if q.id == "first_star" then
					idx = i
				end
			end
			local small = nil
			for _, s in StarNet.Stars do
				if s.kind == "small" then
					small = s.id
					break
				end
			end
			p.progress.stars[small] = true
			p.quests.step = idx
			p.quests.count = 0
			req("ServerScriptService.Server.Systems.Quests").advance(player, nil, 0)
			return idx, p.quests.step
		end)
		expect(after).toBeGreaterThan(before)
	end)
end)
