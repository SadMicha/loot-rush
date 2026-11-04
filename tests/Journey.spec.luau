-- Journey (hero milestones) and the Beta Season (challenges + reward track): pure rules, the save
-- fields and the claim remotes.
local Journey = require("ReplicatedStorage.Shared.Journey")
local Seasons = require("ReplicatedStorage.Shared.Seasons")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Cosmetics = require("ReplicatedStorage.Shared.Cosmetics")

local SEASON = Seasons.Current
local LIVE = SEASON.starts + 3600

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

local function hero(): any
	local h = Profile.reconcile({})
	return h
end

describe("Journey rules", function()
	it("reads the facts from a hero save", function()
		local h = hero()
		h.level = 12
		h.atlas = { green_plains = 7, crystal_caves = 5 }
		h.tier.unlocked = 2
		h.progress.stars = { a = true, b = true, c = false }
		local f = Journey.facts(h)
		expect(f.depth).toBe(7)
		expect(f.level).toBe(12)
		expect(f.tier).toBe(2)
		expect(f.stars).toBe(2)
		expect(f.bosses).toBe(1) -- crystal caves start at depth 6: its boss is not beaten yet
		expect(f.guide).toBe(0)
	end)

	it("claims a finished milestone once and points at the next goal", function()
		local h = hero()
		h.atlas = { green_plains = 3 }
		local f = Journey.facts(h)
		local claimed = {}
		expect(Journey.canClaim("depth_3", f, claimed)).toBe(true)
		expect(Journey.canClaim("depth_5", f, claimed)).toBe(false)
		expect(Journey.canClaim("nope", f, claimed)).toBe(false)
		expect(Journey.canClaim({}, f, claimed)).toBe(false)
		expect(Journey.readyCount(f, claimed)).toBe(2) -- depth 3 + the Green Plains boss
		claimed.depth_3 = true
		expect(Journey.canClaim("depth_3", f, claimed)).toBe(false)
		local goal = Journey.nextGoal(f, claimed)
		expect(goal).toBeTruthy()
		expect((goal :: any).id).toBe("guide")
	end)

	it("scales gold with the best depth and keeps ids unique", function()
		local low = Journey.scaled({ gold = 100 }, 1)
		local deep = Journey.scaled({ gold = 100 }, 30)
		expect(deep.gold).toBeGreaterThan(low.gold)
		expect(Journey.scaled({ gold = 100 }, 0 / 0).gold).toBe(low.gold)
		for _, ms in Journey.List do
			expect(Journey.ById[ms.id]).toBe(ms)
			expect(ms.target).toBeGreaterThan(0)
		end
	end)

	it("repairs junk in the save", function()
		local h = Profile.reconcile({
			journey = { depth_3 = true, fake = true, depth_5 = 1, [3] = true },
		})
		expect(h.journey.depth_3).toBe(true)
		expect(h.journey.fake).toBeNil()
		expect(h.journey.depth_5).toBeNil()
		expect(next(Profile.reconcile({ journey = "x" }).journey)).toBeNil()
	end)
end)

describe("Season rules", function()
	it("has a clock with soon, live and over", function()
		expect(Seasons.phase(SEASON.starts - 1)).toBe("soon")
		expect(Seasons.phase(SEASON.starts)).toBe("live")
		expect(Seasons.phase(SEASON.ends)).toBe("over")
		expect(Seasons.secondsLeft(SEASON.ends - 90)).toBe(90)
		expect(Seasons.countdown(2 * 86400 + 3 * 3600)).toBe("2d 3h")
		expect(Seasons.countdown(125)).toBe("2m")
	end)

	it("counts only while live and finishes challenges", function()
		local d = Seasons.fresh()
		expect(#Seasons.add(d, "kill", 5, SEASON.starts - 10)).toBe(0)
		expect(d.counts.kills).toBeNil()
		expect(#Seasons.add(d, "kill", 1999, LIVE)).toBe(0)
		local done = Seasons.add(d, "kill", 5, LIVE)
		expect(done[1]).toBe("kills")
		expect(d.counts.kills).toBe(2000) -- capped at the target
		expect(#Seasons.add(d, "kill", 0 / 0, LIVE)).toBe(0)
		expect(#Seasons.add(d, "kill", -3, LIVE)).toBe(0)
		expect(#Seasons.add(d, "salvage", 50, SEASON.ends + 1)).toBe(0) -- over
		expect(Seasons.points(d)).toBe(Seasons.ChallengeById.kills.points)
	end)

	it("reads hero facts as the best value seen", function()
		local d = Seasons.fresh()
		Seasons.observe(d, { depth = 12, level = 3, bosses = 2, sockets = 1 }, LIVE)
		expect(d.counts.depth_10).toBe(10)
		expect(d.counts.depth_20).toBe(12)
		Seasons.observe(d, { depth = 4 }, LIVE) -- a weaker hero never lowers it
		expect(d.counts.depth_20).toBe(12)
		Seasons.observe(d, { depth = 30 }, SEASON.ends) -- over: no change
		expect(d.counts.depth_20).toBe(12)
	end)

	it("pays every track step once when the points are there", function()
		local d = Seasons.fresh()
		expect(Seasons.canClaim(d, 1)).toBe(false)
		for _, ch in SEASON.challenges do
			d.counts[ch.id] = ch.target
		end
		expect(Seasons.points(d)).toBe(Seasons.TOTAL_POINTS)
		expect(Seasons.readyCount(d)).toBe(#SEASON.track)
		expect(Seasons.claim(d, 1)).toBe(SEASON.track[1])
		expect(Seasons.claim(d, 1)).toBeNil()
		expect(Seasons.claim(d, 1.5)).toBeNil()
		expect(Seasons.claim(d, "2")).toBeNil()
		expect(Seasons.claim(d, 99)).toBeNil()
		expect(Seasons.readyCount(d)).toBe(#SEASON.track - 1)
	end)

	it("cosmetic rewards exist and are never sold", function()
		for _, s in SEASON.track do
			if s.reward.cosmetic then
				local c = Cosmetics.ById[s.reward.cosmetic]
				expect(c).toBeTruthy()
				expect(c.season).toBe(SEASON.id)
			end
		end
	end)

	it("repairs junk and drops saves of another season", function()
		local a = Profile.reconcileAccount({
			season = {
				id = SEASON.id,
				counts = { kills = 1e9, salvage = 0 / 0, fake = 3, uniques = 2.7 },
				claimed = { ["1"] = true, ["9"] = true, ["01"] = true, x = true },
			},
		})
		expect(a.season.counts.kills).toBe(2000)
		expect(a.season.counts.salvage).toBeNil()
		expect(a.season.counts.fake).toBeNil()
		expect(a.season.counts.uniques).toBe(2)
		expect(a.season.claimed["1"]).toBe(true)
		expect(a.season.claimed["9"]).toBeNil()
		expect(a.season.claimed["01"]).toBeNil()
		local other = Profile.reconcileAccount({ season = { id = "old", counts = { kills = 5 } } })
		expect(other.season.id).toBe(SEASON.id)
		expect(other.season.counts.kills).toBeNil()
		expect(Profile.freshAccount().season.id).toBe(SEASON.id)
	end)
end)

describe("Journey and Season remotes", function()
	it("claims a milestone once and syncs the facts", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
		end)
		sim:run(1)
		expect(#sent("JourneyState")).toBeGreaterThan(0)
		local goldBefore = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			Data.get(player).atlas.green_plains = 3
			return Data.get(player).gold
		end)
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Journey:FireServer("claim", "depth_5") -- not reached: ignored
			Net.Journey:FireServer("claim", "depth_3")
			Net.Journey:FireServer("claim", "depth_3") -- twice: ignored
			Net.Journey:FireServer("claim", { "depth_3" })
		end)
		sim:run(1)
		local journey, gold = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			return Data.get(player).journey, Data.get(player).gold
		end)
		expect(journey.depth_3).toBe(true)
		expect(journey.depth_5).toBeNil()
		local reward = Journey.scaled(Journey.ById.depth_3.reward, 3).gold :: number
		expect(gold).toBe(goldBefore + reward)
		local states = sent("JourneyState")
		local last = states[#states][1]
		expect(last.facts.depth).toBe(3)
		expect(table.find(last.claimed, "depth_3")).toBeTruthy()
	end)

	it("counts season challenges from server events and pays a track step", function()
		server(function(req, player)
			local Systems = "ServerScriptService.Server.Systems."
			req(Systems .. "Seasons").clock = function()
				return LIVE
			end
			local Actions = req("ServerScriptService.Server.Util.Actions")
			for _ = 1, 3 do
				Actions.fire(player, "hatch")
			end
			Actions.fire(player, "salvage", 50)
		end)
		sim:run(2)
		local counts, ready = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			local season = Data.account(player).season
			return table.clone(season.counts), Seasons.readyCount(season)
		end)
		expect(counts.hatch).toBe(1)
		expect(counts.salvage).toBe(50)
		expect(ready).toBe(0) -- 10 points: the first step needs 20
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Season:FireServer("claim", 1)
		end)
		sim:run(1)
		local claimedEarly = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").account(player).season.claimed["1"]
		end)
		expect(claimedEarly).toBeNil()
		-- Dbg "season" finishes challenges until the Beta Trail step is reached
		server(function(req, player)
			local S = req("ServerScriptService.Server.Systems.Seasons")
			for _ = 1, 6 do
				S.completeNext(player)
			end
		end)
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Season:FireServer("claim", 1)
			Net.Season:FireServer("claim", 2)
			Net.Season:FireServer("claim", 2)
		end)
		sim:run(1)
		local claimed, trail = server(function(req, player)
			local account = req("ServerScriptService.Server.Systems.Data").account(player)
			return table.clone(account.season.claimed), account.cosmetics.beta_trail
		end)
		expect(claimed["1"]).toBe(true)
		expect(claimed["2"]).toBe(true)
		expect(trail).toBe(true)
		local states = sent("SeasonState")
		local paid = {}
		for _, st in states do
			if st[1].paid then
				table.insert(paid, st[1].paid)
			end
		end
		expect(table.concat(paid, ",")).toBe("1,2")
		expect(states[#states][1].phase).toBe("live")
	end)

	it("the HUD opens both windows", function()
		local gui = sim.player.PlayerGui
		for _, name in { "Journey", "Season" } do
			local button
			for _, d in gui.LootRushHUD:GetDescendants() do
				if d:IsA("GuiButton") and d.Name == name then
					button = d
				end
			end
			expect(button).toBeTruthy()
			sim:click(button)
			sim:run(1)
			local win = gui:FindFirstChild("LootRush" .. name)
			expect(win).toBeTruthy()
			expect(win.Enabled).toBe(true)
			local rows = 0
			for _, d in win:GetDescendants() do
				if string.match(d.Name, "^Milestone_") or string.match(d.Name, "^Challenge_") then
					rows += 1
				end
			end
			expect(rows).toBe(if name == "Journey" then #Journey.List else #SEASON.challenges)
		end
	end)
end)
