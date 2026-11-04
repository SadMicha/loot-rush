-- Comparison in the inventory: stat deltas only if something is equipped in the same slot.
local function selectedColumn(inv)
	for _, d in inv:GetDescendants() do
		if d.Name == "Selected" and d:FindFirstAncestor("Compare") then
			return d
		end
	end
	return nil
end

local function texts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and d.Text ~= "" then
			out[d.Text] = (out[d.Text] or 0) + 1
		end
	end
	return out
end

local function deltas(root)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == "Delta" then
			n += 1
		end
	end
	return n
end

-- Item cells in the bag grid (empty cells are not named "Item")
local function gridButtons(inv)
	local out = {}
	for _, d in inv:GetDescendants() do
		if
			d:IsA("GuiButton")
			and d.Name == "Item"
			and d:FindFirstAncestorWhichIsA("ScrollingFrame")
		then
			table.insert(out, d)
		end
	end
	return out
end

-- Upgrade icon of a bag cell ("up" / "down") or nil; it must hold a real icon image
local function upgradeMark(cell)
	local mark = cell:FindFirstChild("Upgrade")
	if not mark then
		return nil
	end
	expect(mark:FindFirstChildWhichIsA("TextLabel", true)).toBeNil()
	expect(mark:FindFirstChildWhichIsA("ImageLabel", true)).never.toBeNil()
	return mark:GetAttribute("Kind")
end

local function buttonWithText(inv, text)
	for _, d in inv:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == text then
			local b = d:FindFirstAncestorWhichIsA("GuiButton")
			if b then
				return b
			end
		end
	end
	return nil
end

describe("Inventory", function()
	local Items = require("ReplicatedStorage.Shared.Items")
	local first, second

	it("shows an item's stats only once when nothing is equipped", function()
		sim:boot({ seconds = 1 })
		-- finish the first-join hero setup, otherwise its screen keeps coming back over every window
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
		end)
		sim:run(1)
		local rng = Random.new(7)
		first = Items.roll(5, rng)
		while #first.affixes == 0 do
			first = Items.roll(5, rng)
		end
		repeat
			second = Items.roll(5, rng)
		until second.slot == first.slot and #second.affixes > 0
		sim:runAs("server", function(req)
			req("ServerScriptService.Server.Systems.Inventory").add(sim.player, first)
		end)
		sim:run(0.5)

		local inv = sim.player.PlayerGui.LootRushInventory
		inv.Enabled = true
		local grid = gridButtons(inv)
		expect(#grid).toBeGreaterThan(0)
		-- Empty slot: the bag cell already says "upgrade", and the header counts it
		expect(upgradeMark(grid[1])).toBe("up")
		expect(texts(inv)["1 Upgrade"]).toBe(1)
		sim:click(grid[1])
		sim:run(0.2)

		local column = selectedColumn(inv)
		expect(column).never.toBeNil()
		local seen = texts(column)
		expect(seen[first.name]).toBe(1)
		expect(seen.NEW).toBe(1) -- nothing equipped: no percentage against an old piece
		expect(deltas(inv)).toBe(0)
	end)

	it("compares with the equipped item", function()
		local inv = sim.player.PlayerGui.LootRushInventory
		local equip = buttonWithText(inv, "Equip")
		expect(equip).never.toBeNil()
		sim:click(equip)
		sim:run(0.5)

		sim:runAs("server", function(req)
			req("ServerScriptService.Server.Systems.Inventory").add(sim.player, second)
		end)
		sim:run(0.5)
		local grid = gridButtons(inv)
		expect(#grid).toBe(1)
		-- The cell marker follows the drop label rule against the worn piece
		local up = Items.isUpgrade(second, first)
		expect(upgradeMark(grid[1])).toBe(if up then "up" else "down")
		local chip = inv:FindFirstChild("Upgrades", true)
		expect(chip).never.toBeNil()
		expect(chip.Visible).toBe(up)
		sim:click(grid[1])
		sim:run(0.2)
		expect(deltas(inv)).toBeGreaterThan(0)
	end)
end)

describe("Gear slots on the server", function()
	local SYSTEMS = "ServerScriptService.Server.Systems."
	local NEW = {
		boots = { "speed", 2 },
		gloves = { "crit", 1.5 },
		belt = { "life", 9 },
		offhand = { "damage", 4 },
	}
	local ATTR =
		{ speed = "StatSpeed", crit = "StatCrit", life = "StatLife", damage = "StatDamage" }

	local function server(fn)
		local out = {}
		sim:runAs("server", function(req)
			out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
		end)
		return table.unpack(out, 1, out.n)
	end

	local function stats()
		return server(function(_, player)
			local out = {}
			for stat, attr in ATTR do
				out[stat] = player:GetAttribute(attr) or 0
			end
			return out
		end)
	end

	local function equippedIds()
		return server(function(req, player)
			local out = {}
			for slot, item in req(SYSTEMS .. "Data").get(player).equipped do
				out[slot] = item.id
			end
			return out
		end)
	end

	it("equips boots, gloves, belt and offhand and adds their stats", function()
		-- The UI tests above may have equipped a rolled item in one of these slots
		sim:runAs("client", function(req)
			for slot in NEW do
				req("ReplicatedStorage.Shared.Net").Unequip:FireServer(slot)
			end
		end)
		sim:run(0.3)
		local before = stats()
		for slot, s in NEW do
			server(function(req, player)
				req(SYSTEMS .. "Inventory").add(player, {
					id = "test-" .. slot,
					slot = slot,
					rarity = "normal",
					name = slot,
					ilvl = 1,
					affixes = { { stat = s[1], value = s[2], implicit = true } },
				})
			end)
			sim:runAs("client", function(req)
				req("ReplicatedStorage.Shared.Net").Equip:FireServer("test-" .. slot)
			end)
			sim:run(0.3)
		end
		local ids = equippedIds()
		for slot in NEW do
			expect(ids[slot]).toBe("test-" .. slot)
		end
		local after = stats()
		for _, s in NEW do
			expect(math.abs(after[s[1]] - before[s[1]] - s[2]) < 1e-6).toBe(true)
		end
	end)

	it("swaps an item in a new slot and unequips it again", function()
		server(function(req, player)
			req(SYSTEMS .. "Inventory").add(player, {
				id = "test-boots-2",
				slot = "boots",
				rarity = "normal",
				name = "boots",
				ilvl = 1,
				affixes = { { stat = "speed", value = 3, implicit = true } },
			})
		end)
		local before = stats()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Equip:FireServer("test-boots-2")
		end)
		sim:run(0.3)
		expect(equippedIds().boots).toBe("test-boots-2")
		expect(math.abs(stats().speed - before.speed - 1) < 1e-6).toBe(true)
		local inBag = server(function(req, player)
			for _, item in req(SYSTEMS .. "Data").get(player).inventory do
				if item.id == "test-boots" then
					return true
				end
			end
			return false
		end)
		expect(inBag).toBe(true)

		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Unequip:FireServer("boots")
		end)
		sim:run(0.3)
		expect(equippedIds().boots).toBeNil()
		expect(math.abs(stats().speed - before.speed + 2) < 1e-6).toBe(true)
	end)
end)

describe("Full bag", function()
	it("salvages loot that is no upgrade and keeps upgrades on the ground", function()
		local stored, salvaged, full, goldGain, upStored, upFull, count =
			nil, nil, nil, 0, nil, nil, 0
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			local Items = req("ReplicatedStorage.Shared.Items")
			local Data = req("ServerScriptService.Server.Systems.Data")
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local p = Data.get(player)
			p.autoSalvage = ""
			local rng = Random.new(3)
			while #p.inventory < Items.BAG_MAX do
				table.insert(p.inventory, Items.roll(1, rng))
			end
			-- worn weapon far above the loot: a level 1 weapon is no upgrade
			local worn = Items.roll(60, rng, nil, { slot = "weapon" })
			p.equipped.weapon = worn
			local weak = Items.roll(1, rng, nil, { slot = "weapon" })
			local gold0 = p.gold
			stored, salvaged, full = Inventory.add(player, weak, true)
			goldGain = p.gold - gold0
			-- an empty slot: anything is an upgrade there
			p.equipped.boots = nil
			upStored, _, upFull =
				Inventory.add(player, Items.roll(1, rng, nil, { slot = "boots" }), true)
			count = #p.inventory
		end)
		expect(stored).toBe(true)
		expect(salvaged).toBe(true)
		expect(full).toBe(true)
		expect(goldGain).toBeGreaterThan(0)
		expect(upStored).toBe(false)
		expect(upFull).toBe(true)
		expect(count).toBe(require("ReplicatedStorage.Shared.Items").BAG_MAX)
	end)
end)

describe("Fullscreen windows", function()
	local function menuButton(name)
		for _, d in sim.player.PlayerGui.LootRushHUD:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == name then
				return d
			end
		end
		return nil
	end

	it("inventory and Star Web are never open at the same time", function()
		local pg = sim.player.PlayerGui
		sim:runAs("server", function()
			game:GetService("Players"):GetPlayers()[1]:SetAttribute("Level", 5) -- Star Web unlock
		end)
		sim:run(0.5)
		pg.LootRushInventory.Enabled = false
		sim:click(menuButton("inventory"))
		sim:run(0.2)
		expect(pg.LootRushInventory.Enabled).toBe(true)

		sim:click(menuButton("star_net"))
		sim:run(0.2)
		expect(pg.LootRushStarNet.Enabled).toBe(true)
		expect(pg.LootRushInventory.Enabled).toBe(false)

		sim:pressKey(Enum.KeyCode.I)
		sim:run(0.2)
		expect(pg.LootRushInventory.Enabled).toBe(true)
		expect(pg.LootRushStarNet.Enabled).toBe(false)
	end)

	-- Criteria audit #3: red dot on the Inventory button while an upgrade waits in the bag
	it("shows the upgrade dot until the Inventory is opened", function()
		local pg = sim.player.PlayerGui
		local function dotShown(): boolean
			for _, d in pg.LootRushHUD:GetDescendants() do
				if
					d.Name == "Upgrade"
					and d.Parent
					and d.Parent.Name == "inventory"
					and d.Visible
				then
					return true
				end
			end
			return false
		end
		if pg.LootRushInventory.Enabled then
			sim:pressKey(Enum.KeyCode.I)
		end
		sim:runAs("server", function(req)
			local profile = req("ServerScriptService.Server.Systems.Data").get(sim.player)
			profile.equipped.amulet = nil
			profile.inventory = {}
			req("ServerScriptService.Server.Systems.Inventory").add(sim.player, {
				id = "dot-amulet",
				slot = "amulet",
				rarity = "rare",
				name = "Dot Amulet",
				ilvl = 3,
				affixes = { { stat = "crit", value = 2, implicit = true } },
			})
		end)
		sim:run(0.5)
		expect(pg.LootRushInventory.Enabled).toBe(false)
		expect(dotShown()).toBe(true)
		sim:click(menuButton("inventory"))
		sim:run(0.3)
		expect(pg.LootRushInventory.Enabled).toBe(true)
		expect(dotShown()).toBe(false)
	end)
end)

describe("Inventory clicks", function()
	local Theme = require("ReplicatedStorage.Shared.UI.Theme")

	local function cellsById(inv)
		local out = {}
		for _, b in gridButtons(inv) do
			out[b] = true
		end
		return out
	end

	local function dollSlots(inv)
		local out = {}
		for _, d in inv:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "Slot" then
				out[d] = true
			end
		end
		return out
	end

	local function sameSet(a, b)
		for k in a do
			if not b[k] then
				return false
			end
		end
		for k in b do
			if not a[k] then
				return false
			end
		end
		return true
	end

	local function amulet(id, crit)
		return {
			id = id,
			slot = "amulet",
			rarity = "epic",
			name = id,
			ilvl = 3,
			affixes = { { stat = "crit", value = crit, implicit = true } },
		}
	end

	it("selecting an item keeps every cell and its light sweep (no rebuild)", function()
		local pg = sim.player.PlayerGui
		local inv = pg.LootRushInventory
		sim:runAs("server", function(req)
			local profile = req("ServerScriptService.Server.Systems.Data").get(sim.player)
			profile.equipped.amulet = nil
			profile.inventory = {}
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			Inventory.add(sim.player, amulet("amu-good", 3))
			Inventory.add(sim.player, amulet("amu-best", 6))
			Inventory.add(sim.player, amulet("amu-low", 1))
		end)
		sim:run(0.5)
		inv.Enabled = true
		sim:run(0.2)
		local before = cellsById(inv)
		local doll = dollSlots(inv)
		local grid = gridButtons(inv)
		expect(#grid).toBe(3)
		-- epic cells carry a light sweep band; remember the instances
		local shines = {}
		for _, b in grid do
			local s = b:FindFirstChild("Shine")
			expect(s).never.toBeNil()
			shines[b] = s
		end
		-- empty amulet slot: only the best amulet is marked as the upgrade
		local ups = 0
		for _, b in grid do
			if upgradeMark(b) == "up" then
				ups += 1
			end
		end
		expect(ups).toBe(1)
		expect(texts(inv)["1 Upgrade"]).toBe(1)

		sim:click(grid[2])
		sim:run(0.2)
		sim:click(grid[3])
		sim:run(0.2)
		expect(sameSet(before, cellsById(inv))).toBe(true)
		expect(sameSet(doll, dollSlots(inv))).toBe(true)
		for b, s in shines do
			expect(b:FindFirstChild("Shine")).toBe(s)
		end
		-- the picked cell shows the selection edge in place
		local edge = grid[3]:FindFirstChild("Edge")
		expect(edge.Thickness).toBe(Theme.Flat.SelectStroke)
		expect(grid[2]:FindFirstChild("Edge").Thickness).toBe(Theme.Flat.Stroke)
	end)

	it("after equipping the marked upgrade the other items turn down", function()
		local inv = sim.player.PlayerGui.LootRushInventory
		local best
		for _, b in gridButtons(inv) do
			if upgradeMark(b) == "up" then
				best = b
			end
		end
		expect(best).never.toBeNil()
		sim:click(best)
		sim:run(0.2)
		sim:click(buttonWithText(inv, "Equip"))
		sim:run(0.5)
		local grid = gridButtons(inv)
		expect(#grid).toBe(2)
		for _, b in grid do
			expect(upgradeMark(b)).toBe("down")
		end
		expect(inv:FindFirstChild("Upgrades", true).Visible).toBe(false)
	end)
end)
