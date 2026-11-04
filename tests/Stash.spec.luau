--!nocheck
-- Hub stash (Shared/Stash, Systems/Stash, Client/StashController): pure move rules, the save
-- field, and the real server + window: moves only at the station, never a duplicate.
local Items = require("ReplicatedStorage.Shared.Items")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Stash = require("ReplicatedStorage.Shared.Stash")

local function item(id: string, slot: string?)
	return {
		id = id,
		slot = slot or "ring",
		rarity = "magic",
		name = "Ring " .. id,
		ilvl = 3,
		affixes = {},
	}
end

local function count(data, id)
	local n = 0
	for _, tab in data.tabs do
		for _, it in tab do
			if it.id == id then
				n += 1
			end
		end
	end
	return n
end

describe("Stash rules", function()
	it("moves an item between bag and stash, never copies it", function()
		local data = Stash.fresh()
		expect(#data.tabs).toBe(Stash.TABS)
		local bag = { item("a"), item("b") }
		expect(Stash.deposit(data, bag, "a", 2)).toBe("ok")
		expect(#bag).toBe(1)
		expect(#data.tabs[2]).toBe(1)
		expect(Stash.deposit(data, bag, "a", 1)).toBe("missing") -- already moved
		expect(Stash.withdraw(data, bag, "a", Items.BAG_MAX)).toBe("ok")
		expect(#bag).toBe(2)
		expect(count(data, "a")).toBe(0)
		expect(Stash.withdraw(data, bag, "a", Items.BAG_MAX)).toBe("missing")
	end)

	it("rejects bad tabs, a full tab, a full bag and duplicates", function()
		local data = Stash.fresh()
		local bag = { item("a") }
		for _, t in { 0, Stash.TABS + 1, 1.5, 0 / 0, math.huge, "1" } do
			expect(Stash.deposit(data, bag, "a", t)).toBe("tab")
		end
		for i = 1, Stash.TAB_SLOTS do
			table.insert(data.tabs[1], item("s" .. i))
		end
		expect(Stash.deposit(data, bag, "a", 1)).toBe("full")
		expect(#bag).toBe(1)
		-- same id already stored (broken save): no second copy
		table.insert(data.tabs[3], item("a"))
		expect(Stash.deposit(data, bag, "a", 2)).toBe("duplicate")
		-- full bag: the item stays in the stash
		local full = {}
		for i = 1, 3 do
			table.insert(full, item("f" .. i))
		end
		expect(Stash.withdraw(data, full, "s1", 3)).toBe("bag_full")
		expect(count(data, "s1")).toBe(1)
	end)

	it("stores the whole bag into one tab as long as there is room", function()
		local data = Stash.fresh()
		for i = 1, Stash.TAB_SLOTS - 2 do
			table.insert(data.tabs[1], item("s" .. i))
		end
		local bag = { item("a"), item("b"), item("c") }
		expect(Stash.depositAll(data, bag, 1)).toBe(2)
		expect(#bag).toBe(1)
		expect(bag[1].id).toBe("c")
		expect(Stash.room(data, 1)).toBe(0)
		expect(Stash.depositAll(data, bag, 9)).toBe(0)
	end)

	it("repairs a loaded stash: junk, duplicates, old extra tabs, items a hero owns", function()
		local raw = {
			tabs = {
				{ item("a"), item("a"), "junk", { id = 5 }, item(string.rep("x", 80)) },
				{ item("b") },
				nil,
				{},
				{ item("c") }, -- tab past Stash.TABS
			},
		}
		local data = Stash.reconcile(raw, { b = true })
		expect(#data.tabs).toBe(Stash.TABS)
		expect(count(data, "a")).toBe(1)
		expect(count(data, "b")).toBe(0) -- the hero keeps it, the stash copy goes
		expect(#data.tabs[1]).toBe(1)
		expect(data.tabs[Stash.TABS][1].id).toBe("c")
		expect(#Stash.reconcile("nope").tabs).toBe(Stash.TABS)
	end)

	it("lives in the account save, shared by all heroes", function()
		local account = Profile.freshAccount()
		expect(#account.stash.tabs).toBe(Stash.TABS)
		account.characters[1].inventory = { item("dup") }
		account.stash.tabs[1] = { item("dup"), item("kept") }
		local again = Profile.reconcileAccount(account)
		expect(count(again.stash, "dup")).toBe(0)
		expect(count(again.stash, "kept")).toBe(1)
		expect(#again.characters[1].inventory).toBe(1)
		-- an old save without the field gets an empty stash
		local old = Profile.migrate({ v = Profile.VERSION, data = { characters = {} } })
		expect(#old.data.stash.tabs).toBe(Stash.TABS)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function client(fn)
	sim:runAs("client", function(req)
		fn(req("ReplicatedStorage.Shared.Net"))
	end)
	sim:run(0.4)
end

local function where(id)
	return server(function(req, player)
		local Data = req("ServerScriptService.Server.Systems.Data")
		local inBag = 0
		for _, it in Data.get(player).inventory do
			if it.id == id then
				inBag += 1
			end
		end
		return inBag, count(Data.account(player).stash, id)
	end)
end

local function cells(name)
	local n = 0
	local gui = sim.player.PlayerGui:FindFirstChild("LootRushStash")
	if gui then
		for _, d in gui:GetDescendants() do
			if d.Name == name and d:IsA("GuiButton") then
				n += 1
			end
		end
	end
	return n
end

describe("Stash server and window", function()
	local ids = {}

	it("refuses moves away from the stash station", function()
		sim:boot({ seconds = 2 })
		client(function(Net)
			Net.Character:FireServer("setup", "Stash Hero", "mage")
		end)
		sim:run(1)
		server(function(req, player)
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local rng = Random.new(3)
			for i = 1, 3 do
				local it = Items.roll(2, rng)
				ids[i] = it.id
				Inventory.add(player, it)
			end
			-- far from the stash (spawn is on the other side of the plaza)
			req("ServerScriptService.Server.Systems.Movement").teleported(player)
			player.Character:PivotTo(CFrame.new(req("ReplicatedStorage.Shared.Config").HUB_POS))
		end)
		sim:run(0.5)
		client(function(Net)
			Net.Stash:FireServer("put", ids[1], 1)
		end)
		local bag, stored = where(ids[1])
		expect(bag).toBe(1)
		expect(stored).toBe(0)
	end)

	it("moves items at the station and the window shows both sides", function()
		server(function(req, player)
			local station = workspace.Lumenhaven:FindFirstChild("Station_Stash", true)
			req("ServerScriptService.Server.Systems.Movement").teleported(player)
			player.Character:PivotTo(CFrame.new(station.Position + Vector3.new(0, 0, 4)))
		end)
		sim:run(0.5)
		sim:runAs("client", function(req)
			req(
				"Players." .. sim.player.Name .. ".PlayerScripts.Client.Controllers.StashController"
			).open()
		end)
		sim:run(0.6)
		expect(sim.player.PlayerGui.LootRushStash.Enabled).toBe(true)
		expect(cells("BagItem")).toBe(3)
		expect(cells("StashItem")).toBe(0)

		-- the same item twice in a row (double tap, lag, exploit): stored once
		client(function(Net)
			Net.Stash:FireServer("put", ids[1], 2)
			Net.Stash:FireServer("put", ids[1], 1)
		end)
		local bag, stored = where(ids[1])
		expect(bag).toBe(0)
		expect(stored).toBe(1)
		expect(cells("BagItem")).toBe(2)

		-- junk arguments do nothing
		client(function(Net)
			Net.Stash:FireServer("put", ids[2], 0 / 0)
			Net.Stash:FireServer("put", ids[2], 99)
			Net.Stash:FireServer("put", { ids[2] }, 1)
			Net.Stash:FireServer("take", "not-an-item")
			Net.Stash:FireServer("dupe", ids[2])
		end)
		bag, stored = where(ids[2])
		expect(bag).toBe(1)
		expect(stored).toBe(0)

		-- back to the bag, then everything into tab 1
		client(function(Net)
			Net.Stash:FireServer("take", ids[1])
			Net.Stash:FireServer("take", ids[1])
		end)
		bag, stored = where(ids[1])
		expect(bag).toBe(1)
		expect(stored).toBe(0)
		client(function(Net)
			Net.Stash:FireServer("all", 1)
		end)
		for _, id in ids do
			bag, stored = where(id)
			expect(bag).toBe(0)
			expect(stored).toBe(1)
		end
		expect(cells("BagItem")).toBe(0)
		expect(cells("StashItem")).toBe(3)
	end)

	it("fits phone and tablet (touch)", function()
		local strict = {
			offscreen = true,
			["text-small"] = true,
			["touch-target"] = true,
			topbar = true,
			overlap = true,
			["text-covered"] = true,
			["text-overlap"] = true,
			["text-outside"] = true,
			["scroll-cut"] = true,
			unlabeled = true,
			["empty-row"] = true,
		}
		for _, size in { Vector2.new(844, 390), Vector2.new(1024, 768) } do
			local found = {}
			for _, f in layoutCheck(size, true) do
				if strict[f.kind] and string.find(f.path or "", "LootRushStash", 1, true) then
					table.insert(found, f.kind .. " " .. tostring(f.path))
				end
			end
			expect(table.concat(found, "\n")).toBe("")
		end
	end)

	it("closes the window when the hero walks away", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Movement").teleported(player)
			player.Character:PivotTo(CFrame.new(req("ReplicatedStorage.Shared.Config").HUB_POS))
		end)
		sim:run(1.5)
		expect(sim.player.PlayerGui.LootRushStash.Enabled).toBe(false)
	end)
end)

-- Twink guard: gear an over-levelled hero stored in the shared stash needs the level first
describe("Item level requirement", function()
	it("needs item level minus the grace, at least level 1", function()
		local Balance = require("ReplicatedStorage.Shared.Balance")
		local grace = Balance.P.equip_level_grace
		local low = item("low")
		low.ilvl = 1
		expect(Items.requiredLevel(low)).toBe(1)
		local deep = item("deep")
		deep.ilvl = 31
		expect(Items.requiredLevel(deep)).toBe(31 - grace)
		expect(Items.canWear(deep, 31 - grace - 1)).toBe(false)
		expect(Items.canWear(deep, 31 - grace)).toBe(true)
		local broken = item("nan")
		broken.ilvl = 0 / 0
		expect(Items.requiredLevel(broken)).toBe(1)
		-- an item the hero cannot wear yet gets no upgrade marker
		local marks = Items.upgradeMarks({ deep }, {}, 5)
		expect(marks.deep).toBeNil()
		expect(Items.upgradeMarks({ deep }, {})["deep"]).toBe("up")
	end)

	local function stat(name)
		return server(function(_, player)
			return player:GetAttribute(name)
		end)
	end

	it("a low hero cannot equip, and worn over-level gear gives nothing until the level", function()
		local id = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			req("ServerScriptService.Server.Systems.Combat").setLevel(player, 2, 0)
			local profile = Data.get(player)
			profile.equipped = {}
			local big = {
				id = "twink-ring",
				slot = "ring",
				rarity = "rare",
				name = "Twink Ring",
				ilvl = 40,
				affixes = { { stat = "damage", value = 500 } },
			}
			req("ServerScriptService.Server.Systems.Inventory").add(player, big)
			req("ServerScriptService.Server.Systems.Stats").refresh(player, false)
			return big.id
		end)
		local before = stat("StatDamage")
		client(function(Net)
			Net.Equip:FireServer(id)
		end)
		local worn = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).equipped.ring
		end)
		expect(worn).toBeNil()
		-- worn anyway (a save from before the rule): no stats until level 37
		server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			local profile = Data.get(player)
			profile.equipped.ring = table.remove(profile.inventory, #profile.inventory)
			req("ServerScriptService.Server.Systems.Stats").refresh(player, false)
		end)
		expect(stat("StatDamage")).toBe(before)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").setLevel(player, 37, 0)
		end)
		sim:run(0.3)
		expect(stat("StatDamage")).toBe(before + 500)
	end)
end)
