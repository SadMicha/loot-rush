-- Leaving a Rift always ends in Lumenhaven: owner playtest bug "Back to Hub from the Altered World
-- landed in an empty Green Plains rift". Cause: the server teleport to the Hub re-based the movement
-- check only for one sample; the client's in-flight physics updates still reported the old arena
-- spot, so the next samples (now in the Hub) became a "strike" and the player was pulled back to the
-- arena, which slot 1 had just rebuilt as the empty Green Plains (World.release). Covered here: the
-- movement race itself, leaving in every phase, a repeated leave, leave + "Play again" in one go,
-- and the rescue of a player left standing outside the Hub without a run (FallGuard, Hub button).
local Config = require("ReplicatedStorage.Shared.Config")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function rift(...)
	local args = table.pack(...)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer(table.unpack(args, 1, args.n))
	end)
	sim:run(1.2) -- also refills the Rift remote's rate limit (1/s)
end

local function phase(): string
	return sim.player:GetAttribute("RiftPhase") or ""
end

local function hubDistance(): number
	return server(function(_, player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return if root then (root.Position - Config.HUB_POS).Magnitude else math.huge
	end)
end

-- Every check after a leave: in the Hub, no run, no Altered World map left on any slot
local function expectHome()
	expect(phase()).toBe("")
	expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
	expect(hubDistance()).toBeLessThan(10)
	local runs, slot, leftover, slot1 = server(function(req, player)
		local Rift = req("ServerScriptService.Server.Systems.Rift")
		local World = req("ServerScriptService.Server.Systems.World")
		local found = 0
		for _, f in workspace.Arena:GetChildren() do
			if string.find(f.Name, "altered_world", 1, true) then
				found += 1
			end
		end
		return Rift.count(), Rift.slotOf(player), found, World.current(1)
	end)
	expect(runs).toBe(0)
	expect(slot).toBeNil()
	expect(leftover).toBe(0)
	expect(slot1).toBe("green_plains")
end

local function slayAll()
	server(function(req, player)
		local Combat = req("ServerScriptService.Server.Systems.Combat")
		for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
			Combat.slay(player, e)
		end
	end)
	sim:run(1)
end

local function until_(want: string)
	for _ = 1, 40 do
		if phase() == want then
			return
		end
		slayAll()
	end
end

describe("Movement check after a server teleport", function()
	local Movement = nil
	local arena = Vector3.new(0, 4, 16)
	local hub = Config.HUB_POS

	it("a single re-based sample was the bug: a stale client update caused a pull-back", function()
		Movement = server(function(req)
			return req("ServerScriptService.Server.Systems.Movement")
		end)
		local t = Movement.newTrack(arena, 0)
		t.skip = true -- the old behaviour: only the next sample re-bases
		expect(Movement.step(t, arena, 0.25, 16)).toBe("ok") -- the client had not got the teleport yet
		expect(Movement.step(t, hub, 0.5, 16)).toBe("suspect")
		expect(Movement.step(t, hub, 0.75, 16)).toBe("strike")
		expect(t.last).toBe(arena) -- pulled back into the arena
	end)

	it("now every sample in the settle window re-bases, the player stays in the Hub", function()
		local t = Movement.newTrack(arena, 0)
		Movement.settle(t, 0.1)
		expect(Movement.step(t, arena, 0.25, 16)).toBe("ok")
		expect(Movement.step(t, hub, 0.5, 16)).toBe("ok")
		expect(Movement.step(t, hub, 0.75, 16)).toBe("ok")
		expect(t.last).toBe(hub)
		-- after the window the check is as strict as before
		local later = 0.1 + Config.MOVE_TELEPORT_SETTLE + 0.25
		expect(Movement.step(t, hub, later, 16)).toBe("ok")
		expect(Movement.step(t, hub + Vector3.new(400, 0, 0), later + 0.25, 16)).toBe("suspect")
	end)
end)

describe("Leaving a Rift in the Altered World", function()
	it("leave during the waves ends in the Hub and frees the slot", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Debug:FireServer("atlas") -- opens the Altered World
		end)
		sim:run(1)
		rift("enter", "altered_world")
		expect(phase()).toBe("wave")
		expect(sim.player:GetAttribute("RiftRegion")).toBe("altered_world")
		expect(hubDistance()).toBeGreaterThan(100)
		rift("leave")
		expectHome()
	end)

	it("a second leave changes nothing (idempotent)", function()
		local before = #sim.netLog
		rift("leave")
		expectHome()
		local results = 0
		for i = before + 1, #sim.netLog do
			if sim.netLog[i].name == "RiftResult" then
				results += 1
			end
		end
		expect(results).toBe(0)
	end)

	it("leave during the boss ends in the Hub", function()
		rift("enter", "altered_world")
		until_("boss")
		expect(phase()).toBe("boss")
		rift("leave")
		expectHome()
	end)

	it("Back to Hub after the boss ends in the Hub", function()
		rift("enter", "altered_world")
		until_("clear")
		expect(phase()).toBe("clear")
		rift("leave")
		expectHome()
	end)

	it("leave while dead and waiting for a revive ends the run", function()
		rift("enter", "altered_world")
		server(function(_, player)
			player.Character:FindFirstChildOfClass("Humanoid").Health = 0
		end)
		sim:run(0.5)
		expect(sim.player:GetAttribute("RiftDowned")).toBe(true)
		rift("leave")
		local runs = server(function(req)
			return req("ServerScriptService.Server.Systems.Rift").count()
		end)
		expect(runs).toBe(0)
		expect(phase()).toBe("")
		sim:spawnCharacter() -- the real respawn lands on the Hub's SpawnLocation
		sim:run(Config.RESPAWN_TIME + 2)
		expect(server(function(req)
			return req("ServerScriptService.Server.Systems.Rift").count()
		end)).toBe(0)
	end)

	it("leave and Play again in one go (double tap) ends in the Hub", function()
		-- the sandbox spawned the new body at the origin: the guard brought it home
		sim:run(1)
		expectHome()
		rift("enter", "altered_world")
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Rift:FireServer("leave")
			Net.Rift:FireServer("enter", "altered_world")
		end)
		sim:run(1.5)
		expectHome()
	end)

	it("a leave right after enter is not rate limited away", function()
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Rift:FireServer("enter", "altered_world")
			Net.Rift:FireServer("deeper")
			Net.Rift:FireServer("enter", "altered_world") -- the shared enter budget is spent now
			Net.Rift:FireServer("leave")
		end)
		sim:run(1.5)
		expectHome()
	end)

	it("enter without a valid region is refused (no default Green Plains run)", function()
		for _, bad in { "", "nowhere", 5 } do
			rift("enter", bad)
			expect(phase()).toBe("")
		end
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter")
		end)
		sim:run(1.2)
		expectHome()
	end)

	it("leave while the map is still being built aborts cleanly and frees the slot", function()
		local stream = sim.customs.Player.RequestStreamAroundAsync
		local original = stream.method
		stream.method = function()
			task.wait(1) -- a slow phone: the map streams in for a second
		end
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "altered_world")
		end)
		sim:run(0.3)
		local building = server(function(req)
			return req("ServerScriptService.Server.Systems.Rift").count()
		end)
		expect(building).toBe(1)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(3)
		stream.method = original
		expectHome()
	end)

	it(
		"a player left outside the Hub without a run is brought home (guard and Hub button)",
		function()
			local function strand()
				server(function(_, player)
					player.Character:PivotTo(CFrame.new(Config.RIFT_START)) -- the empty slot-1 Green Plains
				end)
			end
			-- the server guard: without a run only the Hub counts, an idle map slot does not
			strand()
			sim:run(0.5)
			expectHome()
			-- the HUD "Hub" button, before the guard's next tick
			strand()
			expect(hubDistance()).toBeGreaterThan(100)
			sim:runAs("client", function(req)
				local path = "Players." .. sim.player.Name .. ".PlayerScripts.Client.Controllers"
				req(path .. ".RiftController").leave()
			end)
			expect(hubDistance()).toBeLessThan(10)
			sim:run(1)
			expectHome()
		end
	)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
