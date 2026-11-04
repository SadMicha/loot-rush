-- Four classes: every class has a basic attack and 8 skills (4 on the starting bar), the bar
-- fits the class, class choice through the real remote, the new skill kinds hit in game.
local Classes = require("ReplicatedStorage.Shared.Classes")
local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")

describe("Class kits", function()
	it("give every class a basic attack, 8 skills and a valid starting bar", function()
		local seen = {}
		for _, class in Classes.List do
			local kit = Skills.forClass(class.id)
			expect(kit.basic.class).toBe(class.id)
			expect(Skills.ById[kit.basic.id]).toBeNil() -- the basic attack never goes on the bar
			expect(#kit.list).toBe(8)
			local unlocks = 0
			for _, s in kit.list do
				expect(s.class).toBe(class.id)
				expect(seen[s.id]).toBeNil()
				seen[s.id] = true
				expect(Skills.ById[s.id]).toBe(s)
				expect(Skills.Blooms[s.id]).never.toBeNil()
				expect(s.cooldown > 0).toBe(true)
				if s.unlock then
					unlocks += 1
				end
			end
			expect(unlocks).toBe(4)
			expect(#kit.bar).toBe(Skills.SLOTS)
			for _, id in kit.bar do
				expect(Skills.ById[id].class).toBe(class.id)
				expect(Skills.ById[id].unlock).toBeNil()
			end
		end
	end)

	it("refits the bar to the class and only equips own skills", function()
		local data = Progression.fresh()
		expect(Progression.fitBar(data, "mage")).toBe(false)
		expect(Progression.fitBar(data, "warrior")).toBe(true)
		for slot, id in Skills.forClass("warrior").bar do
			expect(data.bar[slot]).toBe(id)
		end
		expect(Progression.equip(data, 1, "spark_ball", 50, "warrior")).toBe(false)
		expect(Progression.equip(data, 1, "blade_storm", 50, "warrior")).toBe(true)
		expect(Progression.equip(data, 1, "blade_storm", 5, "warrior")).toBe(false)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

-- First-join hero setup through the real remote (name + class)
local function setup(id: string)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", id)
	end)
	sim:run(1.2)
end

-- Plays the class like a new hero of that class would (switching heroes rejoins the game, which
-- the sandbox cannot do): class on the active character, then the same refresh as the setup
local function asClass(id: string)
	server(function(req, player)
		req("ServerScriptService.Server.Systems.Data").get(player).class = id
		player:SetAttribute("Class", id)
		req("ServerScriptService.Server.Systems.Progress").classChanged(player)
		req("ServerScriptService.Server.Systems.Weapons").equip(player)
	end)
	sim:run(0.5)
end

-- A slime in front of the player that cannot walk (slow factor 0)
local function slime(offset: Vector3): Model
	return server(function(req, player)
		local root = player.Character.HumanoidRootPart
		local m = req("ServerScriptService.Server.Systems.Enemies").spawn(
			"slime",
			root.Position + offset,
			40, -- deep: survives the automatic basic attack
			{ center = root.Position, run = 55 }
		)
		m:SetAttribute("SlowUntil", os.clock() + 60)
		m:SetAttribute("SlowFactor", 0)
		return m
	end)
end

local function cast(slot: number, aim: Vector3)
	sim:runAs("client", function(req)
		local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart
		req("ReplicatedStorage.Shared.Net").CastSkill:FireServer(slot, aim, root.Position)
	end)
end

describe("Classes in game", function()
	it("asks new players for name + class, then locks the class", function()
		sim:boot({ seconds = 2 })
		local pending = server(function(_, player)
			return player:GetAttribute("SetupDone")
		end)
		expect(pending).toBe(false)
		setup("warrior")
		local class, now, bar1, weapon, name = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			local held = player.Character:FindFirstChild("HeldWeapon")
			return player:GetAttribute("Class"),
				player:GetAttribute("SetupDone"),
				p.progress.bar[1],
				if held then held:GetAttribute("Weapon") else nil,
				p.name
		end)
		expect(class).toBe("warrior")
		expect(now).toBe(true)
		expect(bar1).toBe(Skills.forClass("warrior").bar[1])
		expect(weapon).toBe("warrior_sword")
		expect(name).toBe("Tester Hero")
		-- a second setup (class change) is refused
		setup("ranger")
		local still = server(function(_, player)
			return player:GetAttribute("Class")
		end)
		expect(still).toBe("warrior")
	end)

	it("creates a new hero in a free slot and refuses bad names", function()
		local count, active = server(function(req, player)
			local Characters = req("ServerScriptService.Server.Systems.Characters")
			local bad = Characters.create(player, "x", "mage")
			assert(bad == false, "short name accepted")
			local Profile = req("ReplicatedStorage.Shared.Profile")
			local account = req("ServerScriptService.Server.Systems.Data").account(player)
			-- the slot itself (create = add + switch; the switch rejoins, not possible here)
			local c = Profile.newCharacter(account, "Zap Two", "mage", os.time())
			return #account.characters, account.active, c and c.class
		end)
		expect(count).toBe(2)
		expect(active).toBe("c1")
	end)

	it("hits enemies in front with a melee arc, not behind", function()
		local front = slime(Vector3.new(0, 0, -5))
		local back = slime(Vector3.new(0, 0, 5))
		sim:run(0.2)
		local hp = server(function()
			return front:GetAttribute("Health"), back:GetAttribute("Health")
		end)
		local frontPos = server(function()
			return front:GetPivot().Position
		end)
		cast(1, frontPos) -- Shield Bash
		sim:run(0.3)
		local f, b, bmax = server(function()
			return front:GetAttribute("Health") or 0,
				back:GetAttribute("Health"),
				back:GetAttribute("MaxHealth")
		end)
		expect(f < hp).toBe(true)
		expect(b).toBe(bmax)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(55)
		end)
	end)

	it("leaps to the aim with Charge", function()
		-- a new hero learns Charge (starting skill 3) at a later level (Skills.StartUnlock)
		server(function(_, player)
			player:SetAttribute("Level", Skills.StartUnlock[Skills.SLOTS])
		end)
		local before = server(function(_, player)
			return player.Character.HumanoidRootPart.Position
		end)
		cast(3, before + Vector3.new(15, 0, 0))
		sim:run(0.3)
		local after = server(function(_, player)
			return player.Character.HumanoidRootPart.Position
		end)
		expect((after - before).Magnitude > 5).toBe(true)
		sim:run(5)
	end)

	it("refuses another class's skills after a switch and ticks ranger zones", function()
		asClass("ranger")
		local target = slime(Vector3.new(0, 0, -10))
		sim:run(0.2)
		local hp0 = server(function()
			return target:GetAttribute("Health")
		end)
		local at = server(function()
			return target:GetPivot().Position
		end)
		cast(3, at) -- Arrow Rain: several ticks
		sim:run(1.5)
		local hp1 = server(function()
			return target:GetAttribute("Health") or 0
		end)
		expect(hp1 < hp0).toBe(true)
		local bar = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).progress.bar
		end)
		for _, id in bar do
			expect(Skills.ById[id].class).toBe("ranger")
		end
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(55)
		end)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
