--!strict
-- Held weapons per class, from the owner's weapon pack (assets/weapons/<Folder>/Standard.fbx +
-- Color.png, 2026-11-02). Systems/Weapons puts the weapon into the character's hand.
--
-- How a weapon is held (docs/TECH.md "Weapons"): sword, staff and scepter in the right hand
-- with the arm raised forward (Roblox's own "hold a tool" arm pose, HOLD_ANIM), blade/head up;
-- the bow in the left fist the same way: limbs along the hand's -Z (vertical once the arm is up),
-- riser toward the fingers (forward), string toward the archer. The arm poses: Shared/Anim STANCE.
--
-- The 3D models need two Roblox ids each (see docs/TECH.md "Weapons"): the mesh (Model asset from the
-- FBX) and the texture (Image asset from Color.png). Both live in Assets.Weapon. While an id is
-- empty, the weapon is built from studded parts (same silhouette, class colors), never an error.

export type Weapon = {
	id: string, -- stable key (asset keys "weapon_<id>_model" / "weapon_<id>_texture")
	name: string,
	class: string, -- Shared/Classes id
	folder: string, -- folder in assets/weapons/
	length: number, -- studs: longest side once held (the mesh is scaled to it)
	-- Where the hand holds the weapon: share of the length from the butt (measured on the FBX).
	gripAt: number,
	-- Bounding-box center of the mesh relative to the grip point across the long axis (X, Z in
	-- weapon space), as share of the length; measured on the FBX like gripAt.
	offset: Vector2,
	hand: string, -- "right" | "left"
	ready: boolean, -- true = arm raised forward (HOLD_ANIM); false = arm hangs down
	-- Pose in the hand frame (hand +Y = up the arm, -Z = forward while the arm hangs). Weapon
	-- space: the grip point is the origin and the head/tip points to +Y. With the arm raised
	-- forward (ready) the hand's -Z points up, so CFrame.Angles(-90°, 0, 0) holds a weapon upright.
	grip: CFrame,
	color: Color3, -- main color of the part fallback
	accent: Color3, -- glow/accent color of the part fallback
}

local Weapons = {}

-- Mesh axes. Weapon space is the FBX space of the pack: Y up (head/tip/upper limb at +Y), X and Z
-- as authored. Measured on assets/weapons/Ranger_Bow/Standard.fbx (header UpAxis Y, FrontAxis +Z,
-- CoordAxis +X; the model node turns the Z-long geometry -90° about X so the limbs run along +Y):
-- the riser and the bow's back (outer curve) bulge toward +X (up to x = +0.9 at the grip height),
-- both limb tips and the straight string sit at x ≈ -0.1, so the string side is -X; Z is only the
-- thickness (±0.24). Roblox's importer turns FBX "front +Z" into its own front (-Z): the uploaded
-- MeshPart is the FBX turned 180° about Y (X and Z negated). Without undoing that, the bow showed
-- its string on the wrong side and the hand missed the grip by the mirrored `offset` (2026-11-04
-- screenshot: string away from the body, back of the bow toward the leg). IMPORT undoes it.
Weapons.IMPORT = CFrame.Angles(0, math.pi, 0)

-- Where the loaded MeshPart sits in weapon space: its bounding-box center (gripAt, offset), turned
-- back into FBX axes (IMPORT), then `align` for an import that lies on its side
function Weapons.meshCFrame(w: Weapon, align: CFrame?): CFrame
	return CFrame.new(w.offset.X * w.length, (0.5 - w.gripAt) * w.length, w.offset.Y * w.length)
		* Weapons.IMPORT
		* (align or CFrame.identity)
end

-- Roblox's default "toolnone" animations (arm raised forward, like holding any Roblox tool)
Weapons.HOLD_ANIM = table.freeze({
	R15 = "rbxassetid://507768375",
	R6 = "rbxassetid://182393478",
})

Weapons.List = table.freeze({
	table.freeze({
		id = "warrior_sword",
		name = "Knight's Sword",
		class = "warrior",
		folder = "Warrior_Sword",
		length = 4.2,
		gripAt = 0.19, -- middle of the handle, between pommel and guard
		offset = Vector2.new(-0.038, 0), -- knuckle guard on one side
		hand = "right",
		ready = true,
		-- blade up, tipped 15° forward, edges (and knuckle guard) facing forward
		grip = CFrame.Angles(math.rad(-105), 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
		color = Color3.fromHex("#C9D2DE"),
		accent = Color3.fromHex("#E8B04A"),
	}),
	table.freeze({
		id = "ranger_bow",
		name = "Ranger's Bow",
		class = "ranger",
		folder = "Ranger_Bow",
		length = 4.4,
		gripAt = 0.405, -- narrow handle below the arrow shelf
		offset = Vector2.new(-0.034, 0),
		hand = "left",
		ready = false,
		-- limbs (+Y) along the hand's -Z, riser (+X) toward the fingers, string toward the archer
		grip = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, -1)),
		color = Color3.fromHex("#8A5A34"),
		accent = Color3.fromHex("#7FD27A"),
	}),
	table.freeze({
		id = "mage_staff",
		name = "Spark Staff",
		class = "mage",
		folder = "Mage_Staff",
		length = 6.4, -- taller than the mage: planted, its foot touches the ground (Anim.STANCE)
		gripAt = 0.42,
		offset = Vector2.new(0.013, 0.013),
		hand = "right",
		ready = true,
		grip = CFrame.Angles(math.rad(-100), 0, 0), -- upright, head tipped 10° forward
		color = Color3.fromHex("#6B4A8E"),
		accent = Color3.fromHex("#4FD8F5"),
	}),
	table.freeze({
		id = "druid_scepter",
		name = "Spore Scepter",
		class = "mushroom",
		folder = "Druid_Scepter",
		length = 3.6,
		gripAt = 0.16, -- middle of the shaft, below the mushroom head
		offset = Vector2.new(-0.03, 0),
		hand = "right",
		ready = true,
		grip = CFrame.Angles(math.rad(-100), 0, 0),
		color = Color3.fromHex("#5E7A3A"),
		accent = Color3.fromHex("#E86FB5"),
	}),
} :: { Weapon })

local byId: { [string]: Weapon } = {}
local byClass: { [string]: Weapon } = {}
for _, w in Weapons.List do
	byId[w.id] = w
	byClass[w.class] = w
end
Weapons.ById = table.freeze(byId)
Weapons.ByClass = table.freeze(byClass)

return table.freeze(Weapons)
