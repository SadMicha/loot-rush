--!strict
-- Visible gear (pure data): how worn armor and jewelry look on the hero's body. Systems/Gear builds
-- these pieces from studded parts and welds them to the R15 body parts, so every player sees
-- them, and the inventory preview (a clone of the character) shows them too. No art assets.
--
-- A look ("style") is a short list of pieces per slot. Each piece hangs on one body part and is
-- sized and placed in multiples of that part's size, so it fits every avatar scale:
--   size = part.Size * s (+ pad studs) · position = part.Size * p from the part center
--   (+Y up, -Z = the face/chest side). "{S}" in a part name = both sides (Left/Right, X mirrored).
-- Colors are roles, filled per look and item: main/dark (the look's palette), trim and gem
-- (the item's rarity color; gems glow from "rare" up).
--
-- Looks are separate from items on purpose: the default look of a slot is the hero's class,
-- a gear skin (cosmetic, docs/specs/GEAR-COSMETICS.md) is just another style id for that slot.

local Theme = require(script.Parent.UI.Theme)

local Gear = {}

export type Shape = "block" | "wedge" | "ball" | "disc"
export type Role = "main" | "dark" | "trim" | "gem"
export type Piece = {
	part: string, -- R15 body part ("{S}" = both sides)
	shape: Shape,
	s: Vector3, -- size in part sizes (ball: X only, uniform; disc: X = height, Y = diameter)
	p: Vector3, -- center offset in part sizes
	r: Vector3?, -- rotation in degrees (X, Y, Z)
	pad: Vector3?, -- studs added to the size (thin plates that must stay visible)
	role: Role,
}
export type Palette = { main: Color3, dark: Color3 }
export type Style = {
	id: string,
	name: string,
	palette: Palette,
	pieces: { [string]: { Piece } }, -- slot → pieces (missing slot = default class look)
}

-- Slots with a body look. Weapon/offhand are held (Systems/Weapons), rings are too small to read.
Gear.Slots = table.freeze({ "helmet", "armor", "gloves", "belt", "boots", "amulet" })
Gear.MAX_PIECES = 6 -- per slot and look (performance: 12 players × 6 slots stay < 400 parts)
Gear.MODEL = "WornGear" -- model in the character that holds every piece
Gear.GEM_NEON_RANK = 3 -- Items.rank from which gems glow (rare)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function pc(
	part: string,
	shape: Shape,
	s: Vector3,
	p: Vector3,
	role: Role,
	r: Vector3?,
	pad: Vector3?
): Piece
	return { part = part, shape = shape, s = s, p = p, role = role, r = r, pad = pad }
end

-- Shared shapes (every class): gloves, boots, belt, amulet
local COMMON: { [string]: { Piece } } = {
	gloves = {
		pc("{S}Hand", "block", v(1.2, 1.15, 1.2), v(0, -0.05, 0), "main"),
		pc("{S}LowerArm", "block", v(1.18, 0.28, 1.18), v(0, -0.36, 0), "trim"),
	},
	boots = {
		pc("{S}Foot", "block", v(1.12, 1.2, 1.1), v(0, 0.05, -0.02), "main"),
		pc("{S}LowerLeg", "block", v(1.14, 0.3, 1.14), v(0, -0.3, 0), "trim"),
	},
	belt = {
		pc("LowerTorso", "block", v(1.08, 0.55, 1.2), v(0, 0.12, 0), "dark"),
		pc("LowerTorso", "block", v(0.2, 0.5, 0.05), v(0, 0.12, -0.6), "trim", nil, v(0, 0, 0.1)),
	},
	amulet = {
		pc("UpperTorso", "block", v(0.05, 0.22, 0.02), v(0, 0.3, -0.6), "trim", nil, v(0, 0, 0.06)),
		pc("UpperTorso", "ball", v(0.16, 0, 0), v(0, 0.16, -0.63), "gem"),
	},
}

-- Class looks for helmet and armor (the slots with the biggest silhouette)
local CLASS: { [string]: { [string]: { Piece } } } = {
	-- Brix: knight helm with nose guard and crest, steel chest plate with pauldrons
	warrior = {
		helmet = {
			pc("Head", "block", v(1.16, 0.55, 1.16), v(0, 0.3, 0), "main"),
			pc("Head", "block", v(0.12, 0.6, 0.9), v(0.55, -0.05, 0.05), "main"),
			pc("Head", "block", v(0.12, 0.6, 0.9), v(-0.55, -0.05, 0.05), "main"),
			pc("Head", "block", v(0.12, 0.42, 0.08), v(0, 0.08, -0.58), "dark"),
			pc("Head", "block", v(0.14, 0.32, 0.95), v(0, 0.7, 0.05), "trim"),
		},
		armor = {
			pc("UpperTorso", "block", v(1.08, 0.92, 1.16), v(0, 0.02, 0), "main"),
			pc(
				"UpperTorso",
				"block",
				v(0.32, 0.32, 0.04),
				v(0, 0.1, -0.6),
				"trim",
				nil,
				v(0, 0, 0.06)
			),
			pc("{S}UpperArm", "block", v(1.3, 0.42, 1.3), v(0, 0.34, 0), "dark"),
		},
	},
	-- Fynn: ranger hood with mantle, leather vest with a quiver strap
	ranger = {
		helmet = {
			pc("Head", "block", v(1.18, 0.72, 0.95), v(0, 0.2, 0.12), "main"),
			pc("Head", "wedge", v(1.18, 0.22, 0.4), v(0, 0.45, -0.38), "main", v(0, 180, 0)),
			pc("Head", "block", v(1.3, 0.22, 1.15), v(0, -0.56, 0.06), "dark"),
		},
		armor = {
			pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "main"),
			pc("UpperTorso", "block", v(0.16, 1.3, 1.18), v(0, 0, 0), "dark", v(0, 0, 38)),
			pc("LeftUpperArm", "block", v(1.25, 0.4, 1.25), v(0, 0.34, 0), "trim"),
		},
	},
	-- Zap: pointed wizard hat with a glowing tip, robe with collar and skirt
	mage = {
		helmet = {
			pc("Head", "disc", v(0.1, 1.9, 0), v(0, 0.48, 0), "main"),
			pc("Head", "block", v(0.92, 0.5, 0.92), v(0, 0.75, 0.02), "main"),
			pc("Head", "block", v(0.96, 0.12, 0.96), v(0, 0.56, 0.02), "trim"),
			pc("Head", "block", v(0.6, 0.48, 0.6), v(0, 1.2, 0.08), "main", v(-8, 0, 0)),
			pc("Head", "ball", v(0.28, 0, 0), v(0, 1.5, 0.15), "gem"),
		},
		armor = {
			pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "main"),
			pc("UpperTorso", "block", v(1.12, 0.22, 1.18), v(0, 0.48, 0), "trim"),
			pc("LowerTorso", "block", v(1.1, 2.4, 1.14), v(0, -0.7, 0), "dark"),
		},
	},
	-- Mora: red mushroom cap with cream spots, moss mantle with leaf pauldrons
	mushroom = {
		helmet = {
			pc("Head", "disc", v(0.32, 1.8, 0), v(0, 0.46, 0), "main"),
			pc("Head", "disc", v(0.28, 1.25, 0), v(0, 0.72, 0), "main"),
			pc("Head", "ball", v(0.26, 0, 0), v(0.38, 0.8, -0.22), "trim"),
			pc("Head", "ball", v(0.22, 0, 0), v(-0.3, 0.84, 0.28), "trim"),
		},
		armor = {
			pc("UpperTorso", "block", v(1.06, 0.92, 1.12), v(0, 0.02, 0), "dark"),
			pc("UpperTorso", "block", v(1.22, 0.3, 1.22), v(0, 0.46, 0), "main"),
			pc("{S}UpperArm", "wedge", v(1.3, 0.45, 1.3), v(0, 0.36, 0), "main", v(0, 90, 0)),
		},
	},
}

local PALETTE: { [string]: Palette } = {
	warrior = { main = Color3.fromHex("#B8C0CE"), dark = Color3.fromHex("#5A5F70") },
	ranger = { main = Color3.fromHex("#3F8A3A"), dark = Color3.fromHex("#6B4526") },
	mage = { main = Color3.fromHex("#4A55C8"), dark = Color3.fromHex("#2C2F7A") },
	mushroom = { main = Color3.fromHex("#D8442E"), dark = Color3.fromHex("#4E7A2A") },
}

local NAME: { [string]: string } = {
	warrior = "Knight's Steel",
	ranger = "Ranger's Leather",
	mage = "Spark Robes",
	mushroom = "Spore Garb",
}

local styles: { [string]: Style } = {}
for id, pieces in CLASS do
	local all = table.clone(COMMON)
	for slot, list in pieces do
		all[slot] = list
	end
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

-- Pieces of one slot with "{S}" expanded into a Left and a Right piece (X mirrored)
function Gear.pieces(style: Style, slot: string): { Piece }
	local out: { Piece } = {}
	local list: { Piece } = style.pieces[slot] or {}
	for _, piece in list do
		if string.find(piece.part, "{S}", 1, true) then
			for _, side in { "Left", "Right" } do
				local mirror = if side == "Left" then -1 else 1
				local r = piece.r
				table.insert(out, {
					part = (string.gsub(piece.part, "{S}", side)),
					shape = piece.shape,
					s = piece.s,
					p = Vector3.new(piece.p.X * mirror, piece.p.Y, piece.p.Z),
					r = if r then Vector3.new(r.X, r.Y * mirror, r.Z * mirror) else nil,
					pad = piece.pad,
					role = piece.role,
				})
			end
		else
			table.insert(out, piece)
		end
	end
	return out
end

-- Color of a piece: palette for main/dark, rarity color for trim/gem
function Gear.color(style: Style, role: Role, rarity: string): Color3
	if role == "main" then
		return style.palette.main
	elseif role == "dark" then
		return style.palette.dark
	end
	return Theme.Rarity[rarity] or Theme.Rarity.normal
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
			#Gear.pieces(style, slot) <= Gear.MAX_PIECES,
			`gear look {id}: {slot} too many pieces`
		)
	end
end

return table.freeze(Gear)
