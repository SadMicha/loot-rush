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

describe("Fullscreen windows", function()
	local function menuButton(name)
		for _, d in sim.player.PlayerGui.LootRushHUD:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == name then
				return d
			end
		end
		return nil
	end

	it("inventory and Star Net are never open at the same time", function()
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
end)
