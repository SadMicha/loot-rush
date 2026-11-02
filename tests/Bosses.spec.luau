-- Boss phases (adds at 66 %, enrage at 33 %) and rift variants (rules and the goblin in game).
local Bosses = require("ReplicatedStorage.Shared.Bosses")
local RiftVariants = require("ReplicatedStorage.Shared.RiftVariants")

describe("Rift variants", function()
	it("keep the first depths plain and roll every variant later", function()
		local rng = Random.new(11)
		for _ = 1, 50 do
			expect(RiftVariants.roll(rng, 1)).toBe("")
			expect(RiftVariants.roll(rng, RiftVariants.FROM_DEPTH - 1)).toBe("")
		end
		local seen = {}
		for _ = 1, 2000 do
			seen[RiftVariants.roll(rng, 10)] = true
		end
		expect(seen[""]).toBe(true)
		for _, v in RiftVariants.List do
			expect(seen[v.id]).toBe(true)
		end
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Bosses and variants in game", function()
	it("calls adds at 66 % and enrages at 33 %", function()
		sim:boot({ seconds = 2 })
		local boss = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"the_rift",
				root.Position + Vector3.new(0, 0, -30),
				20,
				{ center = root.Position, run = 44 }
			)
			m:SetAttribute("Health", math.floor(m:GetAttribute("MaxHealth") * 0.6))
			return m
		end)
		sim:run(0.3)
		local phase, count = server(function(req)
			return boss:GetAttribute("BossPhase"),
				req("ServerScriptService.Server.Systems.Enemies").count(44)
		end)
		expect(phase).toBe(2)
		expect(count).toBe(1 + Bosses.ADDS)
		server(function()
			boss:SetAttribute("Health", math.floor(boss:GetAttribute("MaxHealth") * 0.2))
		end)
		sim:run(0.3)
		local enraged, phase3 = server(function()
			return boss:GetAttribute("Enraged"), boss:GetAttribute("BossPhase")
		end)
		expect(enraged).toBe(true)
		expect(phase3).toBe(3)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(44)
		end)
	end)

	it("lets the Treasure Goblin flee and escape", function()
		local goblin, d0 = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"slime",
				root.Position + Vector3.new(0, 0, -20),
				30,
				{ center = root.Position, run = 43, goblin = true }
			)
			return m, ((m:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
		end)
		expect(goblin.Name).toBe("Treasure Goblin")
		sim:run(1)
		local d1 = server(function(_, player)
			local root = player.Character.HumanoidRootPart
			return ((goblin:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
		end)
		expect(d1 > d0).toBe(true)
		sim:run(RiftVariants.GOBLIN_TIME)
		local left = server(function(req)
			return req("ServerScriptService.Server.Systems.Enemies").count(43)
		end)
		expect(left).toBe(0)
	end)

	it("halves enemy life in a swarm", function()
		local full, half = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character.HumanoidRootPart
			local a =
				Enemies.spawn("slime", root.Position + Vector3.new(0, 0, -30), 30, { run = 42 })
			local b = Enemies.spawn(
				"slime",
				root.Position + Vector3.new(4, 0, -30),
				30,
				{ run = 42, healthMult = RiftVariants.SWARM_HEALTH }
			)
			local x, y = a:GetAttribute("MaxHealth"), b:GetAttribute("MaxHealth")
			Enemies.clear(42)
			return x, y
		end)
		expect(half).toBe(math.floor(full * RiftVariants.SWARM_HEALTH))
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
