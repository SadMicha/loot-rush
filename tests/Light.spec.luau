-- Light per place: the server builds an arena, the client in the Hub still keeps the Hub light.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local Looks = require("ReplicatedStorage.Shared.Looks")

describe("Lighting", function()
	it("knows every region", function()
		for _, region in Atlas.Regions do
			expect(Looks.Regions[region.id]).never.toBeNil()
		end
	end)

	it("keeps every place in one brightness band (not too dark, not blown out)", function()
		local places = { hub = Looks.Hub }
		for id, light in Looks.Regions do
			places[id] = light
		end
		local lo, hi = math.huge, 0
		for id, light in places do
			local est = Looks.estimate(light)
			expect(est).toBeGreaterThan(0.45)
			expect(est).toBeLessThan(0.8)
			expect(light.brightness or 0).toBeLessThan(2.4)
			expect(light.bloom or 0).toBeLessThan(0.7)
			lo, hi = math.min(lo, est), math.max(hi, est)
		end
		expect(hi - lo).toBeLessThan(0.22)
		-- the Altered World is no longer the dark outlier
		expect(Looks.estimate(Looks.Regions.altered_world)).toBeGreaterThan(0.48)
	end)

	it("player in the Hub sees Hub light even while the arena is rebuilt", function()
		sim:boot({ seconds = 2 })
		sim:runAs("server", function(req)
			local Config = req("ReplicatedStorage.Shared.Config")
			local player = game:GetService("Players"):GetPlayers()[1]
			player.Character:PivotTo(CFrame.new(Config.HUB_POS))
			local World = req("ServerScriptService.Server.Systems.World")
			World.build(Atlas.ById.altered_world)
		end)
		sim:run(1)
		local place
		sim:runAs("client", function(req)
			place =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightController").place()
		end)
		expect(place).toBe("hub")
		-- in the Rift the region light applies
		sim:runAs("server", function(req)
			local Config = req("ReplicatedStorage.Shared.Config")
			game:GetService("Players")
				:GetPlayers()[1].Character
				:PivotTo(CFrame.new(Config.RIFT_START))
		end)
		-- read at once: without a run, FallGuard brings a player on an idle map slot home
		sim:runAs("client", function(req)
			place =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightController").place()
		end)
		expect(place).toBe("altered_world")
	end)
end)

describe("Arena slots", function()
	it("builds arenas of further Rifts offset and tears them down again", function()
		local info
		sim:runAs("server", function(req)
			local World = req("ServerScriptService.Server.Systems.World")
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			World.build(Atlas.ById.mushroom_swamp, 2)
			local folder = workspace.Arena:FindFirstChild("Region_mushroom_swamp_2")
			local minX = math.huge
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					minX = math.min(minX, d.Position.X)
				end
			end
			local center = World.center(2)
			Enemies.spawn(
				"slime",
				center + Vector3.new(0, 0, -20),
				1,
				{ center = center, run = 99 }
			)
			info = {
				center = folder:GetAttribute("Center"),
				region = folder:GetAttribute("Region"),
				minX = minX,
				count = Enemies.count(99),
				other = Enemies.count(98),
			}
			Enemies.clear(99)
			World.release(2)
			info.gone = workspace.Arena:FindFirstChild("Region_mushroom_swamp_2") == nil
			info.slot1 = World.current(1)
		end)
		sim:run(0.5)
		local spacing = require("ReplicatedStorage.Shared.Config").ARENA_SPACING
		expect(info.center).toBe(Vector3.new(spacing, 0, 0))
		expect(info.region).toBe("mushroom_swamp")
		expect(info.minX).toBeGreaterThan(spacing / 2) -- incl. the horizon, never reaches slot 1
		expect(info.count).toBe(1)
		expect(info.other).toBe(0)
		expect(info.gone).toBe(true)
		expect(info.slot1).never.toBe("")
	end)
end)
