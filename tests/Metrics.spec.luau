-- Metrics: one measurement window per player/run, so parallel Rifts don't mix their reports.

describe("Metrics with two Rifts at once", function()
	it("keeps kills, damage, enemy peak and LastReport per player", function()
		sim:boot({ seconds = 2 })
		local first = game:GetService("Players"):GetPlayers()[1]
		sim:joinPlayer("Second")
		sim:run(1)
		local second = sim.player
		sim:runAs("server", function(req)
			local Metrics = req("ServerScriptService.Server.Systems.Metrics")
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			Metrics.begin(first, 101)
			Metrics.begin(second, 202)
			local far = Vector3.new(0, 3, 5000)
			Enemies.spawn("slime", far, 1, { run = 101 })
			Enemies.spawn("slime", far + Vector3.new(6, 0, 0), 1, { run = 101 })
			Enemies.spawn("slime", far + Vector3.new(12, 0, 0), 1, { run = 202 })
			Combat.EnemyKilled:Fire(first)
			Combat.PlayerHurt:Fire(second, 7)
		end)
		sim:run(1.5) -- at least one server sample for the enemy peak
		local open1, open2
		sim:runAs("server", function(req)
			local Metrics = req("ServerScriptService.Server.Systems.Metrics")
			open1 = Metrics.windowOf(first)
			open2 = Metrics.windowOf(second)
			Metrics.report(first, "Depth 1 cleared")
		end)
		expect(open1.kills).toBe(1)
		expect(open1.damage).toBe(0)
		expect(open1.peak).toBe(2)
		expect(open2.kills).toBe(0)
		expect(open2.damage).toBe(7)
		expect(open2.peak).toBe(1)

		local line1 = first:GetAttribute("LastReport")
		expect(line1).toMatch("1 kills")
		expect(line1).toMatch("enemies max 2")
		expect(second:GetAttribute("LastReport")).toBeNil() -- second window still open

		local stillOpen
		sim:runAs("server", function(req)
			local Metrics = req("ServerScriptService.Server.Systems.Metrics")
			stillOpen = Metrics.windowOf(second) ~= nil
			Metrics.report(second, "Depth 1 left")
			req("ServerScriptService.Server.Systems.Enemies").clear()
		end)
		expect(stillOpen).toBe(true)
		local line2 = second:GetAttribute("LastReport")
		expect(line2).toMatch("0 kills")
		expect(line2).toMatch("7 damage")
		expect(line2).toMatch("enemies max 1")
		expect(first:GetAttribute("LastReport")).toBe(line1) -- untouched by the second report
	end)
end)
