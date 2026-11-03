-- One-time hints (docs/ROADMAP-1.0.md O4): shown once per account, remembered in the settings.
local Settings = require("ReplicatedStorage.Shared.Settings")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function toasts(): number
	local n = 0
	local gui = sim.player.PlayerGui:FindFirstChild("LootRushToast")
	for _, d in (if gui then gui:GetDescendants() else {}) do
		if d.Name == "Toast" then
			n += 1
		end
	end
	return n
end

describe("Hints", function()
	it("are hidden account settings that start unseen", function()
		expect(Settings.fresh().hintRush).toBe(false)
		expect(Settings.validate("hintDodge", true)).toBe(true)
		expect(Settings.validate("hintDodge", "yes")).toBeNil()
	end)

	it("the first Rush shows its hint once and saves it", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Hint Hero", "ranger")
		end)
		sim:run(2)
		local before = toasts()
		server(function(_, player)
			player:SetAttribute("Rushing", true)
		end)
		sim:run(1)
		expect(toasts()).toBeGreaterThan(before)
		local seen = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").account(player).settings.hintRush
		end)
		expect(seen).toBe(true)
		sim:run(8) -- let the toast leave
		local after = toasts()
		server(function(_, player)
			player:SetAttribute("Rushing", false)
			player:SetAttribute("Rushing", true)
		end)
		sim:run(1)
		expect(toasts()).toBe(after)
	end)
end)
