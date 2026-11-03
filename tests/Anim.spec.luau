-- Character animations (Shared/Anim, AnimController): every move is well formed, starts and ends
-- in the rest pose, every class attack and skill has a move, enemy body language leans the right way.
local Anim = require("ReplicatedStorage.Shared.Anim")
local Classes = require("ReplicatedStorage.Shared.Classes")
local Skills = require("ReplicatedStorage.Shared.Skills")
local Weapons = require("ReplicatedStorage.Shared.Weapons")

local function isJoint(name: string): boolean
	return table.find(Anim.JOINTS, name) ~= nil
end

local function size(p: Anim.Pose): number
	local total = 0
	for _, v in p do
		-- full turns (spin, roll) count as rest
		local x = (v.X + 180) % 360 - 180
		local y = (v.Y + 180) % 360 - 180
		local z = (v.Z + 180) % 360 - 180
		total += math.abs(x) + math.abs(y) + math.abs(z)
	end
	return total
end

describe("Animations", function()
	it("has well formed moves", function()
		for id, m in Anim.Moves do
			expect(m.id).toBe(id)
			expect(m.time > 0 and m.time < 1.5).toBe(true)
			expect(m.keys[1].t).toBe(0)
			expect(m.keys[#m.keys].t).toBe(1)
			for i, k in m.keys do
				if i > 1 then
					expect(k.t > m.keys[i - 1].t).toBe(true)
				end
				for joint in k.pose do
					expect(isJoint(joint)).toBe(true)
				end
			end
		end
	end)

	it("starts and ends every move in the rest pose (death holds its last key)", function()
		for _, m in Anim.Moves do
			local start: Anim.Pose = {}
			local lift0 = Anim.sample(m, 0, start)
			expect(size(start) < 0.01).toBe(true)
			expect(lift0.Magnitude < 0.01).toBe(true)
			local mid: Anim.Pose = {}
			Anim.sample(m, m.time * 0.5, mid)
			expect(size(mid) > 1).toBe(true)
			local finish: Anim.Pose = {}
			local lift = Anim.sample(m, m.time + 0.1, finish)
			if m.hold then
				expect(size(finish) > 1).toBe(true)
			else
				expect(size(finish) < 0.01).toBe(true)
				expect(lift.Magnitude < 0.01).toBe(true)
			end
		end
	end)

	it("gives every class attack and skill a move", function()
		for _, c in Classes.List do
			local w = Weapons.ByClass[c.id]
			local style = Anim.STYLE[w.id]
			expect(style).never.toBeNil()
			local kit = Skills.forClass(c.id)
			for combo = 0, 1 do
				local id = Anim.moveFor(style, kit.basic.kind, kit.basic.id, true, combo)
				expect(Anim.Moves[id]).never.toBeNil()
			end
			for _, s in kit.list do
				expect(Anim.Moves[Anim.moveFor(style, s.kind, s.id, false, 0)]).never.toBeNil()
			end
		end
		-- the sword alternates two swings, the bow always shoots
		expect(Anim.moveFor("sword", "arc", "basic_warrior", true, 0)).never.toBe(
			Anim.moveFor("sword", "arc", "basic_warrior", true, 1)
		)
		expect(Anim.moveFor("bow", "projectile", "basic_ranger", true, 3)).toBe("shoot")
	end)

	it("maps every R6 joint onto a known joint", function()
		for name in Anim.R6 do
			expect(isJoint(name)).toBe(true)
		end
		for from, into in Anim.R6_FOLD do
			expect(Anim.R6[from]).toBeNil()
			expect(Anim.R6[into]).never.toBeNil()
		end
		for _, name in Anim.JOINTS do
			expect(Anim.R15[name]).never.toBeNil()
		end
	end)

	it("leans enemies back on windup, forward on the lunge, back on a hit", function()
		expect(Anim.enemyPitch(nil, 10, 10)).toBe(0)
		expect(Anim.enemyPitch(0.9, 10, 10) > 5).toBe(true)
		expect(Anim.enemyPitch(nil, 0.02, 10) < -5).toBe(true)
		expect(Anim.enemyPitch(nil, 10, 0.01) > 5).toBe(true)
		expect(Anim.enemyPitch(nil, Anim.ENEMY_LUNGE_TIME + 0.01, Anim.ENEMY_RECOIL_TIME + 0.01)).toBe(
			0
		)
	end)

	it("turns the body toward the target only while the move plays", function()
		local m = Anim.Moves.slash
		expect(Anim.faceWeight(m, 0)).toBe(0)
		expect(Anim.faceWeight(m, m.time * 0.4)).toBe(1)
		expect(Anim.faceWeight(m, m.time)).toBe(0)
	end)
end)

describe("Holding stances", function()
	it("every weapon has its own stance on real joints, with a moderate pose", function()
		local seen = {}
		for _, w in Weapons.List do
			local s = Anim.STANCE[w.id]
			expect(s).toBeTruthy()
			expect(isJoint(s.arm)).toBe(true)
			for joint, a in s.pose do
				expect(isJoint(joint)).toBe(true)
				expect(math.max(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))).toBeLessThanOrEqual(
					60
				)
			end
			local key = {}
			for joint, a in s.pose do
				table.insert(key, `{joint}{a}`)
			end
			table.sort(key)
			local sig = table.concat(key)
			expect(seen[sig]).toBeNil() -- no two weapons share a stance
			seen[sig] = true
		end
	end)

	it("is full while standing, softer while running and while a move plays", function()
		expect(Anim.stanceWeight(0, false)).toBe(1)
		expect(math.abs(Anim.stanceWeight(1, false) - Anim.STANCE_MOVING)).toBeLessThan(1e-9)
		expect(Anim.stanceWeight(0, true)).toBe(Anim.STANCE_ACTING)
		local pose = {}
		local lift = Anim.stance("warrior_sword", 1, 0, pose)
		expect(lift.Y).toBeLessThan(0) -- guard crouch
		expect(pose.rShoulder).toBeTruthy()
		local none = {}
		expect(Anim.stance("nope", 1, 0, none)).toBe(Vector3.zero)
		expect(next(none)).toBeNil()
		local half = {}
		Anim.stance("mage_staff", 0.5, 0, half)
		expect(half.rElbow.X).toBe(Anim.STANCE.mage_staff.pose.rElbow.X * 0.5)
	end)
end)
