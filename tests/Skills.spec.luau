local Skills = require("ReplicatedStorage.Shared.Skills")
local Assets = require("ReplicatedStorage.Shared.UI.Assets")

describe("Skills", function()
	local all = { Skills.basic }
	for _, s in Skills.list do
		table.insert(all, s)
	end

	it("have unique IDs and valid values", function()
		local ids = {}
		for _, s in all do
			expect(ids[s.id]).toBeNil()
			ids[s.id] = true
			expect(s.damage).toBeGreaterThan(0)
			expect(s.cooldown).toBeGreaterThan(0)
			expect(s.radius).toBeGreaterThan(0)
			if s.kind == "projectile" then
				expect(s.speed).never.toBeNil()
			elseif s.kind == "chain" then
				expect(s.chains).never.toBeNil()
			end
		end
	end)

	it("reference existing icons", function()
		for _, s in all do
			expect(Assets.Icon[s.icon]).never.toBeNil()
		end
	end)
end)
