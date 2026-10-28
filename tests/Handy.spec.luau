-- Handy (844×390, Touch): nichts ragt aus dem Bild, Schrift ≥ 9 px, Knöpfe ≥ 32 px.
-- Gleiche Prüfung wie der UI-Check, hier aber als Test, damit Rückschritte auffallen.
local HANDY = Vector2.new(844, 390)
local DESKTOP = Vector2.new(1920, 1080)
local STRICT = { offscreen = true, ["text-small"] = true, ["touch-target"] = true }

local function problems(where)
	local out = {}
	for _, f in layoutCheck(HANDY, true) do
		if STRICT[f.kind] then
			table.insert(out, string.format("%s: [%s] %s %s", where, f.kind, f.path, f.message))
		end
	end
	layoutCheck(DESKTOP, false)
	return out
end

local function expectClean(list)
	if #list > 0 then
		error(table.concat(list, "\n"), 2)
	end
end

describe("Handy-Layout", function()
	it("HUD", function()
		sim:boot({ seconds = 2 })
		expectClean(problems("HUD"))
	end)

	it("Inventar", function()
		local inv = sim.player.PlayerGui.LootRushInventory
		inv.Enabled = true
		sim:run(0.2)
		expectClean(problems("Inventar"))
		inv.Enabled = false
	end)

	-- Fenster wie ein Spieler über das Menü links öffnen (baut den Inhalt erst beim Öffnen)
	for _, entry in
		{
			{ "skills", "Abilities" },
			{ "sternennetz", "StarNet" },
			{ "schmiede", "Forge" },
			{ "atlas", "Atlas" },
		}
	do
		it("Fenster " .. entry[2], function()
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
end)
