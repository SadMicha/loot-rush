-- Stud Rush: kills fill the meter on the server, a full meter starts the Rush on its own inside a
-- rift (faster walking, glow, buff bar), kills during the Rush extend it, the Rush ends on time.
-- Also the buff/debuff bar (Shared/Status, Systems/Status, HUD).
local Rush = require("ReplicatedStorage.Shared.Rush")
local Status = require("ReplicatedStorage.Shared.Status")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function kill(elite: boolean?)
	server(function(req, player)
		local Enemies = req("ServerScriptService.Server.Systems.Enemies")
		local root = player.Character.HumanoidRootPart
		local e = Enemies.spawn("slime", root.Position + Vector3.new(0, 0, -30), 40, {
			center = root.Position,
			run = 66,
			elite = elite,
			mods = if elite then { "fast" } else nil,
		})
		req("ServerScriptService.Server.Systems.Combat").slay(player, e)
	end)
end

local function fill()
	server(function(req, player)
		req("ServerScriptService.Server.Systems.Rush").add(player, Rush.METER)
	end)
	sim:run(0.3)
end

local function hudFind(name)
	return sim.player.PlayerGui.LootRushHUD:FindFirstChild(name, true)
end

describe("Stud Rush", function()
	it("fills the meter from kills, more for elites", function()
		sim:boot({ seconds = 2 })
		kill()
		sim:run(0.1)
		expect(sim.player:GetAttribute("RushMeter")).toBe(Rush.PER_KILL)
		kill(true)
		sim:run(0.1)
		expect(sim.player:GetAttribute("RushMeter")).toBe(Rush.PER_KILL + Rush.PER_ELITE)
	end)

	it("has no manual trigger remote any more", function()
		expect(game:GetService("ReplicatedStorage").Remotes:FindFirstChild("Rush")).toBeNil()
	end)

	it("waits with a full meter in the hub", function()
		fill()
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
		expect(sim.player:GetAttribute("RushMeter")).toBe(Rush.METER)
		expect(hudFind("RushMeter").Visible).toBe(false) -- the meter only shows in a rift
	end)

	local walk1
	it("starts on its own in a rift: faster, glowing, meter empty, buff shown", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(0.5)
		expect(sim.player:GetAttribute("Rushing")).toBe(true)
		expect(sim.player:GetAttribute("RushMeter")).toBe(0)
		expect(sim.player:GetAttribute(Status.attr("rush"))).toBe(
			sim.player:GetAttribute("RushUntil")
		)
		local glow
		walk1, glow = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed, player.Character:FindFirstChild("RushGlow")
		end)
		expect(glow).never.toBeNil()
		expect(hudFind("RushMeter").Visible).toBe(true)
		expect(hudFind("Buff_rush")).never.toBeNil()
	end)

	it("extends the Rush with kills and ends it on time", function()
		local before = sim.player:GetAttribute("RushUntil")
		kill()
		sim:run(0.1)
		expect(sim.player:GetAttribute("RushUntil") > before).toBe(true)
		expect(sim.player:GetAttribute(Status.attr("rush"))).toBe(
			sim.player:GetAttribute("RushUntil")
		)
		expect(sim.player:GetAttribute("RushMeter")).toBe(0) -- kills during a Rush chain it
		sim:run(Rush.MAX_DURATION) -- rift kills may chain it up to the cap
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
		expect(sim.player:GetAttribute(Status.attr("rush"))).toBeNil()
		local walk2, glow = server(function(_, player)
			return player.Character.Humanoid.WalkSpeed, player.Character:FindFirstChild("RushGlow")
		end)
		expect(walk1 > walk2).toBe(true)
		expect(glow).toBeNil()
		sim:run(0.3)
		expect(hudFind("Buff_rush")).toBeNil()
	end)

	it("starts the moment a kill fills the meter", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Rush").add(player, Rush.METER - 1)
		end)
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
		kill()
		sim:run(0.1)
		expect(sim.player:GetAttribute("Rushing")).toBe(true)
	end)

	it("ends a Rush when the rift ends", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(1)
		expect(sim.player:GetAttribute("Rushing")).toBe(false)
	end)

	it("lists active buffs and debuffs in bar order", function()
		local list = Status.active({
			[Status.attr("chill")] = 15,
			[Status.attr("rush")] = 18,
			[Status.stacksAttr("rush")] = 3,
			[Status.attr("haste")] = 5, -- over
		}, 10)
		expect(#list).toBe(2)
		expect(list[1].def.id).toBe("rush")
		expect(list[1].left).toBe(8)
		expect(list[1].stacks).toBe(3)
		expect(list[2].def.id).toBe("chill")
		expect(list[2].def.debuff).toBe(true)
	end)

	it("shows the Frozen aura chill as a debuff that runs out", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").chill(player, os.clock() + 0.7, 35)
		end)
		sim:run(0.3)
		expect(sim.player:GetAttribute(Status.attr("chill"))).never.toBeNil()
		expect(hudFind("Buff_chill")).never.toBeNil()
		sim:run(1.5)
		expect(sim.player:GetAttribute(Status.attr("chill"))).toBeNil()
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
