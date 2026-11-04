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

	it("plays both phases when one hit skips past 66 %", function()
		local boss = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"the_rift",
				root.Position + Vector3.new(0, 0, -30),
				20,
				{ center = root.Position, run = 45 }
			)
			m:SetAttribute("Health", math.floor(m:GetAttribute("MaxHealth") * 0.2))
			return m
		end)
		sim:run(0.3)
		local phase, count = server(function(req)
			return boss:GetAttribute("BossPhase"),
				req("ServerScriptService.Server.Systems.Enemies").count(45)
		end)
		expect(phase).toBe(3)
		expect(count).toBe(1 + 2 * Bosses.ADDS)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(45)
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

	it("breaks after enough hits, recovers with a bigger meter", function()
		local boss, broken, hits = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local Skills = req("ReplicatedStorage.Shared.Skills")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"crystal_king",
				root.Position + Vector3.new(0, 0, -30),
				20,
				{ center = root.Position, run = 46 }
			)
			local basic = Skills.forClass(player:GetAttribute("Class")).basic
			local n = 0
			while m:GetAttribute("Broken") ~= true and n < 40 do
				Combat.damageEnemy(m, 1, player, basic)
				n += 1
			end
			return m, m:GetAttribute("Broken"), n
		end)
		expect(broken).toBe(true)
		-- 5 per basic hit (crits chip more): the first meter never takes more than 16 hits
		expect(hits <= math.ceil(Bosses.POISE / Bosses.POISE_BASIC)).toBe(true)
		sim:run(Bosses.BREAK_TIME + 0.3)
		local after, max = server(function()
			return boss:GetAttribute("Broken"), boss:GetAttribute("PoiseMax")
		end)
		expect(after).toBeNil()
		expect(max).toBe(math.floor(Bosses.POISE * Bosses.POISE_GROWTH + 0.5))
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(46)
		end)
	end)

	it("turns a dodge roll through a boss attack into a Counter", function()
		local Status = require("ReplicatedStorage.Shared.Status")
		local got, poise, focus = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"crystal_king",
				root.Position + Vector3.new(0, 0, -30),
				20,
				{ center = root.Position, run = 47 }
			)
			Combat.dash(player)
			local through = Combat.hurtPlayer(player, 5, m)
			return through, m:GetAttribute("Poise"), player:GetAttribute(Status.attr("focus"))
		end)
		expect(got).toBe(false)
		expect(poise).toBe(Bosses.POISE - Bosses.POISE_COUNTER)
		expect(focus).never.toBeNil()
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(47)
		end)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
