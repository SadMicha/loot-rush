-- Handy (844×390) und Tablet (1024×768), Touch: nichts ragt aus dem Bild, Schrift ≥ 9 px, Knöpfe ≥ 32 px,
-- nichts unter der Roblox-Topbar, kein Text hinter Icons/Knöpfen oder auf anderem Text, kein Text
-- über den Panelrand, keine leeren Zeilen/Kapseln, gleiche Schließen-Knöpfe in allen Fenstern.
-- Gleiche Prüfung wie der UI-Check, hier aber als Test, damit Rückschritte auffallen.
local HANDY = Vector2.new(844, 390)
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

-- Bekannte, noch offene Befunde auf main (Stand nach PR #23/#24). Nach dem Beheben Eintrag löschen;
-- neue Einträge nur mit Grund. Inventar: Titel „Ausrüstung“ unter der Topbar. Fähigkeiten: Werte-Zeile
-- läuft unter das Tasten-Kästchen. Schmiede: Affix-Zeilen-Knöpfe auf Handy 22 px hoch.
-- Atlas: Mod-/Boss-Texte ragen aus ihrer Kapsel.
local KNOWN: { [string]: { [string]: boolean } } = {
	Inventar = { topbar = true },
	Abilities = { ["text-overlap"] = true, ["text-outside"] = true },
	Forge = { ["touch-target"] = true },
	Atlas = { ["text-covered"] = true, ["text-outside"] = true },
}

local closeLooks = {}

local function problems(where)
	local out = {}
	local known = KNOWN[where] or {}
	for _, size in { HANDY, TABLET } do
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

describe("Handy-Layout", function()
	it("HUD", function()
		sim:boot({ seconds = 2 })
		-- Gegenstände und Material, damit Schmiede & Co. echte Inhalte zeigen
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local Items = req("ReplicatedStorage.Shared.Items")
			for i = 1, 12 do
				Inventory.add(player, Items.roll(1 + i % 12, Random.new(100 + i)))
			end
		end)
		sim:run(0.5)
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

	it("Schließen-Knöpfe sehen überall gleich aus", function()
		expect(#closeLooks).toBeGreaterThan(0)
		local list = {}
		for _, f in compareClose(closeLooks) do
			table.insert(list, f.path .. " " .. f.message)
		end
		expectClean(list)
	end)
end)
