-- Rift run from start to finish: waves → boss → interim state → back to the Hub, death,
-- abort. Checks the summary (Net.RiftResult), best values and the return to the Hub.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local RiftRun = require("ReplicatedStorage.Shared.RiftRun")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function rift(action: string, id: string?)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer(action, id)
	end)
	sim:run(0.5)
end

local function results(): { any }
	local list = {}
	for _, n in sim.netLog do
		if n.name == "RiftResult" and n.dir == "S→C" then
			table.insert(list, n.args[1])
		end
	end
	return list
end

-- Gold paid by onboarding quests so far (Net.Quest snapshots list finished quest texts in `done`)
local function questGold(): number
	local Quests = require("ReplicatedStorage.Shared.Quests")
	local sum = 0
	for _, n in sim.netLog do
		local snap = n.args and n.args[1]
		if n.name == "Quest" and n.dir == "S→C" and type(snap) == "table" and snap.done then
			for _, text in snap.done do
				for _, q in Quests.Chain do
					if q.text == text then
						sum += q.gold
					end
				end
			end
		end
	end
	return sum
end

local function last(): any
	local list = results()
	return list[#list]
end

local function phase(): string
	return sim.player:GetAttribute("RiftPhase") or ""
end

-- Defeats all enemies (like the debug command "slay") until the boss is down
local function clearDepth()
	for _ = 1, 40 do
		if phase() == "clear" then
			return
		end
		server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				Combat.slay(player, e)
			end
		end)
		sim:run(1)
	end
end

local function hubDistance(): number
	return server(function(req, player)
		local Config = req("ReplicatedStorage.Shared.Config")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return if root then (root.Position - Config.HUB_POS).Magnitude else math.huge
	end)
end

describe("Run summary (pure)", function()
	it("reports newly unlocked regions and new best values", function()
		local best = { green_plains = 4 }
		local function get(id)
			return best[id] or 0
		end
		local t = RiftRun.newTally("green_plains", 1, get, 3, 0)
		t.cleared = 5
		RiftRun.addMaterials(t, { candy = 1, dust = 0, bogus = 5 })
		best.green_plains = 5
		local s = RiftRun.summary(t, "end", "left", 5, get, 4, 61.4)
		expect(s.bestBefore).toBe(4)
		expect(s.best).toBe(5)
		expect(s.newBest).toBe(true)
		expect(#s.unlocked).toBe(1)
		expect(s.unlocked[1]).toBe("crystal_caves")
		expect(s.materials.candy).toBe(1)
		expect((s.materials :: any).bogus).toBeNil()
		expect(s.seconds).toBe(61)
		expect(s.levelBefore).toBe(3)
		expect(s.level).toBe(4)
	end)

	it("only knows regions from the Atlas", function()
		for id in
			RiftRun.openSet(function()
				return 99
			end)
		do
			expect(Atlas.ById[id]).never.toBeNil()
		end
	end)
end)

local goldStart = 0

describe("Rift run in game", function()
	it("clears depth 1, sends the interim state and saves the best value", function()
		sim:boot({ seconds = 2 })
		-- onboarding quests pay gold too: finish the chain so only Rift gold counts here
		server(function(req, player)
			local Quests = req("ReplicatedStorage.Shared.Quests")
			req("ServerScriptService.Server.Systems.Data").get(player).quests.step = #Quests.Chain
				+ 1
		end)
		goldStart = sim.player:GetAttribute("Gold") or 0
		rift("enter", "green_plains")
		expect(phase()).toBe("wave")
		expect(hubDistance()).toBeGreaterThan(100) -- in the arena
		clearDepth()
		expect(phase()).toBe("clear")
		local s = last()
		expect(s).never.toBeNil()
		expect(s.kind).toBe("clear")
		expect(s.region).toBe("green_plains")
		expect(s.depth).toBe(1)
		expect(s.cleared).toBe(1)
		expect(s.bestBefore).toBe(0)
		expect(s.best).toBe(1)
		expect(s.newBest).toBe(true)
		expect(s.bosses).toBe(1)
		expect(s.kills).toBeGreaterThan(Atlas.ById.green_plains.depth) -- waves + boss
		expect(s.xp).toBeGreaterThan(0)
		expect(s.materials.candy).toBeGreaterThan(0) -- boss candy
		local saved = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).atlas.green_plains
		end)
		expect(saved).toBe(1)
		expect(sim.player:GetAttribute(Atlas.attr("green_plains"))).toBe(1)
	end)

	it("collects the loot on return and brings the player to the Hub", function()
		rift("leave")
		local s = last()
		expect(s.kind).toBe("end")
		expect(s.reason).toBe("left")
		expect(s.gold).toBeGreaterThan(0)
		-- all gold of the run (plus the onboarding quest rewards earned on the way)
		expect(sim.player:GetAttribute("Gold") - goldStart - questGold()).toBe(s.gold)
		expect(phase()).toBe("")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		expect(hubDistance()).toBeLessThan(10)
		local left = server(function()
			return #workspace.Loot:GetChildren()
		end)
		expect(left).toBe(0)
	end)

	it('offers "Play again" at the resume depth once back in the Hub', function()
		sim:run(1.5)
		local gui = sim.player.PlayerGui:FindFirstChild("LootRushReplay")
		expect(gui).toBeTruthy()
		local card = gui:FindFirstChild("PlayAgain", true)
		expect(card).toBeTruthy()
		expect(card.Visible).toBe(true)
		local text = ""
		for _, d in card:GetDescendants() do
			if d:IsA("TextLabel") then
				text ..= d.Text .. "|"
			end
		end
		expect(string.find(text, "Play again · D2", 1, true)).toBeTruthy()
		expect(string.find(text, "Green Plains", 1, true)).toBeTruthy()
	end)

	it("reports an abort in the middle of a depth", function()
		rift("enter", "green_plains")
		expect(phase()).toBe("wave")
		-- depth 1 is cleared: the run resumes at depth 2 instead of starting over
		expect(sim.player:GetAttribute("RiftDepth")).toBe(2)
		local reach = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).reach["1:green_plains"]
		end)
		expect(reach).toBe(1)
		rift("leave")
		local s = last()
		expect(s.reason).toBe("abandoned")
		expect(s.cleared).toBe(0)
		expect(s.best).toBe(1) -- best value stays
		expect(s.newBest).toBe(false)
		expect(hubDistance()).toBeLessThan(10)
	end)

	it(
		"ends the run on a death without a revive left, also during the choice after the boss",
		function()
			rift("enter", "green_plains")
			clearDepth()
			expect(phase()).toBe("clear")
			local before = #results()
			local function die()
				server(function(_, player)
					local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
					humanoid.Health = 0
				end)
				sim:run(0.5)
			end
			-- the first death of a depth spends the revive: respawn, the run goes on
			die()
			expect(#results()).toBe(before)
			expect(phase()).toBe("clear")
			expect(sim.player:GetAttribute("RiftDowned")).toBe(true)
			local depth = sim.player:GetAttribute("RiftDepth")
			rift("deeper") -- ignored until the new character is back
			expect(sim.player:GetAttribute("RiftDepth")).toBe(depth)
			expect(phase()).toBe("clear")
			sim:spawnCharacter()
			sim:run(0.5)
			expect(sim.player:GetAttribute("RiftDowned")).toBeNil()
			expect(sim.player:GetAttribute("RiftRevives")).toBe(0)
			die()
			expect(#results()).toBe(before + 1)
			local s = last()
			expect(s.kind).toBe("end")
			expect(s.reason).toBe("failed")
			expect(s.cleared).toBe(1)
			expect(phase()).toBe("failed")
			expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
			local enemies = server(function()
				return #game:GetService("CollectionService"):GetTagged("Enemy")
			end)
			expect(enemies).toBe(0)
			for _, issue in sim.issues do
				expect(issue.level).never.toBe("error")
			end
		end
	)
end)
