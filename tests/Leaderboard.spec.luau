-- Leaderboards: value encoding (Shared/Leaderboard), the account bests, Debug/Movement exclusion,
-- the movement check and the window.
local Leaderboard = require("ReplicatedStorage.Shared.Leaderboard")
local Profile = require("ReplicatedStorage.Shared.Profile")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Leaderboard rules", function()
	it("ranks deeper first, then faster", function()
		expect(Leaderboard.encode(12, 300)).toBeGreaterThan(Leaderboard.encode(11, 10))
		expect(Leaderboard.encode(12, 300)).toBeGreaterThan(Leaderboard.encode(12, 400))
		local _, depth, seconds = Leaderboard.decode(Leaderboard.encode(12, 300))
		expect(depth).toBe(12)
		expect(seconds).toBe(300)
	end)

	it("ranks the overall board by World Tier first", function()
		expect(Leaderboard.encodeOverall(2, 1, 9000)).toBeGreaterThan(
			Leaderboard.encodeOverall(1, 40, 10)
		)
		local tier, depth, seconds = Leaderboard.decode(Leaderboard.encodeOverall(3, 25, 61))
		expect(tier).toBe(3)
		expect(depth).toBe(25)
		expect(seconds).toBe(61)
	end)

	it("clamps junk and has one board per tier and class plus overall", function()
		expect(Leaderboard.encode(0 / 0, 0 / 0)).toBe(Leaderboard.MAX_SECONDS)
		expect(Leaderboard.encode(1e9, -5)).toBe(
			Leaderboard.MAX_DEPTH * 10000 + Leaderboard.MAX_SECONDS
		)
		expect(#Leaderboard.Boards).toBe(1 + 4 * 4)
		local v = Leaderboard.values(2, "mage", 10, 100)
		expect(v.overall).toBeTruthy()
		expect(v.t2_mage).toBe(Leaderboard.encode(10, 100))
		expect(Leaderboard.storeName("t2_mage")).toBe("LootRush_Board_t2_mage")
		expect(Leaderboard.time(3725)).toBe("1:02:05")
		expect(Leaderboard.time(65)).toBe("1:05")
	end)

	it("keeps only known boards with sane values in the save", function()
		local account = Profile.reconcileAccount({
			boards = { overall = 120005.5, t1_mage = 0 / 0, nope = 5, t9_x = 1, t1_ranger = -3 },
		})
		expect(account.boards.overall).toBe(120005)
		expect(account.boards.t1_mage).toBeNil()
		expect(account.boards.nope).toBeNil()
		expect(account.boards.t1_ranger).toBeNil()
		local unsent = Profile.reconcileAccount({ unsent = { t1_mage = 50000, bogus = 3 } }).unsent
		expect(unsent.t1_mage).toBe(50000)
		expect(unsent.bogus).toBeNil()
		expect(Profile.fresh().debugged).toBe(false)
	end)
end)

describe("Leaderboard server", function()
	it("writes the run's best once at the end, never for debugged heroes", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer(
				"setup",
				"Board Hero",
				"ranger"
			)
		end)
		sim:run(1)
		local best = server(function(req, player)
			local LB = req("ServerScriptService.Server.Systems.Leaderboard")
			LB.note(player, 1, "ranger", 3, 100)
			LB.note(player, 1, "ranger", 5, 200)
			LB.note(player, 1, "ranger", 4, 50) -- worse: ignored
			LB.flush(player)
			return req("ServerScriptService.Server.Systems.Data").account(player).boards.t1_ranger
		end)
		expect(best).toBe(Leaderboard.encode(5, 200))
		local after = server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			local LB = req("ServerScriptService.Server.Systems.Leaderboard")
			Data.get(player).debugged = true
			LB.note(player, 1, "ranger", 9, 10)
			LB.flush(player)
			Data.get(player).debugged = false
			return Data.account(player).boards.t1_ranger
		end)
		expect(after).toBe(Leaderboard.encode(5, 200))
	end)

	it("a strike or Dbg command during a run drops depths it already cleared", function()
		local best = server(function(req, player)
			local LB = req("ServerScriptService.Server.Systems.Leaderboard")
			req("ServerScriptService.Server.Systems.Data").account(player).unsent.t2_ranger = 42 -- older, unconfirmed
			LB.note(player, 2, "ranger", 7, 100) -- noted, account best raised at once
			LB.taint(player)
			LB.flush(player)
			return req("ServerScriptService.Server.Systems.Data").account(player).boards.t2_ranger
		end)
		expect(best).toBeNil()
		local unsent = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").account(player).unsent.t2_ranger
		end)
		expect(unsent).toBe(42) -- the older unconfirmed best stays queued for a retry
	end)

	it("a test command marks the hero as debugged", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Debug:FireServer("gold", 100)
		end)
		sim:run(0.5)
		local flagged = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).debugged
		end)
		expect(flagged).toBe(true)
	end)

	it("answers a board request with a page, junk ids are ignored", function()
		local before = #sim.netLog
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Board:FireServer("overall")
			Net.Board:FireServer("t9_nobody")
			Net.Board:FireServer({})
		end)
		sim:run(1)
		local pages = {}
		for i = before + 1, #sim.netLog do
			local n = sim.netLog[i]
			if n.name == "BoardData" and n.dir == "S→C" then
				table.insert(pages, n.args[1])
			end
		end
		expect(#pages).toBe(1)
		expect(pages[1].id).toBe("overall")
		expect(typeof(pages[1].entries)).toBe("table")
	end)

	it("the trophy on the HUD opens the window", function()
		local gui = sim.player.PlayerGui
		local button
		for _, d in gui.LootRushHUD:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "Leaderboard" then
				button = d
			end
		end
		expect(button).toBeTruthy()
		sim:click(button)
		sim:run(1)
		local win = gui:FindFirstChild("LootRushLeaderboard")
		expect(win).toBeTruthy()
		expect(win.Enabled).toBe(true)
		local mine = win:FindFirstChild("Mine", true)
		expect(mine).toBeTruthy()
	end)
end)

describe("Movement check", function()
	it("flags a client that moves too far twice in a row, walking and dashing are fine", function()
		local Movement = server(function(req)
			return req("ServerScriptService.Server.Systems.Movement")
		end)
		local t = Movement.newTrack(Vector3.zero, 0)
		-- walking at 20 studs/s for a second, in 0.25 s samples
		for i = 1, 4 do
			expect(Movement.step(t, Vector3.new(5 * i, 0, 0), i * 0.25, 20)).toBe("ok")
		end
		-- a dash (14 studs in one sample) eats into the burst bank, still fine
		expect(Movement.step(t, Vector3.new(20 + 19, 0, 0), 1.25, 20)).toBe("ok")
		-- a 60-stud jump: suspect first, a strike when it is still there on the next sample
		expect(Movement.step(t, Vector3.new(100, 0, 0), 1.5, 20)).toBe("suspect")
		expect(Movement.step(t, Vector3.new(100, 0, 0), 1.75, 20)).toBe("strike")
		expect(t.last).toBe(Vector3.new(39, 0, 0)) -- pulled back here
		-- a marked server teleport only re-bases
		t.skip = true
		expect(Movement.step(t, Vector3.new(500, 0, 0), 2, 20)).toBe("ok")
		expect(t.last).toBe(Vector3.new(500, 0, 0))
		-- a big jump that a server teleport explains between two samples is forgiven
		expect(Movement.step(t, Vector3.new(600, 0, 0), 2.25, 20)).toBe("suspect")
		t.skip = true
		expect(Movement.step(t, Vector3.new(600, 0, 0), 2.5, 20)).toBe("ok")
	end)

	it("lets server teleports through", function()
		local start, strikes = server(function(req, player)
			return player.Character.HumanoidRootPart.Position,
				req("ServerScriptService.Server.Systems.Movement").strikes(player)
		end)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Movement").teleported(player)
			player.Character:PivotTo(CFrame.new(start + Vector3.new(0, 0, -30)))
		end)
		sim:run(1)
		local after = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Movement").strikes(player)
		end)
		expect(after).toBe(strikes)
	end)
end)
