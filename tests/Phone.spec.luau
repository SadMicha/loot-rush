-- Phone (844×390) and tablet (1024×768), touch: nothing sticks out of the screen, font ≥ 9 px, buttons ≥ 32 px,
-- nothing under the Roblox topbar, no text behind icons/buttons or on other text, no text
-- past the panel edge, no empty rows/capsules, identical close buttons in all windows.
-- Same check as the UI check, but as a test here so regressions get noticed.
local PHONE = Vector2.new(844, 390)
local TABLET = Vector2.new(1024, 768)
local DESKTOP = Vector2.new(1920, 1080)
local STRICT = {
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

-- Known, still open findings on main (as of PR #23/#24). Delete the entry once fixed;
-- new entries only with a reason. Inventory: gear title under the topbar. Abilities: stats row
-- runs under the key box. Forge: affix row buttons 22 px high on phones.
-- Atlas: mod/boss texts stick out of their capsule.
local KNOWN: { [string]: { [string]: boolean } } = {
	Inventory = { topbar = true },
	Abilities = { ["text-overlap"] = true, ["text-outside"] = true },
	Forge = { ["touch-target"] = true },
	Atlas = { ["text-covered"] = true, ["text-outside"] = true },
}

local closeLooks = {}

local function problems(where)
	local out = {}
	local known = KNOWN[where] or {}
	for _, size in { PHONE, TABLET } do
		for _, f in layoutCheck(size, true) do
			if STRICT[f.kind] and not known[f.kind] then
				table.insert(
					out,
					string.format(
						"%s %dx%d: [%s] %s %s",
						where,
						size.X,
						size.Y,
						f.kind,
						f.path,
						f.message
					)
				)
			end
		end
	end
	for _, c in closeButtons() do
		c.path = where .. ": " .. c.path
		table.insert(closeLooks, c)
	end
	layoutCheck(DESKTOP, false)
	return out
end

local function expectClean(list)
	if #list > 0 then
		error(table.concat(list, "\n"), 2)
	end
end

describe("Phone layout", function()
	it("HUD", function()
		sim:boot({ seconds = 2 })
		-- finish the first-join hero setup, otherwise its screen keeps coming back over every window
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
		end)
		sim:run(1)
		-- items and materials so the Forge & co. show real content
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			player:SetAttribute("Level", 5) -- unlocks Star Web, Forge, Pets (Shared/Quests)
			player:SetAttribute("BestDepth", 8)
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local Items = req("ReplicatedStorage.Shared.Items")
			for i = 1, 12 do
				Inventory.add(player, Items.roll(1 + i % 12, Random.new(100 + i)))
			end
		end)
		sim:run(0.5)
		expectClean(problems("HUD"))
	end)

	it("Inventory", function()
		local inv = sim.player.PlayerGui.LootRushInventory
		inv.Enabled = true
		sim:run(0.2)
		expectClean(problems("Inventory"))
		inv.Enabled = false
	end)

	-- open windows like a player via the left menu (builds the content only on open)
	for _, entry in
		{
			{ "skills", "Abilities" },
			{ "star_net", "StarNet" },
			{ "forge", "Forge" },
			{ "atlas", "Atlas" },
			{ "Shop_gold", "Shop" }, -- the + on the gold capsule
		}
	do
		it("Window " .. entry[2], function()
			local button = nil
			for _, d in sim.player.PlayerGui.LootRushHUD:GetDescendants() do
				if d:IsA("GuiButton") and d.Name == entry[1] then
					button = d
				end
			end
			expect(button).never.toBeNil()
			sim:click(button)
			sim:run(0.5)
			local gui = sim.player.PlayerGui:FindFirstChild("LootRush" .. entry[2])
			expect(gui.Enabled).toBe(true)
			expectClean(problems(entry[2]))
		end)
	end

	it("close buttons look the same everywhere", function()
		expect(#closeLooks).toBeGreaterThan(0)
		local list = {}
		for _, f in compareClose(closeLooks) do
			table.insert(list, f.path .. " " .. f.message)
		end
		expectClean(list)
	end)
end)
