-- Sound hooks: every skill kind has a cast sound, empty ids stay silent without errors.
local Skills = require("ReplicatedStorage.Shared.Skills")
local Sounds = require("ReplicatedStorage.Shared.Sounds")

describe("Sound hooks", function()
	it("cover every skill kind", function()
		for _, skill in Skills.ById do
			expect(Sounds["cast_" .. skill.kind]).never.toBeNil()
		end
		for name, def in Sounds do
			expect(typeof(def.id)).toBe("string")
			expect(def.volume > 0 and def.volume <= 1).toBe(true)
			expect(name).never.toBeNil()
		end
	end)

	it("stay silent without ids and never error in game", function()
		sim:boot({ seconds = 2 })
		local played = true
		sim:runAs("client", function(req)
			played =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.SoundController").play(
					"hit"
				)
		end)
		expect(played).toBe(false)
		sim:run(1)
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
