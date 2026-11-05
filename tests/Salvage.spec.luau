--!nocheck
-- Stash/bag quality of life (Shared/Salvage, Systems/Inventory, Client/InventoryController):
-- item lock, auto-salvage with "keep upgrades", bulk "Salvage all downgrades", red arrows only on
-- the picked item.
local Forge = require("ReplicatedStorage.Shared.Forge")
local Items = require("ReplicatedStorage.Shared.Items")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Salvage = require("ReplicatedStorage.Shared.Salvage")
local Stash = require("ReplicatedStorage.Shared.Stash")
local Upgrade = require("ReplicatedStorage.Shared.Upgrade")

local function item(id, slot, rarity, value, extra)
	local it = {
		id = id,
		slot = slot or "ring",
		rarity = rarity or "magic",
		name = "Item " .. id,
		ilvl = 3,
		affixes = { { stat = "damage", value = value or 1 } },
		class = "mage",
	}
	for k, v in extra or {} do
		it[k] = v
	end
	return it
end

-- Level 10 mage wearing a strong ring (damage 10)
local function hero()
	return Upgrade.hero({ ring = item("worn", "ring", "rare", 10) }, 10, "mage")
end

describe("Salvage rules", function()
	it("protects locked items and uniques from bulk and auto salvage", function()
		expect(Salvage.isLocked(item("a"))).toBe(false)
		expect(Salvage.isLocked(item("a", nil, nil, nil, { locked = true }))).toBe(true)
		expect(Salvage.canSalvage(item("a", nil, nil, nil, { locked = true }))).toBe(false)
		expect(Salvage.canSalvage(item("u", nil, "unique"))).toBe(true) -- by hand: still possible
		expect(Salvage.protected(item("u", nil, "unique"))).toBe(true)
		expect(Salvage.protected(item("a"))).toBe(false)
	end)

	it("auto-salvages up to the limit and keeps upgrades while asked to", function()
		local h = hero()
		local weak = item("w", "ring", "magic", 1)
		local strong = item("s", "ring", "magic", 50)
		expect(Upgrade.isUpgrade(h, strong)).toBe(true)
		expect(Salvage.auto("magic", true, weak, h)).toBe(true)
		expect(Salvage.auto("magic", true, strong, h)).toBe(false) -- an upgrade is kept
		expect(Salvage.auto("magic", false, strong, h)).toBe(true)
		expect(Salvage.auto("normal", true, weak, h)).toBe(false) -- above the limit
		expect(Salvage.auto("", true, weak, h)).toBe(false) -- off
		expect(Salvage.auto("epic", false, item("u", "ring", "unique"), h)).toBe(false)
		expect(Salvage.auto("epic", false, item("l", "ring", "normal", 1, { locked = true }), h)).toBe(
			false
		)
	end)

	it("knows valid limits", function()
		for _, v in Salvage.AUTO_LIMITS do
			expect(Salvage.validLimit(v)).toBe(true)
		end
		expect(Salvage.validLimit("unique")).toBe(false)
		expect(Salvage.validLimit("bogus")).toBe(false)
		expect(Salvage.validLimit(3)).toBe(false)
	end)

	it("lists downgrades like the red arrow, never locked, unique or unwearable items", function()
		local h = hero()
		local bag = {
			item("down", "ring", "magic", 1),
			item("up", "ring", "magic", 50),
			item("locked", "ring", "magic", 1, { locked = true }),
			item("unique", "ring", "unique", 1),
			item("other", "ring", "magic", 1, { class = "warrior" }), -- another class
			item("high", "ring", "magic", 1, { ilvl = 80 }), -- above the hero's level
		}
		local list = Salvage.downgrades(bag, h)
		expect(#list).toBe(1)
		expect(list[1].id).toBe("down")
		local marks = Upgrade.marks(bag, h)
		expect(marks.down).toBe("down")
	end)

	it("adds up the expected yield", function()
		local y = Salvage.expected({ item("a", nil, "rare"), item("b", nil, "epic") }, 10)
		expect(y.count).toBe(2)
		expect(y.gold).toBe(
			Items.sellValue(item("a", nil, "rare")) + Items.sellValue(item("b", nil, "epic"))
		)
		expect(y.shards).toBe(
			math.floor(Items.Salvage.rare.shards * 1.1 + 0.5)
				+ math.floor(Items.Salvage.epic.shards * 1.1 + 0.5)
		)
		expect(math.abs(y.candy - 1.1) < 1e-9).toBe(true)
		expect(math.abs(y.dust - 0.15) < 1e-9).toBe(true)
		expect(Salvage.expected({}, 0 / 0).count).toBe(0)
	end)

	it("accepts only clean id lists", function()
		expect(#Salvage.validIds({ "a", "b", "a" })).toBe(2)
		expect(Salvage.validIds({})).toBeNil()
		expect(Salvage.validIds("a")).toBeNil()
		expect(Salvage.validIds({ "a", 5 })).toBeNil()
		expect(Salvage.validIds({ "a", x = "b" })).toBeNil()
		expect(Salvage.validIds({ string.rep("x", 65) })).toBeNil()
		local many = {}
		for i = 1, Salvage.MAX_BULK + 1 do
			many[i] = tostring(i)
		end
		expect(Salvage.validIds(many)).toBeNil()
	end)

	it("shows the red arrow only on the picked item or while salvaging", function()
		expect(Upgrade.shownMark("up", false)).toBe("up")
		expect(Upgrade.shownMark("side", false)).toBe("side")
		expect(Upgrade.shownMark("down", false)).toBeNil()
		expect(Upgrade.shownMark("down", true)).toBe("down")
		expect(Upgrade.shownMark("down", false, true)).toBe("down")
		expect(Upgrade.shownMark(nil, true)).toBeNil()
	end)

	it("never fuses a locked duplicate", function()
		local u = Items.UniqueById[next(Items.UniqueById)]
		local a = Items.makeUnique(u, 10, Random.new(1), "mage")
		local b = Items.makeUnique(u, 10, Random.new(2), "mage")
		expect(Forge.duplicateOf(a, { a, b })).toBe(b)
		b.locked = true
		expect(Forge.duplicateOf(a, { a, b })).toBeNil()
	end)
end)

describe("Salvage save fields", function()
	it("loads old saves with keep upgrades on and cleans lock flags", function()
		local old = Profile.reconcile({
			autoSalvage = "rare",
			inventory = {
				item("a", nil, nil, nil, { locked = "yes" }),
				item("b", nil, nil, nil, { locked = true }),
			},
			equipped = { ring = item("c", nil, nil, nil, { locked = 1 }) },
		})
		expect(old.autoSalvage).toBe("rare")
		expect(old.autoKeep).toBe(true)
		expect(old.inventory[1].locked).toBeNil()
		expect(old.inventory[2].locked).toBe(true)
		expect(old.equipped.ring.locked).toBeNil()
		expect(Profile.reconcile({ autoKeep = false }).autoKeep).toBe(false)
		expect(Profile.reconcile({ autoKeep = "no" }).autoKeep).toBe(true)
		expect(Profile.reconcile({ autoSalvage = "epic" }).autoSalvage).toBe("epic")
	end)

	it("keeps the lock on items in the stash", function()
		local data = Stash.reconcile({
			tabs = {
				{
					item("a", nil, nil, nil, { locked = true }),
					item("b", nil, nil, nil, { locked = 0 }),
				},
			},
		})
		expect(data.tabs[1][1].locked).toBe(true)
		expect(data.tabs[1][2].locked).toBeNil()
	end)
end)

local SYSTEMS = "ServerScriptService.Server.Systems."

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
	sim:run(0.5)
end

local function bagIds()
	return server(function(req, player)
		local out = {}
		for _, it in req(SYSTEMS .. "Data").get(player).inventory do
			out[it.id] = it.locked == true
		end
		return out
	end)
end

describe("Salvage on the server", function()
	it("locks an item and refuses to salvage it", function()
		sim:boot({ seconds = 1 })
		client(function(Net)
			Net.Character:FireServer("setup", "Salvage Hero", "mage")
		end)
		server(function(req, player)
			req(SYSTEMS .. "Combat").setLevel(player, 10, 0)
			local p = req(SYSTEMS .. "Data").get(player)
			p.class = "mage"
			table.clear(p.inventory)
			p.equipped = { ring = item("worn", "ring", "rare", 10) }
			req(SYSTEMS .. "Stats").refresh(player, true)
			local Inventory = req(SYSTEMS .. "Inventory")
			Inventory.add(player, item("keep", "ring", "magic", 1))
			Inventory.add(player, item("junk1", "ring", "magic", 1))
			Inventory.add(player, item("junk2", "ring", "normal", 1))
			Inventory.add(player, item("better", "ring", "magic", 50))
			Inventory.add(player, item("uniq", "ring", "unique", 1))
		end)
		client(function(Net)
			Net.ItemLock:FireServer("keep", true)
			Net.ItemLock:FireServer("nope", true)
			Net.ItemLock:FireServer("junk1", "yes")
		end)
		local ids = bagIds()
		expect(ids.keep).toBe(true)
		expect(ids.junk1).toBe(false)
		client(function(Net)
			Net.Sell:FireServer("keep")
		end)
		expect(bagIds().keep).toBe(true) -- still there
	end)

	it("bulk-salvages only downgrades the player may lose", function()
		local gold0 = server(function(req, player)
			return req(SYSTEMS .. "Data").get(player).gold
		end)
		client(function(Net)
			-- a forged list: locked, unique, upgrade and unknown ids are ignored
			Net.SalvageMany:FireServer({ "keep", "junk1", "junk2", "better", "uniq", "ghost" })
		end)
		local ids = bagIds()
		expect(ids.junk1).toBeNil()
		expect(ids.junk2).toBeNil()
		expect(ids.keep).toBe(true)
		expect(ids.better).toBe(false)
		expect(ids.uniq).toBe(false)
		local gold1 = server(function(req, player)
			return req(SYSTEMS .. "Data").get(player).gold
		end)
		expect(gold1).toBeGreaterThan(gold0)
		client(function(Net)
			Net.SalvageMany:FireServer("junk")
			Net.SalvageMany:FireServer({ 1, 2 })
		end)
		expect(bagIds().keep).toBe(true)
	end)

	it("auto-salvage keeps upgrades unless turned off", function()
		client(function(Net)
			Net.AutoSalvage:FireServer("magic", true)
		end)
		local keptUp, junkGone, setting, keepAttr = server(function(req, player)
			local Inventory = req(SYSTEMS .. "Inventory")
			local _, a = Inventory.add(player, item("up2", "ring", "magic", 60), true)
			local _, b = Inventory.add(player, item("junk3", "ring", "magic", 1), true)
			local p = req(SYSTEMS .. "Data").get(player)
			return not a, b, p.autoKeep, player:GetAttribute("AutoKeep")
		end)
		expect(keptUp).toBe(true)
		expect(junkGone).toBe(true)
		expect(setting).toBe(true)
		expect(keepAttr).toBe(true)
		sim:run(0.6) -- rate limit of the setting
		client(function(Net)
			Net.AutoSalvage:FireServer("magic", false)
		end)
		local salvaged = server(function(req, player)
			local _, s =
				req(SYSTEMS .. "Inventory").add(player, item("up3", "ring", "magic", 60), true)
			return s
		end)
		expect(salvaged).toBe(true)
		sim:run(0.6)
		client(function(Net)
			Net.AutoSalvage:FireServer("magic", "maybe") -- invalid: nothing changes
		end)
		expect(server(function(req, player)
			return req(SYSTEMS .. "Data").get(player).autoKeep
		end)).toBe(false)
	end)
end)

describe("Salvage in the bag window", function()
	local function cell(inv, name)
		for _, d in inv:GetDescendants() do
			if
				d:IsA("GuiButton")
				and d.Name == "Item"
				and d:FindFirstAncestorWhichIsA("ScrollingFrame")
			then
				local label = d:FindFirstChild("Keep")
				if name == "locked" and label then
					return d
				end
			end
		end
		return nil
	end

	local function find(inv, name)
		return inv:FindFirstChild(name, true)
	end

	it("shows the lock badge and opens the confirm dialog with count and yield", function()
		server(function(req, player)
			req(SYSTEMS .. "Inventory").add(player, item("junk4", "ring", "magic", 1))
		end)
		local inv = sim.player.PlayerGui.LootRushInventory
		inv.Enabled = true
		sim:run(0.3)
		expect(cell(inv, "locked")).never.toBeNil()
		-- salvage mode: the bulk button opens the dialog
		local toggle = find(inv, "Toggle")
		sim:click(toggle)
		sim:run(0.2)
		local down = find(inv, "SalvageDowngrades")
		expect(down).never.toBeNil()
		sim:click(down)
		sim:run(0.3)
		local dialog = find(inv, "Dialog")
		expect(dialog).never.toBeNil()
		local seen = {}
		for _, d in dialog:GetDescendants() do
			if d:IsA("TextLabel") then
				seen[d.Text] = true
			end
		end
		expect(seen["SALVAGE DOWNGRADES"] or seen["Salvage Downgrades"]).toBe(true)
		local count
		for text in seen do
			local n = string.match(text, "^Salvage (%d+)$")
			if n then
				count = tonumber(n)
			end
		end
		expect(count).toBeGreaterThan(0)
		local cancel
		for _, d in dialog:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == "Cancel" then
				cancel = d:FindFirstAncestorWhichIsA("GuiButton")
			end
		end
		sim:click(cancel)
		sim:run(0.2)
		expect(find(inv, "Dialog")).toBeNil()
		expect(bagIds().junk4).toBe(false) -- cancel salvages nothing
		-- again, and confirm: the downgrade goes, the locked item stays
		sim:click(find(inv, "SalvageDowngrades"))
		sim:run(0.3)
		local confirm
		for _, d in find(inv, "Dialog"):GetDescendants() do
			if d:IsA("TextLabel") and string.match(d.Text, "^Salvage %d+$") then
				confirm = d:FindFirstAncestorWhichIsA("GuiButton")
			end
		end
		sim:click(confirm)
		sim:run(0.5)
		expect(find(inv, "Dialog")).toBeNil()
		local ids = bagIds()
		expect(ids.junk4).toBeNil()
		expect(ids.keep).toBe(true)
		sim:click(toggle)
		sim:run(0.2)
		inv.Enabled = false
	end)
end)
