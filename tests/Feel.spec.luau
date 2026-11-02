-- Combat feel: kills break into studded bricks (Brick Break), hits chip bricks and flash the
-- enemy white, knockback pushes enemies, every brick fades again, hits carry who and what.
-- The real client controllers run from PlayerScripts, so the specs watch the world (the
-- workspace "Bricks" folder, the HitFlash highlight) instead of module state.

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function bricks(): number
	local folder = workspace:FindFirstChild("Bricks")
	return if folder then #folder:GetChildren() else 0
end

-- Spawns a slime near the player that cannot walk (slow factor 0) so positions stay predictable
local function spawnSlime(offset: Vector3): Model
	return server(function(req, player)
		local Enemies = req("ServerScriptService.Server.Systems.Enemies")
		local root = player.Character.HumanoidRootPart
		local slime =
			Enemies.spawn("slime", root.Position + offset, 1, { center = root.Position, run = 77 })
		slime:SetAttribute("SlowUntil", os.clock() + 60)
		slime:SetAttribute("SlowFactor", 0)
		return slime
	end)
end

local function clear()
	server(function(req)
		req("ServerScriptService.Server.Systems.Enemies").clear(77)
	end)
end

describe("Combat feel", function()
	it("breaks a killed enemy into bricks", function()
		sim:boot({ seconds = 2 })
		local before = bricks()
		local slime = spawnSlime(Vector3.new(0, 0, -12))
		sim:run(0.2)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").slay(player, slime)
		end)
		sim:run(0.5)
		expect(bricks()).toBeGreaterThan(before + 5)
	end)

	it("fades every brick out again", function()
		sim:run(2)
		expect(bricks()).toBe(0)
	end)

	it("flashes and chips a hit enemy", function()
		local slime = spawnSlime(Vector3.new(0, 0, -12))
		sim:run(0.2)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").damageEnemy(slime, 1, player)
		end)
		local flashed = false
		for _ = 1, 10 do
			sim:run(1 / 60)
			flashed = flashed or slime:FindFirstChild("HitFlash") ~= nil
		end
		expect(flashed).toBe(true)
		expect(bricks()).toBeGreaterThan(0)
		sim:run(1)
		expect(slime:FindFirstChild("HitFlash")).toBeNil()
		clear()
		sim:run(1.5)
	end)

	it("pushes a hit enemy away from the attacker", function()
		local slime = spawnSlime(Vector3.new(0, 0, -8))
		sim:run(0.1)
		local function dist(): number
			return server(function(_, player)
				local root = player.Character.HumanoidRootPart
				return ((slime:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			end)
		end
		local d0 = dist()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Enemies").knockback(
				slime,
				player.Character.HumanoidRootPart.Position,
				true
			)
		end)
		sim:run(0.5)
		expect(dist()).toBeGreaterThan(d0 + 1)
		clear()
	end)

	it("tags hits with the attacker and the target", function()
		local slime = spawnSlime(Vector3.new(0, 0, -12))
		sim:run(0.1)
		local got
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Fx.OnClientEvent:Connect(function(kind, data)
				if kind == "dmg" and data.target then
					got = data
				end
			end)
		end)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").damageEnemy(slime, 1, player)
		end)
		sim:run(0.2)
		expect(got).never.toBeNil()
		expect(got.by).toBe(game:GetService("Players"):GetPlayers()[1].UserId)
		expect(got.target).toBe(slime)
		clear()
	end)
end)
