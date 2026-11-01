-- Detail view in the inventory: comparison chips only if something is equipped in the same slot.
local function texts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and d.Text ~= "" then
			out[d.Text] = (out[d.Text] or 0) + 1
		end
	end
	return out
end

local function chips(root)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == "Chip" then
			n += 1
		end
	end
	return n
end

local function gridButtons(inv)
	local out = {}
	for _, d in inv:GetDescendants() do
		if d:IsA("ImageButton") and d:FindFirstAncestorWhichIsA("ScrollingFrame") then
			table.insert(out, d)
		end
	end
	return out
end

local function buttonWithText(inv, text)
	for _, d in inv:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == text and d.Parent:IsA("GuiButton") then
			return d.Parent
		end
	end
	return nil
end

describe("Inventory", function()
	local Items = require("ReplicatedStorage.Shared.Items")
	local first, second

	it("shows an item's stats only once when nothing is equipped", function()
		sim:boot({ seconds = 1 })
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

		local seen = texts(inv)
		for _, a in first.affixes do
			expect(seen[Items.affixText(a)]).toBe(1)
		end
		expect(chips(inv)).toBe(0)
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
		expect(chips(inv)).toBeGreaterThan(0)
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
