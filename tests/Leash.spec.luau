-- Enemy zones (Shared/Leash): players outside an enemy's clearing/arena cannot hurt it,
-- and enemies left alone in their zone heal back to full.
local Leash = require("ReplicatedStorage.Shared.Leash")

describe("Leash rules", function()
	local lo, hi = Vector3.new(0, 0, 0), Vector3.new(64, 0, 64)

	it("counts the zone plus the margin as inside", function()
		expect(Leash.inside(Vector3.new(32, 5, 32), lo, hi)).toBe(true)
		expect(Leash.inside(Vector3.new(-Leash.MARGIN, 0, 10), lo, hi)).toBe(true)
		expect(Leash.inside(Vector3.new(64 + Leash.MARGIN + 0.1, 0, 10), lo, hi)).toBe(false)
		expect(Leash.inside(Vector3.new(10, 0, 100), lo, hi)).toBe(false)
		expect(Leash.inside(Vector3.new(0 / 0, 0, 10), lo, hi)).toBe(false)
	end)

	it("only lets attackers inside the zone hit", function()
		local m = Instance.new("Model")
		expect(Leash.canHit(Vector3.new(500, 0, 500), m)).toBe(true) -- no zone: hittable
		m:SetAttribute(Leash.MIN_ATTR, lo)
		m:SetAttribute(Leash.MAX_ATTR, hi)
		expect(Leash.canHit(Vector3.new(30, 0, 30), m)).toBe(true)
		expect(Leash.canHit(Vector3.new(30, 0, 120), m)).toBe(false) -- next clearing
		expect(Leash.canHit(nil, m)).toBe(false) -- no living body
		m:Destroy()
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Enemy zones in game", function()
	local function spawnAt(req, player, offset, run)
		local Enemies = req("ServerScriptService.Server.Systems.Enemies")
		local p = player.Character.HumanoidRootPart.Position + offset
		local half = Vector3.new(30, 0, 30)
		local model = Enemies.spawn(
			"slime",
			p,
			1,
			{ center = p, bounds = { min = p - half, max = p + half }, run = run }
		)
		model:SetAttribute("SlowUntil", os.clock() + 60)
		model:SetAttribute("SlowFactor", 0)
		return model
	end

	it("lets a player inside the clearing hit its enemies", function()
		sim:boot({ seconds = 2 })
		local before, after, can = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local m = spawnAt(req, player, Vector3.new(0, 0, -10), 71)
			local hp = m:GetAttribute("Health")
			Combat.damageEnemy(m, 1, player, nil, true)
			return hp, m:GetAttribute("Health"), Combat.canHit(player, m)
		end)
		expect(can).toBe(true)
		expect(after < before).toBe(true)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(71)
		end)
	end)

	it("ignores hits from a player standing in another zone", function()
		local before, after, can = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			-- clearing 80 studs north: the player stands in the corridor/next clearing
			local m = spawnAt(req, player, Vector3.new(0, 0, -80), 72)
			local hp = m:GetAttribute("Health")
			Combat.damageEnemy(m, 1e6, player, nil, false)
			return hp, m:GetAttribute("Health"), Combat.canHit(player, m)
		end)
		expect(can).toBe(false)
		expect(after).toBe(before)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(72)
		end)
	end)

	it("gives every enemy a zone, the arena around its center by default", function()
		local hasZone = server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local p = player.Character.HumanoidRootPart.Position
			local m =
				Enemies.spawn("slime", p + Vector3.new(0, 0, -10), 1, { center = p, run = 73 })
			local lo, hi = Leash.zoneOf(m)
			local ok = lo ~= nil and hi ~= nil and Leash.inside(p, lo :: Vector3, hi :: Vector3)
			Enemies.clear(73)
			return ok
		end)
		expect(hasZone).toBe(true)
	end)

	it("heals a hurt enemy back to full when nobody is in its zone", function()
		server(function(req, player)
			local m = spawnAt(req, player, Vector3.new(0, 0, -200), 74)
			m.Name = "LeashProbe"
			m:SetAttribute("Health", 1)
		end)
		sim:run(Leash.RESET_AFTER + 1)
		local hp, max = server(function()
			local m = workspace:FindFirstChild("LeashProbe", true)
			return m:GetAttribute("Health"), m:GetAttribute("MaxHealth")
		end)
		expect(hp).toBe(max)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(74)
		end)
	end)
end)
