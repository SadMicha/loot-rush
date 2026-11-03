--!strict
-- Held weapons per class, from the owner's weapon pack (assets/weapons/<Folder>/Standard.fbx +
-- Color.png, 2026-11-02). Systems/Weapons puts the weapon into the character's right hand.
--
-- The 3D models need two Roblox ids each (see docs/WEAPONS.md): the mesh (Model asset from the
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
	-- Pose in the hand frame (hand +Y = up the arm, -Z = forward). Weapon space: the grip point is
	-- the origin and the head/tip points to +Y. Identity = held upright beside the body.
	grip: CFrame,
	color: Color3, -- main color of the part fallback
	accent: Color3, -- glow/accent color of the part fallback
}

local Weapons = {}

Weapons.List = table.freeze({
	table.freeze({
		id = "warrior_sword",
		name = "Knight's Sword",
		class = "warrior",
		folder = "Warrior_Sword",
		length = 4.2,
		gripAt = 0.07,
		grip = CFrame.Angles(math.rad(-70), 0, 0),
		color = Color3.fromHex("#C9D2DE"),
		accent = Color3.fromHex("#E8B04A"),
	}),
	table.freeze({
		id = "ranger_bow",
		name = "Ranger's Bow",
		class = "ranger",
		folder = "Ranger_Bow",
		length = 4.4,
		gripAt = 0.45,
		grip = CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromHex("#8A5A34"),
		accent = Color3.fromHex("#7FD27A"),
	}),
	table.freeze({
		id = "mage_staff",
		name = "Spark Staff",
		class = "mage",
		folder = "Mage_Staff",
		length = 5.2,
		gripAt = 0.29,
		grip = CFrame.Angles(math.rad(-8), 0, 0),
		color = Color3.fromHex("#6B4A8E"),
		accent = Color3.fromHex("#4FD8F5"),
	}),
	table.freeze({
		id = "druid_scepter",
		name = "Spore Scepter",
		class = "mushroom",
		folder = "Druid_Scepter",
		length = 3.6,
		gripAt = 0.25,
		grip = CFrame.Angles(math.rad(-8), 0, 0),
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
