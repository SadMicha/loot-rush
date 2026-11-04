-- Dev tool "Reset Account" (Dbg menu, Systems/Debug "reset" → Data.reset): the whole account goes
-- back to a first-join save, is stored, the session ends and the player is kicked, so the next join
-- runs the real first-join flow (hero creation, quests, hints). Never for other players, never for
-- players outside the debug gate.
local STORE = "LootRush_Profile_v3/global"
local DATA = "ServerScriptService.Server.Systems.Data"

local function raw(key: string)
	return sim.datastores[STORE] and sim.datastores[STORE][key]
end

local function takeKicks(): { string }
	local kicks = {}
	for i = #sim.issues, 1, -1 do
		if sim.issues[i].kind == "kick" then
			table.insert(kicks, sim.issues[i].message)
			table.remove(sim.issues, i) -- expected kick, not an error
		end
	end
	return kicks
end

local function debug(command: string)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Debug:FireServer(command)
	end)
	sim:run(2)
end

local first, second

-- Played a while: set-up hero, gold, level, quests, a seen hint and a second hero
local function play(player, gold: number)
	sim:runAs("server", function(req)
		local Profile = req("ReplicatedStorage.Shared.Profile")
		local Data = req(DATA)
		local p = Data.get(player)
		local account = Data.account(player)
		p.gold = gold
		p.level = 12
		p.setupDone = true
		p.name = "Old Hero"
		p.quests.step = 4
		account.settings.hintSkills = true
		Profile.newCharacter(account, "Second Hero", "warrior", 0)
		Data.saveNow(player)
	end)
	sim:run(1)
end

describe("Reset Account", function()
	it("is ignored for players outside the debug gate", function()
		sim:boot({ seconds = 3 })
		first = sim.player
		second = sim:joinPlayer("Resetter") -- sim.player is now the second player (p_2)
		sim:run(3)
		play(first, 1111)
		play(second, 2222)
		sim.studio = false
		debug("reset")
		sim.studio = true
		expect(#takeKicks()).toBe(0)
		expect(second.Parent).never.toBeNil()
		expect(raw("p_2").Data.data.characters[1].gold).toBe(2222)
	end)

	it("wipes the whole account to a first-join save, stores it and kicks", function()
		debug("reset")
		local kicks = takeKicks()
		expect(#kicks).toBe(1)
		expect(kicks[1]).toMatch("Account reset")
		expect(second.Parent).toBeNil()
		local saved = raw("p_2")
		local account = saved.Data.data
		expect(#account.characters).toBe(1)
		local hero = account.characters[1]
		expect(hero.setupDone).toBe(false)
		expect(hero.name).never.toBe("Old Hero")
		expect(hero.level).toBe(1)
		expect(hero.gold).never.toBe(2222)
		expect(hero.quests.step).toBe(1)
		expect(account.settings.hintSkills).never.toBe(true)
		expect(saved.MetaData.ActiveSession).toBeNil() -- session ended: the next join loads at once
	end)

	it("leaves the other player untouched", function()
		local gold, level, heroes = nil, nil, nil
		sim:runAs("server", function(req)
			local Data = req(DATA)
			local p = Data.get(first)
			gold, level, heroes = p and p.gold, p and p.level, #Data.account(first).characters
		end)
		expect(gold).toBe(1111)
		expect(level).toBe(12)
		expect(heroes).toBe(2)
		expect(first.Parent).never.toBeNil()
		expect(raw("p_1").Data.data.characters[1].gold).toBe(1111)
	end)

	it("the next join runs the first-join flow", function()
		sim.joined = second.UserId - 1 -- rejoin with the same UserId
		local again = sim:joinPlayer("Resetter")
		sim:run(3)
		expect(again.UserId).toBe(second.UserId)
		expect(again:GetAttribute("SetupDone")).toBe(false)
		local p
		sim:runAs("server", function(req)
			p = req(DATA).get(again)
		end)
		expect(p).never.toBeNil()
		expect(p.setupDone).toBe(false)
		expect(p.quests.step).toBe(1)
		expect(#takeKicks()).toBe(0)
	end)
end)
