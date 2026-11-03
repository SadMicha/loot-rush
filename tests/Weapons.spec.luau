-- Classes and held weapons (owner weapon pack, Shared/Weapons, Systems/Weapons).
local Assets = require("ReplicatedStorage.Shared.UI.Assets")
local Classes = require("ReplicatedStorage.Shared.Classes")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Theme = require("ReplicatedStorage.Shared.UI.Theme")
local Weapons = require("ReplicatedStorage.Shared.Weapons")

describe("Classes and weapons", function()
	it("has four classes, each with a weapon, asset slots and skill icons", function()
		expect(#Classes.List).toBe(4)
		for _, c in Classes.List do
			local w = Weapons.ById[c.weapon]
			expect(w).never.toBeNil()
			expect(w.class).toBe(c.id)
			expect(Weapons.ByClass[c.id]).toBe(w)
			expect(Assets.Weapon[w.id]).never.toBeNil()
			expect(Theme.Class.SkillName[c.id]).never.toBeNil()
		end
	end)

	it("keeps the saved class valid", function()
		expect(Profile.fresh().class).toBe(Classes.DEFAULT)
		expect(Profile.reconcile({ class = "ranger" }).class).toBe("ranger")
		expect(Profile.reconcile({ class = "pirate" }).class).toBe(Classes.DEFAULT)
		expect(Profile.reconcile({ class = 3 }).class).toBe(Classes.DEFAULT)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Held weapon in game", function()
	it("puts the class weapon into the hand and swaps it with the class", function()
		sim:boot({ seconds = 2 })
		local class, weapon, welded = server(function(_, player)
			local held = player.Character:FindFirstChild("HeldWeapon")
			local welds = 0
			for _, d in held:GetDescendants() do
				if d:IsA("Weld") then
					welds += 1
				end
			end
			return player:GetAttribute("Class"), held:GetAttribute("Weapon"), welds
		end)
		expect(class).toBe("mage")
		expect(weapon).toBe("mage_staff")
		expect(welded).toBeGreaterThan(0)
		-- held upright: the staff's center sits above the grip point, close to the hand
		local up, side = server(function(_, player)
			local joint = player.Character.HeldWeapon.Grip
			return joint.C0.Position.Y, math.abs(joint.C0.Position.X)
		end)
		expect(up).toBeGreaterThan(0.5)
		expect(side).toBeLessThan(0.5)
		local after, count = server(function(req, player)
			player:SetAttribute("Class", "warrior")
			req("ServerScriptService.Server.Systems.Weapons").equip(player)
			local n = 0
			for _, c in player.Character:GetChildren() do
				if c.Name == "HeldWeapon" then
					n += 1
				end
			end
			return player.Character.HeldWeapon:GetAttribute("Weapon"), n
		end)
		expect(after).toBe("warrior_sword")
		expect(count).toBe(1)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
