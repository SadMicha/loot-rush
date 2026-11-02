-- Spell stones: sockets per skill (max 3, only fitting stones, only owned copies), the effect on
-- the skill, save clean-up and the socket remote.
local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")
local SpellStones = require("ReplicatedStorage.Shared.SpellStones")

describe("Spell stone rules", function()
	it("socket only owned, fitting stones, at most three", function()
		local data = Progression.fresh()
		expect(Progression.socket(data, "spark_ball", 1, "split")).toBe(false) -- not owned
		data.stones.split = 1
		data.stones.power = 3
		data.stones.echo = 1
		expect(Progression.socket(data, "spark_ball", 1, "echo")).toBe(false) -- nova only
		expect(Progression.socket(data, "spark_ball", 1, "split")).toBe(true)
		expect(Progression.socket(data, "meteor", 1, "split")).toBe(false) -- the only copy is in use
		for i = 2, 3 do
			expect(Progression.socket(data, "spark_ball", i, "power")).toBe(true)
		end
		expect(Progression.socket(data, "spark_ball", 4, "power")).toBe(false)
		expect(#data.sockets.spark_ball).toBe(SpellStones.SOCKETS)
		expect(Progression.socket(data, "spark_ball", 1, "")).toBe(true)
		expect(#data.sockets.spark_ball).toBe(2)
	end)

	it("change the skill", function()
		local data = Progression.fresh()
		data.stones.split = 1
		data.stones.power = 1
		local base = Skills.ById.spark_ball
		local before = Progression.effectiveSkill(base, data)
		Progression.socket(data, "spark_ball", 1, "split")
		Progression.socket(data, "spark_ball", 2, "power")
		local after = Progression.effectiveSkill(base, data)
		expect(after.count).toBe(3)
		expect(after.damage > before.damage).toBe(true)
		expect(after.cooldown > before.cooldown).toBe(true)
	end)

	it("drop broken saves", function()
		local data = Progression.reconcile({
			stones = { power = 1, bogus = 4, wide = -2 },
			sockets = { spark_ball = { "power", "power", "echo", "bogus" }, nope = { "power" } },
		})
		expect(data.stones.power).toBe(1)
		expect(data.stones.bogus).toBeNil()
		expect(data.stones.wide).toBeNil()
		expect(#data.sockets.spark_ball).toBe(1) -- one copy, echo does not fit, bogus unknown
		expect(data.sockets.nope).toBeNil()
	end)
end)

describe("Spell stones in game", function()
	it("socket through the remote", function()
		sim:boot({ seconds = 2 })
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			req("ServerScriptService.Server.Systems.Data").get(player).progress.stones.wide = 1
		end)
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Loadout:FireServer("socket", "thunderstorm", { 1, "wide" })
			Net.Loadout:FireServer("socket", "thunderstorm", { 1, 7 }) -- junk is ignored
			Net.Loadout:FireServer("socket", "thunderstorm", "x")
		end)
		sim:run(0.5)
		local socketed
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			socketed =
				req("ServerScriptService.Server.Systems.Data").get(player).progress.sockets.thunderstorm
		end)
		expect(socketed[1]).toBe("wide")
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
