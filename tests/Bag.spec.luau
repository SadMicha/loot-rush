-- Bag upgrades (Shared/Bag, Systems/Inventory): capacity and price curve, the save field in the
-- season data (account-wide, reset with the season), the Net.Bag purchase and the full-bag rules
-- with the bigger bag. The server tests build on each other (one sandbox per spec file).
local Bag = require("ReplicatedStorage.Shared.Bag")
local Items = require("ReplicatedStorage.Shared.Items")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Seasons = require("ReplicatedStorage.Shared.Seasons")

local STORE = "LootRush_Profile_v3/global"
local SYSTEMS = "ServerScriptService.Server.Systems."

describe("Bag rules", function()
	it("grows from 40 to 100 slots in 12 steps of 5", function()
		expect(Bag.BASE).toBe(40)
		expect(Bag.MAX_LEVEL).toBe(12)
		expect(Bag.capacity(0)).toBe(40)
		expect(Bag.capacity(1)).toBe(45)
		expect(Bag.capacity(12)).toBe(100)
		expect(Bag.MAX_CAPACITY).toBe(100)
		-- junk levels are clamped, never above the largest bag
		expect(Bag.capacity(99)).toBe(100)
		expect(Bag.capacity(-3)).toBe(40)
		expect(Bag.level(0 / 0)).toBe(0)
		expect(Bag.level(math.huge)).toBe(0)
		expect(Bag.level("5" :: any)).toBe(0)
		expect(Bag.level(3.9)).toBe(3)
	end)

	it("prices every step higher, the first one cheap and the last one a deep sink", function()
		expect(Bag.price(0)).toBe(1200)
		local total, last = 0, 0
		for level = 0, Bag.MAX_LEVEL - 1 do
			local price = Bag.price(level) :: number
			expect(price).toBeGreaterThan(last)
			-- each step costs at least 1.5x the one before (steep curve)
			expect(price >= last * 1.5).toBe(true)
			last = price
			total += price
		end
		expect(Bag.price(Bag.MAX_LEVEL)).toBeNil()
		expect(last).toBe(770000)
		expect(total).toBe(1734300)
		-- level 1 in the first session: about a quarter hour of depth-1 gold (~100 per minute,
		-- docs/balancing.md)
		expect(Bag.price(0) :: number <= 100 * 15).toBe(true)
	end)

	it("checks the target level, the gold and the largest bag", function()
		expect(Bag.check(0, 1, 1200)).toBe("ok")
		expect(Bag.check(0, 1, 1199)).toBe("gold")
		expect(Bag.check(0, 1, 0 / 0)).toBe("gold")
		expect(Bag.check(0, 2, 1e9)).toBe("stale") -- skips a level
		expect(Bag.check(1, 1, 1e9)).toBe("stale") -- double tap
		expect(Bag.check(12, 13, 1e12)).toBe("max")
		expect(Bag.validTarget(1)).toBe(true)
		expect(Bag.validTarget(12)).toBe(true)
		for _, bad in { 0, 13, 1.5, 0 / 0, math.huge, "1", {}, nil :: any } do
			expect(Bag.validTarget(bad)).toBe(false)
		end
		expect(Bag.fromAttribute(nil)).toBe(40)
		expect(Bag.fromAttribute(55)).toBe(55)
		expect(Bag.fromAttribute(1e9)).toBe(100)
	end)
end)

describe("Bag level in the season data", function()
	it("old saves load with the base bag and junk is clamped", function()
		local old = Profile.reconcileAccount({ season = { id = Seasons.Current.id, counts = {} } })
		expect(old.season.bag).toBe(0)
		expect(Profile.freshAccount().season.bag).toBe(0)
		local function loaded(raw: any): number
			return Seasons.reconcile({ id = Seasons.Current.id, bag = raw }).bag
		end
		expect(loaded(4)).toBe(4)
		expect(loaded(4.7)).toBe(4)
		expect(loaded(-1)).toBe(0)
		expect(loaded(500)).toBe(Bag.MAX_LEVEL)
		expect(loaded(0 / 0)).toBe(0)
		expect(loaded("7")).toBe(0)
		expect(loaded({})).toBe(0)
	end)

	it("a new season resets the bag with the rest of the season data", function()
		local account = Profile.freshAccount()
		account.season.bag = 7
		account.season.counts.kills = 100
		-- same season: kept
		expect(Profile.reconcileAccount(account).season.bag).toBe(7)
		-- the save is from another season (the server now runs a new Seasons.Current): reset
		local copy = Profile.copy({ v = Profile.VERSION, data = account })
		copy.data.season.id = "pre_beta"
		local reloaded = Profile.migrate(copy).data
		expect(reloaded.season.id).toBe(Seasons.Current.id)
		expect(reloaded.season.bag).toBe(0)
		expect(reloaded.season.counts.kills).toBeNil()
	end)
end)

local function seed(key: string, account: any)
	sim.datastores[STORE] = sim.datastores[STORE] or {}
	sim.datastores[STORE][key] = {
		Data = { v = Profile.VERSION, data = account },
		MetaData = { ProfileCreateTime = 0, SessionLoadCount = 1, MetaTags = {} },
		RobloxMetaData = {},
		UserIds = {},
		GlobalUpdates = { 0, {} },
	}
end

local function server(player, fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, player))
	end)
	return table.unpack(out, 1, out.n)
end

local function results(): { any }
	local list = {}
	for _, n in sim.netLog do
		if n.name == "BagResult" and n.dir == "S→C" then
			table.insert(list, n.args[1])
		end
	end
	return list
end

local function bagState(player)
	return server(player, function(req, p)
		local Data = req(SYSTEMS .. "Data")
		return Data.account(p).season.bag,
			Data.get(p).gold,
			p:GetAttribute("BagLevel"),
			p:GetAttribute("BagMax"),
			#Data.get(p).inventory
	end)
end

-- Sends Net.Bag requests (at most 4 per call: the remote allows 2 per second, burst 4)
local function send(calls: { { any } })
	sim:runAs("client", function(req)
		local remote = req("ReplicatedStorage.Shared.Net").Bag
		for _, args in calls do
			remote:FireServer(table.unpack(args, 1, 2))
		end
	end)
	sim:run(2.5) -- refills the burst
end

local function upgrade(action: any, level: any)
	send({ { action, level } })
end

local function rolls(n: number, seedNumber: number): { any }
	local rng = Random.new(seedNumber)
	local list = {}
	for _ = 1, n do
		table.insert(list, Items.roll(1, rng))
	end
	return list
end

describe("Bag upgrade on the server", function()
	local player

	it("starts with the base bag and buys one level with the hero's gold", function()
		sim:boot({ seconds = 2 })
		player = sim.player
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Bag Hero", "mage")
		end)
		sim:run(1)
		local level, _, attrLevel, attrMax = bagState(player)
		expect(level).toBe(0)
		expect(attrLevel).toBe(0)
		expect(attrMax).toBe(40)
		server(player, function(req, p)
			req(SYSTEMS .. "Data").get(p).gold = 1500
		end)
		upgrade("upgrade", 1)
		local bag, gold, aLevel, aMax = bagState(player)
		expect(bag).toBe(1)
		expect(gold).toBe(300)
		expect(aLevel).toBe(1)
		expect(aMax).toBe(45)
		expect(player:GetAttribute("Gold")).toBe(300)
		local last = results()[#results()]
		expect(last.ok).toBe(true)
		expect(last.capacity).toBe(45)
		expect(last.price).toBe(1200)
		expect(last.text).toBe("Bag upgraded to 45 slots")
	end)

	it("refuses without enough gold and leaves gold and level alone", function()
		upgrade("upgrade", 2) -- costs 2,200, the hero has 300
		local bag, gold = bagState(player)
		expect(bag).toBe(1)
		expect(gold).toBe(300)
		local last = results()[#results()]
		expect(last.ok).toBe(false)
		expect(last.text).toBe(Bag.Text.gold)
		expect(last.level).toBe(1)
	end)

	it("ignores invalid input and answers a stale level without paying", function()
		server(player, function(req, p)
			req(SYSTEMS .. "Data").get(p).gold = 1e7
		end)
		local before = #results()
		send({ { "upgrade", "2" }, { "upgrade", 0 / 0 }, { "upgrade", 2.5 }, { "upgrade", 99 } })
		send({ { "upgrade", nil }, { "buy", 2 }, { { "upgrade" }, 2 }, { "upgrade", 0 } })
		expect(#results()).toBe(before) -- dropped without an answer
		upgrade("upgrade", 1) -- already owned (double tap)
		local bag, gold = bagState(player)
		expect(bag).toBe(1)
		expect(gold).toBe(1e7)
		expect(results()[#results()].text).toBe(Bag.Text.stale)
	end)

	it("stops at the largest bag", function()
		server(player, function(req, p)
			req(SYSTEMS .. "Data").account(p).season.bag = Bag.MAX_LEVEL - 1
		end)
		upgrade("upgrade", Bag.MAX_LEVEL)
		local bag, gold, _, aMax = bagState(player)
		expect(bag).toBe(Bag.MAX_LEVEL)
		expect(aMax).toBe(100)
		expect(gold).toBe(1e7 - (Bag.price(Bag.MAX_LEVEL - 1) :: number))
		upgrade("upgrade", Bag.MAX_LEVEL) -- valid number, but there is no next level
		expect(bagState(player)).toBe(Bag.MAX_LEVEL)
		expect(results()[#results()].text).toBe(Bag.Text.max)
		upgrade("upgrade", Bag.MAX_LEVEL + 1)
		expect(bagState(player)).toBe(Bag.MAX_LEVEL)
	end)

	it("a bigger bag takes more items; full means the new capacity", function()
		local first, stored, salvaged, full, count, isFull, snapCap
		server(player, function(req, p)
			local Data = req(SYSTEMS .. "Data")
			local Inventory = req(SYSTEMS .. "Inventory")
			Data.account(p).season.bag = 1 -- 45 slots
			local profile = Data.get(p)
			profile.autoSalvage = ""
			profile.inventory = rolls(44, 5)
			-- a strong weapon the hero can wear (gear above the hero's level counts as an empty
			-- slot, Shared/Upgrade), so weak weapon drops are no upgrade
			p:SetAttribute("Level", 80)
			profile.equipped.weapon = Items.roll(60, Random.new(1), nil, { slot = "weapon" })
			-- slot 45 is free
			first = table.pack(
				Inventory.add(p, Items.roll(1, Random.new(2), nil, { slot = "weapon" }), true)
			)
			-- now full: a weak drop is salvaged, the bag stays at 45
			stored, salvaged, full =
				Inventory.add(p, Items.roll(1, Random.new(3), nil, { slot = "weapon" }), true)
			count = #profile.inventory
			isFull = Inventory.isFull(p)
			snapCap = Inventory.capacity(p)
		end)
		expect(first[1]).toBe(true) -- stored
		expect(first[2]).toBe(false) -- not salvaged
		expect(first[3]).toBe(false) -- bag was not full
		expect(stored).toBe(true)
		expect(salvaged).toBe(true)
		expect(full).toBe(true)
		expect(count).toBe(45)
		expect(isFull).toBe(true)
		expect(snapCap).toBe(45)
	end)

	it("a bag over its capacity keeps every item and takes nothing new", function()
		local stored, full, count, unequipped, worn
		server(player, function(req, p)
			local Data = req(SYSTEMS .. "Data")
			local Inventory = req(SYSTEMS .. "Inventory")
			Data.account(p).season.bag = 0 -- e.g. after a season reset
			local profile = Data.get(p)
			profile.inventory = rolls(50, 6)
			profile.equipped.boots = nil
			-- an empty slot takes the drop directly (Inventory.add): the full bag stays as it is
			local boots = Items.roll(1, Random.new(4), nil, { slot = "boots" })
			stored, _, full = Inventory.add(p, boots, true)
			worn = profile.equipped.boots == boots
			count = #profile.inventory
			profile.equipped.ring = Items.roll(1, Random.new(7), nil, { slot = "ring" })
		end)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Unequip:FireServer("ring")
		end)
		sim:run(0.5)
		unequipped = server(player, function(req, p)
			return req(SYSTEMS .. "Data").get(p).equipped.ring == nil
		end)
		expect(stored).toBe(true)
		expect(worn).toBe(true)
		expect(full).toBe(false)
		expect(count).toBe(50)
		expect(unequipped).toBe(false) -- no room: stays worn
		local _, _, _, _, after = bagState(player)
		expect(after).toBe(50)
	end)
end)

describe("Bag level across heroes and seasons (save loads)", function()
	local function account(bag: any, items: number?): any
		local a = Profile.freshAccount()
		local first = a.characters[1]
		first.setupDone = true
		first.name = "First"
		first.gold = 5000
		local second = Profile.reconcile({ id = "c2", name = "Second", setupDone = true })
		second.gold = 10
		second.inventory = rolls(items or 0, 9)
		table.insert(a.characters, second)
		a.active = "c2"
		a.season.bag = bag
		return a
	end

	it("every hero of the account shares the bag level", function()
		local key = `p_{sim.joined + 1}`
		seed(key, account(3))
		local p = sim:joinPlayer("Shared")
		sim:run(3)
		local bag, gold, _, aMax = bagState(p)
		expect(bag).toBe(3)
		expect(gold).toBe(10) -- the second hero plays
		expect(aMax).toBe(55)
		-- leave; the save now plays the first hero: same bag
		sim:signal(game:GetService("Players"), "PlayerRemoving"):Fire(p)
		p.Parent = nil
		sim:run(3)
		local stored = sim.datastores[STORE][key].Data
		expect(stored.data.season.bag).toBe(3)
		stored.data.active = "c1"
		sim.joined = p.UserId - 1
		local again = sim:joinPlayer("Shared")
		sim:run(3)
		local bag2, gold2, _, aMax2 = bagState(again)
		expect(bag2).toBe(3)
		expect(gold2).toBe(5000) -- the first hero plays
		expect(aMax2).toBe(55)
	end)

	it("an old save without the field loads with the base bag", function()
		seed(`p_{sim.joined + 1}`, account(nil))
		local p = sim:joinPlayer("Old")
		sim:run(3)
		local bag, _, aLevel, aMax = bagState(p)
		expect(bag).toBe(0)
		expect(aLevel).toBe(0)
		expect(aMax).toBe(40)
	end)

	it("a save from another season loads with the base bag and keeps every item", function()
		local a = account(6, 50)
		a.season.id = "pre_beta"
		seed(`p_{sim.joined + 1}`, a)
		local p = sim:joinPlayer("Season")
		sim:run(3)
		local bag, _, _, aMax, count = bagState(p)
		expect(bag).toBe(0)
		expect(aMax).toBe(40)
		expect(count).toBe(50)
		local full = server(p, function(req, pl)
			return req(SYSTEMS .. "Inventory").isFull(pl)
		end)
		expect(full).toBe(true)
	end)
end)
