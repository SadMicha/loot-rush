--!strict
-- Uploaded UI images in the mock-up look (assets/ui_upload_v3) and icon atlases (ui_upload_v2).
-- Slice = stretchable (ScaleType Slice, center in source pixels), Fixed = fixed size (ScaleType Fit).
-- If an entry is missing, Kit uses the flat style.

export type Slice = { id: string, size: Vector2, center: Rect }
export type Fixed = { id: string, size: Vector2 }
export type Icon = { id: string, offset: Vector2 }

local Assets = {}

Assets.Slice = table.freeze({
	window_main = table.freeze({
		id = "rbxassetid://82567780601268",
		size = Vector2.new(1014, 561),
		center = Rect.new(70, 70, 944, 491),
	}),
	window_tall = table.freeze({
		id = "rbxassetid://133130370315983",
		size = Vector2.new(426, 647),
		center = Rect.new(62, 62, 364, 585),
	}),
	window_small = table.freeze({
		id = "rbxassetid://124463441554826",
		size = Vector2.new(468, 322),
		center = Rect.new(62, 62, 406, 260),
	}),
	btn_gold = table.freeze({
		id = "rbxassetid://125339320044510",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_gold_pressed = table.freeze({
		id = "rbxassetid://106343024301161",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_gold_disabled = table.freeze({
		id = "rbxassetid://71834594408287",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_blue = table.freeze({
		id = "rbxassetid://119802837697644",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_blue_pressed = table.freeze({
		id = "rbxassetid://86069804275693",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_blue_disabled = table.freeze({
		id = "rbxassetid://139332338408263",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_red = table.freeze({
		id = "rbxassetid://117304138420622",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	btn_red_pressed = table.freeze({
		id = "rbxassetid://99993677429600",
		size = Vector2.new(672, 152),
		center = Rect.new(58, 58, 614, 94),
	}),
	nav_idle = table.freeze({
		id = "rbxassetid://138093077358094",
		size = Vector2.new(234, 263),
		center = Rect.new(62, 62, 172, 201),
	}),
	nav_active = table.freeze({
		id = "rbxassetid://73325288772564",
		size = Vector2.new(286, 315),
		center = Rect.new(76, 76, 210, 239),
	}),
	tab_idle = table.freeze({
		id = "rbxassetid://78960679153232",
		size = Vector2.new(188, 186),
		center = Rect.new(52, 52, 136, 134),
	}),
	tab_active = table.freeze({
		id = "rbxassetid://101204472335224",
		size = Vector2.new(236, 237),
		center = Rect.new(66, 66, 170, 171),
	}),
	btn_sort = table.freeze({
		id = "rbxassetid://109754724045279",
		size = Vector2.new(705, 164),
		center = Rect.new(62, 62, 643, 102),
	}),
	pill_gold = table.freeze({
		id = "rbxassetid://117937349096594",
		size = Vector2.new(463, 107),
		center = Rect.new(175, 45, 343, 62),
	}),
	pill_purple = table.freeze({
		id = "rbxassetid://137064645956062",
		size = Vector2.new(462, 106),
		center = Rect.new(175, 45, 342, 61),
	}),
	pill_cyan = table.freeze({
		id = "rbxassetid://94941047433713",
		size = Vector2.new(463, 107),
		center = Rect.new(175, 45, 343, 62),
	}),
	pill3_gold = table.freeze({
		id = "rbxassetid://99369761313861",
		size = Vector2.new(471, 120),
		center = Rect.new(62, 44, 409, 76),
	}),
	pill3_purple = table.freeze({
		id = "rbxassetid://93783153686248",
		size = Vector2.new(471, 120),
		center = Rect.new(62, 44, 409, 76),
	}),
	pill3_cyan = table.freeze({
		id = "rbxassetid://78380056051436",
		size = Vector2.new(471, 120),
		center = Rect.new(62, 44, 409, 76),
	}),
	search_field = table.freeze({
		id = "rbxassetid://134328595926962",
		size = Vector2.new(764, 152),
		center = Rect.new(132, 56, 694, 96),
	}),
	stage_backdrop = table.freeze({
		id = "rbxassetid://82665349013008",
		size = Vector2.new(539, 929),
		center = Rect.new(50, 50, 489, 879),
	}),
	stat_tile = table.freeze({
		id = "rbxassetid://123010495639775",
		size = Vector2.new(450, 141),
		center = Rect.new(58, 58, 392, 83),
	}),
	chip_green = table.freeze({
		id = "rbxassetid://111702894705451",
		size = Vector2.new(328, 94),
		center = Rect.new(48, 44, 280, 50),
	}),
	chip_red = table.freeze({
		id = "rbxassetid://134621436900346",
		size = Vector2.new(328, 93),
		center = Rect.new(48, 44, 280, 49),
	}),
	bar_frame = table.freeze({
		id = "rbxassetid://127385567684431",
		size = Vector2.new(1024, 53),
		center = Rect.new(31, 22, 993, 31),
	}),
	bar_fill = table.freeze({
		id = "rbxassetid://92090882266948",
		size = Vector2.new(1024, 53),
		center = Rect.new(31, 22, 993, 31),
	}),
	header_banner = table.freeze({
		id = "rbxassetid://125265440038686",
		size = Vector2.new(1024, 136),
		center = Rect.new(61, 51, 963, 85),
	}),
} :: { [string]: Slice })

Assets.Fixed = table.freeze({
	slot_empty = table.freeze({ id = "rbxassetid://125056307032988", size = Vector2.new(192, 192) }),
	slot_normal = table.freeze({
		id = "rbxassetid://123965511108242",
		size = Vector2.new(192, 192),
	}),
	slot_magic = table.freeze({ id = "rbxassetid://70717392170486", size = Vector2.new(192, 192) }),
	slot_rare = table.freeze({ id = "rbxassetid://72707565080469", size = Vector2.new(192, 192) }),
	slot_epic = table.freeze({ id = "rbxassetid://109297843847039", size = Vector2.new(192, 192) }),
	slot_unique = table.freeze({ id = "rbxassetid://84255349807067", size = Vector2.new(192, 192) }),
	slot_legend = table.freeze({
		id = "rbxassetid://139929493927957",
		size = Vector2.new(192, 192),
	}),
	slot_selected = table.freeze({
		id = "rbxassetid://98281980680183",
		size = Vector2.new(224, 224),
	}),
	close_dark = table.freeze({ id = "rbxassetid://96979247364085", size = Vector2.new(189, 189) }),
	close_red = table.freeze({ id = "rbxassetid://114685331210280", size = Vector2.new(189, 188) }),
	plus_gold = table.freeze({ id = "rbxassetid://97395908772157", size = Vector2.new(88, 87) }),
	plus_purple = table.freeze({ id = "rbxassetid://122971756198736", size = Vector2.new(88, 87) }),
	plus_cyan = table.freeze({ id = "rbxassetid://96095283592925", size = Vector2.new(88, 87) }),
	icon_search = table.freeze({
		id = "rbxassetid://138528434334751",
		size = Vector2.new(174, 175),
	}),
	stage_glow = table.freeze({ id = "rbxassetid://133805688311422", size = Vector2.new(576, 960) }),
	stage_ring = table.freeze({ id = "rbxassetid://135127539214507", size = Vector2.new(628, 245) }),
	divider = table.freeze({ id = "rbxassetid://114622747152381", size = Vector2.new(1024, 31) }),
} :: { [string]: Fixed })

local ICON_SIZE = Vector2.new(256, 256)
Assets.IconSize = ICON_SIZE

local ATLAS = {
	icons_01 = "rbxassetid://101719755603977",
	icons_02 = "rbxassetid://108148932147569",
	icons_03 = "rbxassetid://126164635021880",
	icons_04 = "rbxassetid://128477293347002",
	icons_05 = "rbxassetid://71829188595873",
	icons_06 = "rbxassetid://134028671599088",
	icons_07 = "rbxassetid://84863698262790",
	icons_08 = "rbxassetid://82781022026414",
	icons_09 = "rbxassetid://76979407408909",
	icons_10 = "rbxassetid://76489694074987",
}

-- Icons in the atlas images: ImageRectOffset = offset, ImageRectSize = IconSize.
-- Unassigned icons keep their sheet code (A11 ... K44), see Icon_Zuordnung.csv.
local icon: { [string]: Icon } = {
	inventory = { id = ATLAS.icons_01, offset = Vector2.new(0, 0) },
	star_net = { id = ATLAS.icons_01, offset = Vector2.new(256, 0) },
	skills = { id = ATLAS.icons_01, offset = Vector2.new(512, 0) },
	forge = { id = ATLAS.icons_01, offset = Vector2.new(768, 0) },
	hub = { id = ATLAS.icons_01, offset = Vector2.new(0, 256) },
	companion = { id = ATLAS.icons_01, offset = Vector2.new(256, 256) },
	atlas = { id = ATLAS.icons_01, offset = Vector2.new(512, 256) },
	soulstar = { id = ATLAS.icons_01, offset = Vector2.new(768, 256) },
	gold = { id = ATLAS.icons_01, offset = Vector2.new(0, 512) },
	crystal = { id = ATLAS.icons_01, offset = Vector2.new(256, 512) },
	quest = { id = ATLAS.icons_01, offset = Vector2.new(512, 512) },
	sword = { id = ATLAS.icons_01, offset = Vector2.new(768, 512) },
	fire = { id = ATLAS.icons_01, offset = Vector2.new(0, 768) },
	lightning = { id = ATLAS.icons_01, offset = Vector2.new(256, 768) },
	ice = { id = ATLAS.icons_01, offset = Vector2.new(512, 768) },
	flask_red = { id = ATLAS.icons_01, offset = Vector2.new(768, 768) },
	flask_blue = { id = ATLAS.icons_02, offset = Vector2.new(0, 0) },
	skill_dash = { id = ATLAS.icons_02, offset = Vector2.new(256, 0) },
	portal = { id = ATLAS.icons_02, offset = Vector2.new(512, 0) },
	close = { id = ATLAS.icons_02, offset = Vector2.new(768, 0) },
	candy = { id = ATLAS.icons_02, offset = Vector2.new(0, 256) },
	glitter_dust = { id = ATLAS.icons_02, offset = Vector2.new(256, 256) },
	pouch = { id = ATLAS.icons_02, offset = Vector2.new(512, 256) },
	settings = { id = ATLAS.icons_02, offset = Vector2.new(768, 256) },
	lock = { id = ATLAS.icons_02, offset = Vector2.new(0, 512) },
	reroll = { id = ATLAS.icons_02, offset = Vector2.new(256, 512) },
	target = { id = ATLAS.icons_02, offset = Vector2.new(512, 512) },
	life = { id = ATLAS.icons_02, offset = Vector2.new(768, 512) },
	filter = { id = ATLAS.icons_02, offset = Vector2.new(0, 768) },
	sort = { id = ATLAS.icons_02, offset = Vector2.new(256, 768) },
	upgrade = { id = ATLAS.icons_02, offset = Vector2.new(512, 768) },
	timer = { id = ATLAS.icons_02, offset = Vector2.new(768, 768) },
	item_level = { id = ATLAS.icons_03, offset = Vector2.new(0, 0) },
	heal = { id = ATLAS.icons_03, offset = Vector2.new(256, 0) },
	salvage = { id = ATLAS.icons_03, offset = Vector2.new(512, 0) },
	horn = { id = ATLAS.icons_03, offset = Vector2.new(768, 0) },
	poison = { id = ATLAS.icons_03, offset = Vector2.new(0, 256) },
	whirl = { id = ATLAS.icons_03, offset = Vector2.new(256, 256) },
	ice_cube = { id = ATLAS.icons_03, offset = Vector2.new(512, 256) },
	shield_buff = { id = ATLAS.icons_03, offset = Vector2.new(768, 256) },
	crown = { id = ATLAS.icons_03, offset = Vector2.new(0, 512) },
	trophy = { id = ATLAS.icons_03, offset = Vector2.new(256, 512) },
	chest = { id = ATLAS.icons_03, offset = Vector2.new(512, 512) },
	wings = { id = ATLAS.icons_03, offset = Vector2.new(768, 512) },
	slot_helmet = { id = ATLAS.icons_03, offset = Vector2.new(0, 768) },
	slot_armor = { id = ATLAS.icons_03, offset = Vector2.new(256, 768) },
	slot_gloves = { id = ATLAS.icons_03, offset = Vector2.new(512, 768) },
	slot_belt = { id = ATLAS.icons_03, offset = Vector2.new(768, 768) },
	slot_boots = { id = ATLAS.icons_04, offset = Vector2.new(0, 0) },
	slot_ring = { id = ATLAS.icons_04, offset = Vector2.new(256, 0) },
	slot_amulet = { id = ATLAS.icons_04, offset = Vector2.new(512, 0) },
	slot_shield = { id = ATLAS.icons_04, offset = Vector2.new(768, 0) },
	slot_weapon = { id = ATLAS.icons_04, offset = Vector2.new(0, 256) },
	slot_staff = { id = ATLAS.icons_04, offset = Vector2.new(256, 256) },
	slot_bow = { id = ATLAS.icons_04, offset = Vector2.new(512, 256) },
	A12 = { id = ATLAS.icons_04, offset = Vector2.new(768, 256) },
	A13 = { id = ATLAS.icons_04, offset = Vector2.new(0, 512) },
	A22 = { id = ATLAS.icons_04, offset = Vector2.new(256, 512) },
	A23 = { id = ATLAS.icons_04, offset = Vector2.new(512, 512) },
	A31 = { id = ATLAS.icons_04, offset = Vector2.new(768, 512) },
	A33 = { id = ATLAS.icons_04, offset = Vector2.new(0, 768) },
	A42 = { id = ATLAS.icons_04, offset = Vector2.new(256, 768) },
	A43 = { id = ATLAS.icons_04, offset = Vector2.new(512, 768) },
	D21 = { id = ATLAS.icons_04, offset = Vector2.new(768, 768) },
	D22 = { id = ATLAS.icons_05, offset = Vector2.new(0, 0) },
	E11 = { id = ATLAS.icons_05, offset = Vector2.new(256, 0) },
	E12 = { id = ATLAS.icons_05, offset = Vector2.new(512, 0) },
	E13 = { id = ATLAS.icons_05, offset = Vector2.new(768, 0) },
	E14 = { id = ATLAS.icons_05, offset = Vector2.new(0, 256) },
	E21 = { id = ATLAS.icons_05, offset = Vector2.new(256, 256) },
	E22 = { id = ATLAS.icons_05, offset = Vector2.new(512, 256) },
	E23 = { id = ATLAS.icons_05, offset = Vector2.new(768, 256) },
	E24 = { id = ATLAS.icons_05, offset = Vector2.new(0, 512) },
	E31 = { id = ATLAS.icons_05, offset = Vector2.new(256, 512) },
	E32 = { id = ATLAS.icons_05, offset = Vector2.new(512, 512) },
	E33 = { id = ATLAS.icons_05, offset = Vector2.new(768, 512) },
	E34 = { id = ATLAS.icons_05, offset = Vector2.new(0, 768) },
	E41 = { id = ATLAS.icons_05, offset = Vector2.new(256, 768) },
	E42 = { id = ATLAS.icons_05, offset = Vector2.new(512, 768) },
	E43 = { id = ATLAS.icons_05, offset = Vector2.new(768, 768) },
	E44 = { id = ATLAS.icons_06, offset = Vector2.new(0, 0) },
	F11 = { id = ATLAS.icons_06, offset = Vector2.new(256, 0) },
	F12 = { id = ATLAS.icons_06, offset = Vector2.new(512, 0) },
	F13 = { id = ATLAS.icons_06, offset = Vector2.new(768, 0) },
	F14 = { id = ATLAS.icons_06, offset = Vector2.new(0, 256) },
	F21 = { id = ATLAS.icons_06, offset = Vector2.new(256, 256) },
	F22 = { id = ATLAS.icons_06, offset = Vector2.new(512, 256) },
	F23 = { id = ATLAS.icons_06, offset = Vector2.new(768, 256) },
	F24 = { id = ATLAS.icons_06, offset = Vector2.new(0, 512) },
	F31 = { id = ATLAS.icons_06, offset = Vector2.new(256, 512) },
	F32 = { id = ATLAS.icons_06, offset = Vector2.new(512, 512) },
	F33 = { id = ATLAS.icons_06, offset = Vector2.new(768, 512) },
	F34 = { id = ATLAS.icons_06, offset = Vector2.new(0, 768) },
	F41 = { id = ATLAS.icons_06, offset = Vector2.new(256, 768) },
	F42 = { id = ATLAS.icons_06, offset = Vector2.new(512, 768) },
	F43 = { id = ATLAS.icons_06, offset = Vector2.new(768, 768) },
	F44 = { id = ATLAS.icons_07, offset = Vector2.new(0, 0) },
	G11 = { id = ATLAS.icons_07, offset = Vector2.new(256, 0) },
	G12 = { id = ATLAS.icons_07, offset = Vector2.new(512, 0) },
	G13 = { id = ATLAS.icons_07, offset = Vector2.new(768, 0) },
	G14 = { id = ATLAS.icons_07, offset = Vector2.new(0, 256) },
	G21 = { id = ATLAS.icons_07, offset = Vector2.new(256, 256) },
	G22 = { id = ATLAS.icons_07, offset = Vector2.new(512, 256) },
	G23 = { id = ATLAS.icons_07, offset = Vector2.new(768, 256) },
	G24 = { id = ATLAS.icons_07, offset = Vector2.new(0, 512) },
	G31 = { id = ATLAS.icons_07, offset = Vector2.new(256, 512) },
	G32 = { id = ATLAS.icons_07, offset = Vector2.new(512, 512) },
	G33 = { id = ATLAS.icons_07, offset = Vector2.new(768, 512) },
	G34 = { id = ATLAS.icons_07, offset = Vector2.new(0, 768) },
	G41 = { id = ATLAS.icons_07, offset = Vector2.new(256, 768) },
	G42 = { id = ATLAS.icons_07, offset = Vector2.new(512, 768) },
	G43 = { id = ATLAS.icons_07, offset = Vector2.new(768, 768) },
	G44 = { id = ATLAS.icons_08, offset = Vector2.new(0, 0) },
	H11 = { id = ATLAS.icons_08, offset = Vector2.new(256, 0) },
	H12 = { id = ATLAS.icons_08, offset = Vector2.new(512, 0) },
	H13 = { id = ATLAS.icons_08, offset = Vector2.new(768, 0) },
	H14 = { id = ATLAS.icons_08, offset = Vector2.new(0, 256) },
	H21 = { id = ATLAS.icons_08, offset = Vector2.new(256, 256) },
	H23 = { id = ATLAS.icons_08, offset = Vector2.new(512, 256) },
	H24 = { id = ATLAS.icons_08, offset = Vector2.new(768, 256) },
	H31 = { id = ATLAS.icons_08, offset = Vector2.new(0, 512) },
	H32 = { id = ATLAS.icons_08, offset = Vector2.new(256, 512) },
	H33 = { id = ATLAS.icons_08, offset = Vector2.new(512, 512) },
	H34 = { id = ATLAS.icons_08, offset = Vector2.new(768, 512) },
	H41 = { id = ATLAS.icons_08, offset = Vector2.new(0, 768) },
	H42 = { id = ATLAS.icons_08, offset = Vector2.new(256, 768) },
	H43 = { id = ATLAS.icons_08, offset = Vector2.new(512, 768) },
	H44 = { id = ATLAS.icons_08, offset = Vector2.new(768, 768) },
	J11 = { id = ATLAS.icons_09, offset = Vector2.new(0, 0) },
	J12 = { id = ATLAS.icons_09, offset = Vector2.new(256, 0) },
	J13 = { id = ATLAS.icons_09, offset = Vector2.new(512, 0) },
	J14 = { id = ATLAS.icons_09, offset = Vector2.new(768, 0) },
	J21 = { id = ATLAS.icons_09, offset = Vector2.new(0, 256) },
	J22 = { id = ATLAS.icons_09, offset = Vector2.new(256, 256) },
	J23 = { id = ATLAS.icons_09, offset = Vector2.new(512, 256) },
	J24 = { id = ATLAS.icons_09, offset = Vector2.new(768, 256) },
	J31 = { id = ATLAS.icons_09, offset = Vector2.new(0, 512) },
	J32 = { id = ATLAS.icons_09, offset = Vector2.new(256, 512) },
	J33 = { id = ATLAS.icons_09, offset = Vector2.new(512, 512) },
	J34 = { id = ATLAS.icons_09, offset = Vector2.new(768, 512) },
	J41 = { id = ATLAS.icons_09, offset = Vector2.new(0, 768) },
	J42 = { id = ATLAS.icons_09, offset = Vector2.new(256, 768) },
	J43 = { id = ATLAS.icons_09, offset = Vector2.new(512, 768) },
	J44 = { id = ATLAS.icons_09, offset = Vector2.new(768, 768) },
	K33 = { id = ATLAS.icons_10, offset = Vector2.new(0, 0) },
	K34 = { id = ATLAS.icons_10, offset = Vector2.new(256, 0) },
	K41 = { id = ATLAS.icons_10, offset = Vector2.new(512, 0) },
	K42 = { id = ATLAS.icons_10, offset = Vector2.new(768, 0) },
}
-- Readable names for library icons that have a job in the game (same atlas cell as the code)
local ICON_ALIAS: { [string]: string } = {
	trail_gilded = "H11", -- golden star trail
	trail_frost = "K41", -- ice streak
	aura_ember = "G44", -- ring of fire
	aura_frost = "G43", -- frost ring
	pet_shroomling = "F13",
	pet_spark_fox = "F11",
	gold_sack = "J24", -- coin sack (gold pouch offers)
	gold_hoard = "E13", -- gold burst (gold hoard offers)
	buff_damage = "G22", -- crossed swords medallion
	buff_armor = "G12", -- shield medallion
	buff_haste = "G23", -- winged boot medallion
	buff_shield = "G33", -- hex shield medallion
	leaderboard = "F41", -- golden podium
	shards_big = "J34", -- crystal shard (market card)
	candy_big = "J41", -- rune candy (market card)
	dust_big = "J42", -- glitter bottle (market card)
	-- Atlas fallbacks for Assets.IconImage entries (shown until the image is uploaded)
	soulstars_s = "soulstar",
	soulstars_m = "soulstar",
	soulstars_l = "soulstar",
	soulstars_xl = "soulstar",
	starter_pack = "chest",
	pack_ember = "fire",
	pass_vip = "crown",
	pass_magnet = "chest",
	pass_pet_slot = "companion",
}
for name, code in ICON_ALIAS do
	icon[name] = icon[code]
end
Assets.Icon = table.freeze(icon)

-- Scene images and nodes of the Abilities, Star Net, Forge, Atlas and Shop windows
-- (upload package LootRush_Upload_v8_Fenster). Entries without an ID are ignored; the windows
-- then show the flat style (nodes as slots, lines as thin strokes).
local ART: { [string]: Fixed } = {
	bg_skills = { id = "rbxassetid://124530469380025", size = Vector2.new(1024, 576) },
	bg_starnet = { id = "rbxassetid://139376981558417", size = Vector2.new(1024, 576) },
	bg_forge = { id = "rbxassetid://107475350254463", size = Vector2.new(1024, 576) },
	bg_atlas = { id = "rbxassetid://70777486837402", size = Vector2.new(1024, 576) },
	node_ring = { id = "rbxassetid://111253634336460", size = Vector2.new(342, 344) },
	node_ring_active = { id = "rbxassetid://77679967363235", size = Vector2.new(397, 399) },
	node_ring_locked = { id = "rbxassetid://117172837136806", size = Vector2.new(341, 344) },
	star_small = { id = "rbxassetid://81361090237287", size = Vector2.new(164, 164) },
	star_small_active = { id = "rbxassetid://78945369747414", size = Vector2.new(176, 182) },
	star_big = { id = "rbxassetid://124027696902019", size = Vector2.new(290, 293) },
	star_big_active = { id = "rbxassetid://90212884026288", size = Vector2.new(320, 325) },
	star_core = { id = "rbxassetid://92507514261248", size = Vector2.new(426, 449) },
	plaque_region = { id = "rbxassetid://117854959815810", size = Vector2.new(543, 230) },
	plaque_status = { id = "rbxassetid://101106260708476", size = Vector2.new(818, 282) },
	forge_anvil = { id = "rbxassetid://117223988059627", size = Vector2.new(1000, 536) },
	island_green_plains = { id = "rbxassetid://128994372809509", size = Vector2.new(493, 485) },
	island_crystal_caves = { id = "rbxassetid://120779780565906", size = Vector2.new(471, 474) },
	island_mushroom_swamp = { id = "rbxassetid://104699148537669", size = Vector2.new(479, 480) },
	island_fire_desert = { id = "rbxassetid://131302023646308", size = Vector2.new(512, 518) },
	island_sky_islands = { id = "rbxassetid://95013806127090", size = Vector2.new(512, 497) },
	island_altered_world = { id = "rbxassetid://119053802123572", size = Vector2.new(498, 481) },
	region_green_plains = { id = "rbxassetid://89294082178280", size = Vector2.new(768, 432) },
	region_crystal_caves = { id = "rbxassetid://107712681289481", size = Vector2.new(768, 432) },
	region_mushroom_swamp = { id = "rbxassetid://128283999127426", size = Vector2.new(768, 432) },
	region_fire_desert = { id = "rbxassetid://110395739727001", size = Vector2.new(768, 432) },
	region_sky_islands = { id = "rbxassetid://84354190494860", size = Vector2.new(768, 432) },
	region_altered_world = { id = "rbxassetid://115295026536755", size = Vector2.new(768, 432) },
}
local art: { [string]: Fixed } = {}
for name, a in ART do
	if a.id ~= "" then
		art[name] = table.freeze(a)
	end
end
Assets.Art = table.freeze(art)

-- In-game HUD (assets/ui/icons/hud, assets/ui/icons/skills, assets/ui/icons/*.png).
-- Entries with an empty id are ignored and Kit draws the flat HUD
-- (flat orbs, ring frames, atlas icons). Sizes = pixel size of the uploaded file.
local HUD: { [string]: Fixed } = {
	-- Orbs: frame and fill share the same 512x512 canvas (Aligned_HUD_512)
	orb_health_frame = { id = "rbxassetid://123008289598540", size = Vector2.new(512, 512) },
	orb_health_fill = { id = "rbxassetid://125390058242273", size = Vector2.new(512, 512) },
	orb_mana_frame = { id = "rbxassetid://112168174760943", size = Vector2.new(512, 512) },
	orb_mana_fill = { id = "rbxassetid://76117262356717", size = Vector2.new(512, 512) },
	-- Rings (Icons_256: centered squares)
	minimap_frame = { id = "rbxassetid://75741502477555", size = Vector2.new(256, 256) },
	ring_gold = { id = "rbxassetid://101733664786827", size = Vector2.new(256, 256) },
	ring_silver = { id = "rbxassetid://107397262650494", size = Vector2.new(256, 256) },
	-- Skill icons (skills/128px)
	skill_storm = { id = "rbxassetid://119358956574948", size = Vector2.new(128, 128) },
	skill_spark = { id = "rbxassetid://78541866026299", size = Vector2.new(128, 128) },
	skill_chain = { id = "rbxassetid://75188928851964", size = Vector2.new(128, 128) },
	skill_nova = { id = "rbxassetid://110139009058803", size = Vector2.new(128, 128) },
	skill_dash = { id = "rbxassetid://125754218329440", size = Vector2.new(128, 128) },
	-- Hub icon bar (assets/ui/icons/*.png, native size)
	menu_inventory = { id = "rbxassetid://84376860245263", size = Vector2.new(376, 380) },
	menu_star_net = { id = "rbxassetid://125186955183258", size = Vector2.new(377, 370) },
	menu_skills = { id = "rbxassetid://89943484818795", size = Vector2.new(445, 379) },
	menu_hub = { id = "rbxassetid://119271064945748", size = Vector2.new(441, 417) }, -- assets/ui/icons/city.png
	menu_atlas = { id = "rbxassetid://104595046752790", size = Vector2.new(416, 362) },
	menu_forge = { id = "rbxassetid://80101622482185", size = Vector2.new(405, 395) },
	menu_shop = { id = "rbxassetid://113985532990245", size = Vector2.new(362, 384) },
	menu_pets = { id = "rbxassetid://77889190601004", size = Vector2.new(400, 396) }, -- assets/ui/icons/pets.png
	-- Daily rewards button (1.0, ROADMAP-1.0 §4.2); no hub bar entry until the feature ships
	menu_daily = { id = "rbxassetid://87505829317379", size = Vector2.new(400, 395) }, -- assets/ui/icons/daily.png
	-- Dash charge diamonds (Icons_256): cyan = charge available, dark = spent
	hud_diamond_cyan = { id = "rbxassetid://101631660350220", size = Vector2.new(256, 256) },
	hud_diamond_dark = { id = "rbxassetid://113509830744033", size = Vector2.new(256, 256) },
	hud_settings = { id = "rbxassetid://96002533781558", size = Vector2.new(373, 368) },
}
local hud: { [string]: Fixed } = {}
for name, h in HUD do
	if h.id ~= "" then
		hud[name] = table.freeze(h)
	end
end
Assets.Hud = table.freeze(hud)

-- Per-class equipment and skill icons (assets/ui/icons/equipment/<Class>, assets/ui/icons/skills/128px/<Class>).
-- Keys: equip_<class>_<slot>, skill_<class>_<nn>_<name> (see Theme.Class).
-- Ids from the Open Cloud upload (tools/upload-manifest.json); entries with an empty id are ignored and the atlas icons are used.
local CLASS: { [string]: Fixed } = {
	equip_mage_amulet = { id = "rbxassetid://125065924404980", size = Vector2.new(350, 398) },
	equip_mage_armor = { id = "rbxassetid://88546356759786", size = Vector2.new(435, 442) },
	equip_mage_belt = { id = "rbxassetid://136413239566372", size = Vector2.new(463, 299) },
	equip_mage_boots = { id = "rbxassetid://71654561936327", size = Vector2.new(421, 392) },
	equip_mage_gloves = { id = "rbxassetid://134129283354820", size = Vector2.new(415, 361) },
	equip_mage_head = { id = "rbxassetid://70711621986135", size = Vector2.new(422, 404) },
	equip_mage_offhand = { id = "rbxassetid://87723442321285", size = Vector2.new(535, 493) },
	equip_mage_ring = { id = "rbxassetid://89704376825245", size = Vector2.new(468, 465) },
	equip_mage_weapon = { id = "rbxassetid://118281350894971", size = Vector2.new(434, 537) },
	equip_mushroom_amulet = { id = "rbxassetid://98788927387712", size = Vector2.new(363, 432) },
	equip_mushroom_armor = { id = "rbxassetid://110507614481058", size = Vector2.new(431, 441) },
	equip_mushroom_belt = { id = "rbxassetid://92920422809515", size = Vector2.new(453, 309) },
	equip_mushroom_boots = { id = "rbxassetid://132859660492209", size = Vector2.new(409, 357) },
	equip_mushroom_gloves = { id = "rbxassetid://127288130512700", size = Vector2.new(397, 373) },
	equip_mushroom_head = { id = "rbxassetid://132761668570268", size = Vector2.new(435, 400) },
	equip_mushroom_offhand = { id = "rbxassetid://109970797209355", size = Vector2.new(431, 450) },
	equip_mushroom_ring = { id = "rbxassetid://79986580971668", size = Vector2.new(462, 453) },
	equip_mushroom_weapon = { id = "rbxassetid://71030802331984", size = Vector2.new(560, 515) },
	equip_ranger_amulet = { id = "rbxassetid://71531343814620", size = Vector2.new(341, 424) },
	equip_ranger_armor = { id = "rbxassetid://136876909534210", size = Vector2.new(477, 425) },
	equip_ranger_belt = { id = "rbxassetid://115301549948112", size = Vector2.new(470, 361) },
	equip_ranger_boots = { id = "rbxassetid://106955056249108", size = Vector2.new(424, 391) },
	equip_ranger_gloves = { id = "rbxassetid://140700089989243", size = Vector2.new(394, 357) },
	equip_ranger_head = { id = "rbxassetid://110523064662289", size = Vector2.new(395, 392) },
	equip_ranger_offhand = { id = "rbxassetid://110403891829235", size = Vector2.new(491, 480) },
	equip_ranger_ring = { id = "rbxassetid://122566908212990", size = Vector2.new(450, 443) },
	equip_ranger_weapon = { id = "rbxassetid://130519774902241", size = Vector2.new(614, 524) },
	equip_warrior_amulet = { id = "rbxassetid://131663837069949", size = Vector2.new(379, 382) },
	equip_warrior_armor = { id = "rbxassetid://121208819353265", size = Vector2.new(524, 454) },
	equip_warrior_belt = { id = "rbxassetid://102200700274450", size = Vector2.new(471, 382) },
	equip_warrior_boots = { id = "rbxassetid://124674053786716", size = Vector2.new(412, 400) },
	equip_warrior_gloves = { id = "rbxassetid://77615257344190", size = Vector2.new(393, 395) },
	equip_warrior_head = { id = "rbxassetid://103177720247932", size = Vector2.new(402, 437) },
	equip_warrior_offhand = { id = "rbxassetid://135179584987585", size = Vector2.new(469, 483) },
	equip_warrior_ring = { id = "rbxassetid://128944551124714", size = Vector2.new(391, 428) },
	equip_warrior_weapon = { id = "rbxassetid://75790849392331", size = Vector2.new(578, 523) },
	skill_ranger_01_crystalarrow = {
		id = "rbxassetid://131295537950494",
		size = Vector2.new(128, 128),
	},
	skill_ranger_02_arrowvolley = {
		id = "rbxassetid://86954073317495",
		size = Vector2.new(128, 128),
	},
	skill_ranger_03_arrowrain = { id = "rbxassetid://74794222341995", size = Vector2.new(128, 128) },
	skill_ranger_04_trap = { id = "rbxassetid://70439174381773", size = Vector2.new(128, 128) },
	skill_ranger_05_poisonarrow = {
		id = "rbxassetid://81324622110411",
		size = Vector2.new(128, 128),
	},
	skill_ranger_06_bladewhirl = {
		id = "rbxassetid://129507514143623",
		size = Vector2.new(128, 128),
	},
	skill_ranger_07_icearrow = { id = "rbxassetid://109380023692342", size = Vector2.new(128, 128) },
	skill_ranger_08_falcon = { id = "rbxassetid://119996703331790", size = Vector2.new(128, 128) },
	skill_ranger_09_sprint = { id = "rbxassetid://85144176896379", size = Vector2.new(128, 128) },
	skill_mushroom_01_mushroomsummon = {
		id = "rbxassetid://136030302445760",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_02_poisoncloud = {
		id = "rbxassetid://99506992064796",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_03_healingmushrooms = {
		id = "rbxassetid://82643503460824",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_04_mushroomtotem = {
		id = "rbxassetid://96198416368508",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_05_graspingvines = {
		id = "rbxassetid://84572335337145",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_06_purplemushrooms = {
		id = "rbxassetid://117935905313645",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_07_sporeburst = {
		id = "rbxassetid://108045065751577",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_08_rootsnare = {
		id = "rbxassetid://125085633449819",
		size = Vector2.new(128, 128),
	},
	skill_mushroom_09_sprint = { id = "rbxassetid://122908955419505", size = Vector2.new(128, 128) },
	skill_mage_01_arcaneorb = { id = "rbxassetid://78541866026299", size = Vector2.new(128, 128) },
	skill_mage_02_chainlightning = {
		id = "rbxassetid://75188928851964",
		size = Vector2.new(128, 128),
	},
	skill_mage_03_icenova = { id = "rbxassetid://110139009058803", size = Vector2.new(128, 128) },
	skill_mage_04_icelance = { id = "rbxassetid://138790665582930", size = Vector2.new(128, 128) },
	skill_mage_05_thunderstorm = {
		id = "rbxassetid://119358956574948",
		size = Vector2.new(128, 128),
	},
	skill_mage_06_firewall = { id = "rbxassetid://93391119960740", size = Vector2.new(128, 128) },
	skill_mage_07_teleport = { id = "rbxassetid://100424727285556", size = Vector2.new(128, 128) },
	skill_mage_08_magicshield = { id = "rbxassetid://82431048331402", size = Vector2.new(128, 128) },
	skill_mage_09_sprint = { id = "rbxassetid://125754218329440", size = Vector2.new(128, 128) },
	skill_warrior_01_shieldbash = {
		id = "rbxassetid://72113908970070",
		size = Vector2.new(128, 128),
	},
	skill_warrior_02_whirlwind = {
		id = "rbxassetid://122449989418230",
		size = Vector2.new(128, 128),
	},
	skill_warrior_03_battlecry = {
		id = "rbxassetid://80352221437294",
		size = Vector2.new(128, 128),
	},
	skill_warrior_04_groundslam = {
		id = "rbxassetid://116325284481174",
		size = Vector2.new(128, 128),
	},
	skill_warrior_05_charge = { id = "rbxassetid://95920873728352", size = Vector2.new(128, 128) },
	skill_warrior_06_taunt = { id = "rbxassetid://132431220958547", size = Vector2.new(128, 128) },
	skill_warrior_07_stonearmor = {
		id = "rbxassetid://94172705395298",
		size = Vector2.new(128, 128),
	},
	skill_warrior_08_swordslash = {
		id = "rbxassetid://120232738581425",
		size = Vector2.new(128, 128),
	},
	skill_warrior_09_sprint = { id = "rbxassetid://126173903836694", size = Vector2.new(128, 128) },
}
local class: { [string]: Fixed } = {}
for name, c in CLASS do
	if c.id ~= "" then
		class[name] = table.freeze(c)
	end
end
Assets.Class = table.freeze(class)

-- Standalone icon images (painted library style, 256x256, assets/ui/icons/store/...).
-- Kit.icon prefers them over the atlas; entries with an empty id are ignored.
local ICON_IMAGE: { [string]: Fixed } = {
	soulstars_s = { id = "rbxassetid://77736787215851", size = Vector2.new(256, 256) },
	soulstars_m = { id = "rbxassetid://95605756220230", size = Vector2.new(256, 256) },
	soulstars_l = { id = "rbxassetid://120495636577171", size = Vector2.new(256, 256) },
	soulstars_xl = { id = "rbxassetid://129298297527669", size = Vector2.new(256, 256) },
	pass_pet_slot = { id = "rbxassetid://113670167155375", size = Vector2.new(256, 256) },
	pass_magnet = { id = "rbxassetid://83134635006465", size = Vector2.new(256, 256) },
	pass_vip = { id = "rbxassetid://137405036075950", size = Vector2.new(256, 256) },
	pack_ember = { id = "rbxassetid://115660814935673", size = Vector2.new(256, 256) },
	starter_pack = { id = "rbxassetid://70917385823543", size = Vector2.new(256, 256) },
}
local iconImage: { [string]: Fixed } = {}
for name, c in ICON_IMAGE do
	if c.id ~= "" then
		iconImage[name] = table.freeze(c)
	end
end
Assets.IconImage = table.freeze(iconImage)

-- Held weapon meshes per class (Shared/Weapons, docs/WEAPONS.md). Paste the ids from
-- assets/ui-asset-ids.csv after the upload: model = "weapon_<id>_model" (Model asset from the FBX),
-- texture = "weapon_<id>_texture" (Image asset from Color.png). Empty = part-built fallback.
Assets.Weapon = table.freeze({
	warrior_sword = table.freeze({
		model = "rbxassetid://93287839309680",
		texture = "rbxassetid://130914505484937",
	}),
	ranger_bow = table.freeze({
		model = "rbxassetid://137257012727377",
		texture = "rbxassetid://80404162491006",
	}),
	mage_staff = table.freeze({
		model = "rbxassetid://122366270633643",
		texture = "rbxassetid://122658965398935",
	}),
	druid_scepter = table.freeze({
		model = "rbxassetid://100336404154752",
		texture = "rbxassetid://106110248003359",
	}),
} :: { [string]: { model: string, texture: string } })

-- World VFX textures (assets/vfx/*.png, upload keys "vfx_<name>"), e.g. Trail.Texture of the
-- cosmetic trails (Shared/Cosmetics `texture`). Paste the ids from assets/ui-asset-ids.csv after the
-- upload. Empty = the effect keeps its flat color look.
Assets.Vfx = table.freeze({
	trail_gilded = "rbxassetid://112657872833926",
	trail_ember = "rbxassetid://97154003089217",
	trail_frost = "rbxassetid://133044313718164",
	trail_void = "rbxassetid://137876026395589",
} :: { [string]: string })

-- Robux glyph (Roblox built-in texture). Empty string = the shop writes "R$" instead.
Assets.Robux = "rbxasset://textures/ui/common/robux.png"

return table.freeze(Assets)
