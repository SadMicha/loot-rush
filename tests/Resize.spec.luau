-- The window can open small and be resized later (PC): after a shrink and a grow back, every text
-- must have its original size again (the minimum-text rule enlarges text at small scales and must
-- release it when the screen grows).
local DESKTOP = Vector2.new(1600, 900)
local SMALL = Vector2.new(560, 320)
local TINY = Vector2.new(240, 140)

local function snapshot()
	local out: { [string]: number } = {}
	for _, d in sim.player.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			out[d:GetFullName()] = (d :: any).TextSize
		end
	end
	return out
end

local function openWindow(buttonName: string)
	local button = nil
	for _, d in sim.player.PlayerGui.LootRushHUD:GetDescendants() do
		if d:IsA("GuiButton") and d.Name == buttonName then
			button = d
		end
	end
	expect(button).never.toBeNil()
	sim:click(button)
	sim:run(0.5)
end

describe("Window resize", function()
	it("text returns to its size after shrinking and growing the window", function()
		sim:setViewport(DESKTOP, false)
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
		end)
		sim:run(1)
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			player:SetAttribute("Level", 5)
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local Items = req("ReplicatedStorage.Shared.Items")
			for i = 1, 12 do
				Inventory.add(player, Items.roll(1 + i % 12, Random.new(100 + i)))
			end
		end)
		sim:run(0.5)

		-- windows open and built at the big size
		for _, name in { "skills", "forge" } do
			openWindow(name)
		end
		sim:run(3)
		local before = snapshot()

		-- close them, so the resize happens while the windows are off (their guis are not laid out)
		for _, name in { "skills", "forge" } do
			openWindow(name)
		end
		-- a tiny window: the minimum-text rule must never ask for more than Roblox accepts (it clamps
		-- TextSize to 100, and the clamped value then became the text's design size for good)
		sim:setViewport(TINY, false)
		sim:run(1)
		for path, size in snapshot() do
			if size > 100 then
				error(path .. " asks for TextSize " .. size, 2)
			end
		end
		sim:setViewport(SMALL, false)
		sim:run(1)
		sim:setViewport(DESKTOP, false)
		sim:run(1)
		for _, name in { "skills", "forge" } do
			openWindow(name)
		end
		sim:run(1)
		local after = snapshot()

		local bad = {}
		for path, size in before do
			local now = after[path]
			if now ~= nil and now > size + 0.5 then
				table.insert(bad, string.format("%s: %d -> %d", path, size, now))
			end
		end
		table.sort(bad)
		if #bad > 0 then
			error(
				string.format(
					"%d texts stayed bigger:\n%s",
					#bad,
					table.concat(bad, "\n", 1, math.min(#bad, 15))
				),
				2
			)
		end
	end)
end)
