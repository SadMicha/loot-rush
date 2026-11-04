-- Tutorial hints (docs/CRITERIA-AUDIT.md §3 #2): callouts next to the button they explain, shown
-- at a calm moment, saved as seen only once they were on screen. Daily popup after the first fight (#5).
local Settings = require("ReplicatedStorage.Shared.Settings")

-- The real client controllers run from PlayerScripts (the StarterPlayerScripts copies are unused)
local function CLIENT_(): string
	return "Players." .. sim.player.Name .. ".PlayerScripts.Client."
end

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function client(fn)
	local out = {}
	sim:runAs("client", function(req)
		out = table.pack(fn(req))
	end)
	return table.unpack(out, 1, out.n)
end

local function seen(key: string): boolean
	return server(function(req, player)
		return req("ServerScriptService.Server.Systems.Data").account(player).settings[key]
	end)
end

local function callout()
	local gui = sim.player.PlayerGui:FindFirstChild("LootRushHints")
	return gui and gui:FindFirstChild("Callout", true)
end

local function find(guiName: string, name: string)
	local gui = sim.player.PlayerGui:FindFirstChild(guiName)
	return gui and gui:FindFirstChild(name, true)
end

describe("Hints", function()
	it("are hidden account settings that start unseen", function()
		for _, key in
			{ "hintSkills", "hintDodge", "hintRush", "hintBreak", "hintCounter", "hintEquip" }
		do
			expect(Settings.fresh()[key]).toBe(false)
		end
		expect(Settings.validate("hintDodge", true)).toBe(true)
		expect(Settings.validate("hintDodge", "yes")).toBeNil()
	end)

	it("a new player gets no Daily popup before the first fight", function()
		sim:boot({ seconds = 2 })
		client(function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Hint Hero", "ranger")
		end)
		sim:run(6)
		local daily = sim.player.PlayerGui:FindFirstChild("LootRushDaily")
		expect(daily).toBeTruthy()
		expect(daily.Enabled).toBe(false)
		-- First rift entered and back in the hub: now it pops up
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Quests").advance(player, "rift", 1)
		end)
		sim:run(4)
		expect(daily.Enabled).toBe(true)
		client(function(req)
			req(CLIENT_() .. "Controllers.DailyController").toggle()
		end)
		sim:run(0.5)
		expect(daily.Enabled).toBe(false)
	end)

	it("waits for a calm moment and is not saved before it was on screen", function()
		client(function(req)
			req(CLIENT_() .. "Controllers.DailyController").open() -- a window is open: not calm
		end)
		server(function(_, player)
			-- A running Rush shows the Rush meter and queues its hint
			player:SetAttribute("RushUntil", workspace:GetServerTimeNow() + 60)
			player:SetAttribute("Rushing", true)
		end)
		sim:run(3)
		expect(callout()).toBeNil()
		expect(seen("hintRush")).toBe(false)
		client(function(req)
			req(CLIENT_() .. "Controllers.DailyController").toggle()
		end)
		sim:run(1)
		local card = callout()
		expect(card).toBeTruthy()
		expect(client(function(req)
			return req(CLIENT_() .. "Controllers.HintsController").current()
		end)).toBe("hintRush")
		expect(seen("hintRush")).toBe(false) -- up for a moment only: not seen yet
	end)

	it("sits next to the element it explains, with a ring around it", function()
		local card = callout()
		local target = find("LootRushHUD", "RushMeter")
		local ring = find("LootRushHints", "CalloutRing")
		expect(card).toBeTruthy()
		expect(target).toBeTruthy()
		expect(ring and ring.Visible).toBe(true)
		local function center(g)
			return g.AbsolutePosition + g.AbsoluteSize / 2
		end
		expect((center(ring) - center(target)).Magnitude).toBeLessThan(4)
		-- The Rush meter sits at the bottom centre: the card stands above it, close by
		local cardBottom = card.AbsolutePosition.Y + card.AbsoluteSize.Y
		expect(cardBottom).toBeLessThan(target.AbsolutePosition.Y + 1)
		expect(target.AbsolutePosition.Y - cardBottom).toBeLessThan(80)
		local v = workspace.CurrentCamera.ViewportSize
		expect(card.AbsolutePosition.X).toBeGreaterThan(-1)
		expect(card.AbsolutePosition.X + card.AbsoluteSize.X).toBeLessThan(v.X + 1)
	end)

	it("a tap closes it, saves it, and it never comes back", function()
		local card = callout()
		sim:click(card:FindFirstChild("Close"))
		sim:run(0.5)
		expect(callout()).toBeNil()
		expect(seen("hintRush")).toBe(true)
		server(function(_, player)
			player:SetAttribute("Rushing", false)
			player:SetAttribute("Rushing", true)
		end)
		sim:run(2)
		expect(callout()).toBeNil()
	end)

	it("a callout left alone stays up, then counts as seen", function()
		client(function(req)
			req(CLIENT_() .. "Controllers.HintsController").queue("hintRush") -- already seen: ignored
		end)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Quests").advance(player, "kill", 10)
			req("ServerScriptService.Server.Systems.Quests").advance(player, "pickup", 3)
		end)
		sim:run(1.5)
		-- Quest "Equip an item" at rest: points at the Inventory button in the hub bar
		expect(client(function(req)
			return req(CLIENT_() .. "Controllers.HintsController").current()
		end)).toBe("hintEquip")
		local ring = find("LootRushHints", "CalloutRing")
		local inv = find("LootRushHUD", "HubBar")
		inv = inv and inv:FindFirstChild("inventory", true)
		expect(inv).toBeTruthy()
		local function center(g)
			return g.AbsolutePosition + g.AbsoluteSize / 2
		end
		expect((center(ring) - center(inv)).Magnitude).toBeLessThan(4)
		sim:run(4)
		expect(callout()).toBeTruthy() -- still up after the old 2.4 s toast time
		sim:run(6)
		expect(callout()).toBeNil()
		expect(seen("hintEquip")).toBe(true)
	end)

	it("fits on a phone screen (844×390, touch)", function()
		sim:setViewport(Vector2.new(844, 390), true)
		client(function(req)
			req(CLIENT_() .. "Prefs").set("hintEquip", false) -- as after "Defaults": comes back once
		end)
		sim:run(2)
		local card = callout()
		expect(card).toBeTruthy()
		local v = workspace.CurrentCamera.ViewportSize
		local p, size = card.AbsolutePosition, card.AbsoluteSize
		expect(p.X).toBeGreaterThan(-1)
		expect(p.Y).toBeGreaterThan(-1)
		expect(p.X + size.X).toBeLessThan(v.X + 1)
		expect(p.Y + size.Y).toBeLessThan(v.Y + 1)
		expect(card:FindFirstChild("Foot", true).Text).toBe("Tap to close")
	end)
end)
