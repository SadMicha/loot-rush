-- First-open explainers (client/UI/Intro): Star Web, Forge and Pet Stable show a short card the
-- first time they open; "Got it" saves it as seen for the account, so it never comes back.
local Settings = require("ReplicatedStorage.Shared.Settings")

local function CLIENT_(): string
	return "Players." .. sim.player.Name .. ".PlayerScripts.Client."
end

local function seen(key: string): boolean
	local out = false
	sim:runAs("server", function(req)
		local player = game:GetService("Players"):GetPlayers()[1]
		out = req("ServerScriptService.Server.Systems.Data").account(player).settings[key]
	end)
	return out
end

local function togglePets()
	sim:runAs("client", function(req)
		req(CLIENT_() .. "Controllers.PetWindowController").toggle()
	end)
	sim:run(0.5)
end

local function intro()
	local gui = sim.player.PlayerGui:FindFirstChild("LootRushPets")
	return gui and gui:FindFirstChild("Intro", true)
end

describe("Window intros", function()
	it("are hidden account settings that start unseen", function()
		for _, key in { "introStarWeb", "introForge", "introPets" } do
			expect(Settings.fresh()[key]).toBe(false)
		end
		expect(Settings.validate("introPets", true)).toBe(true)
	end)

	it("show once on the first open and stay away after Got it", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Intro Hero", "mage")
		end)
		sim:run(2)
		togglePets()
		local card = intro()
		expect(card).toBeTruthy()
		local ok = card:FindFirstChild("GotIt", true)
		expect(ok).toBeTruthy()
		sim:click(ok)
		sim:run(0.5)
		expect(intro()).toBeNil()
		expect(seen("introPets")).toBe(true)
		togglePets() -- close
		togglePets() -- open again
		expect(intro()).toBeNil()
	end)

	it("every line fits its row on a small phone, where text grows to the minimum size", function()
		sim:setViewport(Vector2.new(667, 375), true)
		sim:runAs("client", function(req)
			req(CLIENT_() .. "Prefs").set("introPets", false) -- as after "Defaults"
		end)
		togglePets() -- close
		togglePets() -- open: the card is back
		local card = intro()
		expect(card).toBeTruthy()
		local lines = 0
		for _, l in card:GetDescendants() do
			if l:IsA("TextLabel") and l.Name:match("^Line") then
				lines += 1
				-- rough width per character (Montserrat ~0.55 em); rows at 1.2 line height
				local perRow = math.floor(l.Size.X.Offset / (l.TextSize * 0.55))
				if l.Size.X.Scale > 0 then
					perRow = math.floor(l.Parent.Size.X.Offset / (l.TextSize * 0.55))
				end
				if perRow <= 0 then
					perRow = math.floor(632 / (l.TextSize * 0.55))
				end
				local rows = math.ceil(#l.Text / perRow)
				expect(rows * l.TextSize * 1.2).toBeLessThanOrEqual(l.Size.Y.Offset)
			end
		end
		expect(lines).toBe(3)
	end)
end)
