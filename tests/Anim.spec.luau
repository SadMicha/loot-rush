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

-- Forward kinematics of the weapon arm on a standard R15 block rig (UpperTorso space, origin at
-- its center, +X right, +Y up, -Z forward): shoulder, elbow and wrist positions from the rig
-- attachments, then Weapons.grip. Gives where the held weapon points and where it is.
local DEG = math.pi / 180
local function rot(a: Vector3?): CFrame
	local x = a or Vector3.zero
	return CFrame.fromEulerAnglesYXZ(x.X * DEG, x.Y * DEG, x.Z * DEG)
end

local function weaponFrame(w: Weapons.Weapon, arm: Anim.Pose): CFrame
	local side = if w.hand == "left" then -1 else 1
	local names = Anim.ARM[w.hand]
	return CFrame.new(side * 1, 0.563, 0)
		* rot(arm[names[1]])
		* CFrame.new(side * 0.5, -0.75, 0)
		* rot(arm[names[2]])
		* CFrame.new(0, -0.66, 0)
		* rot(arm[names[3]])
		* CFrame.new(0, -0.28, 0)
		* w.grip
end

-- Points along the weapon (weapon space: grip at the origin, tip +Y); the bow also its string
local function weaponPoints(w: Weapons.Weapon): { Vector3 }
	local out = {}
	for i = 0, 10 do
		local y = (-w.gripAt + i / 10) * w.length
		table.insert(out, Vector3.new(0, y, 0))
		if w.id == "ranger_bow" and math.abs(y) < w.length * 0.45 then
			table.insert(out, Vector3.new(-0.6, y, 0)) -- string side
		end
	end
	return out
end

-- Torso, hips, legs and head (arms excluded)
local BODY = {
	{ min = Vector3.new(-1, -3.1, -0.5), max = Vector3.new(1, 0.8, 0.5) },
	{ min = Vector3.new(-0.6, 0.8, -0.6), max = Vector3.new(0.6, 2, 0.6) },
}
local function inBody(p: Vector3): boolean
	for _, b in BODY do
		if
			p.X > b.min.X
			and p.X < b.max.X
			and p.Y > b.min.Y
			and p.Y < b.max.Y
			and p.Z > b.min.Z
			and p.Z < b.max.Z
		then
			return true
		end
	end
	return false
end

local function tilt(f: CFrame): number
	return math.deg(math.acos(math.clamp(f.UpVector.Y, -1, 1)))
end

describe("Holding stances", function()
	it("every weapon has its own stance on real joints, with a moderate body pose", function()
		local seen = {}
		for _, w in Weapons.List do
			local s = Anim.STANCE[w.id]
			expect(s).toBeTruthy()
			expect(s.hand).toBe(w.hand)
			local names = Anim.ARM[s.hand]
			for joint in s.hold do
				expect(table.find(names, joint)).toBeTruthy()
			end
			-- the ready arm (ref) is used by exactly the weapons that raise the arm
			expect(s.ref ~= nil).toBe(w.ready)
			for joint, a in s.pose do
				expect(isJoint(joint)).toBe(true)
				expect(table.find(names, joint)).toBeNil() -- the weapon arm is `hold`, not added
				expect(math.max(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))).toBeLessThanOrEqual(
					60
				)
			end
			local key = {}
			for joint, a in s.hold do
				table.insert(key, `{joint}{a}`)
			end
			table.sort(key)
			local sig = table.concat(key)
			expect(seen[sig]).toBeNil() -- no two weapons share a stance
			seen[sig] = true
		end
	end)

	it("holds every weapon upright (the sword over the shoulder), clear of the body", function()
		for _, w in Weapons.List do
			for _, weight in { 1, Anim.STANCE_MOVING, Anim.STANCE_ACTING } do
				local arm = {}
				local mix = Anim.hold(w.id, weight, false, arm)
				if mix < 1 then
					continue -- the Animator's arm takes part: only the full stance is ours alone
				end
				local f = weaponFrame(w, arm)
				expect(tilt(f)).toBeLessThan(40)
				if w.id ~= "warrior_sword" then -- the sword rests back over the shoulder
					expect(f.UpVector.Z).toBeLessThan(0.1) -- tip not toward the face/back
				end
				for _, p in weaponPoints(w) do
					expect(inBody(f * p)).toBe(false)
				end
			end
		end
	end)

	it("matches the weapon's own pose", function()
		local function standing(id: string): CFrame
			local arm = {}
			Anim.hold(id, 1, false, arm)
			return weaponFrame(Weapons.ById[id], arm)
		end
		local sword = standing("warrior_sword")
		expect(sword.Position.Z).toBeLessThan(-0.8) -- hand in front of the chest
		expect(sword.UpVector.Z).toBeGreaterThan(0.3) -- blade leans back over the shoulder
		expect(sword.Position.X + sword.UpVector.X * 3).toBeGreaterThan(0.8) -- beside the head
		local staff = standing("mage_staff")
		expect(tilt(staff)).toBeLessThan(10) -- upright beside the body
		expect(staff.Position.X).toBeGreaterThan(1.2)
		local scepter = standing("druid_scepter")
		expect(tilt(scepter)).toBeLessThan(10) -- upright in front of the chest
		expect(scepter.Position.X).toBeLessThan(1)
		expect(scepter.Position.Z).toBeLessThan(-0.8)
		local bow = standing("ranger_bow")
		expect(tilt(bow)).toBeLessThan(15) -- limbs vertical at the side
		expect(bow.Position.X).toBeLessThan(-1.2)
		-- the ready arm the attack moves were made for: blade up, 15° forward
		local arm = {}
		Anim.hold("warrior_sword", 0, false, arm)
		local ref = weaponFrame(Weapons.ById.warrior_sword, arm)
		expect(math.abs(tilt(ref) - 15)).toBeLessThan(1)
	end)

	it("folds elbow and wrist into the shoulder on R6", function()
		for _, w in Weapons.List do
			local r15, r6 = {}, {}
			Anim.hold(w.id, 1, false, r15)
			Anim.hold(w.id, 1, true, r6)
			local names = Anim.ARM[w.hand]
			expect(r6[names[2]]).toBeNil()
			expect(r6[names[3]]).toBeNil()
			expect((r6[names[1]] - (r15[names[1]] + r15[names[2]] + r15[names[3]])).Magnitude).toBeLessThan(
				1e-6
			)
			expect(Anim.R6[names[1]]).never.toBeNil()
		end
	end)

	it("is full while standing, softer while running and while a move plays", function()
		expect(Anim.stanceWeight(0, false)).toBe(1)
		expect(math.abs(Anim.stanceWeight(1, false) - Anim.STANCE_MOVING)).toBeLessThan(1e-9)
		expect(Anim.stanceWeight(0, true)).toBe(Anim.STANCE_ACTING)
		local pose = {}
		local lift = Anim.stance("warrior_sword", 1, 0, pose)
		expect(lift.Y).toBeLessThan(0) -- guard crouch
		expect(pose.waist).toBeTruthy()
		local none = {}
		expect(Anim.stance("nope", 1, 0, none)).toBe(Vector3.zero)
		expect(next(none)).toBeNil()
		expect(Anim.hold("nope", 1, false, none)).toBe(0)
		expect(next(none)).toBeNil()
		local half = {}
		Anim.stance("mage_staff", 0.5, 0, half)
		expect(half.lElbow.X).toBe(Anim.STANCE.mage_staff.pose.lElbow.X * 0.5)
		-- ready weapons: the arm is always ours; the bow arm blends with the Animator's by weight
		expect(Anim.hold("mage_staff", 0.3, false, {})).toBe(1)
		expect(Anim.hold("ranger_bow", 0.3, false, {})).toBe(0.3)
	end)
end)
