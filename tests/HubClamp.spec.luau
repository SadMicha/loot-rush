-- The server is the last word on where a player in the Hub may stand (Systems/FallGuard): walls and
-- the client clamp can be beaten (lag spike, exploit), the server check cannot. Outside a Rift only
-- the Hub counts (no idle arena slot); a running Rift is never clamped back into the Hub, and the
-- legit Hub → Rift teleport is not undone.
local Config = require("ReplicatedStorage.Shared.Config")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function rootPos(): Vector3
	return server(function(_, player)
		return player.Character.HumanoidRootPart.Position
	end)
end

local function put(pos: Vector3)
	server(function(_, player)
		player.Character:PivotTo(CFrame.new(pos))
	end)
end

local function insideHub(pos: Vector3): boolean
	local d = pos - Config.HUB_ORIGIN
	return math.abs(d.X) <= Config.HUB_HALF and math.abs(d.Z) <= Config.HUB_HALF
end

describe("Server Hub clamp", function()
	it("a sprint or roll past the wall ends back inside within a few ticks", function()
		sim:boot({ seconds = 2 })
		put(Config.HUB_POS)
		sim:run(0.3)
		for _, offset in
			{
				Vector3.new(Config.HUB_HALF + 20, 3, 0), -- east
				Vector3.new(-(Config.HUB_HALF + 30), 3, 20), -- west
				Vector3.new(10, 3, Config.HUB_HALF + 25), -- south
				Vector3.new(Config.HUB_HALF + 15, 3, -(Config.HUB_HALF + 15)), -- corner
			}
		do
			put(Config.HUB_ORIGIN + offset)
			sim:run(Config.FALL_TICK * 3)
			expect(insideHub(rootPos())).toBe(true)
		end
	end)

	it("far out (tunnelled, launched) goes back to the spawn", function()
		put(Config.HUB_ORIGIN + Vector3.new(Config.HUB_HALF + 120, 3, 0))
		sim:run(Config.FALL_TICK * 3)
		expect((rootPos() - Config.HUB_POS).Magnitude).toBeLessThan(1)
	end)

	it("an idle arena slot is not a place to stand outside a Rift", function()
		put(Config.RIFT_START)
		sim:run(Config.FALL_TICK * 3)
		expect((rootPos() - Config.HUB_POS).Magnitude).toBeLessThan(1)
	end)

	it("the Hub → Rift teleport is not undone, and a Rift is not clamped into the Hub", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(1)
		expect(sim.player:GetAttribute("RiftPhase")).toBe("wave")
		local start = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Rift").safeSpot(player)
		end)
		sim:run(1)
		expect(insideHub(rootPos())).toBe(false)
		expect((rootPos() - start).Magnitude).toBeLessThan(Config.HUB_HALF)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(1)
		expect((rootPos() - Config.HUB_POS).Magnitude).toBeLessThan(10)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
