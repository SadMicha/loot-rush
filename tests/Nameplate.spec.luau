-- Overhead nameplates + floating station labels (Shared/Nameplate, Client/NameplateController).
local Nameplate = require("ReplicatedStorage.Shared.Nameplate")

describe("Nameplate rules", function()
	it("fades player plates out towards the far range", function()
		expect(Nameplate.playerAlpha(0)).toBe(1)
		expect(Nameplate.playerAlpha(Nameplate.PLAYER_FAR - Nameplate.PLAYER_FADE)).toBe(1)
		local mid = Nameplate.playerAlpha(Nameplate.PLAYER_FAR - Nameplate.PLAYER_FADE / 2)
		expect(mid > 0.4 and mid < 0.6).toBe(true)
		expect(Nameplate.playerAlpha(Nameplate.PLAYER_FAR)).toBe(0)
		expect(Nameplate.playerAlpha(0 / 0)).toBe(0)
		expect(Nameplate.playerAlpha(-1)).toBe(0)
		expect(Nameplate.playerAlpha(math.huge)).toBe(0)
	end)

	it("hides station labels at the prompt and far away", function()
		expect(Nameplate.labelAlpha(0)).toBe(0)
		expect(Nameplate.labelAlpha(Nameplate.LABEL_NEAR)).toBe(0)
		expect(Nameplate.labelAlpha(Nameplate.LABEL_NEAR + Nameplate.LABEL_NEAR_FADE)).toBe(1)
		expect(Nameplate.labelAlpha(40)).toBe(1)
		expect(Nameplate.labelAlpha(Nameplate.LABEL_FAR)).toBe(0)
		-- the label is gone before the ProximityPrompt (12 studs) shows the same name
		expect(Nameplate.LABEL_NEAR <= 12).toBe(true)
	end)

	it("declutters station labels on the screen", function()
		local a = { 0, 0, 100, 20 }
		local b = { 50, 10, 150, 30 } -- overlaps a
		local c = { 300, 0, 400, 20 } -- free
		local d = { 600, 0, 700, 20 } -- under a HUD block
		local shown = Nameplate.declutter({ a, b, c, d, false }, { 1, 5, 0, 9, 99 }, {
			{ 650, 0, 800, 100 },
		}, 4)
		expect(shown[2]).toBe(true) -- higher priority wins the overlap
		expect(shown[1]).toBe(false)
		expect(shown[3]).toBe(true)
		expect(shown[4]).toBe(false)
		expect(shown[5]).toBe(false) -- behind the camera
		-- the gap counts: rectangles 3 px apart collide with a 4 px gap
		local near = Nameplate.declutter({ { 0, 0, 10, 10 }, { 13, 0, 20, 10 } }, { 2, 1 }, {}, 4)
		expect(near[1]).toBe(true)
		expect(near[2]).toBe(false)
	end)

	it("shows the locked line only up close", function()
		expect(Nameplate.subAlpha(10)).toBe(1)
		expect(Nameplate.subAlpha(Nameplate.SUB_FAR)).toBe(0)
		expect(Nameplate.lockText("Clear depth 5")).toBe("Locked · Clear depth 5")
	end)

	it("fills bars safely", function()
		expect(Nameplate.fill(50, 100)).toBe(0.5)
		expect(Nameplate.fill(150, 100)).toBe(1)
		expect(Nameplate.fill(-5, 100)).toBe(0)
		expect(Nameplate.fill(10, 0)).toBe(0)
		expect(Nameplate.fill(0 / 0, 100)).toBe(0)
		expect(Nameplate.fill(nil, 100)).toBe(0)
		expect(Nameplate.fill("5", 100)).toBe(0)
	end)

	it("shows the hero name, else the display name", function()
		expect(Nameplate.displayName("Brix", "Roblox")).toBe("Brix")
		expect(Nameplate.displayName("  Brix ", "Roblox")).toBe("Brix")
		expect(Nameplate.displayName("", "Roblox")).toBe("Roblox")
		expect(Nameplate.displayName(nil, "Roblox")).toBe("Roblox")
		expect(Nameplate.displayName(42, "Roblox")).toBe("Roblox")
		expect(Nameplate.displayName("\255\254", "Roblox")).toBe("Roblox")
		expect(#Nameplate.displayName(string.rep("a", 40), "x")).toBe(Nameplate.NAME_MAX)
		expect(Nameplate.levelText(12.7)).toBe("12")
		expect(Nameplate.levelText(nil)).toBe("")
		expect(Nameplate.levelText(0)).toBe("")
	end)

	it("shows the own bar only while hurt or shielded", function()
		expect(Nameplate.showOwnBar(100, 100, 0)).toBe(false)
		expect(Nameplate.showOwnBar(60, 100, 0)).toBe(true)
		expect(Nameplate.showOwnBar(100, 100, 20)).toBe(true)
	end)

	it("reads the station window", function()
		local p = Instance.new("Part")
		p.Name = "Station_Inventory"
		expect(Nameplate.windowOf(p)).toBe("Inventory")
		p:SetAttribute(Nameplate.WINDOW_ATTR, "Atlas")
		expect(Nameplate.windowOf(p)).toBe("Atlas")
		p:Destroy()
		expect(Nameplate.windowOf(Instance.new("Part"))).toBeNil()
	end)
end)

describe("Nameplates in game", function()
	it("hides the Roblox overlay, labels the stations and draws plates", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer(
				"setup",
				"Plate Hero",
				"ranger"
			)
		end)
		sim:run(2)

		local character = sim.player.Character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		expect(humanoid.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.None)
		expect(humanoid.HealthDisplayType).toBe(Enum.HumanoidHealthDisplayType.AlwaysOff)
		expect(sim.player:GetAttribute("CharacterName")).toBe("Plate Hero")

		-- every hub station is tagged with a label, and the client floats it
		local CollectionService = game:GetService("CollectionService")
		local seen = {}
		for _, part in CollectionService:GetTagged(Nameplate.STATION_TAG) do
			local title = part:GetAttribute(Nameplate.LABEL_ATTR)
			expect(typeof(title)).toBe("string")
			seen[title] = true
			local gui = part:FindFirstChild("StationLabel")
			expect(gui).toBeTruthy()
			expect(gui.Title.Text).toBe(string.upper(title))
		end
		for _, title in { "Stash", "Forge", "Market", "Pet Stable", "Rift Gate", "Leaderboard" } do
			expect(seen[title]).toBe(true)
		end

		-- the first quest points at the Rift Gate: its label is the gold one
		local gate = workspace.Lumenhaven:FindFirstChild("Station_Atlas", true)
		local stash = workspace.Lumenhaven:FindFirstChild("Station_Inventory", true)
		expect(gate.StationLabel.Title.TextSize > stash.StationLabel.Title.TextSize).toBe(true)

		-- the Forge is locked for a new hero
		local forge = workspace.Lumenhaven:FindFirstChild("Station_Forge", true)
		expect(forge.StationLabel.Sub.Visible).toBe(true)
		expect(string.find(forge.StationLabel.Sub.Text, "^Locked · ")).toBeTruthy()

		-- the stations' prompts are drawn by the game (Gilded Ink card), not Roblox's grey box
		local prompt = gate:FindFirstChildOfClass("ProximityPrompt")
		expect(prompt.Style).toBe(Enum.ProximityPromptStyle.Custom)
		local promptGui = sim.player.PlayerGui:FindFirstChild("LootRushPrompt")
		expect(promptGui).toBeTruthy()
		expect(promptGui:FindFirstChild("Card", true)).toBeTruthy()

		-- own plate: bar only, shown once hurt
		local plate = character:FindFirstChild("Nameplate", true)
		expect(plate).toBeTruthy()
		expect(plate:FindFirstChild("Name", true)).toBeNil()
		expect(plate.Enabled).toBe(false)
		sim:runAs("server", function()
			humanoid.Health = humanoid.MaxHealth * 0.5
		end)
		sim:run(0.5)
		expect(plate.Enabled).toBe(true)
		local fill = plate:FindFirstChild("Fill", true)
		expect(math.abs(fill.Size.X.Scale - 0.5) < 0.01).toBe(true)
	end)
end)
