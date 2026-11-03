-- Guaranteed first drops (docs/ROADMAP-1.0.md O3, Balance.FirstDrops): a new character's first
-- normal kills always drop an item, the very first one a Magic+ weapon.
local Balance = require("ReplicatedStorage.Shared.Balance")
local Items = require("ReplicatedStorage.Shared.Items")
local Profile = require("ReplicatedStorage.Shared.Profile")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("First drops rule", function()
	it("forces a slot when asked, and never rolls a unique then", function()
		for seed = 1, 100 do
			local item = Items.roll(
				5,
				Random.new(seed),
				nil,
				{ shift = 50, min = "magic", slot = "weapon", uniques = true }
			)
			expect(item.slot).toBe("weapon")
			expect(Items.rank(item.rarity)).toBeGreaterThanOrEqual(Items.rank("magic"))
			expect(item.rarity).never.toBe("unique")
		end
		-- an unknown slot falls back to a random one
		expect(Items.SlotName[Items.roll(5, Random.new(1), nil, { slot = "tail" }).slot]).toBeTruthy()
	end)

	it("new and old saves start with no first drops given", function()
		expect(Profile.fresh().starters).toBe(0)
		expect(Profile.reconcile({ starters = 0 / 0 }).starters).toBe(0)
		expect(Profile.reconcile({ starters = 2.7 }).starters).toBe(2)
	end)
end)

describe("First drops server", function()
	it("the first kills of a new hero always drop, the first is a Magic+ weapon", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Loot Hero", "ranger")
		end)
		sim:run(1)
		local Loot = server(function(req)
			return req("ServerScriptService.Server.Systems.Loot")
		end)
		expect(Loot.starter(0, 1).slot).toBe(Balance.FirstDrops.firstSlot)
		expect(Loot.starter(Balance.FirstDrops.kills, 1)).toBeNil()

		local items, given = server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			local pos = player.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 200)
			for _ = 1, Balance.FirstDrops.kills do
				Combat.EnemyKilled:Fire(player, pos, 1, false, nil, 1, 1, nil, 0, false)
			end
			local _, got = req("ServerScriptService.Server.Systems.Loot").collect(player)
			return got, req("ServerScriptService.Server.Systems.Data").get(player).starters
		end)
		expect(#items).toBe(Balance.FirstDrops.kills)
		expect(given).toBe(Balance.FirstDrops.kills)
		local weapon = false
		for _, item in items do
			if item.slot == "weapon" and Items.rank(item.rarity) >= Items.rank("magic") then
				weapon = true
			end
		end
		expect(weapon).toBe(true)
	end)
end)
