-- Licht je Ort: Server baut eine Arena, der Client im Hub behält trotzdem das Hub-Licht.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local Looks = require("ReplicatedStorage.Shared.Looks")

describe("Licht", function()
	it("kennt jedes Gebiet", function()
		for _, region in Atlas.Regions do
			expect(Looks.Regions[region.id]).never.toBeNil()
		end
	end)

	it("Spieler im Hub sieht Hub-Licht, auch wenn die Arena umgebaut wird", function()
		sim:boot({ seconds = 2 })
		sim:runAs("server", function(req)
			local Config = req("ReplicatedStorage.Shared.Config")
			local player = game:GetService("Players"):GetPlayers()[1]
			player.Character:PivotTo(CFrame.new(Config.HUB_POS))
			local World = req("ServerScriptService.Server.Systems.World")
			World.build(Atlas.ById.veraenderte_welt)
		end)
		sim:run(1)
		local place
		sim:runAs("client", function(req)
			place =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightController").place()
		end)
		expect(place).toBe("hub")
		-- im Rift gilt das Gebiets-Licht
		sim:runAs("server", function(req)
			local Config = req("ReplicatedStorage.Shared.Config")
			game:GetService("Players")
				:GetPlayers()[1].Character
				:PivotTo(CFrame.new(Config.RIFT_START))
		end)
		sim:run(1)
		sim:runAs("client", function(req)
			place =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightController").place()
		end)
		expect(place).toBe("veraenderte_welt")
	end)
end)

describe("Arena-Plätze", function()
	it("baut Arenen weiterer Rifts versetzt und räumt sie wieder ab", function()
		local info
		sim:runAs("server", function(req)
			local World = req("ServerScriptService.Server.Systems.World")
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			World.build(Atlas.ById.pilzsumpf, 2)
			local folder = workspace.Arena:FindFirstChild("Gebiet_pilzsumpf_2")
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
			info.gone = workspace.Arena:FindFirstChild("Gebiet_pilzsumpf_2") == nil
			info.slot1 = World.current(1)
		end)
		sim:run(0.5)
		expect(info.center).toBe(Vector3.new(400, 0, 0))
		expect(info.region).toBe("pilzsumpf")
		expect(info.minX).toBeGreaterThan(200)
		expect(info.count).toBe(1)
		expect(info.other).toBe(0)
		expect(info.gone).toBe(true)
		expect(info.slot1).never.toBe("")
	end)
end)
