-- Skills only work in a running Rift: the server refuses casts in the Hub (no effect, no cooldown
-- spent) and the client's SkillController does not even send them there. Dodge stays everywhere.
local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function count(name: string, dir: string): number
	local n = 0
	for _, e in sim.netLog do
		if e.name == name and e.dir == dir then
			n += 1
		end
	end
	return n
end

-- The server path: CastSkill fired straight at the remote (like an exploit would)
local function fireCast()
	sim:runAs("client", function(req)
		local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position
		req("ReplicatedStorage.Shared.Net").CastSkill:FireServer(
			1,
			root + Vector3.new(6, 0, 0),
			root
		)
	end)
	sim:run(0.5)
end

local function cooldown(): number
	return server(function(req, player)
		local Progression = req("ReplicatedStorage.Shared.Progression")
		local profile = req("ServerScriptService.Server.Systems.Data").get(player)
		local skill = Progression.barSkill(profile.progress, 1)
		return req("ServerScriptService.Server.Systems.Combat").cooldownLeft(player, skill.id)
	end)
end

local function phase(): string
	return sim.player:GetAttribute("RiftPhase") or ""
end

describe("Skills in the Hub", function()
	it("the server refuses a cast in the Hub: no SkillCast, no cooldown", function()
		sim:boot({ seconds = 2 })
		expect(phase()).toBe("")
		local before = count("SkillCast", "S→C")
		fireCast()
		expect(count("SkillCast", "S→C")).toBe(before)
		expect(cooldown()).toBe(0)
		local inRift = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Combat").inRift(player)
		end)
		expect(inRift).toBe(false)
	end)

	it("the client does not send a cast from the Hub (keys and buttons)", function()
		local before = count("CastSkill", "C→S")
		sim:pressKey(Enum.KeyCode.Q)
		sim:runAs("client", function(req)
			local path = "Players." .. sim.player.Name .. ".PlayerScripts.Client.Controllers"
			local SkillController = req(path .. ".SkillController")
			expect(SkillController.inRift()).toBe(false)
			SkillController.cast(1) -- what a HUD skill button tap calls
		end)
		sim:run(0.5)
		expect(count("CastSkill", "C→S")).toBe(before)
		expect(cooldown()).toBe(0)
	end)

	it("dodge still works in the Hub", function()
		local function rolls(): number
			local n = 0
			for _, e in sim.netLog do
				local d = e.args and e.args[2]
				if
					e.name == "Fx"
					and e.args[1] == "act"
					and type(d) == "table"
					and d.kind == "dash"
				then
					n += 1
				end
			end
			return n
		end
		local before = rolls()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Dash:FireServer()
		end)
		sim:run(0.5)
		expect(rolls()).toBe(before + 1)
	end)

	it("casts work inside a Rift and stop again after leaving it", function()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(1)
		expect(phase()).toBe("wave")
		local before = count("SkillCast", "S→C")
		fireCast()
		expect(count("SkillCast", "S→C")).toBe(before + 1)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
		end)
		sim:run(1)
		expect(phase()).toBe("")
		sim:run(10) -- the Rift cast's cooldown runs out
		local after = count("SkillCast", "S→C")
		fireCast()
		expect(count("SkillCast", "S→C")).toBe(after)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
