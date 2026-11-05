-- Boss loot burst (Systems/Loot, FxController): a boss's drops fountain out one after another and
-- land on a ring around it, the best item last; the server sends the flight paths once and creates
-- each real drop when its arc arrives.
local Config = require("ReplicatedStorage.Shared.Config")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function lootCount(): number
	local folder = workspace:FindFirstChild("Loot")
	return if folder then #folder:GetChildren() else 0
end

describe("Loot burst plan (pure)", function()
	it("spreads drops on a ring, items inside, and fits in the burst span", function()
		local Loot = server(function(req)
			return req("ServerScriptService.Server.Systems.Loot")
		end)
		local mid = (Config.LOOT_BURST_RADIUS_MIN + Config.LOOT_BURST_RADIUS_MAX) / 2
		for _, n in { 1, 3, 8, 30 } do
			local items = math.min(3, n)
			local pos = Vector3.new(10, 5, -4)
			local plan = Loot.burstPlan(pos, n, items, Random.new(n))
			expect(#plan).toBe(n)
			local last = -1
			for i, p in plan do
				expect(p.delay).toBeGreaterThanOrEqual(last)
				last = p.delay
				local dist = (Vector3.new(p.at.X, 0, p.at.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
				expect(dist).toBeGreaterThanOrEqual(Config.LOOT_BURST_RADIUS_MIN - 0.01)
				expect(dist).toBeLessThanOrEqual(Config.LOOT_BURST_RADIUS_MAX + 0.01)
				if i > n - items then
					expect(dist).toBeLessThanOrEqual(mid + 0.01)
				else
					expect(dist).toBeGreaterThanOrEqual(mid - 0.01)
				end
			end
			expect(last + Config.LOOT_BURST_FLIGHT).toBeLessThanOrEqual(
				Config.LOOT_BURST_SPAN + 0.001
			)
		end
		-- the leftovers are vacuumed only after the whole burst landed
		expect(Loot.VACUUM_DELAY).toBeGreaterThan(Config.LOOT_BURST_SPAN)
	end)
end)

describe("Loot burst in game", function()
	it("sends one burst for a boss kill and the drops arrive as the arcs land", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer(
				"setup",
				"Burst Hero",
				"knight"
			)
		end)
		sim:run(1)
		local before = lootCount()
		local start = #sim.netLog
		server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local pos = player.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 200)
			Combat.EnemyKilled:Fire(player, pos, 1, true, nil, 1, 1, nil, 100, false)
		end)
		local burst = nil
		for i = start + 1, #sim.netLog do
			local n = sim.netLog[i]
			if n.name == "Fx" and n.dir == "S→C" and n.args[1] == "lootburst" then
				burst = n.args[2]
			end
		end
		expect(burst).toBeTruthy()
		expect(#burst.arcs).toBeGreaterThan(Config.LOOT_BOSS_GOLD_DROPS)
		expect(lootCount()).toBe(before) -- nothing has landed yet
		sim:run(Config.LOOT_BURST_SPAN + 0.3)
		expect(lootCount()).toBe(before + #burst.arcs)
		-- the best item flies last
		local lastArc = burst.arcs[#burst.arcs]
		expect(lastArc.big).toBe(true)
	end)
end)
