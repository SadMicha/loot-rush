-- Rift Trail (docs/specs/WORLD-MAPS.md §4): start pad → clearings with packs → boss arena.
local Config = require("ReplicatedStorage.Shared.Config")
local Trail = require("ReplicatedStorage.Shared.Trail")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

-- Walkable tiles reachable from the start pad (4-neighbour flood fill)
local function reachable(l: Trail.Layout): { [number]: boolean }
	local seen: { [number]: boolean } = {}
	local x0 = math.floor((l.start.x0 + l.start.x1) / 2)
	local queue = { { x0, l.start.z0 } }
	seen[Trail.key(x0, l.start.z0)] = true
	while #queue > 0 do
		local c = table.remove(queue) :: { number }
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local k = Trail.key(c[1] + d[1], c[2] + d[2])
			if l.cells[k] and not seen[k] then
				seen[k] = true
				table.insert(queue, { c[1] + d[1], c[2] + d[2] })
			end
		end
	end
	return seen
end

describe("Trail layout (pure)", function()
	it("connects the start pad through every clearing to the boss arena", function()
		for seed = 1, 40 do
			local l = Trail.layout(seed * 31)
			expect(#l.clearings).toBe(Config.TRAIL_CLEARINGS)
			local seen = reachable(l)
			for key in l.cells do
				expect(seen[key]).toBe(true)
			end
			-- walking order: clearing 1 is closest to the start, the arena is north of all
			for i = 2, #l.clearings do
				expect(l.clearings[i].z0).toBeLessThan(l.clearings[i - 1].z0)
			end
			expect(l.clearings[#l.clearings].z0).toBeGreaterThan(l.arena.z1)
			expect(l.start.z0).toBeGreaterThan(l.clearings[1].z1)
		end
	end)

	it("is the same for the same seed and differs between depths", function()
		local a, b =
			Trail.layout(Trail.seed("green_plains", 3)), Trail.layout(Trail.seed("green_plains", 3))
		expect(a.clearings[1].x0).toBe(b.clearings[1].x0)
		local differs = false
		for d = 1, 10 do
			local c = Trail.layout(Trail.seed("green_plains", d))
			if c.clearings[1].x0 ~= a.clearings[1].x0 or c.clearings[2].x0 ~= a.clearings[2].x0 then
				differs = true
			end
		end
		expect(differs).toBe(true)
	end)

	it("gives regions with equally long ids different paths", function()
		expect(Trail.seed("fire_desert", 2) ~= Trail.seed("sky_islands", 2)).toBe(true)
		expect(Trail.seed("crystal_caves", 1) ~= Trail.seed("altered_world", 1)).toBe(true)
	end)
end)

describe("Trail in game", function()
	it("starts on the start pad and puts pack 1 into clearing 1", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(0.5)
		local info = server(function(req, player)
			local World = req("ServerScriptService.Server.Systems.World")
			local Rift = req("ServerScriptService.Server.Systems.Rift")
			local slot = Rift.slotOf(player)
			local lo, hi = World.clearing(slot, 1)
			local start = World.startOf(slot)
			local root = player.Character.HumanoidRootPart.Position
			local inside, total = 0, 0
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				local p = e:GetPivot().Position
				total += 1
				if p.X >= lo.X and p.X <= hi.X and p.Z >= lo.Z and p.Z <= hi.Z then
					inside += 1
				end
			end
			return {
				atStart = (Vector3.new(root.X, 0, root.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude,
				inside = inside,
				total = total,
				walk = World.walkableAt(slot, root),
				wave = player:GetAttribute("RiftWave"),
			}
		end)
		expect(info.atStart).toBeLessThan(2)
		expect(info.walk).toBe(true)
		expect(info.total).toBeGreaterThan(0)
		expect(info.inside).toBe(info.total)
		expect(info.wave).toBe(1)
	end)

	it("lights the waypoint and moves the safe spot there after a pack is down", function()
		for _ = 1, 10 do
			local wave = sim.player:GetAttribute("RiftWave")
			if wave and wave >= 2 then
				break
			end
			server(function(req, player)
				local Combat = req("ServerScriptService.Server.Systems.Combat")
				for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
					Combat.slay(player, e)
				end
			end)
			sim:run(1)
		end
		local info = server(function(req, player)
			local World = req("ServerScriptService.Server.Systems.World")
			local Rift = req("ServerScriptService.Server.Systems.Rift")
			local slot = Rift.slotOf(player)
			local lo, hi = World.clearing(slot, 1)
			local spot = Rift.safeSpot(player)
			local folder = workspace.Arena:FindFirstChild("Region_green_plains")
			local core = folder.Trail.Waypoint_1.Core
			return {
				wave = player:GetAttribute("RiftWave"),
				inClearing = spot.X >= lo.X
					and spot.X <= hi.X
					and spot.Z >= lo.Z
					and spot.Z <= hi.Z,
				neon = core.Material == Enum.Material.Neon,
			}
		end)
		expect(info.wave).toBe(2)
		expect(info.inClearing).toBe(true)
		expect(info.neon).toBe(true)
	end)

	it("unlights every waypoint when the same map is used for the next run", function()
		local lit = server(function(req)
			local World = req("ServerScriptService.Server.Systems.World")
			World.build(nil, 1)
			World.lightWaypoint(1, 1, Color3.new(1, 0, 0))
			World.build(nil, 1) -- same region and seed: kept, but reset
			local m = workspace.Arena:FindFirstChild("Region_green_plains", true)
			local core = m and m.Trail.Waypoint_1.Core
			return core and core.Material == Enum.Material.Neon
		end)
		expect(lit).toBe(false)
	end)
end)
