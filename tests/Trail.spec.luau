-- Rift Trail (docs/specs/WORLD-MAPS.md §4): start pad → clearings with packs → boss arena.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
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

-- Every region id (nil = default shape) × many depths
local function eachLayout(fn: (Trail.Layout, Trail.Shape, string) -> ())
	local ids = { "default" }
	for _, r in Atlas.Regions do
		table.insert(ids, r.id)
	end
	for _, id in ids do
		local region = if id == "default" then nil else id
		local shape = Trail.shape(region)
		for depth = 1, 30 do
			fn(Trail.layout(Trail.seed(id, depth), region), shape, id)
		end
	end
end

local function touches(a: Trail.Rect, b: Trail.Rect, gap: number): boolean
	return a.x0 - gap <= b.x1 and b.x0 - gap <= a.x1 and a.z0 - gap <= b.z1 and b.z0 - gap <= a.z1
end

-- Do the rects share a side (a 4-neighbour step leads from one into the other)?
local function adjacent(a: Trail.Rect, b: Trail.Rect): boolean
	local xs = a.x0 <= b.x1 and b.x0 <= a.x1
	local zs = a.z0 <= b.z1 and b.z0 <= a.z1
	return (xs and (a.z1 + 1 == b.z0 or b.z1 + 1 == a.z0))
		or (zs and (a.x1 + 1 == b.x0 or b.x1 + 1 == a.x0))
end

local function inside(r: Trail.Rect, x: number, z: number): boolean
	return x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
end

-- Shortest walk in tiles from the start pad to the arena (4-neighbour BFS)
local function walkLength(l: Trail.Layout): number
	local x0 = math.floor((l.start.x0 + l.start.x1) / 2)
	local dist: { [number]: number } = { [Trail.key(x0, l.start.z1)] = 0 }
	local queue = { { x0, l.start.z1 } }
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local d = dist[Trail.key(c[1], c[2])]
		if inside(l.arena, c[1], c[2]) then
			return d
		end
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local k = Trail.key(c[1] + o[1], c[2] + o[2])
			if l.cells[k] and dist[k] == nil then
				dist[k] = d + 1
				table.insert(queue, { c[1] + o[1], c[2] + o[2] })
			end
		end
	end
	return math.huge
end

describe("Trail floor plan (pure)", function()
	it("connects every tile, rooms never overlap or touch, all inside the trail bounds", function()
		eachLayout(function(l, s)
			local seen = reachable(l)
			for key in l.cells do
				expect(seen[key]).toBe(true)
			end
			-- rooms keep at least one tile apart (only corridors join them)
			local rooms: { Trail.Rect } = { l.arena, l.start }
			for _, r in l.clearings do
				table.insert(rooms, r)
			end
			for _, r in l.alcoves do
				table.insert(rooms, r)
			end
			for i = 1, #rooms do
				for j = i + 1, #rooms do
					expect(touches(rooms[i], rooms[j], 1)).toBe(false)
				end
			end
			-- the rects are exactly the walkable tiles (FallGuard / client clamp use their union)
			local union: { [number]: boolean } = {}
			for _, r in Trail.rects(l) do
				expect(r.x0 >= -s.maxX and r.x1 <= s.maxX).toBe(true)
				expect(r.x0 >= l.minX and r.x1 <= l.maxX).toBe(true)
				expect(r.z0 >= l.minZ and r.z1 <= l.maxZ).toBe(true)
				if r ~= l.arena then
					expect(r.z0).toBeGreaterThan(l.arena.z1) -- the trail lies south of the arena
				end
				for x = r.x0, r.x1 do
					for z = r.z0, r.z1 do
						union[Trail.key(x, z)] = true
					end
				end
			end
			for key in l.cells do
				expect(union[key]).toBe(true)
			end
			for key in union do
				expect(l.cells[key]).toBe(true)
			end
			-- start pad and boss arena on the walk, clearings in order toward the boss
			expect(walkLength(l) < math.huge).toBe(true)
			for i = 2, #l.clearings do
				expect(l.clearings[i].z0).toBeLessThan(l.clearings[i - 1].z0)
			end
		end)
	end)

	it("keeps alcoves dead ends reached through one neck from one clearing", function()
		local count = 0
		eachLayout(function(l)
			for _, a in l.alcoves do
				count += 1
				local necks = 0
				for _, c in l.corridors do
					if adjacent(a, c) then
						necks += 1
						local from = 0
						for _, r in l.clearings do
							if adjacent(c, r) then
								from += 1
							end
						end
						expect(from).toBe(1)
					end
				end
				expect(necks).toBe(1)
				-- every walkable tile next to the alcove belongs to that neck
				for x = a.x0 - 1, a.x1 + 1 do
					for z = a.z0 - 1, a.z1 + 1 do
						if not inside(a, x, z) and l.cells[Trail.key(x, z)] then
							local inNeck = false
							for _, c in l.corridors do
								inNeck = inNeck or (inside(c, x, z) and adjacent(a, c))
							end
							expect(inNeck).toBe(true)
						end
					end
				end
			end
		end)
		expect(count).toBeGreaterThan(0)
	end)

	it("is reproducible per seed and region", function()
		local function dump(l: Trail.Layout): string
			local parts = {}
			for _, r in Trail.rects(l) do
				table.insert(parts, `{r.x0},{r.x1},{r.z0},{r.z1}`)
			end
			return table.concat(parts, ";")
		end
		for _, id in { "green_plains", "crystal_caves", "sky_islands", "fire_desert" } do
			for depth = 1, 5 do
				local seed = Trail.seed(id, depth)
				expect(dump(Trail.layout(seed, id))).toBe(dump(Trail.layout(seed, id)))
			end
		end
	end)

	it("has a wider hall before the boss, jogs and a similar walk", function()
		local jogs, total, walk, runs = 0, 0, 0, 0
		eachLayout(function(l, s, id)
			expect(l.clearings[#l.clearings].x1 - l.clearings[#l.clearings].x0 + 1).toBe(s.hall)
			for i = 1, Config.TRAIL_CLEARINGS do
				total += 1
				if l.corridors[i].x1 - l.corridors[i].x0 + 1 > s.corridorWidth then
					jogs += 1
				end
			end
			if id == "default" or id == "green_plains" then
				walk += walkLength(l)
				runs += 1
			end
		end)
		expect(jogs).toBeGreaterThan(0)
		expect(jogs).toBeLessThan(total)
		-- old straight trail: 3 × (3-tile corridor + 8-tile clearing) + tail ≈ 35 tiles
		local mean = walk / runs
		expect(mean).toBeGreaterThan(30)
		expect(mean).toBeLessThan(50)
	end)

	it("has shapes whose clearings fit a straight corridor", function()
		for _, id in { "default", "crystal_caves", "mushroom_swamp", "fire_desert", "sky_islands" } do
			local s = Trail.shape(if id == "default" then nil else id)
			expect(s.roomMin >= s.corridorWidth + 2).toBe(true)
			expect(s.roomMin <= s.roomMax).toBe(true)
			expect(s.bendsMin <= s.bendsMax).toBe(true)
		end
		expect(Trail.shape("fire_desert").hall).toBeGreaterThan(Trail.shape(nil).hall)
		expect(Trail.shape("crystal_caves").bendsMin).toBe(2)
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

	it(
		"a death respawns at the last lit waypoint once per depth, the second fails the run",
		function()
			local function die()
				server(function(_, player)
					player.Character:FindFirstChildOfClass("Humanoid").Health = 0
				end)
				sim:run(0.3)
			end
			expect(sim.player:GetAttribute("RiftRevives")).toBe(Config.RIFT_REVIVES)
			die()
			expect(sim.player:GetAttribute("RiftDowned")).toBe(true)
			expect(sim.player:GetAttribute("RiftPhase")).toBe("wave")
			sim:spawnCharacter() -- the engine respawns the player in the Hub
			sim:run(0.5)
			local info = server(function(req, player)
				local Rift = req("ServerScriptService.Server.Systems.Rift")
				local spot = Rift.safeSpot(player)
				local root = player.Character.HumanoidRootPart.Position
				return {
					running = Rift.isRunning(player),
					dist = (Vector3.new(root.X, 0, root.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude,
					health = player.Character:FindFirstChildOfClass("Humanoid").Health,
				}
			end)
			expect(info.running).toBe(true)
			expect(info.dist).toBeLessThan(2)
			expect(info.health).toBeGreaterThan(0)
			expect(sim.player:GetAttribute("RiftDowned")).toBeNil()
			expect(sim.player:GetAttribute("RiftRevives")).toBe(0)
			expect(sim.player:GetAttribute("RiftWave")).toBe(2) -- same pack, the run went on
			die()
			local running = server(function(req, player)
				return req("ServerScriptService.Server.Systems.Rift").isRunning(player)
			end)
			expect(running).toBe(false)
			expect(sim.player:GetAttribute("RiftPhase")).toBe("failed")
			sim:spawnCharacter()
			sim:run(Config.RESPAWN_TIME + 1.5)
		end
	)

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
