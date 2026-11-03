-- Stud Rush: kills fill the meter on the server, a full meter starts a Rush through the real
-- remote (faster walking, glow), kills during the Rush extend it, the Rush ends on time.
local Rush = require("ReplicatedStorage.Shared.Rush")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function kill(elite: boolean?)
	server(function(req, player)
		local Enemies = req("ServerScriptService.Server.Systems.Enemies")
		local root = player.Character.HumanoidRootPart
		local e = Enemies.spawn("slime", root.Position + Vector3.new(0, 0, -30), 40, {
			center = root.Position,
			run = 66,
			elite = elite,
			mods = if elite then { "fast" } else nil,
		})
		req("ServerScriptService.Server.Systems.Combat").slay(player, e)
	end)
end

local function startRush()
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rush:FireServer("start")
	end)
	sim:run(0.3)
end

describe("Stud Rush", function()
	it("fills the meter from kills, more for elites", function()
		sim:boot({ seconds = 2 })
		kill()
		sim:run(0.1)
		expect(sim.player:GetAttribute("RushMeter")).toBe(Rush.PER_KILL)
		kill(true)
		sim:run(0.1)
		expect(sim.player:GetAttribute("RushMeter")).toBe(Rush.PER_KILL + Rush.PER_ELITE)
	end)

	it("refuses a Rush with a meter that is not full", function()
		startRush()
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
	end)

	it("starts a Rush only inside a rift", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Rush").add(player, Rush.METER)
		end)
		startRush() -- in the hub: refused, the meter stays full
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
		expect(sim.player:GetAttribute("RushMeter")).toBe(Rush.METER)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(0.5)
	end)

	it("starts a Rush with a full meter: faster, glowing, meter empty", function()
		local walk0 = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed
		end)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Rush").add(player, Rush.METER)
		end)
		startRush()
		expect(sim.player:GetAttribute("Rushing")).toBe(true)
		expect(sim.player:GetAttribute("RushMeter")).toBe(0)
		local walk1, glow = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed, player.Character:FindFirstChild("RushGlow")
		end)
		expect(walk1 > walk0).toBe(true)
		expect(glow).never.toBeNil()
	end)

	it("extends the Rush with kills and ends it on time", function()
		local before = sim.player:GetAttribute("RushUntil")
		kill()
		sim:run(0.1)
		expect(sim.player:GetAttribute("RushUntil") > before).toBe(true)
		expect(sim.player:GetAttribute("RushMeter")).toBe(0) -- kills during a Rush chain it
		sim:run(Rush.MAX_DURATION) -- rift kills may chain it up to the cap
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
		local glow = server(function(_, player)
			return player.Character:FindFirstChild("RushGlow")
		end)
		expect(glow).toBeNil()
	end)

	it("ends a Rush when the rift ends", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Rush").add(player, Rush.METER)
		end)
		startRush()
		expect(sim.player:GetAttribute("Rushing")).toBe(true)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(1)
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
