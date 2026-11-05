-- Release notes (Shared/Changelog) and the "What's New" window (Client/Controllers/ChangelogController).
local Changelog = require("ReplicatedStorage.Shared.Changelog")
local Settings = require("ReplicatedStorage.Shared.Settings")

local function CLIENT_(): string
	return "Players." .. sim.player.Name .. ".PlayerScripts.Client."
end

local function seenOnServer(): number
	local out = -1
	sim:runAs("server", function(req)
		local player = game:GetService("Players"):GetPlayers()[1]
		out = req("ServerScriptService.Server.Systems.Data").account(player).settings.changelogSeen
	end)
	return out
end

local function gui()
	return sim.player.PlayerGui:FindFirstChild("LootRushWhatsNew")
end

describe("Changelog rules", function()
	it("lists releases newest first with unique, rising builds", function()
		expect(#Changelog.Releases > 0).toBe(true)
		for i, r in Changelog.Releases do
			expect(r.build % 1).toBe(0)
			expect(r.build >= 1).toBe(true)
			if i > 1 then
				expect(r.build < Changelog.Releases[i - 1].build).toBe(true)
			end
		end
		expect(Changelog.latest()).toBe(Changelog.Releases[1])
	end)

	it("keeps every entry short and complete", function()
		for _, r in Changelog.Releases do
			expect(#r.version > 0).toBe(true)
			expect(#r.title > 0).toBe(true)
			expect(r.date:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil).toBe(true)
			expect(#r.notes >= 1 and #r.notes <= 8).toBe(true)
			for _, note in r.notes do
				expect(#note > 0 and #note <= Changelog.MAX_NOTE).toBe(true)
			end
		end
	end)

	it("returns only releases above the seen build", function()
		expect(#Changelog.since(0)).toBe(#Changelog.Releases)
		expect(#Changelog.since(Changelog.latest().build)).toBe(0)
	end)

	it("stores the seen build as a whole-number hidden setting", function()
		expect(Settings.fresh().changelogSeen).toBe(0)
		expect(Settings.validate("changelogSeen", 3.4)).toBe(3)
		expect(Settings.validate("changelogSeen", -2)).toBe(0)
		expect(Settings.validate("changelogSeen", 0 / 0)).toBeNil()
		expect(Settings.GAME_VERSION).toBe(Changelog.latest().version)
	end)
end)

describe("What's New window", function()
	it("does not pop up for a new account but marks the newest build as seen", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "News Hero", "mage")
		end)
		sim:run(6)
		local g = gui()
		expect(g ~= nil and g.Enabled).toBe(false)
		expect(seenOnServer()).toBe(Changelog.latest().build)
	end)

	it("opens from Settings and shows every release with its notes", function()
		sim:runAs("client", function(req)
			req(CLIENT_() .. "Controllers.SettingsController").open()
		end)
		sim:run(0.5)
		local settings = sim.player.PlayerGui:FindFirstChild("LootRushSettings")
		local button = settings and settings:FindFirstChild("WhatsNew", true)
		expect(button).toBeTruthy()
		sim:click(button)
		sim:run(0.5)
		local g = gui()
		expect(g ~= nil and g.Enabled).toBe(true)
		for _, r in Changelog.Releases do
			local block = g:FindFirstChild("Release_" .. r.build, true)
			expect(block).toBeTruthy()
			expect(block:FindFirstChild("Note" .. #r.notes, true)).toBeTruthy()
		end
		local ok = g:FindFirstChild("GotIt", true)
		sim:click(ok)
		sim:run(0.5)
		expect(g.Enabled).toBe(false)
	end)
end)
