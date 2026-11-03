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
		-- the staff's center lies along its long axis from the grip point (head up in the pose)
		local staff = Weapons.ById.mage_staff
		local along, side = server(function(_, player)
			local joint = player.Character.HeldWeapon.Grip
			local p = joint.C0.Position
			local axis = staff.grip.UpVector
			return p:Dot(axis), (p - axis * p:Dot(axis)).Magnitude
		end)
		expect(along).toBeGreaterThan(0.5)
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

describe("Weapon grips", function()
	it("holds every weapon by a hand with a sane grip point and pose", function()
		for _, w in Weapons.List do
			expect(w.hand == "right" or w.hand == "left").toBe(true)
			expect(w.gripAt > 0 and w.gripAt < 0.5).toBe(true)
			expect(math.abs(w.offset.X) < 0.1 and math.abs(w.offset.Y) < 0.1).toBe(true)
			if w.ready then
				-- arm raised forward: the hand's -Z points up, the head must point that way
				expect(w.grip.UpVector:Dot(Vector3.new(0, 0, -1))).toBeGreaterThan(0.9)
			else
				expect(w.grip.UpVector.Y).toBeGreaterThan(0.9) -- arm down: weapon upright
			end
		end
		expect(Weapons.ByClass.ranger.hand).toBe("left")
		expect(Weapons.ByClass.warrior.hand).toBe("right")
	end)
end)
