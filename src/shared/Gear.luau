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
Gear.MAX_PIECES = 22
Gear.MAX_SET = 72
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

-- Rivets, studs and buttons: small domes half sunk into the face of a plate (metal by default),
-- detail every rarity shows. size = ball diameter in part sizes; mirror = a pair at -X.
local function rivet(part: string, p: Vector3, size: number, role: Role, mirror: boolean?): Piece
	return pc(part, "ball", v(size, 0, 0), p, role, { mirror = mirror })
end

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
			rivet("Head", v(0.36, 0.08, -0.62), 0.1, "metal", true),
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
			rivet("UpperTorso", v(0.4, 0.22, -0.69), 0.06, "metal", true),
			rivet("UpperTorso", v(0.34, -0.22, -0.67), 0.06, "metal", true),
			rivet("{S}UpperArm", v(0.08, 0.34, -0.71), 0.12, "metal"),
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
			rivet("LowerTorso", v(0.3, 0.15, -0.6), 0.06, "metal", true),
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
			rivet("LowerTorso", v(0.3, 0.12, -0.59), 0.06, "metal", true),
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
			rivet("{S}LowerLeg", v(0, 0.1, -0.58), 0.16, "metal"),
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
			rivet("UpperTorso", v(0, -0.15, -0.57), 0.06, "metal"),
			rivet("UpperTorso", v(0, -0.35, -0.57), 0.06, "metal"),
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
			rivet("LowerTorso", v(0.3, 0.15, -0.61), 0.06, "metal", true),
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
			rivet("LowerTorso", v(0.3, 0.12, -0.59), 0.07, "accent", true),
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
Gear.Styles = table.freeze(styles)

-- Gear skins (cosmetic looks, docs/specs/GEAR-COSMETICS.md; catalog, prices and sources:
-- Shared/GearSkins). A skin is a style for ONE slot with its own palette. Trim, gems and glow
-- edges still take the item's rarity, so the body keeps telling how strong the gear is.
local SKIN_LOOKS: { [string]: { name: string, slot: string, colors: { string }, pieces: { Piece } } } =
	{}

local function skinLook(
	id: string,
	name: string,
	slot: string,
	colors: { string },
	pieces: { Piece }
)
	SKIN_LOOKS[id] = { name = name, slot = slot, colors = colors, pieces = pieces }
end

-- Chain bars of a pendant (rotated, so they never count as a chest plate)
local function chain(): { Piece }
	return {
		pc(
			"UpperTorso",
			"block",
			v(0.025, 0.2, 0.025),
			v(0.06, 0.45, -0.62),
			"metal",
			{ r = v(0, 0, -36), pad = v(0.04, 0, 0.04), mirror = true }
		),
	}
end

local function with(list: { Piece }, more: { Piece }): { Piece }
	local out = table.clone(list)
	for _, p in more do
		table.insert(out, p)
	end
	return out
end

-- Palette order: main, dark, metal, accent
-- ── Free skins (play milestones) ──────────────────────────────────────────────────────────
skinLook(
	"lumen_circlet",
	"Lumen Circlet",
	"helmet",
	{ "#F4E6B8", "#8A6A2A", "#E8C060", "#9FF0FF" },
	{
		pc("Head", "block", v(1.12, 0.14, 1.12), v(0, 0.3, 0), "metal"),
		pc("Head", "block", v(0.3, 0.22, 0.06), v(0, 0.34, -0.58), "main", { pad = v(0, 0, 0.04) }),
		pc(
			"Head",
			"block",
			v(0.06, 0.32, 0.4),
			v(0.58, 0.42, 0.1),
			"main",
			{ r = v(0, 0, -15), mirror = true }
		),
		pc("Head", "block", v(0.2, 0.04, 0.04), v(0, 0.49, -0.6), "rune", { pad = THIN_XZ }),
		pc("Head", "block", v(1.16, 0.04, 1.16), v(0, 0.3, 0), "trim", { pad = THIN_Y }),
		pc("Head", "ball", v(0.14, 0, 0), v(0, 0.34, -0.64), "gem"),
		pc(
			"Head",
			"block",
			v(0.04, 0.04, 0.36),
			v(0.64, 0.6, 0.1),
			"glow",
			{ pad = THIN_XZ, mirror = true }
		),
	}
)
skinLook(
	"conqueror_crown",
	"Conqueror's Crown",
	"helmet",
	{ "#F2C14E", "#7A1E2A", "#FFE08A", "#B8332E" },
	{
		pc("Head", "block", v(1.1, 0.22, 1.1), v(0, 0.62, 0), "main"),
		pc("Head", "block", v(0.9, 0.14, 0.9), v(0, 0.76, 0), "accent"),
		pc("Head", "block", v(0.16, 0.28, 0.08), v(0, 0.86, -0.52), "metal"),
		pc(
			"Head",
			"block",
			v(0.14, 0.22, 0.08),
			v(0.38, 0.83, -0.4),
			"metal",
			{ r = v(0, 40, 0), mirror = true }
		),
		pc(
			"Head",
			"block",
			v(0.14, 0.22, 0.08),
			v(0.4, 0.83, 0.38),
			"metal",
			{ r = v(0, -40, 0), mirror = true }
		),
		pc("Head", "block", v(1.14, 0.05, 1.14), v(0, 0.56, 0), "trim", { pad = THIN_Y }),
		pc("Head", "ball", v(0.12, 0, 0), v(0, 0.62, -0.57), "gem"),
		pc("Head", "ball", v(0.08, 0, 0), v(0, 1.02, -0.52), "glow"),
	}
)
skinLook(
	"rift_walker_boots",
	"Rift Walker Boots",
	"boots",
	{ "#5A2A8A", "#1E1030", "#C8D2E8", "#58E1F0" },
	{
		pc("{S}Foot", "block", v(1.16, 1.25, 1.16), v(0, 0.06, -0.03), "main"),
		pc("{S}LowerLeg", "block", v(1.18, 0.6, 1.18), v(0, -0.2, 0), "dark"),
		pc(
			"{S}LowerLeg",
			"block",
			v(0.04, 0.46, 0.04),
			v(0, -0.2, -0.6),
			"rune",
			{ pad = THIN_XZ }
		),
		pc("{S}LowerLeg", "block", v(1.22, 0.05, 1.22), v(0, 0.06, 0), "trim", { pad = THIN_Y }),
		pc("{S}LowerLeg", "ball", v(0.16, 0, 0), v(0, 0.12, -0.62), "gem"),
		pc("{S}Foot", "block", v(1.0, 0.03, 0.04), v(0, -0.45, -0.6), "glow", { pad = THIN_Y }),
	}
)
skinLook(
	"daily_loyalist_belt",
	"Daily Loyalist Belt",
	"belt",
	{ "#8A2A2A", "#4A1A1A", "#E8B04A", "#F2E6C8" },
	{
		pc("LowerTorso", "block", v(1.1, 0.32, 1.2), v(0, 0.3, 0), "main"),
		pc(
			"LowerTorso",
			"block",
			v(0.3, 0.3, 0.06),
			v(0, 0.3, -0.62),
			"metal",
			{ pad = v(0, 0, 0.06) }
		),
		pc("{S}UpperLeg", "block", v(0.4, 0.3, 0.3), v(0.3, 0.32, -0.4), "accent"),
		pc("LowerTorso", "block", v(1.14, 0.05, 1.24), v(0, 0.3, 0), "trim", { pad = THIN_Y }),
		pc("LowerTorso", "ball", v(0.1, 0, 0), v(0, 0.3, -0.68), "gem"),
		pc("LowerTorso", "block", v(1.0, 0.03, 0.04), v(0, 0.15, -0.62), "glow", { pad = THIN_Y }),
	}
)
skinLook(
	"journey_gauntlets",
	"Journey Gauntlets",
	"gloves",
	{ "#2A4A8A", "#1A2238", "#E8B04A", "#FFE08A" },
	{
		pc("{S}Hand", "block", v(1.22, 1.2, 1.22), v(0, 0, 0), "main"),
		pc("{S}LowerArm", "block", v(1.32, 0.55, 1.32), v(0, -0.25, 0), "metal"),
		pc("{S}LowerArm", "ball", v(0.2, 0, 0), v(0, -0.25, -0.68), "rune"),
		pc("{S}LowerArm", "block", v(1.36, 0.05, 1.36), v(0, -0.05, 0), "trim", { pad = THIN_Y }),
		pc("{S}Hand", "ball", v(0.16, 0, 0), v(0, 0.1, 0.62), "gem"),
		pc("{S}Hand", "block", v(0.04, 0.04, 1.0), v(0.62, 0, 0), "glow", { pad = THIN_XZ }),
	}
)
-- ── Beta Season "Beacon Dawn": warm gold plates, beacon-teal glow ──────────────────────────
local BEACON = { "#E8B04A", "#6A4A22", "#FFF1B8", "#2EC4B6" }
skinLook("beacon_dawn_helm", "Beacon Dawn Helm", "helmet", BEACON, {
	pc("Head", "block", v(1.18, 0.5, 1.18), v(0, 0.32, 0), "main"),
	pc("Head", "block", v(1.26, 0.1, 1.26), v(0, 0.1, 0), "dark"),
	pc("Head", "block", v(0.22, 0.36, 0.22), v(0, 0.74, 0), "metal"),
	pc("Head", "ball", v(0.22, 0, 0), v(0, 0.98, 0), "rune"),
	pc("Head", "block", v(1.22, 0.05, 1.22), v(0, 0.15, 0), "trim", { pad = THIN_Y }),
	pc("Head", "ball", v(0.14, 0, 0), v(0, 0.3, -0.62), "gem"),
	pc("Head", "block", v(0.3, 0.04, 0.3), v(0, 0.88, 0), "glow", { pad = THIN_Y }),
})
skinLook("beacon_mantle", "Beacon Mantle", "armor", BEACON, {
	pc("UpperTorso", "block", v(1.08, 0.92, 1.14), v(0, 0.02, 0), "main"),
	pc(
		"UpperTorso",
		"block",
		v(0.4, 0.76, 0.06),
		v(0, -0.06, -0.58),
		"accent",
		{ pad = v(0, 0, 0.06) }
	),
	pc("{S}UpperArm", "block", v(1.4, 0.36, 1.4), v(0.08, 0.36, 0), "metal"),
	pc("UpperTorso", "block", v(0.74, 0.12, 1.2), v(0, 0.48, 0), "dark"),
	pc(
		"UpperTorso",
		"block",
		v(0.12, 0.2, 0.04),
		v(0, -0.02, -0.63),
		"rune",
		{ pad = v(0, 0, 0.06) }
	),
	pc(
		"UpperTorso",
		"block",
		v(0.04, 0.76, 0.04),
		v(0.21, -0.06, -0.6),
		"trim",
		{ pad = v(0.04, 0, 0.08), mirror = true }
	),
	pc("UpperTorso", "ball", v(0.1, 0, 0), v(0, -0.32, -0.64), "gem"),
	pc("{S}UpperArm", "block", v(1.44, 0.03, 0.04), v(0.08, 0.2, -0.68), "glow", { pad = THIN_Y }),
})
skinLook("beacon_dawn_greaves", "Beacon Dawn Greaves", "boots", BEACON, {
	pc("{S}Foot", "block", v(1.16, 1.25, 1.16), v(0, 0.06, -0.03), "main"),
	pc("{S}LowerLeg", "block", v(1.18, 0.62, 1.18), v(0, -0.19, 0), "dark"),
	pc(
		"{S}LowerLeg",
		"block",
		v(0.5, 0.3, 0.12),
		v(0, 0.36, -0.56),
		"metal",
		{ pad = v(0, 0, 0.04) }
	),
	pc("{S}LowerLeg", "ball", v(0.16, 0, 0), v(0, 0.36, -0.66), "rune"),
	pc("{S}LowerLeg", "block", v(1.22, 0.05, 1.22), v(0, 0.06, 0), "trim", { pad = THIN_Y }),
	pc("{S}Foot", "block", v(1.0, 0.03, 0.04), v(0, -0.45, -0.6), "glow", { pad = THIN_Y }),
})
skinLook("beacon_dawn_gauntlets", "Beacon Dawn Gauntlets", "gloves", BEACON, {
	pc("{S}Hand", "block", v(1.22, 1.2, 1.22), v(0, 0, 0), "main"),
	pc("{S}LowerArm", "block", v(1.3, 0.5, 1.3), v(0, -0.25, 0), "accent"),
	pc("{S}Hand", "ball", v(0.2, 0, 0), v(0, 0.1, 0.62), "rune"),
	pc("{S}LowerArm", "block", v(1.34, 0.05, 1.34), v(0, -0.04, 0), "trim", { pad = THIN_Y }),
	pc("{S}LowerArm", "ball", v(0.16, 0, 0), v(0, -0.25, -0.66), "gem"),
	pc("{S}Hand", "block", v(0.04, 0.04, 1.0), v(0.62, 0, 0), "glow", { pad = THIN_XZ }),
})
skinLook("beacon_dawn_sash", "Beacon Dawn Sash", "belt", BEACON, {
	pc("LowerTorso", "block", v(1.1, 0.34, 1.2), v(0, 0.3, 0), "main"),
	pc(
		"LowerTorso",
		"block",
		v(0.22, 0.6, 0.06),
		v(0.3, -0.1, -0.6),
		"accent",
		{ pad = v(0, 0, 0.04) }
	),
	pc(
		"LowerTorso",
		"block",
		v(0.26, 0.26, 0.06),
		v(0, 0.3, -0.62),
		"metal",
		{ pad = v(0, 0, 0.06) }
	),
	pc("LowerTorso", "block", v(1.14, 0.05, 1.24), v(0, 0.3, 0), "trim", { pad = THIN_Y }),
	pc("LowerTorso", "ball", v(0.1, 0, 0), v(0, 0.3, -0.68), "gem"),
	pc("LowerTorso", "block", v(0.04, 0.5, 0.04), v(0.3, -0.12, -0.66), "glow", { pad = THIN_XZ }),
})
skinLook(
	"beacon_dawn_lantern",
	"Beacon Dawn Lantern",
	"amulet",
	BEACON,
	with(chain(), {
		pc(
			"UpperTorso",
			"block",
			v(0.1, 0.14, 0.08),
			v(0, 0.32, -0.63),
			"metal",
			{ pad = v(0, 0, 0.04) }
		),
		pc("UpperTorso", "ball", v(0.07, 0, 0), v(0, 0.32, -0.69), "rune"),
		pc(
			"UpperTorso",
			"block",
			v(0.14, 0.03, 0.08),
			v(0, 0.41, -0.63),
			"trim",
			{ pad = v(0, 0.03, 0.04) }
		),
		pc("UpperTorso", "ball", v(0.05, 0, 0), v(0, 0.22, -0.66), "gem"),
	})
)
skinLook(
	"beta_pioneer_pendant",
	"Beta Pioneer Pendant",
	"amulet",
	{ "#8A5A34", "#4A3020", "#C9A25A", "#2EC4B6" },
	with(chain(), {
		pc(
			"UpperTorso",
			"block",
			v(0.16, 0.16, 0.03),
			v(0, 0.33, -0.62),
			"metal",
			{ pad = v(0, 0, 0.06) }
		),
		pc(
			"UpperTorso",
			"block",
			v(0.02, 0.12, 0.02),
			v(0, 0.33, -0.66),
			"rune",
			{ pad = v(0.03, 0, 0.04) }
		),
		pc(
			"UpperTorso",
			"block",
			v(0.2, 0.2, 0.02),
			v(0, 0.33, -0.61),
			"trim",
			{ pad = v(0, 0, 0.05) }
		),
		pc("UpperTorso", "ball", v(0.05, 0, 0), v(0, 0.44, -0.66), "gem"),
	})
)
-- ── Shop skins (class-free) ────────────────────────────────────────────────────────────────
skinLook("pumpkin_helm", "Pumpkin Helm", "helmet", { "#E8762A", "#8A3A12", "#4E7A2A", "#FFC24A" }, {
	pc("Head", "block", v(1.3, 1.1, 1.3), v(0, 0.1, 0), "main"),
	pc(
		"Head",
		"block",
		v(0.04, 1.0, 0.08),
		v(0.66, 0.1, 0),
		"dark",
		{ pad = THIN_XZ, mirror = true }
	),
	pc(
		"Head",
		"block",
		v(0.2, 0.16, 0.04),
		v(0.25, 0.18, -0.66),
		"rune",
		{ pad = THIN_XZ, mirror = true }
	),
	pc("Head", "block", v(0.5, 0.1, 0.04), v(0, -0.2, -0.66), "rune", { pad = THIN_XZ }),
	pc("Head", "block", v(0.16, 0.3, 0.16), v(0, 0.8, 0), "metal"),
	pc("Head", "block", v(0.3, 0.04, 0.2), v(0.16, 0.72, 0.1), "metal", { r = v(0, 0, 15) }),
	pc("Head", "block", v(0.2, 0.06, 0.2), v(0, 0.7, 0), "trim", { pad = THIN_Y }),
	pc("Head", "ball", v(0.12, 0, 0), v(0, 0.98, 0), "gem"),
	pc("Head", "block", v(0.6, 0.03, 0.03), v(0, 0.36, -0.66), "glow", { pad = THIN_XZ }),
})
skinLook(
	"crystal_plate",
	"Crystal Plate",
	"armor",
	{ "#BFE8F5", "#3A6A8A", "#E6F2FA", "#7FD4FF" },
	{
		pc("UpperTorso", "block", v(1.08, 0.92, 1.14), v(0, 0.02, 0), "dark"),
		pc(
			"UpperTorso",
			"block",
			v(0.9, 0.42, 0.12),
			v(0, 0.1, -0.6),
			"main",
			{ pad = v(0, 0, 0.06) }
		),
		pc("{S}UpperArm", "block", v(1.3, 0.4, 1.3), v(0.08, 0.34, 0), "main"),
		pc("{S}UpperArm", "wedge", v(0.3, 0.5, 0.3), v(0.1, 0.78, 0), "accent"),
		pc("UpperTorso", "block", v(0.7, 0.1, 1.18), v(0, 0.5, 0), "metal"),
		pc(
			"UpperTorso",
			"block",
			v(0.9, 0.04, 0.04),
			v(0, -0.12, -0.66),
			"trim",
			{ pad = v(0, 0, 0.04) }
		),
		pc("UpperTorso", "ball", v(0.14, 0, 0), v(0, 0.12, -0.7), "gem"),
		pc(
			"{S}UpperArm",
			"block",
			v(1.34, 0.03, 0.04),
			v(0.08, 0.15, -0.66),
			"glow",
			{ pad = THIN_Y }
		),
	}
)
skinLook(
	"ember_gauntlets",
	"Ember Gauntlets",
	"gloves",
	{ "#3A2A2A", "#1E1414", "#C07E22", "#FF7A2A" },
	{
		pc("{S}Hand", "block", v(1.22, 1.2, 1.22), v(0, 0, 0), "main"),
		pc("{S}LowerArm", "block", v(1.3, 0.5, 1.3), v(0, -0.25, 0), "dark"),
		pc(
			"{S}LowerArm",
			"block",
			v(0.04, 0.3, 0.04),
			v(0.66, -0.25, 0),
			"rune",
			{ pad = THIN_XZ }
		),
		pc("{S}LowerArm", "block", v(1.34, 0.05, 1.34), v(0, -0.04, 0), "trim", { pad = THIN_Y }),
		pc("{S}LowerArm", "ball", v(0.18, 0, 0), v(0, -0.25, -0.66), "gem"),
		pc("{S}Hand", "block", v(0.04, 0.04, 1.0), v(0.62, 0, 0), "glow", { pad = THIN_XZ }),
	}
)
skinLook(
	"cloud_striders",
	"Cloud Striders Deluxe",
	"boots",
	{ "#F4F6FA", "#B8C8E0", "#E8B04A", "#9FD8FF" },
	{
		pc("{S}Foot", "block", v(1.16, 1.25, 1.16), v(0, 0.06, -0.03), "main"),
		pc("{S}LowerLeg", "ball", v(0.8, 0, 0), v(0.25, -0.35, 0.1), "main"),
		pc("{S}LowerLeg", "ball", v(0.7, 0, 0), v(-0.25, -0.3, -0.1), "dark"),
		pc("{S}Foot", "block", v(0.04, 0.04, 0.9), v(0, -0.45, 0), "trim", { pad = THIN_XZ }),
		pc("{S}Foot", "ball", v(0.14, 0, 0), v(0, 0.2, -0.62), "gem"),
		pc("{S}Foot", "block", v(1.0, 0.03, 0.04), v(0, -0.45, -0.6), "glow", { pad = THIN_Y }),
	}
)
-- ── Class sets (shop): Paladin (Knight), Wildwood (Ranger), Stormlord (Mage), Elder Spore (Shaman)
local PALADIN = { "#E8ECF2", "#2E3E6E", "#F2C14E", "#4A7AE0" }
skinLook("paladin_helm", "Paladin Helm", "helmet", PALADIN, {
	pc("Head", "block", v(1.2, 0.58, 1.2), v(0, 0.3, 0), "main"),
	pc("Head", "block", v(1.1, 0.32, 0.12), v(0, -0.05, -0.58), "main"),
	pc("Head", "block", v(0.6, 0.06, 0.04), v(0, 0.02, -0.65), "dark", { pad = THIN_XZ }),
	pc(
		"Head",
		"block",
		v(0.08, 0.4, 0.5),
		v(0.6, 0.5, 0.1),
		"metal",
		{ r = v(0, 0, -20), mirror = true }
	),
	pc("Head", "block", v(0.14, 0.4, 0.9), v(0, 0.75, 0.1), "accent"),
	pc("Head", "block", v(1.24, 0.06, 1.24), v(0, 0.06, 0), "trim", { pad = THIN_Y }),
	pc("Head", "ball", v(0.14, 0, 0), v(0, 0.38, -0.62), "gem"),
	pc("Head", "block", v(0.04, 0.04, 0.86), v(0, 0.96, 0.1), "glow", { pad = THIN_XZ }),
})
skinLook("paladin_plate", "Paladin Plate", "armor", PALADIN, {
	pc("UpperTorso", "block", v(1.08, 0.94, 1.16), v(0, 0.02, 0), "dark"),
	pc(
		"UpperTorso",
		"block",
		v(0.96, 0.46, 0.12),
		v(0, 0.08, -0.6),
		"main",
		{ pad = v(0, 0, 0.06) }
	),
	pc(
		"UpperTorso",
		"block",
		v(0.1, 0.36, 0.04),
		v(0, 0.08, -0.68),
		"metal",
		{ pad = v(0, 0, 0.06) }
	),
	pc(
		"UpperTorso",
		"block",
		v(0.3, 0.1, 0.04),
		v(0, 0.14, -0.68),
		"metal",
		{ pad = v(0, 0, 0.06) }
	),
	pc("{S}UpperArm", "block", v(1.46, 0.5, 1.46), v(0.08, 0.34, 0), "main"),
	pc("{S}UpperArm", "block", v(1.3, 0.24, 1.3), v(0.1, 0.04, 0), "dark"),
	pc(
		"UpperTorso",
		"block",
		v(0.36, 0.4, 0.06),
		v(0, -0.3, -0.58),
		"accent",
		{ pad = v(0, 0, 0.04) }
	),
	pc("{S}UpperArm", "block", v(1.5, 0.06, 1.5), v(0.08, 0.14, 0), "trim", { pad = THIN_Y }),
	pc("UpperTorso", "ball", v(0.1, 0, 0), v(0, 0.14, -0.74), "gem"),
	pc(
		"UpperTorso",
		"block",
		v(0.9, 0.03, 0.03),
		v(0, -0.16, -0.67),
		"glow",
		{ pad = v(0, 0.04, 0.04) }
	),
})
skinLook("paladin_gauntlets", "Paladin Gauntlets", "gloves", PALADIN, {
	pc("{S}Hand", "block", v(1.22, 1.2, 1.22), v(0, 0, 0), "main"),
	pc("{S}LowerArm", "block", v(1.4, 0.5, 1.4), v(0, -0.24, 0), "metal"),
	pc("{S}LowerArm", "block", v(1.2, 0.3, 1.2), v(0, -0.6, 0), "dark"),
	pc("{S}LowerArm", "block", v(1.44, 0.05, 1.44), v(0, -0.04, 0), "trim", { pad = THIN_Y }),
	pc("{S}LowerArm", "ball", v(0.18, 0, 0), v(0, -0.24, -0.72), "gem"),
	pc("{S}Hand", "block", v(0.04, 0.04, 1.0), v(0.62, 0, 0), "glow", { pad = THIN_XZ }),
})
local WILDWOOD = { "#2F6B2A", "#5A3A1E", "#C9A25A", "#8CCB4A" }
skinLook("wildwood_hood", "Wildwood Hood", "helmet", WILDWOOD, {
	pc("Head", "block", v(1.2, 0.75, 1.0), v(0, 0.2, 0.1), "main"),
	pc(
		"Head",
		"block",
		v(0.3, 0.08, 0.4),
		v(0.3, 0.62, -0.2),
		"accent",
		{ r = v(0, 0, 20), mirror = true }
	),
	pc(
		"Head",
		"block",
		v(0.06, 0.4, 0.06),
		v(0.42, 0.74, 0.12),
		"dark",
		{ r = v(0, 0, -25), mirror = true }
	),
	pc("Head", "block", v(1.3, 0.2, 1.1), v(0, -0.55, 0.05), "dark"),
	pc(
		"Head",
		"block",
		v(0.06, 0.6, 0.06),
		v(0.58, 0.15, -0.38),
		"trim",
		{ pad = THIN_XZ, mirror = true }
	),
	pc("Head", "ball", v(0.15, 0, 0), v(0, -0.55, -0.6), "gem"),
	pc(
		"Head",
		"block",
		v(0.04, 0.04, 0.3),
		v(0.3, 0.68, -0.2),
		"glow",
		{ pad = THIN_XZ, mirror = true }
	),
})
skinLook("wildwood_jerkin", "Wildwood Jerkin", "armor", WILDWOOD, {
	pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "main"),
	pc(
		"UpperTorso",
		"block",
		v(0.3, 0.7, 0.06),
		v(0.3, 0, -0.57),
		"dark",
		{ pad = v(0, 0, 0.06), mirror = true }
	),
	pc("{S}UpperArm", "block", v(1.2, 0.3, 1.2), v(0, 0.4, 0), "accent"),
	pc("UpperTorso", "block", v(0.12, 1.25, 1.25), v(0, 0, 0), "dark", { r = v(0, 0, 38) }),
	pc(
		"UpperTorso",
		"block",
		v(0.04, 0.7, 0.04),
		v(0.14, 0, -0.6),
		"trim",
		{ pad = v(0.04, 0, 0.08), mirror = true }
	),
	pc("UpperTorso", "ball", v(0.08, 0, 0), v(0, 0.1, -0.7), "gem"),
	pc("{S}UpperArm", "block", v(1.24, 0.03, 0.04), v(0, 0.3, -0.6), "glow", { pad = THIN_Y }),
})
skinLook("wildwood_boots", "Wildwood Boots", "boots", WILDWOOD, {
	pc("{S}Foot", "block", v(1.16, 1.25, 1.16), v(0, 0.06, -0.03), "dark"),
	pc("{S}LowerLeg", "block", v(1.2, 0.55, 1.2), v(0, -0.2, 0), "main"),
	pc(
		"{S}LowerLeg",
		"block",
		v(0.4, 0.06, 0.3),
		v(0.4, 0.14, -0.3),
		"accent",
		{ r = v(0, 0, -20) }
	),
	pc("{S}LowerLeg", "block", v(1.24, 0.05, 1.24), v(0, 0, 0), "trim", { pad = THIN_Y }),
	pc("{S}LowerLeg", "ball", v(0.14, 0, 0), v(0, 0.02, -0.64), "gem"),
	pc("{S}Foot", "block", v(1.0, 0.03, 0.04), v(0, -0.45, -0.6), "glow", { pad = THIN_Y }),
})
local STORMLORD = { "#3A3A5E", "#14142A", "#C8D2E8", "#8FE8FF" }
skinLook("stormlord_hat", "Stormlord Hat", "helmet", STORMLORD, {
	pc("Head", "block", v(1.5, 0.08, 1.5), v(0, 0.1, 0), "dark"),
	pc("Head", "block", v(0.9, 0.6, 0.9), v(0, 0.45, 0), "main"),
	pc("Head", "block", v(0.5, 0.4, 0.5), v(0.05, 0.9, 0.05), "main", { r = v(0, 0, 12) }),
	pc("Head", "block", v(0.94, 0.12, 0.94), v(0, 0.22, 0), "metal"),
	pc(
		"Head",
		"block",
		v(0.06, 0.5, 0.04),
		v(0.2, 0.45, -0.47),
		"rune",
		{ r = v(0, 0, 25), pad = THIN_XZ }
	),
	pc("Head", "block", v(0.96, 0.05, 0.96), v(0, 0.35, 0), "trim", { pad = THIN_Y }),
	pc("Head", "ball", v(0.12, 0, 0), v(0, 0.24, -0.5), "gem"),
	pc("Head", "block", v(1.54, 0.03, 1.54), v(0, 0.1, 0), "glow", { pad = THIN_Y }),
})
skinLook("stormlord_robe", "Stormlord Robe", "armor", STORMLORD, {
	pc("UpperTorso", "block", v(1.08, 0.94, 1.16), v(0, 0.02, 0), "main"),
	pc("{S}UpperArm", "ball", v(0.9, 0, 0), v(0.1, 0.45, 0), "dark"),
	pc("{S}UpperArm", "ball", v(0.7, 0, 0), v(0.3, 0.3, 0.2), "dark"),
	pc(
		"UpperTorso",
		"block",
		v(0.06, 0.5, 0.04),
		v(0.15, -0.05, -0.6),
		"rune",
		{ r = v(0, 0, 25), pad = v(0, 0, 0.04), mirror = true }
	),
	pc("UpperTorso", "block", v(0.8, 0.12, 1.2), v(0, 0.48, 0), "metal"),
	pc(
		"UpperTorso",
		"block",
		v(0.9, 0.04, 0.04),
		v(0, -0.4, -0.6),
		"trim",
		{ pad = v(0, 0, 0.04) }
	),
	pc("UpperTorso", "ball", v(0.12, 0, 0), v(0, 0.15, -0.66), "gem"),
	pc("{S}UpperArm", "ball", v(0.2, 0, 0), v(0.2, 0.7, 0), "glow"),
})
skinLook(
	"stormlord_amulet",
	"Stormlord Amulet",
	"amulet",
	STORMLORD,
	with(chain(), {
		pc(
			"UpperTorso",
			"block",
			v(0.12, 0.12, 0.03),
			v(0, 0.33, -0.62),
			"metal",
			{ pad = v(0, 0, 0.06) }
		),
		pc("UpperTorso", "ball", v(0.08, 0, 0), v(0, 0.33, -0.68), "rune"),
		pc(
			"UpperTorso",
			"block",
			v(0.16, 0.16, 0.02),
			v(0, 0.33, -0.61),
			"trim",
			{ pad = v(0, 0, 0.05) }
		),
		pc("UpperTorso", "ball", v(0.05, 0, 0), v(0, 0.23, -0.66), "gem"),
	})
)
local ELDER = { "#7A3CA8", "#3A2A4A", "#6A4A2A", "#B8F06A" }
skinLook("elder_spore_cap", "Elder Spore Cap", "helmet", ELDER, {
	pc("Head", "block", v(1.6, 0.18, 1.6), v(0, 0.35, 0), "main"),
	pc("Head", "block", v(1.2, 0.4, 1.2), v(0, 0.6, 0), "main"),
	pc("Head", "block", v(1.5, 0.06, 1.5), v(0, 0.24, 0), "accent"),
	pc("Head", "ball", v(0.18, 0, 0), v(0.3, 0.74, -0.4), "rune"),
	pc("Head", "ball", v(0.16, 0, 0), v(-0.35, 0.7, 0.3), "rune"),
	pc("Head", "block", v(0.9, 0.3, 0.2), v(0, -0.55, -0.5), "dark"),
	pc("Head", "block", v(1.64, 0.05, 1.64), v(0, 0.35, 0), "trim", { pad = THIN_Y }),
	pc("Head", "ball", v(0.12, 0, 0), v(0, 0.84, 0), "gem"),
	pc("Head", "block", v(0.5, 0.04, 0.04), v(0, 0.45, -0.62), "glow", { pad = THIN_XZ }),
})
skinLook("elder_spore_robe", "Elder Spore Robe", "armor", ELDER, {
	pc("UpperTorso", "block", v(1.08, 0.94, 1.16), v(0, 0.02, 0), "main"),
	pc("UpperTorso", "block", v(0.8, 0.14, 1.2), v(0, 0.47, 0), "dark"),
	pc("{S}UpperArm", "block", v(1.5, 0.25, 1.5), v(0.08, 0.5, 0), "main"),
	pc("{S}UpperArm", "block", v(1.1, 0.25, 1.1), v(0.08, 0.7, 0), "main"),
	pc("{S}UpperArm", "ball", v(0.2, 0, 0), v(0.3, 0.82, -0.2), "rune"),
	pc("UpperTorso", "block", v(0.6, 0.4, 0.08), v(0, 0, -0.6), "metal", { pad = v(0, 0, 0.06) }),
	pc("{S}UpperArm", "block", v(1.54, 0.05, 1.54), v(0.08, 0.5, 0), "trim", { pad = THIN_Y }),
	pc("UpperTorso", "ball", v(0.1, 0, 0), v(0, 0, -0.68), "gem"),
	pc("UpperTorso", "block", v(0.5, 0.03, 0.04), v(0, -0.24, -0.66), "glow", { pad = THIN_Y }),
})
skinLook("elder_spore_belt", "Elder Spore Belt", "belt", ELDER, {
	pc("LowerTorso", "block", v(1.1, 0.32, 1.2), v(0, 0.3, 0), "metal"),
	pc("{S}UpperLeg", "block", v(0.5, 0.12, 0.5), v(0.4, 0.4, -0.2), "main"),
	pc("{S}UpperLeg", "block", v(0.14, 0.2, 0.14), v(0.4, 0.28, -0.2), "dark"),
	pc("LowerTorso", "ball", v(0.12, 0, 0), v(0.3, 0.3, -0.64), "rune"),
	pc("LowerTorso", "block", v(1.14, 0.05, 1.24), v(0, 0.3, 0), "trim", { pad = THIN_Y }),
	pc("LowerTorso", "ball", v(0.1, 0, 0), v(0, 0.3, -0.68), "gem"),
	pc("LowerTorso", "block", v(1.0, 0.03, 0.04), v(0, 0.15, -0.62), "glow", { pad = THIN_Y }),
})

local skinStyles: { [string]: Style } = {}
for id, look in SKIN_LOOKS do
	local c = look.colors
	skinStyles[id] = table.freeze({
		id = id,
		name = look.name,
		palette = table.freeze({
			main = Color3.fromHex(c[1]),
			dark = Color3.fromHex(c[2]),
			metal = Color3.fromHex(c[3]),
			accent = Color3.fromHex(c[4]),
		}),
		pieces = table.freeze({ [look.slot] = look.pieces }),
	})
end
Gear.Skins = table.freeze(skinStyles)

-- The look a slot shows: a skin with a look for that slot, else the hero's class look.
-- Whether the hero may wear the skin (owned, class) is checked before (Shared/GearSkins.fits).
function Gear.style(class: string, slot: string, skin: string?): Style?
	local s = if skin then skinStyles[skin] else nil
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
for id, style in skinStyles do
	for slot in style.pieces do
		assert(table.find(Gear.Slots, slot), `gear skin {id}: unknown slot {slot}`)
		assert(
			#Gear.pieces(style, slot, Gear.TOP_RARITY) <= Gear.MAX_PIECES,
			`gear skin {id}: too many pieces`
		)
	end
end

return table.freeze(Gear)
