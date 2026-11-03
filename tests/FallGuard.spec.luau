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
	it("fences the Hub and the arena with four invisible walls", function()
		sim:boot({ seconds = 2 })
		local hub, arena = server(function()
			local region = workspace.Arena:FindFirstChildWhichIsA("Folder")
			return walls(workspace.Lumenhaven), if region then walls(region) else 0
		end)
		expect(hub).toBe(4)
		expect(arena).toBe(4)
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
					local s = p.Size
					if s.Y < 150 or math.min(s.X, s.Z) < 8 then
						return false
					end
				end
			end
			return true
		end)
		expect(ok).toBe(true)
	end)

	it("tags every Bounds folder with its walkable rectangle in world space", function()
		local hub, arena = server(function(req)
			local Bounds = req("ReplicatedStorage.Shared.Util.Bounds")
			local cs = game:GetService("CollectionService")
			local region = workspace.Arena:FindFirstChildWhichIsA("Folder")
			local a = region.Bounds
			return cs:HasTag(workspace.Lumenhaven.Bounds, Bounds.TAG) and Bounds.read(
				workspace.Lumenhaven.Bounds
			),
				cs:HasTag(a, Bounds.TAG) and Bounds.read(a)
		end)
		expect(hub).never.toBeNil()
		expect(hub.halfX).toBe(Config.HUB_HALF)
		expect((hub.center - Config.HUB_ORIGIN).Magnitude < 0.01).toBe(true)
		expect(arena).never.toBeNil()
		expect(arena.halfX > 40).toBe(true)
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
				Bounds.pushBack(Vector3.new(55, -5, 0), rects)
		end)
		expect(near).never.toBeNil()
		expect(near.X <= 50 and near.Z <= 40 and near.X > 45).toBe(true)
		expect(inside).toBeNil()
		expect(far).toBeNil()
		expect(below).toBeNil()
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

	it("leaves a player standing in the Hub alone", function()
		local here = Config.HUB_ORIGIN + Vector3.new(10, 3, 10)
		server(function(_, player)
			player.Character:PivotTo(CFrame.new(here))
		end)
		sim:run(0.6)
		expect((rootPos() - here).Magnitude < 1).toBe(true)
	end)

	it("in a Rift brings a fallen player back to the arena start, run still going", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(0.5)
		local center = server(function(req, player)
			local c = req("ServerScriptService.Server.Systems.Rift").centerOf(player)
			if c then
				player.Character:PivotTo(CFrame.new(c + Vector3.new(0, -50, 0)))
			end
			return c
		end)
		expect(center).never.toBeNil()
		sim:run(0.6)
		expect((rootPos() - (center + Config.RIFT_START)).Magnitude < 1).toBe(true)
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
