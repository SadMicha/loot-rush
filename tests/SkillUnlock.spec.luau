-- Gradual skill unlocks: new heroes start with two skills and learn starting skills 3-4 at
-- Skills.StartUnlock levels; heroes from before keep all four. Rules, saves and the game (cast
-- refused, HUD hides locked slots, level-up card and hint name the new skill).
local Profile = require("ReplicatedStorage.Shared.Profile")
local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")

describe("Skill unlock rules", function()
	it("unlocks starting skills one by one only for gradual heroes", function()
		local kit = Skills.forClass("ranger")
		local old = Progression.fresh()
		local new = Progression.fresh()
		new.gradual = true
		for i, id in kit.bar do
			local s = Skills.ById[id]
			expect(Progression.unlockLevel(s, old)).toBe(1)
			expect(Progression.unlockLevel(s, nil)).toBe(1)
			expect(Progression.unlockLevel(s, new)).toBe(Skills.StartUnlock[i])
		end
		expect(Skills.StartUnlock[1]).toBe(1) -- a new hero always has a skill
		expect(Skills.StartUnlock[Skills.SLOTS]).toBeLessThan(5) -- all four before the Star Web
		-- skills 5-8 keep their own levels for everyone
		local falcon = kit.list[8]
		expect(Progression.unlockLevel(falcon, new)).toBe(falcon.unlock)
		expect(Progression.unlockLevel(falcon, old)).toBe(falcon.unlock)
		local last = Skills.ById[kit.bar[4]]
		expect(Progression.isUnlocked(last, Skills.StartUnlock[4] - 1, new)).toBe(false)
		expect(Progression.isUnlocked(last, Skills.StartUnlock[4], new)).toBe(true)
		expect(Progression.isUnlocked(last, 1, old)).toBe(true)
	end)

	it("names the skills a level-up unlocks", function()
		local new = Progression.fresh()
		new.gradual = true
		local kit = Skills.forClass("mage")
		local got = Progression.unlockedBetween(new, "mage", 1, Skills.StartUnlock[3])
		expect(#got).toBe(1)
		expect(got[1].id).toBe(kit.bar[3])
		expect(#Progression.unlockedBetween(new, "mage", 1, Skills.StartUnlock[4])).toBe(2)
		expect(#Progression.unlockedBetween(Progression.fresh(), "mage", 1, 4)).toBe(0)
		expect(#Progression.unlockedBetween(Progression.fresh(), "mage", 7, 8)).toBe(1)
	end)

	it("refuses to equip a starting skill before its level", function()
		local data = Progression.fresh()
		data.gradual = true
		local fourth = Skills.DefaultBar[4]
		local need = Skills.StartUnlock[4]
		local ok, why = Progression.canEquip(fourth, need - 1, "mage", data)
		expect(ok).toBe(false)
		expect(why).toBe(string.format("Unlocks at level %d", need))
		expect(Progression.equip(data, 1, fourth, need - 1, "mage")).toBe(false)
		expect(Progression.equip(data, 1, fourth, need, "mage")).toBe(true)
		-- an open skill cannot be swapped onto a key that still holds a locked skill
		local early = Progression.fresh()
		early.gradual = true
		local locked = Skills.StartUnlock[4]
		expect(Progression.equip(early, 4, Skills.DefaultBar[1], locked - 1, "mage")).toBe(false)
		expect(early.bar[1]).toBe(Skills.DefaultBar[1])
		expect(early.bar[4]).toBe(Skills.DefaultBar[4])
		expect(Progression.equip(early, 2, Skills.DefaultBar[1], 1, "mage")).toBe(true) -- open keys swap
	end)

	it("keeps old heroes open and marks new heroes gradual", function()
		-- a save from before the rule has no field: all four stay open
		local oldSave = Profile.reconcile({
			name = "Veteran",
			setupDone = true,
			progress = { bar = table.clone(Skills.DefaultBar) },
		})
		expect(oldSave.progress.gradual).toBe(false)
		expect(Profile.fresh().progress.gradual).toBe(false)
		-- the flag survives a save round trip
		local kept = Progression.reconcile({ gradual = true })
		expect(kept.gradual).toBe(true)
		expect(Progression.reconcile({ gradual = "yes" }).gradual).toBe(false)
		-- a hero made with "Create hero" is gradual
		local account = Profile.freshAccount()
		local hero = Profile.newCharacter(account, "Fresh One", "warrior", 0)
		expect(hero and hero.progress.gradual).toBe(true)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function CLIENT_(): string
	return "Players." .. sim.player.Name .. ".PlayerScripts.Client."
end

local function casts(): number
	local n = 0
	for _, e in sim.netLog do
		if e.name == "SkillCast" and e.dir == "S→C" then
			n += 1
		end
	end
	return n
end

local function castAll()
	sim:runAs("client", function(req)
		local Net = req("ReplicatedStorage.Shared.Net")
		local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position
		for slot = 1, Skills.SLOTS do
			Net.CastSkill:FireServer(slot, root + Vector3.new(6, 0, 0), root)
		end
	end)
	sim:run(0.5)
end

local function skillButton(slot: number)
	local hud = sim.player.PlayerGui:FindFirstChild("LootRushHUD")
	return hud and hud:FindFirstChild("Skill" .. slot, true)
end

describe("Skill unlocks in game", function()
	-- Slots a gradual hero has at this level
	local function openAt(level: number): number
		local n = 0
		for _, need in Skills.StartUnlock do
			if level >= need then
				n += 1
			end
		end
		return n
	end

	local function expectShown(n: number)
		for slot = 1, Skills.SLOTS do
			expect(skillButton(slot).Visible).toBe(slot <= n)
		end
	end

	it("a new hero starts with fewer skills on the HUD", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Unlock Hero", "mage")
		end)
		sim:run(2)
		local gradual = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).progress.gradual
		end)
		expect(gradual).toBe(true)
		expect(openAt(1)).toBeLessThan(Skills.SLOTS)
		expectShown(openAt(1))
	end)

	it("the server refuses locked skills", function()
		local before = casts()
		castAll()
		expect(casts() - before).toBe(openAt(1))
	end)

	it("a level-up shows the new button and names it on the card", function()
		local level = Skills.StartUnlock[openAt(1) + 1]
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").setLevel(player, level, 0)
		end)
		sim:run(1)
		expectShown(openAt(level))
		local slot = openAt(level)
		local skill = Skills.ById[Skills.DefaultBar[slot]]
		local line = ""
		sim:runAs("client", function(req)
			local LevelUp = req(CLIENT_() .. "Controllers.LevelUpController")
			line = LevelUp.skillLine(skill, Skills.DefaultBar, false)
		end)
		local keys = { "Q", "E", "R", "F" }
		expect(line).toBe("New skill: " .. skill.name .. " · press " .. keys[slot])
		sim:run(9) -- cooldowns from the last test run out
		server(function(req, player) -- Chain Lightning needs a target
			local root = player.Character.HumanoidRootPart.Position
			local m = req("ServerScriptService.Server.Systems.Enemies").spawn(
				"slime",
				root + Vector3.new(6, 0, 0),
				40,
				{ center = root, run = 55 }
			)
			m:SetAttribute("SlowUntil", os.clock() + 60)
			m:SetAttribute("SlowFactor", 0)
		end)
		sim:run(0.2)
		local before = casts()
		castAll()
		expect(casts() - before).toBe(openAt(level))
	end)

	it("all four are there by the last unlock level", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Combat").setLevel(
				player,
				Skills.StartUnlock[Skills.SLOTS],
				0
			)
		end)
		sim:run(1)
		expectShown(Skills.SLOTS)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
