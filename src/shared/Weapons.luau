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
	-- Grip relative to the hand: the weapon's long axis runs along -Y of the hand (down to the
	-- floor for a staff, forward for a sword after the swing animation). Tune in Studio.
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
		grip = CFrame.new(0, -1.6, -0.4) * CFrame.Angles(math.rad(-90), 0, 0),
		color = Color3.fromHex("#C9D2DE"),
		accent = Color3.fromHex("#E8B04A"),
	}),
	table.freeze({
		id = "ranger_bow",
		name = "Ranger's Bow",
		class = "ranger",
		folder = "Ranger_Bow",
		length = 4.4,
		grip = CFrame.new(0, -0.9, 0) * CFrame.Angles(0, math.rad(90), 0),
		color = Color3.fromHex("#8A5A34"),
		accent = Color3.fromHex("#7FD27A"),
	}),
	table.freeze({
		id = "mage_staff",
		name = "Spark Staff",
		class = "mage",
		folder = "Mage_Staff",
		length = 5.2,
		grip = CFrame.new(0, -0.9, 0),
		color = Color3.fromHex("#6B4A8E"),
		accent = Color3.fromHex("#4FD8F5"),
	}),
	table.freeze({
		id = "druid_scepter",
		name = "Spore Scepter",
		class = "mushroom",
		folder = "Druid_Scepter",
		length = 3.6,
		grip = CFrame.new(0, -0.8, 0),
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
