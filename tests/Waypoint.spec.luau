-- Quest waypoint (docs/ROADMAP.md O1): beam to the active quest's hub station + minimap marker.
local Quests = require("ReplicatedStorage.Shared.Quests")

describe("Quest waypoint rules", function()
	it("points hub goals at their station and Rift/window goals nowhere", function()
		expect(Quests.waypoint(1)).toBe("Atlas") -- enter a Rift: the Rift Gate
		for step, q in Quests.Chain do
			local w = Quests.waypoint(step)
			if q.goal == "kill" or q.goal == "pickup" or q.goal == "equip" or q.goal == "level" then
				expect(w).toBeNil()
			end
		end
		expect(Quests.waypoint(#Quests.Chain + 1)).toBeNil()
	end)
end)

describe("Quest waypoint client", function()
	it("shows a beam from a new hero to the Rift Gate and a marker on the minimap", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Way Hero", "ranger")
		end)
		sim:run(2)
		local root = sim.player.Character.HumanoidRootPart
		local beam = root:FindFirstChild("QuestWaypoint", true)
		expect(beam).toBeTruthy()
		expect(beam.Enabled).toBe(true)
		local gate = workspace.Lumenhaven:FindFirstChild("Station_Atlas", true)
		expect(beam.Attachment1.Parent).toBe(gate)
		local marker = sim.player.PlayerGui.LootRushHUD:FindFirstChild("Quest", true)
		expect(marker).toBeTruthy()
		expect(marker.Visible).toBe(true)
	end)
end)
