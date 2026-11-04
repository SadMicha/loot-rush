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

local function handFrame(hand: string, arm: Anim.Pose): CFrame
	local side = if hand == "left" then -1 else 1
	local names = Anim.ARM[hand]
	return CFrame.new(side * 1, 0.563, 0)
		* rot(arm[names[1]])
		* CFrame.new(side * 0.5, -0.75, 0)
		* rot(arm[names[2]])
		* CFrame.new(0, -0.66, 0)
		* rot(arm[names[3]])
		* CFrame.new(0, -0.28, 0)
end

local function weaponFrame(w: Weapons.Weapon, arm: Anim.Pose): CFrame
	return handFrame(w.hand, arm) * w.grip
end

-- Sole of a leg (hip below the torso, thigh and shin 0.85, ankle to sole 0.4): standing straight
-- it is at y = -3.1
local function sole(side: number, hip: Vector3?, knee: Vector3?): Vector3
	return (
		CFrame.new(side * 0.5, -1, 0)
		* rot(hip)
		* CFrame.new(0, -0.85, 0)
		* rot(knee)
		* CFrame.new(0, -0.85, 0)
	) * Vector3.new(0, -0.4, 0)
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
	local function standing(id: string): (CFrame, Anim.Pose)
		local arm = {}
		Anim.hold(id, 1, false, arm, {})
		return weaponFrame(Weapons.ById[id], arm), arm
	end

	it("every weapon has its own stance on real joints, legs included", function()
		local seen = {}
		for _, w in Weapons.List do
			local s = Anim.STANCE[w.id]
			expect(s).toBeTruthy()
			expect(s.hand).toBe(w.hand)
			local names = Anim.ARM[s.hand]
			for joint in s.hold do
				expect(table.find(names, joint)).toBeTruthy()
			end
			for joint in s.ref do
				expect(table.find(names, joint)).toBeTruthy()
			end
			for joint in s.off or {} do
				expect(table.find(names, joint)).toBeNil()
				expect(table.find(Anim.ARM.left, joint) or table.find(Anim.ARM.right, joint)).toBeTruthy()
			end
			for joint, a in s.pose do
				expect(isJoint(joint)).toBe(true)
				expect(table.find(Anim.LEGS, joint)).toBeNil() -- legs go into `legs` (fade on walk)
				expect(table.find(Anim.ARM.left, joint) or table.find(Anim.ARM.right, joint)).toBeNil()
				expect(math.max(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))).toBeLessThanOrEqual(
					45
				)
			end
			-- a grounded stance: both legs spread out, knees bent, body lowered
			local legs = assert(s.legs)
			for joint in legs do
				expect(table.find(Anim.LEGS, joint)).toBeTruthy()
			end
			expect(legs.rHip.Z).toBeGreaterThan(5)
			expect(legs.lHip.Z).toBeLessThan(-5)
			expect(legs.rKnee.X + legs.lKnee.X).toBeLessThan(-10)
			expect(assert(s.lift).Y).toBeLessThan(0)
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

	it("keeps the feet on the ground and flat", function()
		for _, w in Weapons.List do
			local s = Anim.STANCE[w.id]
			local legs = assert(s.legs)
			local lift = assert(s.lift).Y
			for _, side in { { 1, "rHip", "rKnee", "rAnkle" }, { -1, "lHip", "lKnee", "lAnkle" } } do
				local hip, knee, ankle = legs[side[2]], legs[side[3]], legs[side[4]]
				local y = sole(side[1], hip, knee).Y + lift
				expect(math.abs(y + 3.1)).toBeLessThan(0.1) -- neither floating nor sunk
				local foot = (hip and hip.X or 0)
					+ (knee and knee.X or 0)
					+ (ankle and ankle.X or 0)
				expect(math.abs(foot)).toBeLessThan(8)
			end
		end
	end)

	it("holds every weapon clear of the body, in the ready pose too", function()
		for _, w in Weapons.List do
			for _, weight in { 1, Anim.STANCE_MOVING, Anim.STANCE_ACTING, 0 } do
				local arm = {}
				Anim.hold(w.id, weight, false, arm, {})
				local f = weaponFrame(w, arm)
				if w.id ~= "warrior_sword" or weight == 0 then
					expect(tilt(f)).toBeLessThan(16) -- upright (staff, scepter, bow limbs; ready 15° forward)
				end
				for _, p in weaponPoints(w) do
					if
						w.id == "mage_staff"
						and weight == 1
						and p.Y < -w.gripAt * w.length + 0.5
					then
						continue -- the planted foot stands beside the leg on the ground
					end
					expect(inBody(f * p)).toBe(false)
				end
			end
		end
	end)

	it("gives each weapon its own pose", function()
		-- sword: blade low at the right hip, angled forward at the enemy
		local sword = standing("warrior_sword")
		expect(tilt(sword) > 40 and tilt(sword) < 70).toBe(true)
		expect(sword.UpVector.Z).toBeLessThan(-0.5)
		expect(sword.Position.Y).toBeLessThan(0)
		expect(sword.Position.X).toBeGreaterThan(0.8)
		-- bow at rest, like a real archer: held at its grip in the left hand beside the left leg,
		-- upright, the lower tip just above the ground, the arm slightly forward and out; riser out
		-- and forward (its face shows), string toward the body; the right hand rests
		local bw = Weapons.ById.ranger_bow
		local bow = standing("ranger_bow")
		expect(tilt(bow)).toBeLessThan(5)
		expect(bow.Position.X > -2.3 and bow.Position.X < -1.6).toBe(true) -- beside the left leg
		expect(bow.Position.Z < 0 and bow.Position.Z > -0.6).toBe(true) -- slightly forward
		expect(bow.Position.Y < -0.3 and bow.Position.Y > -1).toBe(true) -- hand at the hip
		local low = bow * Vector3.new(0, -bw.gripAt * bw.length, 0)
		expect(low.Y + assert(Anim.STANCE.ranger_bow.lift).Y > -3.1).toBe(true) -- above the ground
		expect(low.Y < -2.2).toBe(true)
		expect(bow.RightVector.X).toBeLessThan(-0.6) -- riser out
		expect(bow.RightVector.Z).toBeLessThan(-0.3) -- and forward
		local str = bow * Vector3.new(-0.6, 0, 0)
		expect(str.X).toBeGreaterThan(bow.Position.X + 0.4) -- string toward the body
		expect(Anim.STANCE.ranger_bow.off).toBeNil()
		-- staff: upright beside the body, its foot on the ground (lowered with the stance)
		local staff = standing("mage_staff")
		local w = Weapons.ById.mage_staff
		local foot = staff * Vector3.new(0, -w.gripAt * w.length, 0)
		expect(tilt(staff)).toBeLessThan(6)
		expect(staff.Position.X).toBeGreaterThan(1.6)
		expect(math.abs(foot.Y + assert(Anim.STANCE.mage_staff.lift).Y + 3.1)).toBeLessThan(0.15)
		expect(w.length).toBeGreaterThan(6)
		-- scepter: raised upright before the face, its head above the head
		local scepter = standing("druid_scepter")
		local sw = Weapons.ById.druid_scepter
		expect(tilt(scepter)).toBeLessThan(15)
		expect(scepter.Position.Z).toBeLessThan(-1.2)
		expect((scepter * Vector3.new(0, (1 - sw.gripAt) * sw.length, 0)).Y).toBeGreaterThan(2.5)
		-- the ready arm the attack moves were made for: blade up, 15° forward
		local arm = {}
		Anim.hold("warrior_sword", 0, false, arm, {})
		expect(math.abs(tilt(weaponFrame(Weapons.ById.warrior_sword, arm)) - 15)).toBeLessThan(1)
	end)

	it("raises the bow straight for the shot", function()
		local arm = {}
		Anim.hold("ranger_bow", Anim.stanceWeight(0, true, "ranger_bow"), false, arm, {})
		local shot: Anim.Pose = {}
		local m = Anim.Moves.shoot
		Anim.sample(m, m.time * 0.5, shot)
		for _, joint in Anim.ARM.left do
			arm[joint] = (arm[joint] or Vector3.zero) + (shot[joint] or Vector3.zero)
		end
		local f = weaponFrame(Weapons.ById.ranger_bow, arm)
		expect(tilt(f)).toBeLessThan(15)
		expect(f.Position.Y).toBeGreaterThan(0.2) -- arm up at the target
	end)

	it("keeps the bow's limbs near vertical in every ranger move", function()
		local w = Weapons.ById.ranger_bow
		local kit = Skills.forClass("ranger")
		local ids = { [Anim.moveFor("bow", kit.basic.kind, kit.basic.id, true, 0)] = true }
		for _, skill in kit.list do
			ids[Anim.moveFor("bow", skill.kind, skill.id, false, 0)] = true
		end
		expect(ids.volley).toBe(true) -- Arrow Rain aims at the sky, not the ground
		for id in ids do
			local m = Anim.Moves[id]
			for i = 0, 10 do
				local arm = {}
				Anim.hold(w.id, Anim.stanceWeight(0, true, w.id), false, arm, {})
				local moved: Anim.Pose = {}
				Anim.sample(m, m.time * i / 10, moved)
				for _, joint in Anim.ARM.left do
					arm[joint] = (arm[joint] or Vector3.zero) + (moved[joint] or Vector3.zero)
				end
				expect(tilt(weaponFrame(w, arm))).toBeLessThan(60)
			end
		end
	end)

	it("folds elbow and wrist into the shoulder on R6", function()
		for _, w in Weapons.List do
			local r15, r6 = {}, {}
			Anim.hold(w.id, 1, false, r15, {})
			Anim.hold(w.id, 1, true, r6, {})
			for _, names in { Anim.ARM.left, Anim.ARM.right } do
				if not r15[names[1]] then
					continue
				end
				expect(r6[names[2]]).toBeNil()
				expect(r6[names[3]]).toBeNil()
				local sum = r15[names[1]]
					+ (r15[names[2]] or Vector3.zero)
					+ (r15[names[3]] or Vector3.zero)
				expect((r6[names[1]] - sum).Magnitude).toBeLessThan(1e-6)
				expect(Anim.R6[names[1]]).never.toBeNil()
			end
		end
	end)

	it("is full while standing, softer while running and while a move plays", function()
		expect(Anim.stanceWeight(0, false)).toBe(1)
		expect(math.abs(Anim.stanceWeight(1, false) - Anim.STANCE_MOVING)).toBeLessThan(1e-9)
		expect(Anim.stanceWeight(0, true)).toBe(Anim.STANCE_ACTING)
		expect(Anim.stanceWeight(0, true, "warrior_sword")).toBe(Anim.STANCE_ACTING)
		-- the bow shoots from its ready carry: no rest-pose arm turn in the aim
		expect(Anim.stanceWeight(0, true, "ranger_bow")).toBe(0)
		local aim = {}
		Anim.hold("ranger_bow", Anim.stanceWeight(0, true, "ranger_bow"), false, aim, {})
		expect(aim.lShoulder.Y).toBe(0)
		expect(Anim.STANCE_DROP).toBeGreaterThan(Anim.STANCE_BLEND)
		expect(Anim.stanceLegs(0)).toBe(1)
		expect(Anim.stanceLegs(Anim.STANCE_STILL)).toBe(0)
		local pose = {}
		local lift = Anim.stance("warrior_sword", 1, 1, 0, pose)
		expect(lift.Y).toBeLessThan(0) -- crouch
		expect(pose.waist).toBeTruthy()
		expect(pose.lKnee).toBeTruthy()
		-- walking: no leg stance, no crouch
		local walking = {}
		local walkLift = Anim.stance("warrior_sword", 0.5, 0, 0, walking)
		expect(walking.lKnee).toBeNil()
		expect(walkLift).toBe(Vector3.zero)
		local none = {}
		expect(Anim.stance("nope", 1, 1, 0, none)).toBe(Vector3.zero)
		expect(next(none)).toBeNil()
		local mix = {}
		Anim.hold("nope", 1, false, none, mix)
		expect(next(none)).toBeNil()
		expect(next(mix)).toBeNil()
		local half = {}
		Anim.stance("mage_staff", 0.5, 1, 0, half)
		expect(half.waist.X).toBe(Anim.STANCE.mage_staff.pose.waist.X * 0.5)
		-- the weapon arm is always ours; the off arm blends with the Animator's by weight
		local arm, share = {}, {}
		Anim.hold("warrior_sword", 0.3, false, arm, share)
		expect(share.rShoulder).toBe(1)
		expect(share.lShoulder).toBe(0.3)
		-- the bow has no off arm: the draw hand stays the Animator's at rest
		local bowArm, bowShare = {}, {}
		Anim.hold("ranger_bow", 1, false, bowArm, bowShare)
		expect(bowShare.lShoulder).toBe(1)
		expect(bowShare.rShoulder).toBeNil()
	end)
end)
