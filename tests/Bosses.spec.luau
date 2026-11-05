-- Boss phases (adds at 66 %, enrage at 33 %) and rift affixes (rules and the goblin in game).
local Bosses = require("ReplicatedStorage.Shared.Bosses")
local RiftAffixes = require("ReplicatedStorage.Shared.RiftAffixes")

describe("Rift affixes", function()
	it("have unique ids, a rule text and a reward weight", function()
		local seen = {}
		for _, a in RiftAffixes.List do
			expect(seen[a.id]).toBeNil()
			seen[a.id] = true
			expect(#a.text > 0).toBe(true)
			expect(a.weight >= 1).toBe(true)
		end
		expect(#RiftAffixes.List >= 11).toBe(true)
	end)
end)

describe("Boss teaching by depth", function()
	it("starts with the Break meter only and adds one idea at a time", function()
		local d1 = Bosses.rules(1)
		expect(d1.maxPhase).toBe(1)
		expect(d1.adds).toBe(false)
		expect(d1.mortar).toBe(false)
		expect(d1.openings).toBe(false)
		expect(d1.counter).toBe(false)
		expect(d1.pursuit).toBe(false)
		expect(d1.health < 1).toBe(true) -- eased first boss (EASE_HEALTH)
		local d3 = Bosses.rules(3)
		expect(d3.maxPhase).toBe(2)
		expect(d3.openings).toBe(true)
		expect(d3.counter).toBe(true)
		expect(d3.adds).toBe(false)
		expect(Bosses.rules(4).pursuit).toBe(true)
		local d5 = Bosses.rules(5)
		expect(d5.maxPhase).toBe(3)
		expect(d5.adds).toBe(true)
		expect(d5.mortar).toBe(true)
		expect(d5.health).toBe(1)
		expect(Bosses.rules(30).health).toBe(1)
		expect(Bosses.rules(0 / 0).maxPhase).toBe(1) -- NaN depth: the gentlest rules
		-- life grows back to full over the first depths
		for d = 2, 5 do
			expect(Bosses.rules(d).health >= Bosses.rules(d - 1).health).toBe(true)
		end
	end)

	it("measures Pursuit against the player's own reach", function()
		-- Green Plains boss: range 11. Ranger basic 38, Spark Mage 30
		expect(Bosses.reach(11, 38)).toBe(38 + Bosses.PURSUIT_MARGIN)
		expect(Bosses.reach(11, 30)).toBe(30 + Bosses.PURSUIT_MARGIN)
		expect(Bosses.reach(11, 8)).toBe(11 + Bosses.PURSUIT_MARGIN)
		expect(Bosses.reach(11, nil)).toBe(11 + Bosses.PURSUIT_MARGIN)
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
		sim:run(RiftAffixes.GOBLIN_TIME)
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
				{ run = 42, healthMult = RiftAffixes.SWARM_HEALTH }
			)
			local x, y = a:GetAttribute("MaxHealth"), b:GetAttribute("MaxHealth")
			Enemies.clear(42)
			return x, y
		end)
		expect(half).toBe(math.floor(full * RiftAffixes.SWARM_HEALTH))
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

	it("keeps a depth 1 boss in phase 1, without adds, and shorter", function()
		local phase, eased, full = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"crystal_king",
				root.Position + Vector3.new(0, 0, -30),
				1,
				{ center = root.Position, run = 48 }
			)
			m:SetAttribute("Health", math.floor(m:GetAttribute("MaxHealth") * 0.2))
			return m,
				Enemies.stats("crystal_king", 1).health,
				Enemies.stats("crystal_king", 5).health
		end)
		sim:run(0.3)
		local stage, n = server(function(req)
			return phase:GetAttribute("BossPhase"),
				req("ServerScriptService.Server.Systems.Enemies").count(48)
		end)
		expect(stage).toBeNil() -- never left phase 1
		expect(n).toBe(1)
		-- depth 1 life is eased well below what depth growth alone gives
		local Balance = require("ReplicatedStorage.Shared.Balance")
		local raw = full / Balance.enemyHealth(5) * Balance.enemyHealth(1)
		expect(math.abs(eased - raw * Bosses.rules(1).health) <= 2).toBe(true)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(48)
		end)
	end)

	it("treats a dodge at depth 1 as a plain dodge, not a Counter", function()
		local got, poise = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local root = player.Character.HumanoidRootPart
			local m = Enemies.spawn(
				"crystal_king",
				root.Position + Vector3.new(0, 0, -30),
				1,
				{ center = root.Position, run = 49 }
			)
			Combat.dash(player)
			return Combat.hurtPlayer(player, 5, m), m:GetAttribute("Poise")
		end)
		expect(got).toBe(false)
		expect(poise).toBe(Bosses.POISE)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(49)
		end)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
