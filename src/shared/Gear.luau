--!strict
-- Visible gear (pure data): how worn armor and jewelry look on the hero's body. Systems/Gear builds
-- these pieces from studded parts and welds them to the R15 body parts, so every player sees
-- them, and the inventory preview (a clone of the character) shows them too. No art assets.
--
-- A look ("style") is a list of chunky, layered pieces per slot. Each piece hangs on one body part
-- and is sized and placed in multiples of that part's size, so it fits every avatar scale:
--   size = part.Size * s (+ pad studs) · position = part.Size * p from the part center
--   (+Y up, -Z = the face/chest side, +X = the hero's right). "{S}" in a part name = both sides
--   (Left/Right, X mirrored); `mirror` = a second copy on the same part at -X.
-- Colors are roles: main/dark/metal/accent from the look's palette, rune = the palette accent
-- glowing (Neon); trim, gem and glow take the item's rarity color.
--
-- Rarity shows on the body (docs/TECH.md "Visible gear"): a piece appears from its role's floor
-- (trim: magic, gem: rare, glow: epic) or its own `min`, whichever is higher. Normal = the plain
-- base look, magic adds rarity trim plates, rare adds glowing gems and extra plates, epic and
-- unique add thin Neon edges (no particles, no per-frame work).
--
-- Looks are separate from items on purpose: the default look of a slot is the hero's class,
-- a gear skin (cosmetic, docs/specs/GEAR-COSMETICS.md) is just another style id for that slot.

local Items = require(script.Parent.Items)
local Theme = require(script.Parent.UI.Theme)

local Gear = {}

export type Shape = "block" | "wedge" | "ball" | "disc"
export type Role = "main" | "dark" | "metal" | "accent" | "rune" | "trim" | "gem" | "glow"
export type Finish = "studs" | "glass" | "neon"
export type Piece = {
	part: string, -- R15 body part ("{S}" = both sides)
	shape: Shape,
	s: Vector3, -- size in part sizes (ball: X only, uniform; disc: X = height, Y = diameter)
	p: Vector3, -- center offset in part sizes
	r: Vector3?, -- rotation in degrees (X, Y, Z)
	pad: Vector3?, -- studs added to the size (thin plates that must stay visible)
	role: Role,
	min: string?, -- lowest item rarity that shows the piece (on top of the role's floor)
	mirror: boolean?, -- also place a copy at -X on the same part
}
export type Palette = { main: Color3, dark: Color3, metal: Color3, accent: Color3 }
export type Style = {
	id: string,
	name: string,
	palette: Palette,
	pieces: { [string]: { Piece } }, -- slot → pieces (missing slot = default class look)
}

-- Slots with a body look. Weapon/offhand are held (Systems/Weapons), rings are too small to read.
Gear.Slots = table.freeze({ "helmet", "armor", "gloves", "belt", "boots", "amulet" })
-- Budget (performance, 12 players): parts per slot and per full set at the top rarity
Gear.MAX_PIECES = 16
Gear.MAX_SET = 60
Gear.TOP_RARITY = "unique"
Gear.MODEL = "WornGear" -- model in the character that holds every piece
Gear.GEM_NEON_RANK = 3 -- Items.rank from which gems glow (rare)
Gear.Roles = table.freeze({
	main = true,
	dark = true,
	metal = true,
	accent = true,
	rune = true,
	trim = true,
	gem = true,
	glow = true,
})
Gear.Shapes = table.freeze({ block = true, wedge = true, ball = true, disc = true })
-- Rarity floor per role: rarity trim from magic, gems from rare, Neon edges from epic
Gear.RoleMin = table.freeze({ trim = "magic", gem = "rare", glow = "epic" } :: { [string]: string })

type Opt = { r: Vector3?, pad: Vector3?, min: string?, mirror: boolean? }

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function pc(part: string, shape: Shape, s: Vector3, p: Vector3, role: Role, o: Opt?): Piece
	return {
		part = part,
		shape = shape,
		s = s,
		p = p,
		role = role,
		r = o and o.r,
		pad = o and o.pad,
		min = o and o.min,
		mirror = o and o.mirror,
	}
end

-- Thin plates: a few hundredths of a stud of pad keep them visible on small avatars.
-- Rims (trim/glow/rune bands) sit INSIDE the height of the piece they frame and are only a hair
-- wider (<= 0.08 part sizes), so just a thin edge line shows, never a plate (spec "edge rims").
local THIN_Y = v(0, 0.04, 0)
local THIN_XZ = v(0.04, 0, 0.04)

-- Amulet (every class, colored by the class palette): two short chain bars and a small pendant high
-- on the chest. Chest plates of every class stay below y = 0.3 in front so the pendant shows.
local AMULET: { Piece } = {
	pc(
		"UpperTorso",
		"block",
		v(0.025, 0.2, 0.025),
		v(0.06, 0.45, -0.62),
		"metal",
		{ r = v(0, 0, -36), pad = v(0.04, 0, 0.04), mirror = true }
	),
	pc(
		"UpperTorso",
		"block",
		v(0.1, 0.12, 0.03),
		v(0, 0.33, -0.63),
		"metal",
		{ pad = v(0, 0, 0.08) }
	),
	pc(
		"UpperTorso",
		"block",
		v(0.14, 0.16, 0.02),
		v(0, 0.33, -0.61),
		"trim",
		{ pad = v(0, 0, 0.06) }
	),
	pc("UpperTorso", "ball", v(0.08, 0, 0), v(0, 0.33, -0.69), "gem"),
}

local CLASS: { [string]: { [string]: { Piece } } } = {
	-- Brix: great helm with cheek guards and a red crest, heavy steel plates over chainmail,
	-- big layered pauldrons, gauntlets, tassets and sabatons
	warrior = {
		helmet = {
			pc("Head", "block", v(1.2, 0.55, 1.2), v(0, 0.3, 0), "main"),
			pc(
				"Head",
				"block",
				v(0.12, 0.62, 0.95),
				v(0.56, -0.05, 0.05),
				"main",
				{ mirror = true }
			),
			pc("Head", "block", v(1.24, 0.12, 1.24), v(0, 0.08, 0), "dark"),
			pc("Head", "block", v(0.12, 0.42, 0.08), v(0, 0, -0.6), "dark"),
			pc("Head", "block", v(0.14, 0.34, 1), v(0, 0.72, 0.05), "accent"),
			pc("Head", "block", v(0.2, 0.08, 1.06), v(0, 0.57, 0.05), "trim"),
			pc("Head", "block", v(1.1, 0.3, 0.14), v(0, -0.2, 0.6), "main", { min = "rare" }),
			pc("Head", "ball", v(0.16, 0, 0), v(0, 0.32, -0.62), "gem"),
			pc("Head", "block", v(1.26, 0.03, 1.26), v(0, 0.155, 0), "glow", { pad = THIN_Y }),
			pc(
				"Head",
				"block",
				v(0.18, 0.03, 1.04),
				v(0, 0.9, 0.05),
				"glow",
				{ pad = THIN_Y, min = "unique" }
			),
		},
		armor = {
			pc("UpperTorso", "block", v(1.08, 0.94, 1.16), v(0, 0.02, 0), "dark"),
			pc(
				"UpperTorso",
				"block",
				v(0.94, 0.4, 0.12),
				v(0, 0.1, -0.6),
				"main",
				{ pad = v(0, 0, 0.06) }
			),
			pc(
				"UpperTorso",
				"block",
				v(0.82, 0.22, 0.1),
				v(0, -0.22, -0.59),
				"main",
				{ pad = v(0, 0, 0.06) }
			),
			pc("UpperTorso", "block", v(0.72, 0.12, 1.2), v(0, 0.5, 0), "metal"),
			pc("{S}UpperArm", "block", v(1.42, 0.48, 1.42), v(0.08, 0.34, 0), "main"),
			pc("{S}UpperArm", "block", v(1.32, 0.26, 1.32), v(0.1, 0.04, 0), "dark"),
			pc(
				"UpperTorso",
				"block",
				v(0.28, 0.28, 0.04),
				v(0, 0.1, -0.7),
				"trim",
				{ pad = v(0, 0, 0.06) }
			),
			pc(
				"{S}UpperArm",
				"block",
				v(1.46, 0.06, 1.46),
				v(0.08, 0.14, 0),
				"trim",
				{ pad = THIN_Y }
			),
			pc("UpperTorso", "ball", v(0.1, 0, 0), v(0, 0.1, -0.76), "gem"),
			pc(
				"{S}UpperArm",
				"block",
				v(1.12, 0.2, 1.12),
				v(0.08, 0.64, 0),
				"metal",
				{ min = "rare" }
			),
			pc(
				"UpperTorso",
				"block",
				v(0.96, 0.03, 0.03),
				v(0, -0.1, -0.68),
				"glow",
				{ pad = v(0, 0.04, 0.04) }
			),
		},
		gloves = {
			pc("{S}Hand", "block", v(1.22, 1.2, 1.22), v(0, 0, 0), "main"),
			pc("{S}LowerArm", "block", v(1.26, 0.42, 1.26), v(0, -0.28, 0), "dark"),
			pc("{S}LowerArm", "block", v(1.3, 0.06, 1.3), v(0, -0.16, 0), "trim", { pad = THIN_Y }),
			pc("{S}LowerArm", "ball", v(0.2, 0, 0), v(0.64, -0.28, 0), "gem"),
		},
		belt = {
			pc("LowerTorso", "block", v(1.1, 0.6, 1.2), v(0, 0.15, 0), "dark"),
			pc(
				"LowerTorso",
				"block",
				v(0.24, 0.55, 0.06),
				v(0, 0.15, -0.62),
				"metal",
				{ pad = v(0, 0, 0.08) }
			),
			pc("{S}UpperLeg", "block", v(1.14, 0.28, 1.16), v(0.02, 0.34, 0), "main"),
			pc("LowerTorso", "block", v(1.14, 0.12, 1.24), v(0, -0.08, 0), "trim"),
			pc("LowerTorso", "ball", v(0.1, 0, 0), v(0, 0.15, -0.7), "gem"),
			pc(
				"{S}UpperLeg",
				"block",
				v(1.18, 0.03, 1.2),
				v(0.02, 0.23, 0),
				"glow",
				{ pad = THIN_Y }
			),
		},
		boots = {
			pc("{S}Foot", "block", v(1.16, 1.25, 1.16), v(0, 0.06, -0.03), "main"),
			pc("{S}LowerLeg", "block", v(1.16, 0.55, 1.16), v(0, -0.2, 0), "dark"),
			pc("{S}LowerLeg", "block", v(1.2, 0.06, 1.2), v(0, 0, 0), "trim", { pad = THIN_Y }),
			pc(
				"{S}LowerLeg",
				"block",
				v(0.6, 0.26, 0.12),
				v(0, 0.38, -0.56),
				"main",
				{ pad = v(0, 0, 0.04), min = "rare" }
			),
		},
	},
	-- Fynn: green hood with a leather cowl, green tunic under an open leather vest, quiver strap,
	-- a guard on the bow shoulder, bracers and cuffed boots; a back pouch on the belt
	ranger = {
		helmet = {
			pc("Head", "block", v(1.18, 0.72, 0.95), v(0, 0.2, 0.12), "main"),
			pc(
				"Head",
				"wedge",
				v(1.18, 0.22, 0.4),
				v(0, 0.45, -0.38),
				"main",
				{ r = v(0, 180, 0) }
			),
			pc("Head", "block", v(1.3, 0.22, 1.15), v(0, -0.56, 0.06), "dark"),
			pc("Head", "block", v(0.45, 0.36, 0.3), v(0, 0.36, 0.66), "main", { r = v(-25, 0, 0) }),
			pc(
				"Head",
				"block",
				v(0.06, 0.6, 0.08),
				v(0.6, 0.12, -0.34),
				"trim",
				{ pad = THIN_XZ, mirror = true }
			),
			pc("Head", "ball", v(0.15, 0, 0), v(0, -0.56, -0.56), "gem"),
			pc(
				"Head",
				"block",
				v(0.07, 0.42, 0.2),
				v(0.64, 0.5, 0.25),
				"trim",
				{ r = v(0, 0, -20), pad = v(0.03, 0, 0), min = "rare" }
			),
			pc("Head", "block", v(1.34, 0.03, 1.19), v(0, -0.52, 0.06), "glow", { pad = THIN_Y }),
			pc(
				"Head",
				"block",
				v(0.06, 0.03, 0.9),
				v(0, 0.57, 0.12),
				"glow",
				{ pad = v(0.04, 0.04, 0), min = "unique" }
			),
		},
		armor = {
			pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "main"),
			pc(
				"UpperTorso",
				"block",
				v(0.32, 0.8, 0.06),
				v(0.3, -0.02, -0.57),
				"dark",
				{ pad = v(0, 0, 0.06), mirror = true }
			),
			pc("UpperTorso", "block", v(0.16, 1.3, 1.3), v(0, 0, 0), "accent", { r = v(0, 0, 38) }),
			pc(
				"UpperTorso",
				"block",
				v(0.13, 0.1, 0.04),
				v(0, 0, -0.68),
				"metal",
				{ r = v(0, 0, 38), pad = v(0, 0, 0.06) }
			),
			pc("LeftUpperArm", "block", v(1.16, 0.3, 1.16), v(0, 0.38, 0), "dark"),
			pc("LeftUpperArm", "block", v(0.96, 0.12, 0.96), v(0, 0.58, 0), "accent"),
			pc(
				"UpperTorso",
				"block",
				v(0.04, 0.8, 0.04),
				v(0.14, -0.02, -0.6),
				"trim",
				{ pad = v(0.04, 0, 0.08), mirror = true }
			),
			pc("LeftUpperArm", "block", v(1.2, 0.06, 1.2), v(0, 0.3, 0), "trim", { pad = THIN_Y }),
			pc("UpperTorso", "ball", v(0.08, 0, 0), v(0, 0, -0.74), "gem"),
			pc(
				"RightUpperArm",
				"block",
				v(1.18, 0.2, 1.18),
				v(0, 0.3, 0),
				"dark",
				{ min = "rare" }
			),
			pc("LeftUpperArm", "block", v(1, 0.03, 1), v(0, 0.58, 0), "glow", { pad = THIN_Y }),
		},
		gloves = {
			pc("{S}Hand", "block", v(1.16, 1.1, 1.16), v(0, 0.05, 0), "dark"),
			pc("{S}LowerArm", "block", v(1.2, 0.62, 1.2), v(0, -0.12, 0), "accent"),
			pc("{S}LowerArm", "block", v(1.24, 0.06, 1.24), v(0, 0.1, 0), "trim", { pad = THIN_Y }),
			pc("{S}LowerArm", "ball", v(0.18, 0, 0), v(0.62, -0.12, 0), "gem"),
		},
		belt = {
			pc("LowerTorso", "block", v(1.08, 0.55, 1.18), v(0, 0.12, 0), "dark"),
			pc(
				"LowerTorso",
				"block",
				v(0.2, 0.5, 0.05),
				v(0, 0.12, -0.6),
				"metal",
				{ pad = v(0, 0, 0.1) }
			),
			pc("LowerTorso", "block", v(0.26, 0.9, 0.22), v(0.3, -0.25, 0.66), "accent"),
			pc("LowerTorso", "block", v(1.12, 0.12, 1.22), v(0, -0.08, 0), "trim"),
			pc("LowerTorso", "ball", v(0.08, 0, 0), v(0, 0.12, -0.69), "gem"),
			pc(
				"LowerTorso",
				"block",
				v(0.12, 1, 0.16),
				v(-0.3, -0.3, 0.64),
				"dark",
				{ r = v(0, 0, 15), min = "rare" }
			),
		},
		boots = {
			pc("{S}Foot", "block", v(1.12, 1.2, 1.12), v(0, 0.05, -0.02), "dark"),
			pc("{S}LowerLeg", "block", v(1.08, 0.6, 1.08), v(0, -0.2, 0), "dark"),
			pc("{S}LowerLeg", "block", v(1.16, 0.18, 1.16), v(0, 0.1, 0), "accent"),
			pc("{S}LowerLeg", "block", v(1.2, 0.05, 1.2), v(0, 0.1, 0), "trim", { pad = THIN_Y }),
		},
	},
	-- Zap: pointed hat with a bent tip and a glowing band, robe with yoke, gold sash and a glowing
	-- rune seam, wide sleeves with glowing cuffs, sash belt with tails, curled shoes
	mage = {
		helmet = {
			pc("Head", "disc", v(0.1, 1.9, 0), v(0, 0.48, 0), "main"),
			pc("Head", "block", v(0.92, 0.5, 0.92), v(0, 0.75, 0.02), "main"),
			pc("Head", "block", v(0.96, 0.12, 0.96), v(0, 0.56, 0.02), "dark"),
			pc("Head", "block", v(0.98, 0.03, 0.98), v(0, 0.635, 0.02), "rune", { pad = THIN_Y }),
			pc("Head", "block", v(0.64, 0.44, 0.64), v(0, 1.15, 0.1), "main", { r = v(-10, 0, 0) }),
			pc("Head", "block", v(0.38, 0.38, 0.38), v(0, 1.5, 0.24), "main", { r = v(-22, 0, 0) }),
			pc("Head", "disc", v(0.04, 1.98, 0), v(0, 0.46, 0), "trim"),
			pc("Head", "ball", v(0.18, 0, 0), v(0, 0.56, -0.5), "gem"),
			pc("Head", "ball", v(0.16, 0, 0), v(0, 1.72, 0.36), "gem"),
			pc("Head", "block", v(0.95, 0.03, 0.95), v(0, 0.85, 0.02), "glow", { pad = THIN_Y }),
		},
		armor = {
			pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "main"),
			pc("LowerTorso", "block", v(1.1, 2.4, 1.14), v(0, -0.7, 0), "dark"),
			pc("UpperTorso", "block", v(1.14, 0.2, 1.2), v(0, 0.44, 0), "dark"),
			pc(
				"UpperTorso",
				"block",
				v(0.16, 1.3, 1.18),
				v(0, 0, 0),
				"metal",
				{ r = v(0, 0, -35) }
			),
			pc(
				"UpperTorso",
				"block",
				v(0.05, 0.6, 0.03),
				v(0, -0.1, -0.58),
				"rune",
				{ pad = v(0.03, 0, 0.05) }
			),
			pc("{S}UpperArm", "block", v(1.28, 0.38, 1.28), v(0.04, 0.36, 0), "main"),
			pc("UpperTorso", "block", v(1.18, 0.06, 1.24), v(0, 0.38, 0), "trim", { pad = THIN_Y }),
			pc(
				"{S}UpperArm",
				"block",
				v(1.32, 0.06, 1.32),
				v(0.04, 0.22, 0),
				"trim",
				{ pad = THIN_Y }
			),
			pc("UpperTorso", "ball", v(0.12, 0, 0), v(0, 0.12, -0.64), "gem"),
			pc(
				"LowerTorso",
				"block",
				v(0.3, 2.1, 0.06),
				v(0, -0.75, -0.59),
				"metal",
				{ pad = v(0, 0, 0.06), min = "rare" }
			),
			pc(
				"{S}UpperArm",
				"block",
				v(1.32, 0.03, 1.32),
				v(0.04, 0.5, 0),
				"glow",
				{ pad = THIN_Y }
			),
		},
		gloves = {
			pc("{S}Hand", "block", v(1.14, 1.1, 1.14), v(0, 0.05, 0), "dark"),
			pc("{S}LowerArm", "block", v(1.36, 0.48, 1.36), v(0, -0.24, 0), "main"),
			pc("{S}LowerArm", "block", v(1.4, 0.03, 1.4), v(0, -0.44, 0), "rune", { pad = THIN_Y }),
			pc("{S}LowerArm", "block", v(1.4, 0.06, 1.4), v(0, -0.08, 0), "trim", { pad = THIN_Y }),
		},
		belt = {
			pc("LowerTorso", "block", v(1.16, 0.6, 1.22), v(0, 0.15, 0), "main"),
			pc(
				"LowerTorso",
				"block",
				v(0.22, 0.55, 0.05),
				v(0, 0.15, -0.62),
				"metal",
				{ pad = v(0, 0, 0.08) }
			),
			pc(
				"LowerTorso",
				"block",
				v(0.12, 1.6, 0.04),
				v(0.28, -0.55, -0.6),
				"main",
				{ r = v(0, 0, 6), pad = v(0, 0, 0.06) }
			),
			pc("LowerTorso", "block", v(1.2, 0.1, 1.26), v(0, -0.08, 0), "trim"),
			pc("LowerTorso", "ball", v(0.1, 0, 0), v(0, 0.15, -0.7), "gem"),
			pc(
				"LowerTorso",
				"block",
				v(0.12, 1.3, 0.04),
				v(0.4, -0.5, -0.59),
				"main",
				{ r = v(0, 0, -6), pad = v(0, 0, 0.06), min = "rare" }
			),
		},
		boots = {
			pc("{S}Foot", "block", v(1.1, 1.2, 1.14), v(0, 0.05, -0.04), "dark"),
			pc(
				"{S}Foot",
				"block",
				v(0.5, 0.9, 0.32),
				v(0, 0.3, -0.62),
				"dark",
				{ r = v(25, 0, 0) }
			),
			pc("{S}LowerLeg", "block", v(1.12, 0.42, 1.12), v(0, -0.3, 0), "main"),
			pc(
				"{S}LowerLeg",
				"block",
				v(1.16, 0.06, 1.16),
				v(0, -0.14, 0),
				"trim",
				{ pad = THIN_Y }
			),
		},
	},
	-- Mora: red mushroom cap with cream spots and gills, moss robe with a bark collar and chest
	-- plate, mushroom-cap shoulder pads, bark gloves and boots with tiny mushrooms
	mushroom = {
		helmet = {
			pc("Head", "disc", v(0.3, 1.8, 0), v(0, 0.46, 0), "main"),
			pc("Head", "disc", v(0.28, 1.3, 0), v(0, 0.7, 0), "main"),
			pc("Head", "ball", v(0.9, 0, 0), v(0, 0.78, 0), "main"),
			pc("Head", "disc", v(0.05, 1.72, 0), v(0, 0.28, 0), "accent"),
			pc("Head", "ball", v(0.24, 0, 0), v(0.4, 0.82, -0.28), "accent"),
			pc("Head", "ball", v(0.2, 0, 0), v(-0.32, 0.86, 0.3), "accent"),
			pc("Head", "disc", v(0.08, 1.86, 0), v(0, 0.36, 0), "trim"),
			pc("Head", "ball", v(0.2, 0, 0), v(0, 1.28, 0), "gem"),
			pc("Head", "ball", v(0.18, 0, 0), v(0.12, 1, 0.4), "accent", { min = "rare" }),
			pc("Head", "disc", v(0.03, 1.84, 0), v(0, 0.55, 0), "glow"),
			pc("Head", "disc", v(0.03, 1.34, 0), v(0, 0.78, 0), "glow", { min = "unique" }),
		},
		armor = {
			pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "dark"),
			pc("UpperTorso", "block", v(1.2, 0.28, 1.2), v(0, 0.42, 0), "metal"),
			pc("{S}UpperArm", "disc", v(0.22, 1.5, 0), v(0.06, 0.44, 0), "main"),
			pc("{S}UpperArm", "ball", v(1, 0, 0), v(0.06, 0.52, 0), "main"),
			pc("{S}UpperArm", "ball", v(0.26, 0, 0), v(0.3, 0.86, -0.14), "accent"),
			pc(
				"UpperTorso",
				"block",
				v(0.46, 0.36, 0.06),
				v(0, -0.12, -0.58),
				"metal",
				{ pad = v(0, 0, 0.06) }
			),
			pc("{S}UpperArm", "disc", v(0.06, 1.58, 0), v(0.06, 0.36, 0), "trim"),
			pc("UpperTorso", "ball", v(0.12, 0, 0), v(0, -0.12, -0.66), "gem"),
			pc(
				"{S}UpperArm",
				"disc",
				v(0.05, 1.36, 0),
				v(0.06, 0.32, 0),
				"accent",
				{ min = "rare" }
			),
			pc("UpperTorso", "ball", v(0.08, 0, 0), v(0.3, 0.1, -0.58), "glow"),
			pc("UpperTorso", "ball", v(0.08, 0, 0), v(-0.32, -0.26, -0.58), "glow"),
		},
		gloves = {
			pc("{S}Hand", "block", v(1.18, 1.15, 1.18), v(0, 0, 0), "metal"),
			pc("{S}LowerArm", "block", v(1.22, 0.36, 1.22), v(0, -0.3, 0), "dark"),
			pc("{S}LowerArm", "ball", v(0.32, 0, 0), v(0.56, -0.24, 0), "main"),
			pc(
				"{S}LowerArm",
				"block",
				v(1.26, 0.06, 1.26),
				v(0, -0.2, 0),
				"trim",
				{ pad = THIN_Y }
			),
		},
		belt = {
			pc("LowerTorso", "block", v(1.08, 0.5, 1.18), v(0, 0.12, 0), "metal"),
			pc(
				"LowerTorso",
				"block",
				v(0.16, 0.6, 0.06),
				v(0, 0.12, -0.62),
				"accent",
				{ pad = v(0, 0, 0.08) }
			),
			pc("LowerTorso", "ball", v(0.2, 0, 0), v(0.5, -0.2, 0.4), "main"),
			pc("LowerTorso", "block", v(1.12, 0.1, 1.22), v(0, -0.06, 0), "trim"),
			pc("LowerTorso", "ball", v(0.1, 0, 0), v(0, 0.12, -0.7), "gem"),
			pc(
				"LowerTorso",
				"ball",
				v(0.16, 0, 0),
				v(-0.45, -0.25, 0.42),
				"main",
				{ min = "rare" }
			),
		},
		boots = {
			pc("{S}Foot", "block", v(1.14, 1.2, 1.14), v(0, 0.05, -0.02), "metal"),
			pc("{S}LowerLeg", "block", v(1.14, 0.5, 1.14), v(0, -0.25, 0), "dark"),
			pc(
				"{S}LowerLeg",
				"block",
				v(1.18, 0.06, 1.18),
				v(0, -0.08, 0),
				"trim",
				{ pad = THIN_Y }
			),
			pc("{S}LowerLeg", "ball", v(0.28, 0, 0), v(0.54, -0.2, 0), "main", { min = "rare" }),
		},
	},
}

-- Class palettes: main/dark as before, metal for buckles/collars/sashes, accent for the class's
-- signature color (Knight red cloth, Ranger tan leather, Mage cyan runes, Shaman cream spots)
local PALETTE: { [string]: Palette } = {
	warrior = {
		main = Color3.fromHex("#B8C0CE"),
		dark = Color3.fromHex("#5A5F70"),
		metal = Color3.fromHex("#E8B04A"),
		accent = Color3.fromHex("#B8332E"),
	},
	ranger = {
		main = Color3.fromHex("#3F8A3A"),
		dark = Color3.fromHex("#6B4526"),
		metal = Color3.fromHex("#C9A25A"),
		accent = Color3.fromHex("#8A5A34"),
	},
	mage = {
		main = Color3.fromHex("#4A55C8"),
		dark = Color3.fromHex("#2C2F7A"),
		metal = Color3.fromHex("#E8B04A"),
		accent = Color3.fromHex("#4FD8F5"),
	},
	mushroom = {
		main = Color3.fromHex("#D8442E"),
		dark = Color3.fromHex("#4E7A2A"),
		metal = Color3.fromHex("#7A5230"),
		accent = Color3.fromHex("#F2E6C8"),
	},
}

local NAME: { [string]: string } = {
	warrior = "Knight's Steel",
	ranger = "Ranger's Leather",
	mage = "Spark Robes",
	mushroom = "Spore Garb",
}

local styles: { [string]: Style } = {}
for id, pieces in CLASS do
	local all = table.clone(pieces)
	all.amulet = all.amulet or AMULET
	styles[id] = table.freeze({
		id = id,
		name = NAME[id],
		palette = table.freeze(PALETTE[id]),
		pieces = table.freeze(all),
	})
end
-- Gear skins (cosmetics) are added here as further styles; see docs/specs/GEAR-COSMETICS.md
Gear.Styles = table.freeze(styles)

-- The look a slot shows: a valid skin for that slot, else the hero's class look
function Gear.style(class: string, slot: string, skin: string?): Style?
	local s = if skin then styles[skin] else nil
	if s and s.pieces[slot] then
		return s
	end
	return styles[class]
end

-- Lowest item rank (Items.rank) that shows this piece: its role's floor or its own `min`
function Gear.minRank(piece: Piece): number
	local floor = Gear.RoleMin[piece.role]
	local own = if piece.min then Items.rank(piece.min) else 1
	return math.max(1, own, if floor then Items.rank(floor) else 1)
end

-- Does an item of this rarity show the piece? Unknown rarities count as normal.
function Gear.shows(piece: Piece, rarity: string): boolean
	return math.max(1, Items.rank(rarity)) >= Gear.minRank(piece)
end

local function copy(piece: Piece, part: string, mirror: number): Piece
	local r = piece.r
	return {
		part = part,
		shape = piece.shape,
		s = piece.s,
		p = Vector3.new(piece.p.X * mirror, piece.p.Y, piece.p.Z),
		r = if r and mirror < 0 then Vector3.new(r.X, -r.Y, -r.Z) else r,
		pad = piece.pad,
		role = piece.role,
		min = piece.min,
	}
end

-- Pieces of one slot with "{S}" expanded into a Left and a Right piece and `mirror` into two
-- copies (X mirrored). With a rarity only the pieces that rarity shows (Gear.shows).
function Gear.pieces(style: Style, slot: string, rarity: string?): { Piece }
	local out: { Piece } = {}
	local list: { Piece } = style.pieces[slot] or {}
	for _, piece in list do
		if rarity and not Gear.shows(piece, rarity) then
			continue
		end
		if string.find(piece.part, "{S}", 1, true) then
			table.insert(out, copy(piece, (string.gsub(piece.part, "{S}", "Left")), -1))
			table.insert(out, copy(piece, (string.gsub(piece.part, "{S}", "Right")), 1))
		elseif piece.mirror then
			table.insert(out, copy(piece, piece.part, 1))
			table.insert(out, copy(piece, piece.part, -1))
		else
			table.insert(out, piece)
		end
	end
	return out
end

-- Parts of a full set (every visible slot) at one rarity: the performance budget
function Gear.count(style: Style, rarity: string): number
	local n = 0
	for _, slot in Gear.Slots do
		n += #Gear.pieces(style, slot, rarity)
	end
	return n
end

-- Color of a piece: palette for main/dark/metal/accent (rune = glowing accent), rarity color
-- for trim/gem/glow
function Gear.color(style: Style, role: Role, rarity: string): Color3
	local palette = style.palette
	if role == "main" then
		return palette.main
	elseif role == "dark" then
		return palette.dark
	elseif role == "metal" then
		return palette.metal
	elseif role == "accent" or role == "rune" then
		return palette.accent
	end
	return Theme.Rarity[rarity] or Theme.Rarity.normal
end

-- Surface of a piece: glow (Neon) for rune/glow and gems from GEM_NEON_RANK, glass for lower
-- gems, else the stud look (Studs.applyAllFaces)
function Gear.finish(role: Role, rarity: string): Finish
	if role == "rune" or role == "glow" then
		return "neon"
	elseif role == "gem" then
		return if Items.rank(rarity) >= Gear.GEM_NEON_RANK then "neon" else "glass"
	end
	return "studs"
end

-- Size and offset of a piece on a body part of this size
function Gear.place(piece: Piece, partSize: Vector3): (Vector3, CFrame)
	local size: Vector3
	if piece.shape == "ball" then
		size = Vector3.one * (piece.s.X * partSize.X)
	elseif piece.shape == "disc" then
		local d = piece.s.Y * partSize.X
		size = Vector3.new(piece.s.X * partSize.Y, d, d) -- cylinder axis = X, turned upright
	else
		size = partSize * piece.s
	end
	size += piece.pad or Vector3.zero
	local r = piece.r or Vector3.zero
	local cf = CFrame.new(partSize * piece.p)
		* CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	if piece.shape == "disc" then
		cf *= CFrame.Angles(0, 0, math.rad(90))
	end
	return size, cf
end

-- What the worn gear of a hero looks like, as one string: Systems/Gear rebuilds only on change
function Gear.signature(
	class: string,
	equipped: { [string]: any }, -- slot → Items.Item
	skins: { [string]: string }?
): string
	local parts = { class }
	for _, slot in Gear.Slots do
		local item = equipped[slot]
		local skin = skins and skins[slot] or ""
		table.insert(parts, if item then `{slot}:{item.rarity}:{skin}` else "-")
	end
	return table.concat(parts, "|")
end

for id, style in styles do
	for _, slot in Gear.Slots do
		assert(style.pieces[slot], `gear look {id}: slot {slot} missing`)
		assert(
			#Gear.pieces(style, slot, Gear.TOP_RARITY) <= Gear.MAX_PIECES,
			`gear look {id}: {slot} too many pieces`
		)
	end
	assert(Gear.count(style, Gear.TOP_RARITY) <= Gear.MAX_SET, `gear look {id}: set over budget`)
end

return table.freeze(Gear)
