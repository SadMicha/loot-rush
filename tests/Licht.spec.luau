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
