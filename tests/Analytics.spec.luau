-- Analytics facade (Systems/Analytics, ROADMAP N10): onboarding funnel from the first join,
-- Rift progression start/complete/fail per depth, LevelUp custom event.

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function recent(): { any }
	return server(function(req)
		return table.clone(req("ServerScriptService.Server.Systems.Analytics").recent)
	end)
end

local function find(kind: string, pred: ((any) -> boolean)?): any
	for _, e in recent() do
		if e.kind == kind and (pred == nil or pred(e)) then
			return e
		end
	end
	return nil
end

describe("Analytics", function()
	it("logs the funnel from the first join through hero setup and the first quest", function()
		sim:boot({ seconds = 3 })
		local joined = find("funnel", function(e)
			return e.step == 1
		end)
		expect(joined).toBeTruthy()
		expect(joined.name).toBe("joined")
		expect(joined.userId).toBe(sim.player.UserId)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Stat Hero", "warrior")
		end)
		sim:run(1)
		local hero = find("funnel", function(e)
			return e.step == 2
		end)
		expect(hero).toBeTruthy()
		expect(hero.name).toBe("hero_created")
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(1)
		local quest = find("funnel", function(e)
			return e.step == 3
		end)
		expect(quest).toBeTruthy()
		expect(quest.name).toBe("enter_rift")
		local start = find("rift_start")
		expect(start).toBeTruthy()
		expect(start.value).toBe(1)
		expect(start.name).toBe("green_plains")
	end)

	it("does not count leaving mid-depth as a fail", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(1)
		expect(find("rift_fail")).toBeNil()
	end)

	it("logs a fail only for an open depth, and LevelUp on level gains", function()
		server(function(req, player)
			local A = req("ServerScriptService.Server.Systems.Analytics")
			A.riftStart(player, 4, "green_plains")
			A.riftClear(player, 4, "green_plains")
			A.riftEnd(player, true, "green_plains") -- died after the clear: no fail
			A.riftStart(player, 5, "green_plains")
			A.riftEnd(player, true, "green_plains")
			local level = player:GetAttribute("Level") or 1
			player:SetAttribute("Level", level + 1)
		end)
		sim:run(0.2)
		local fails = 0
		for _, e in recent() do
			if e.kind == "rift_fail" then
				fails += 1
				expect(e.value).toBe(5)
			end
		end
		expect(fails).toBe(1)
		expect(find("rift_clear", function(e)
			return e.value == 4
		end)).toBeTruthy()
		local up = find("custom", function(e)
			return e.name == "LevelUp"
		end)
		expect(up).toBeTruthy()
	end)
end)
