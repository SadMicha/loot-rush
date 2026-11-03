-- Daily rewards: pure calendar rules (Shared/Daily), the account save field and the claim remote.
local Daily = require("ReplicatedStorage.Shared.Daily")
local Profile = require("ReplicatedStorage.Shared.Profile")

local DAY = Daily.DAY
local T0 = 20000 * DAY + 3600 -- some UTC day, 01:00

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function sent(name: string): { any }
	local list = {}
	for _, n in sim.netLog do
		if n.name == name and n.dir == "S→C" then
			table.insert(list, n.args)
		end
	end
	return list
end

describe("Daily rules", function()
	it("claims once per UTC day and walks through the 7-day cycle", function()
		local d = Daily.fresh()
		expect(Daily.canClaim(d, T0)).toBe(true)
		expect(Daily.claim(d, T0)).toBe(1)
		expect(Daily.claim(d, T0 + 3600)).toBeNil() -- same day
		expect(Daily.secondsLeft(d, T0)).toBe(DAY - 3600)
		expect(Daily.claim(d, T0 + DAY)).toBe(2)
		for i = 3, 7 do
			expect(Daily.claim(d, T0 + (i - 1) * DAY)).toBe(i)
		end
		expect(Daily.claim(d, T0 + 7 * DAY)).toBe(1) -- the cycle repeats
		expect(d.claimed).toBe(8)
	end)

	it("never resets on a missed day and ignores a clock going backwards", function()
		local d = Daily.fresh()
		Daily.claim(d, T0)
		Daily.claim(d, T0 + DAY)
		expect(Daily.claim(d, T0 + 10 * DAY)).toBe(3) -- a week away: still day 3
		expect(Daily.canClaim(d, T0 + 2 * DAY)).toBe(false) -- clock went back
		expect(Daily.claim(d, T0 + 2 * DAY)).toBeNil()
	end)

	it("scales gold with the best depth, day 7 is the biggest", function()
		local low = Daily.reward(1, 1)
		local deep = Daily.reward(1, 30)
		expect(deep.gold).toBeGreaterThan(low.gold)
		local big = Daily.reward(7, 1)
		for i = 1, 6 do
			expect(big.gold).toBeGreaterThan(Daily.reward(i, 1).gold)
		end
		expect(big.soulstars).toBeGreaterThan(0)
		expect(Daily.reward(99, 0 / 0).gold).toBe(Daily.reward(7, 1).gold) -- clamped, NaN safe
	end)

	it("repairs junk in the save", function()
		local account = Profile.reconcileAccount({ daily = { claimed = 0 / 0, last = -5 } })
		expect(account.daily.claimed).toBe(0)
		expect(account.daily.last).toBe(0)
		expect(Profile.freshAccount().daily.claimed).toBe(0)
		local kept = Profile.reconcileAccount({ daily = { claimed = 4.7, last = 20001 } })
		expect(kept.daily.claimed).toBe(4)
		expect(kept.daily.last).toBe(20001)
	end)
end)

describe("Daily remote", function()
	it("pays today's reward once and sends the calendar", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
		end)
		sim:run(1)
		expect(#sent("DailyState")).toBeGreaterThan(0)
		local goldBefore = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).gold
		end)
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Daily:FireServer("claim")
			Net.Daily:FireServer("claim") -- same day: ignored
			Net.Daily:FireServer({ "claim" })
		end)
		sim:run(1)
		local claimed, gold, shards = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			return Data.account(player).daily.claimed,
				Data.get(player).gold,
				Data.get(player).materials.shards
		end)
		expect(claimed).toBe(1)
		expect(gold).toBeGreaterThan(goldBefore)
		expect(shards).toBeGreaterThan(0)
		local states = sent("DailyState")
		local last = states[#states][1]
		expect(last.canClaim).toBe(false)
		expect(last.index).toBe(2)
		-- Debug "Next day" rewinds the calendar: the next claim pays day 2
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Daily").rewind(player)
		end)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Daily:FireServer("claim")
		end)
		sim:run(1)
		local after = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").account(player).daily.claimed
		end)
		expect(after).toBe(2)
	end)

	it("the window shows seven days and the claim button", function()
		local gui = sim.player.PlayerGui
		local daily = gui:FindFirstChild("LootRushDaily")
		expect(daily).toBeTruthy()
		local days = 0
		for _, d in daily:GetDescendants() do
			if string.match(d.Name, "^Day%d$") then
				days += 1
			end
		end
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Daily").sync(player)
		end)
		sim:run(0.5)
		local button
		for _, d in gui.LootRushHUD:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "Daily" then
				button = d
			end
		end
		expect(button).toBeTruthy()
		if not daily.Enabled then
			sim:click(button)
		end
		sim:run(0.5)
		days = 0
		for _, d in daily:GetDescendants() do
			if string.match(d.Name, "^Day%d$") then
				days += 1
			end
		end
		expect(days).toBe(7)
		expect(daily.Enabled).toBe(true)
	end)
end)
