-- Nobody falls off a map: invisible walls around the Hub and every arena, and the FallGuard puts
-- anyone below the floor or outside the walls back on a safe spot.
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

local function walls(folder: Instance): number
	local bounds = folder:FindFirstChild("Bounds")
	local n = 0
	if bounds then
		for _, p in bounds:GetChildren() do
			if p:IsA("BasePart") and p.CanCollide and p.Anchored and p.Transparency == 1 then
				n += 1
			end
		end
	end
	return n
end

describe("Fall guard", function()
	it("fences the Hub with four invisible walls and the whole Rift Trail map", function()
		sim:boot({ seconds = 2 })
		local hub, arena = server(function()
			local region = workspace.Arena:FindFirstChildWhichIsA("Folder")
			return walls(workspace.Lumenhaven), if region then walls(region) else 0
		end)
		expect(hub).toBe(4)
		expect(arena).toBeGreaterThan(8) -- arena + corridors + clearings
	end)

	it("walls answer raycasts, so a leap stops at the edge instead of passing through", function()
		local all = server(function()
			for _, p in workspace.Lumenhaven.Bounds:GetChildren() do
				if not (p:IsA("BasePart") and p.CanQuery) then
					return false
				end
			end
			return true
		end)
		expect(all).toBe(true)
	end)

	it("walls are tall and thick enough that nobody sprints or dashes over them", function()
		local ok = server(function()
			local region = workspace.Arena:FindFirstChildWhichIsA("Folder")
			for _, folder in { workspace.Lumenhaven, region } do
				for _, p in folder.Bounds:GetChildren() do
					local s = if p:IsA("BasePart") then p.Size else Vector3.new(8, 200, 8)
					if s.Y < 150 or math.min(s.X, s.Z) < 8 then
						return false
					end
				end
			end
			return true
		end)
		expect(ok).toBe(true)
	end)

	it("tags the walkable rectangles of every map in world space", function()
		local hub, areas, covered = server(function(req)
			local Bounds = req("ReplicatedStorage.Shared.Util.Bounds")
			local World = req("ServerScriptService.Server.Systems.World")
			local cs = game:GetService("CollectionService")
			local region = workspace.Arena:FindFirstChildWhichIsA("Folder")
			local rects = {}
			for _, a in region.Bounds:GetChildren() do
				if cs:HasTag(a, Bounds.TAG) then
					table.insert(rects, Bounds.read(a))
				end
			end
			-- every rectangle center is on a walkable tile (the union matches the trail)
			local ok = #rects > 0
			for _, r in rects do
				ok = ok and World.walkableAt(1, r.center)
			end
			local hubBounds = workspace.Lumenhaven.Bounds
			local trail = req("ReplicatedStorage.Shared.Trail")
			-- one Area per rectangle of the layout (arena, start, corridors, clearings, alcoves)
			ok = ok and #rects == #trail.rects(World.layoutOf(1))
			return cs:HasTag(hubBounds, Bounds.TAG) and Bounds.read(hubBounds), #rects, ok
		end)
		expect(hub).never.toBeNil()
		expect(hub.halfX).toBe(Config.HUB_HALF)
		expect((hub.center - Config.HUB_ORIGIN).Magnitude < 0.01).toBe(true)
		expect(areas >= 3 + Config.TRAIL_CLEARINGS * 2).toBe(true) -- arena, start, links + tail, clearings
		expect(covered).toBe(true)
	end)

	it("pushes back to the edge a player who got a little past a wall", function()
		local start = Config.HUB_ORIGIN + Vector3.new(Config.HUB_HALF + 12, 5, 10)
		server(function(_, player)
			player.Character:PivotTo(CFrame.new(start))
		end)
		sim:run(0.6)
		local pos = rootPos()
		local edge = Config.HUB_ORIGIN.X + Config.HUB_HALF
		expect(pos.X <= edge).toBe(true)
		expect(pos.X > edge - 4).toBe(true) -- at the edge, not back on the spawn
		expect(math.abs(pos.Z - start.Z) < 1).toBe(true)
	end)

	it("clamps to the closest map and leaves far or fallen players to the full rescue", function()
		local near, inside, far, below = server(function(req)
			local Bounds = req("ReplicatedStorage.Shared.Util.Bounds")
			local rects = {
				{ center = Vector3.zero, halfX = 50, halfZ = 40 },
				{ center = Vector3.new(1000, 0, 0), halfX = 50, halfZ = 40 },
			}
			return Bounds.pushBack(Vector3.new(60, 3, 45), rects),
				Bounds.pushBack(Vector3.new(10, 3, 0), rects),
				Bounds.pushBack(Vector3.new(500, 3, 0), rects),
				Bounds.pushBack(Vector3.new(55, -10, 0), rects)
		end)
		expect(near).never.toBeNil()
		expect(near.X <= 50 and near.Z <= 40 and near.X > 45).toBe(true)
		expect(inside).toBeNil()
		expect(far).toBeNil()
		expect(below).toBeNil()
		local river = server(function(req)
			local Bounds = req("ReplicatedStorage.Shared.Util.Bounds")
			return Bounds.pushBack(
				Vector3.new(55, -1, 0),
				{ { center = Vector3.zero, halfX = 50, halfZ = 40 } }
			)
		end)
		expect(river).never.toBeNil() -- slightly below map level (river) still gets the edge, not the spawn
	end)

	it("puts a player who fell below the Hub back on the spawn", function()
		server(function(_, player)
			player.Character:PivotTo(CFrame.new(Config.HUB_ORIGIN + Vector3.new(0, -60, 0)))
		end)
		sim:run(0.6)
		local pos = rootPos()
		expect((pos - Config.HUB_POS).Magnitude < 1).toBe(true)
	end)

	it("puts a player far outside every map back into the Hub", function()
		server(function(_, player)
			player.Character:PivotTo(CFrame.new(-300, 5, 900))
		end)
		sim:run(0.6)
		expect((rootPos() - Config.HUB_POS).Magnitude < 1).toBe(true)
	end)

	it("puts a player who glitched onto a roof or cliff in the Hub back on the spawn", function()
		local hubTop = server(function(req)
			local Bounds = req("ReplicatedStorage.Shared.Util.Bounds")
			local r = Bounds.read(workspace.Lumenhaven.Bounds)
			return r and r.top
		end)
		expect(hubTop).toBe(Config.HUB_TOP)
		server(function(_, player)
			player.Character:PivotTo(
				CFrame.new(Config.HUB_ORIGIN + Vector3.new(-70, Config.HUB_TOP + 8, 70))
			)
		end)
		sim:run(0.6)
		expect((rootPos() - Config.HUB_POS).Magnitude < 1).toBe(true)
	end)

	it("leaves a player on the Rift terrace alone (below the Hub ceiling)", function()
		local here = Config.HUB_ORIGIN + Vector3.new(0, 9, -64)
		server(function(_, player)
			player.Character:PivotTo(CFrame.new(here))
		end)
		sim:run(0.6)
		expect((rootPos() - here).Magnitude < 1).toBe(true)
	end)

	it("leaves a player standing in the Hub alone", function()
		local here = Config.HUB_ORIGIN + Vector3.new(10, 3, 10)
		server(function(_, player)
			player.Character:PivotTo(CFrame.new(here))
		end)
		sim:run(0.6)
		expect((rootPos() - here).Magnitude < 1).toBe(true)
	end)

	it("in a Rift brings a fallen player back to the trail start, run still going", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(0.5)
		local spot = server(function(req, player)
			local Rift = req("ServerScriptService.Server.Systems.Rift")
			local c = Rift.centerOf(player)
			if c then
				player.Character:PivotTo(CFrame.new(c + Vector3.new(0, -50, 0)))
			end
			return Rift.safeSpot(player)
		end)
		expect(spot).never.toBeNil()
		sim:run(0.6)
		expect((rootPos() - spot).Magnitude < 1).toBe(true)
		local region = server(function(_, player)
			return player:GetAttribute("RiftRegion")
		end)
		expect(region).toBe("green_plains")
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(0.5)
	end)
end)
