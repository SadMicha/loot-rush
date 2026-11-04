--!strict
-- Character animations without uploaded assets (docs/ANIMATIONS.md). Every move is a short list
-- of keyframes per joint; AnimController layers them on top of Roblox's own idle/walk/run and the
-- weapon hold pose by rotating the rig's joints (Motor6D or AnimationConstraint) every frame (client only, nothing is
-- replicated). Pure data and math here, so the specs can sample every move headless.
--
-- Joint angles are degrees in the parent part's space at the joint (character space: +X right,
-- +Y up, -Z forward), the same on R15 and R6 (AnimController converts them per motor):
--   X+ swings a limb forward/up (shoulder, hip); on root/waist/neck X+ leans back, X- forward
--   Y+ turns left;  Z+ moves an arm out to the right side (right shoulder), Z- the left arm out
--   elbow X+ bends the forearm forward, knee X- bends the shin back
-- `lift` moves the whole body (root joint) in studs, e.g. (0, -0.6, 0) = crouch.

export type Pose = { [string]: Vector3 }
export type Key = {
	t: number, -- 0..1 share of the move time
	pose: Pose,
	lift: Vector3?,
	snap: boolean?, -- this segment eases out fast (strikes, releases)
}
export type Move = {
	id: string,
	time: number, -- seconds
	face: boolean, -- turn the body toward the target point while it plays
	hold: boolean?, -- keep the last key until the character is gone (death)
	keys: { Key },
}

local Anim = {}

-- Joints every move may use. R6 has no waist, elbows, wrists or knees: waist folds into the root there.
Anim.JOINTS = table.freeze({
	"root",
	"waist",
	"neck",
	"rShoulder",
	"lShoulder",
	"rElbow",
	"lElbow",
	"rHip",
	"lHip",
	"rKnee",
	"lKnee",
	"rWrist",
	"lWrist",
})

-- Motor6D per joint: { part that holds the motor, motor name }
Anim.R15 = table.freeze({
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
	rShoulder = { "RightUpperArm", "RightShoulder" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	rElbow = { "RightLowerArm", "RightElbow" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	rHip = { "RightUpperLeg", "RightHip" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	rWrist = { "RightHand", "RightWrist" },
	lWrist = { "LeftHand", "LeftWrist" },
})
Anim.R6 = table.freeze({
	root = { "HumanoidRootPart", "RootJoint" },
	neck = { "Torso", "Neck" },
	rShoulder = { "Torso", "Right Shoulder" },
	lShoulder = { "Torso", "Left Shoulder" },
	rHip = { "Torso", "Right Hip" },
	lHip = { "Torso", "Left Hip" },
})
-- R6 joints that do not exist are added to another one (or dropped when missing here)
Anim.R6_FOLD = table.freeze({ waist = "root" } :: { [string]: string })

-- Tuning (AnimController)
Anim.RANGE = 140 -- studs from the camera: characters further away get no extra animation
Anim.MAX_CHARACTERS = 16 -- animated characters at once (nearest first)
Anim.RUN_LEAN = 9 -- degrees forward lean at full run speed
Anim.RUN_SPEED = 24 -- studs/s that count as full run speed
Anim.BREATH = 1.6 -- degrees of idle breathing (chest and arms)
Anim.BREATH_RATE = 1.9 -- breaths per ~3 seconds (radians per second / pi)
Anim.FACE_MAX = 110 -- degrees the body turns toward a target at most
Anim.LAYERS_MAX = 3 -- moves at once per character (the oldest is dropped)
Anim.JOINT_RETRY = 0.5 -- seconds between joint searches while a rig has none (avatar loading)
Anim.JOINT_WARN = 4 -- seconds without joints on the own character: warn once in the Output
Anim.DEATH_BREAK = 0.95 -- seconds after death: the fallen body breaks into bricks

-- Enemy body language (server, Systems/Enemies; pivot rotation only)
Anim.ENEMY_WINDUP_LEAN = 14 -- degrees leaning back while winding up an attack
Anim.ENEMY_LUNGE = 20 -- degrees snapping forward when the attack lands
Anim.ENEMY_LUNGE_TIME = 0.28
Anim.ENEMY_RECOIL = 11 -- degrees knocked back by a direct hit
Anim.ENEMY_RECOIL_TIME = 0.18
Anim.ENEMY_WADDLE = 5 -- degrees side to side while walking
Anim.ENEMY_WALK_RATE = 7 -- same rhythm as the walking hop

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function move(id: string, time: number, face: boolean, keys: { Key }, hold: boolean?): Move
	return table.freeze({ id = id, time = time, face = face, hold = hold, keys = keys })
end

local Z: Pose = {}

Anim.Moves = table.freeze({
	-- Sword basic, first hit: horizontal slash right to left
	slash = move("slash", 0.32, true, {
		{ t = 0, pose = Z },
		{
			t = 0.35,
			pose = { waist = v(0, -25, 0), rShoulder = v(5, -55, 10), neck = v(0, 12, 0) },
		},
		{
			t = 0.6,
			snap = true,
			pose = { waist = v(0, 30, 0), rShoulder = v(-15, 55, 0), rElbow = v(10, 0, 0) },
		},
		{ t = 1, pose = Z },
	}),
	-- Sword basic, second hit: overhead chop
	chop = move("chop", 0.34, true, {
		{ t = 0, pose = Z },
		{ t = 0.35, pose = { rShoulder = v(55, 0, 0), waist = v(8, 0, 0) } },
		{
			t = 0.6,
			snap = true,
			pose = { rShoulder = v(-45, 0, 0), waist = v(-14, 0, 0), neck = v(-6, 0, 0) },
			lift = v(0, -0.2, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Warrior arc skills (Shield Bash, Blade Storm): wide, heavy swing with a step in
	cleave = move("cleave", 0.48, true, {
		{ t = 0, pose = Z },
		{
			t = 0.38,
			pose = {
				waist = v(4, -40, 0),
				rShoulder = v(10, -80, 15),
				lShoulder = v(20, 0, -25),
				rHip = v(-10, 0, 0),
				lHip = v(20, 0, 0),
			},
			lift = v(0, -0.25, 0),
		},
		{
			t = 0.6,
			snap = true,
			pose = {
				waist = v(-10, 45, 0),
				rShoulder = v(-20, 80, 0),
				lShoulder = v(-20, 0, -20),
				rHip = v(15, 0, 0),
				lHip = v(-10, 0, 0),
			},
			lift = v(0, -0.15, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Whirlwind-like novas: one full turn with the arms out
	spin = move("spin", 0.45, false, {
		{ t = 0, pose = Z },
		{
			t = 0.5,
			pose = { root = v(0, 180, 0), rShoulder = v(0, 0, 65), lShoulder = v(0, 0, -65) },
			lift = v(0, -0.2, 0),
		},
		{
			t = 0.9,
			pose = { root = v(0, 360, 0), rShoulder = v(0, 0, 30), lShoulder = v(0, 0, -30) },
		},
		{ t = 1, pose = { root = v(0, 360, 0) } },
	}),
	-- Novas: raise both arms, slam down into a crouch
	slam = move("slam", 0.55, false, {
		{ t = 0, pose = Z },
		{
			t = 0.4,
			pose = { rShoulder = v(70, 0, 0), lShoulder = v(140, 0, 0), waist = v(12, 0, 0) },
			lift = v(0, 0.3, 0),
		},
		{
			t = 0.6,
			snap = true,
			pose = {
				rShoulder = v(-20, 0, 0),
				lShoulder = v(30, 0, 0),
				waist = v(-25, 0, 0),
				rHip = v(30, 0, 0),
				lHip = v(30, 0, 0),
				rKnee = v(-45, 0, 0),
				lKnee = v(-45, 0, 0),
			},
			lift = v(0, -0.7, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Staff / scepter basic and bolts: push the weapon forward, free hand follows
	cast = move("cast", 0.32, true, {
		{ t = 0, pose = Z },
		{
			t = 0.4,
			pose = { waist = v(6, 0, 0), rShoulder = v(25, 0, 0), lShoulder = v(30, 0, -10) },
		},
		{
			t = 0.65,
			snap = true,
			pose = {
				waist = v(-12, 0, 0),
				rShoulder = v(-15, 0, 0),
				lShoulder = v(85, 0, 0),
				lElbow = v(15, 0, 0),
			},
		},
		{ t = 1, pose = Z },
	}),
	-- Staff / scepter skill bolts: same with a small hop
	castBig = move("castBig", 0.45, true, {
		{ t = 0, pose = Z },
		{
			t = 0.4,
			pose = { waist = v(14, 0, 0), rShoulder = v(55, 0, 0), lShoulder = v(60, 0, -20) },
			lift = v(0, 0.35, 0),
		},
		{
			t = 0.62,
			snap = true,
			pose = {
				waist = v(-18, 0, 0),
				rShoulder = v(-25, 0, 0),
				lShoulder = v(95, 0, 0),
				rHip = v(-15, 0, 0),
				lHip = v(20, 0, 0),
			},
			lift = v(0, -0.2, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Bow: turn side-on, bow arm up, draw to the chin, release
	shoot = move("shoot", 0.38, true, {
		{ t = 0, pose = Z },
		{
			t = 0.45,
			pose = {
				waist = v(0, -35, 0),
				neck = v(0, 30, 0),
				lShoulder = v(88, 25, 0),
				rShoulder = v(82, 20, 0),
				rElbow = v(40, 0, 0),
			},
		},
		{
			t = 0.62,
			snap = true,
			pose = {
				waist = v(0, -35, 0),
				neck = v(0, 30, 0),
				lShoulder = v(88, 25, 0),
				rShoulder = v(60, 0, 35),
				rElbow = v(10, 0, 0),
			},
		},
		{ t = 1, pose = Z },
	}),
	-- Chains (lightning, vines, falcon): point at the target
	point = move("point", 0.36, true, {
		{ t = 0, pose = Z },
		{ t = 0.4, pose = { lShoulder = v(40, 0, -10), waist = v(4, 0, 0) } },
		{
			t = 0.6,
			snap = true,
			pose = { lShoulder = v(95, 0, 0), waist = v(-6, -20, 0), neck = v(0, 15, 0) },
		},
		{ t = 1, pose = Z },
	}),
	-- Leaps (Charge): crouch, launch forward, land
	leap = move("leap", 0.5, true, {
		{ t = 0, pose = Z },
		{
			t = 0.3,
			pose = {
				waist = v(-25, 0, 0),
				rShoulder = v(-40, 0, 0),
				lShoulder = v(-40, 0, 0),
				rHip = v(30, 0, 0),
				lHip = v(30, 0, 0),
				rKnee = v(-40, 0, 0),
				lKnee = v(-40, 0, 0),
			},
			lift = v(0, -0.4, 0),
		},
		{
			t = 0.6,
			snap = true,
			pose = {
				root = v(-20, 0, 0),
				rShoulder = v(30, 0, 20),
				lShoulder = v(-30, 0, -20),
				rHip = v(50, 0, 0),
				lHip = v(-20, 0, 0),
				rKnee = v(-60, 0, 0),
			},
			lift = v(0, 1.2, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Zones (Arrow Rain, clouds, totems): weapon high, then strike the ground
	plant = move("plant", 0.5, true, {
		{ t = 0, pose = Z },
		{
			t = 0.4,
			pose = { rShoulder = v(75, 0, 0), lShoulder = v(150, 0, 0), waist = v(15, 0, 0) },
		},
		{
			t = 0.65,
			snap = true,
			pose = { rShoulder = v(-25, 0, 0), lShoulder = v(60, 0, 0), waist = v(-15, 0, 0) },
			lift = v(0, -0.3, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Buffs (Battle Cry, Stone Armor, Healing Mushrooms): gather, then burst out
	roar = move("roar", 0.6, false, {
		{ t = 0, pose = Z },
		{
			t = 0.3,
			pose = { waist = v(-15, 0, 0), rShoulder = v(-20, 0, 0), lShoulder = v(-20, 0, 0) },
			lift = v(0, -0.3, 0),
		},
		{
			t = 0.55,
			snap = true,
			pose = {
				waist = v(18, 0, 0),
				neck = v(20, 0, 0),
				rShoulder = v(20, 0, 70),
				lShoulder = v(20, 0, -70),
			},
			lift = v(0, 0.2, 0),
		},
		{
			t = 0.8,
			pose = {
				waist = v(15, 0, 0),
				neck = v(15, 0, 0),
				rShoulder = v(20, 0, 65),
				lShoulder = v(20, 0, -65),
			},
			lift = v(0, 0.15, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Dodge roll: forward somersault, tucked
	roll = move("roll", 0.32, false, {
		{ t = 0, pose = Z },
		{
			t = 0.5,
			pose = {
				root = v(-180, 0, 0),
				rShoulder = v(40, 0, 0),
				lShoulder = v(40, 0, 0),
				rHip = v(70, 0, 0),
				lHip = v(70, 0, 0),
				rKnee = v(-90, 0, 0),
				lKnee = v(-90, 0, 0),
			},
			lift = v(0, -1.2, 0),
		},
		{ t = 1, pose = { root = v(-360, 0, 0) } },
	}),
	-- Hit reaction
	hurt = move("hurt", 0.28, false, {
		{ t = 0, pose = Z },
		{
			t = 0.3,
			snap = true,
			pose = {
				waist = v(14, 0, 0),
				neck = v(18, 0, 0),
				rShoulder = v(0, 0, 12),
				lShoulder = v(0, 0, -12),
			},
			lift = v(0, -0.1, 0),
		},
		{ t = 1, pose = Z },
	}),
	-- Death: knees give way, fall forward, stay down (then breaks into bricks)
	death = move("death", 0.75, false, {
		{ t = 0, pose = Z },
		{
			t = 0.35,
			pose = {
				waist = v(-20, 0, 0),
				neck = v(-10, 0, 0),
				rHip = v(40, 0, 0),
				lHip = v(40, 0, 0),
				rKnee = v(-80, 0, 0),
				lKnee = v(-80, 0, 0),
				rShoulder = v(-10, 0, 15),
				lShoulder = v(-10, 0, -15),
			},
			lift = v(0, -1, 0),
		},
		{
			t = 1,
			snap = true,
			pose = {
				root = v(-82, 0, 0),
				neck = v(25, 15, 0),
				rShoulder = v(150, 0, 20),
				lShoulder = v(150, 0, -20),
			},
			lift = v(0, -2.3, 0),
		},
	}, true),
	-- Level up: both arms up, small jump
	cheer = move("cheer", 0.75, false, {
		{ t = 0, pose = Z },
		{
			t = 0.25,
			pose = { rShoulder = v(10, 0, 0), lShoulder = v(10, 0, 0) },
			lift = v(0, -0.3, 0),
		},
		{
			t = 0.45,
			snap = true,
			pose = {
				rShoulder = v(70, 0, 20),
				lShoulder = v(165, 0, -15),
				neck = v(12, 0, 0),
				waist = v(8, 0, 0),
			},
			lift = v(0, 0.6, 0),
		},
		{
			t = 0.75,
			pose = { rShoulder = v(60, 0, 20), lShoulder = v(150, 0, -15), neck = v(8, 0, 0) },
		},
		{ t = 1, pose = Z },
	}),
} :: { [string]: Move })

-- Weapon style per held weapon (Shared/Weapons ids)
Anim.STYLE = table.freeze({
	warrior_sword = "sword",
	ranger_bow = "bow",
	mage_staff = "staff",
	druid_scepter = "staff",
} :: { [string]: string })

-- Holding stance per held weapon (Shared/Weapons ids). Two parts:
--   hold  the weapon arm (shoulder, elbow, wrist) as an ABSOLUTE pose in the same angles as moves
--         (parent space, 0 = arm hanging straight). It replaces whatever the Animator put on that
--         arm (Weapons.HOLD_ANIM, walk swing), so the weapon's angle in the world is known and the
--         specs can check it (tests/Anim.spec.luau "Holding stances" computes the weapon axis).
--   pose  the rest of the body (waist, neck, off arm, hips), ADDED on top of idle/walk.
-- `ref` is the arm pose the attack moves were made for (Roblox's tool-hold arm: raised straight
-- forward); nil = the Animator's own arm (the bow arm hangs and swings while walking). Standing,
-- the arm takes `hold`; it eases toward `ref` while running (STANCE_MOVING) and while a move plays
-- (STANCE_ACTING), so attacks keep their shape. The weapon arm sways slowly (STANCE_SWAY degrees).
-- Weapon angles in the hand: Weapons.grip (hand +Y up the arm, -Z forward while the arm hangs).
-- Shoulder X + elbow X + wrist X = how far the hand frame is turned forward/up: 90 = the hand's -Z
-- points up, which holds sword, staff and scepter upright with their grips.
--   sword    guard: hand low in front, blade up and leaning toward the enemy, weight back
--   bow      relaxed: bow arm a little forward and out, wrist keeps the bow upright, draw hand
--            resting near the string
--   staff    planted: elbow bent, the staff stands upright beside the body
--   scepter  close: scepter upright in front of the chest, off hand near it
Anim.STANCE_MOVING = 0.45 -- stance share while running at full speed
Anim.STANCE_ACTING = 0.25 -- stance share while an attack or other move plays
Anim.STANCE_BLEND = 6 -- per second: how fast the stance weight follows (no snapping)
Anim.STANCE_SWAY = 2.5 -- degrees the weapon arm sways while standing
Anim.STANCE_SWAY_RATE = 1.3 -- radians per second

-- Arm joints per hand, shoulder to wrist
Anim.ARM = table.freeze({
	right = table.freeze({ "rShoulder", "rElbow", "rWrist" }),
	left = table.freeze({ "lShoulder", "lElbow", "lWrist" }),
} :: { [string]: { string } })

local READY: Pose = table.freeze({ rShoulder = v(90, 0, 0) }) -- Roblox's tool-hold arm

export type Stance = {
	hand: string, -- "right" | "left" (Anim.ARM)
	ref: Pose?,
	hold: Pose,
	pose: Pose,
	lift: Vector3?,
}

Anim.STANCE = table.freeze({
	warrior_sword = table.freeze({
		hand = "right",
		ref = READY,
		hold = table.freeze({ rShoulder = v(45, 15, 0), rElbow = v(30, 0, 0) }),
		lift = v(0, -0.15, 0),
		pose = table.freeze({
			waist = v(0, -12, 0),
			neck = v(0, 10, 0),
			lShoulder = v(20, 0, -10),
			lElbow = v(30, 0, 0),
			rHip = v(8, 0, 0),
			lHip = v(-8, 0, 0),
		}),
	}),
	ranger_bow = table.freeze({
		hand = "left",
		hold = table.freeze({
			lShoulder = v(12, 0, -10),
			lElbow = v(20, 0, 0),
			lWrist = v(-32, 0, 0),
		}),
		pose = table.freeze({
			waist = v(0, 8, 0),
			neck = v(0, -6, 0),
			rShoulder = v(15, 0, 0),
			rElbow = v(50, 0, 0),
		}),
	}),
	mage_staff = table.freeze({
		hand = "right",
		ref = READY,
		hold = table.freeze({ rShoulder = v(10, 0, 5), rElbow = v(90, 0, 0) }),
		pose = table.freeze({
			waist = v(-3, 0, 0),
			neck = v(3, 0, 0),
			lShoulder = v(0, 0, -6),
			lElbow = v(15, 0, 0),
		}),
	}),
	druid_scepter = table.freeze({
		hand = "right",
		ref = READY,
		hold = table.freeze({ rShoulder = v(20, 30, 0), rElbow = v(80, 0, 0) }),
		pose = table.freeze({
			waist = v(-5, 0, 0),
			neck = v(-4, 0, 0),
			lShoulder = v(20, 0, -6),
			lElbow = v(40, 0, 0),
		}),
	}),
} :: { [string]: Stance })

-- Target stance weight 0..1: `run` = 0..1 of full run speed, `acting` = a move plays
function Anim.stanceWeight(run: number, acting: boolean): number
	local w = 1 + (Anim.STANCE_MOVING - 1) * math.clamp(run, 0, 1)
	return if acting then math.min(w, Anim.STANCE_ACTING) else w
end

-- Adds the body part of the stance of `weaponId` at `weight` into `out` (plus the weapon arm's
-- sway at time `now`); returns the body lift in studs. Unknown weapons add nothing.
function Anim.stance(weaponId: string?, weight: number, now: number, out: Pose): Vector3
	local s = weaponId and Anim.STANCE[weaponId]
	if not s or weight <= 0 then
		return Vector3.zero
	end
	for joint, a in s.pose do
		out[joint] = (out[joint] or Vector3.zero) + a * weight
	end
	local sway = math.sin(now * Anim.STANCE_SWAY_RATE) * Anim.STANCE_SWAY * weight
	local arm = Anim.ARM[s.hand][1]
	out[arm] = (out[arm] or Vector3.zero) + Vector3.new(sway, 0, sway * 0.4)
	return (s.lift or Vector3.zero) * weight
end

-- Absolute weapon-arm pose of `weaponId` at stance `weight` into `out` (every arm joint, zero =
-- straight); returns how much of it replaces the Animator's arm (0..1). With a `ref` the arm is
-- always ours (ref..hold); without one the Animator's arm blends toward `hold` by `weight`.
-- R6 has no elbow or wrist: their angles fold into the shoulder (the weapon keeps its angle).
function Anim.hold(weaponId: string?, weight: number, r6: boolean, out: Pose): number
	local s = weaponId and Anim.STANCE[weaponId]
	if not s then
		return 0
	end
	local w = math.clamp(weight, 0, 1)
	local ref = s.ref
	local names = Anim.ARM[s.hand]
	for _, joint in names do
		local hold = s.hold[joint] or Vector3.zero
		out[joint] = if ref then (ref[joint] or Vector3.zero):Lerp(hold, w) else hold
	end
	if r6 then
		out[names[1]] = out[names[1]] + out[names[2]] + out[names[3]]
		out[names[2]] = nil
		out[names[3]] = nil
	end
	return if ref then 1 else w
end

-- Skills with their own move (otherwise the skill kind decides)
Anim.SKILL_MOVE = table.freeze({
	whirlwind = "spin",
	blade_whirl = "spin",
	arc_whirl = "spin",
	taunt = "roar",
} :: { [string]: string })

-- Move for an attack: `style` from Anim.STYLE, `kind` = Skills kind, `basic` = auto attack,
-- `combo` counts the character's basic attacks (sword alternates slash and chop)
function Anim.moveFor(
	style: string?,
	kind: string,
	skillId: string?,
	basic: boolean,
	combo: number
): string
	if basic then
		if style == "sword" then
			return if combo % 2 == 0 then "slash" else "chop"
		elseif style == "bow" then
			return "shoot"
		end
		return "cast"
	end
	local special = skillId and Anim.SKILL_MOVE[skillId]
	if special then
		return special
	end
	if kind == "projectile" then
		return if style == "bow" then "shoot" else "castBig"
	elseif kind == "arc" then
		return "cleave"
	elseif kind == "nova" then
		return "slam"
	elseif kind == "chain" then
		return if style == "bow" then "shoot" else "point"
	elseif kind == "leap" then
		return "leap"
	elseif kind == "zone" then
		return "plant"
	elseif kind == "buff" then
		return "roar"
	end
	return "cast"
end

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

local function snapOut(a: number): number
	local b = 1 - a
	return 1 - b * b * b
end

local function lerpPose(a: Pose, b: Pose, w: number, out: Pose, weight: number)
	for _, j in Anim.JOINTS do
		local va = a[j]
		local vb = b[j]
		if va or vb then
			local x = (va or Vector3.zero):Lerp(vb or Vector3.zero, w) * weight
			out[j] = (out[j] or Vector3.zero) + x
		end
	end
end

-- Adds the move's pose at `elapsed` seconds (times `weight`) into `out`; returns the body lift.
-- Past the end the pose is zero, except for hold moves (they keep the last key).
function Anim.sample(m: Move, elapsed: number, out: Pose, weight: number?): Vector3
	local w = weight or 1
	local keys = m.keys
	local t = elapsed / m.time
	if t >= 1 then
		if not m.hold then
			return Vector3.zero
		end
		local last = keys[#keys]
		lerpPose(last.pose, last.pose, 0, out, w)
		return (last.lift or Vector3.zero) * w
	end
	t = math.max(t, 0)
	for i = 2, #keys do
		local b = keys[i]
		if t <= b.t then
			local a = keys[i - 1]
			local span = b.t - a.t
			local f = if span > 0 then (t - a.t) / span else 1
			f = if b.snap then snapOut(f) else smooth(f)
			lerpPose(a.pose, b.pose, f, out, w)
			return (a.lift or Vector3.zero):Lerp(b.lift or Vector3.zero, f) * w
		end
	end
	return Vector3.zero
end

-- How strongly a move turns the body toward its target: ramps in fast, out over the last third
function Anim.faceWeight(m: Move, elapsed: number): number
	local t = elapsed / m.time
	if t <= 0 or t >= 1 then
		return 0
	end
	if t < 0.15 then
		return smooth(t / 0.15)
	elseif t > 0.7 then
		return smooth((1 - t) / 0.3)
	end
	return 1
end

-- Enemy pivot tilt (degrees, + = lean back): windup share 0..1 (or nil), seconds since the attack
-- landed and since the last direct hit
function Anim.enemyPitch(windup: number?, sinceLunge: number, sinceHit: number): number
	local pitch = 0
	if windup then
		pitch += Anim.ENEMY_WINDUP_LEAN * smooth(math.clamp(windup, 0, 1))
	end
	if sinceLunge >= 0 and sinceLunge < Anim.ENEMY_LUNGE_TIME then
		pitch -= Anim.ENEMY_LUNGE * (1 - snapOut(sinceLunge / Anim.ENEMY_LUNGE_TIME))
	end
	if sinceHit >= 0 and sinceHit < Anim.ENEMY_RECOIL_TIME then
		pitch += Anim.ENEMY_RECOIL * (1 - smooth(sinceHit / Anim.ENEMY_RECOIL_TIME))
	end
	return pitch
end

return table.freeze(Anim)
