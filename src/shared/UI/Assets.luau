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
	gold_chest = "chest", -- gold chest offers (atlas fallback for Assets.IconImage)
	buff_damage = "G22", -- crossed swords medallion
	buff_armor = "G12", -- shield medallion
	buff_haste = "G23", -- winged boot medallion
	buff_shield = "G33", -- hex shield medallion
	leaderboard = "F41", -- golden podium
	shards_big = "J34", -- crystal shard (market card)
	candy_big = "J41", -- Forge Candy (market card)
	dust_big = "J42", -- glitter bottle (market card)
	-- Atlas fallbacks for Assets.IconImage entries (shown until the image is uploaded)
	soulstars_s = "soulstar",
	soulstars_m = "soulstar",
	soulstars_l = "soulstar",
	soulstars_xl = "soulstar",
	starter_pack = "chest",
	season_beta = "crown",
	journey = "quest",
	great_build = "hub", -- Great Build monument (window, milestones, Builder Aura)
	buff_chill = "ice",
	buff_rush = "fire",
	stone_linger = "skills",
	stone_pierce = "skills",
	stone_split = "skills",
	stone_link = "skills",
	stone_echo = "skills",
	stone_ember = "skills",
	stone_wide = "skills",
	stone_haste = "skills",
	stone_power = "skills",
	pet_star_cat = "companion",
	pet_cloud_whale = "companion",
	pet_rune_dragon = "companion",
	egg_meadow = "companion",
	egg_star = "companion",
	pet_crystal_beetle = "companion",
	pet_firefly = "companion",
	pet_moss_frog = "companion",
	trail_ember = "fire",
	trail_void = "portal",
	aura_void = "whirl",
	pack_void = "portal",
	pack_frost = "ice",
	pack_ember = "fire",
	pass_vip = "crown",
	pass_magnet = "chest",
	pass_pet_slot = "companion",
}
for name, code in ICON_ALIAS do
	icon[name] = icon[code]
end
Assets.Icon = table.freeze(icon)

-- Scene images and nodes of the Abilities, Star Web, Forge, Atlas and Shop windows
-- (upload package LootRush_Upload_v8_Fenster). Entries without an ID are ignored; the windows
-- then show the flat style (nodes as slots, lines as thin strokes).
local ART: { [string]: Fixed } = {
	-- Window backgrounds and the forge anvil are retired (docs/ART-STYLE.md): empty id = plain
	-- Gilded Ink graphite background like every other window.
	bg_skills = { id = "", size = Vector2.new(1024, 576) },
	bg_starnet = { id = "", size = Vector2.new(1024, 576) },
	bg_forge = { id = "", size = Vector2.new(1024, 576) },
	bg_atlas = { id = "", size = Vector2.new(1024, 576) },
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
	forge_anvil = { id = "", size = Vector2.new(1000, 536) },
	island_green_plains = { id = "rbxassetid://105645223665871", size = Vector2.new(494, 489) },
	island_crystal_caves = { id = "rbxassetid://70766805869187", size = Vector2.new(484, 489) },
	island_mushroom_swamp = { id = "rbxassetid://84661071441944", size = Vector2.new(510, 496) },
	island_fire_desert = { id = "rbxassetid://115654270158828", size = Vector2.new(500, 502) },
	island_sky_islands = { id = "rbxassetid://73005692141420", size = Vector2.new(484, 512) },
	island_altered_world = { id = "rbxassetid://91049121021436", size = Vector2.new(509, 505) },
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
	skill_storm = { id = "rbxassetid://75878339554775", size = Vector2.new(128, 128) },
	skill_spark = { id = "rbxassetid://130582316644560", size = Vector2.new(128, 128) },
	skill_chain = { id = "rbxassetid://98732456791700", size = Vector2.new(128, 128) },
	skill_nova = { id = "rbxassetid://117336520590202", size = Vector2.new(128, 128) },
	skill_dash = { id = "rbxassetid://77220099605869", size = Vector2.new(128, 128) },
	-- Hub icon bar (assets/ui/icons/*.png, native size)
	menu_inventory = { id = "rbxassetid://84136238176131", size = Vector2.new(383, 400) },
	menu_star_net = { id = "rbxassetid://136756846212342", size = Vector2.new(389, 400) },
	menu_skills = { id = "rbxassetid://117271248256066", size = Vector2.new(394, 400) },
	menu_hub = { id = "rbxassetid://93459009336607", size = Vector2.new(367, 400) }, -- assets/ui/icons/city.png
	menu_atlas = { id = "rbxassetid://78423416722635", size = Vector2.new(400, 395) },
	menu_forge = { id = "rbxassetid://81445057582388", size = Vector2.new(392, 400) },
	menu_shop = { id = "rbxassetid://100688622296241", size = Vector2.new(360, 400) },
	menu_pets = { id = "rbxassetid://77889190601004", size = Vector2.new(400, 396) }, -- assets/ui/icons/pets.png
	-- Daily rewards button (1.0, docs/ROADMAP.md §4.2); no hub bar entry until the feature ships
	menu_daily = { id = "rbxassetid://87505829317379", size = Vector2.new(400, 395) }, -- assets/ui/icons/daily.png
	-- Dash charge diamonds (Icons_256): cyan = charge available, dark = spent
	hud_diamond_cyan = { id = "rbxassetid://101631660350220", size = Vector2.new(256, 256) },
	hud_diamond_dark = { id = "rbxassetid://113509830744033", size = Vector2.new(256, 256) },
	hud_settings = { id = "rbxassetid://128673325472229", size = Vector2.new(399, 400) },
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
	equip_mage_amulet = { id = "rbxassetid://121726684258208", size = Vector2.new(349, 420) },
	equip_mage_armor = { id = "rbxassetid://114342027595152", size = Vector2.new(415, 411) },
	equip_mage_belt = { id = "rbxassetid://114515965701962", size = Vector2.new(383, 346) },
	equip_mage_boots = { id = "rbxassetid://96578885578505", size = Vector2.new(386, 369) },
	equip_mage_gloves = { id = "rbxassetid://84972623750116", size = Vector2.new(410, 355) },
	equip_mage_head = { id = "rbxassetid://129982199542182", size = Vector2.new(388, 405) },
	equip_mage_offhand = { id = "rbxassetid://111792689072767", size = Vector2.new(436, 421) },
	equip_mage_ring = { id = "rbxassetid://116967409376591", size = Vector2.new(345, 347) },
	equip_mage_weapon = { id = "rbxassetid://104093834457068", size = Vector2.new(378, 431) },
	equip_mushroom_amulet = { id = "rbxassetid://80300797364029", size = Vector2.new(339, 413) },
	equip_mushroom_armor = { id = "rbxassetid://125523562301879", size = Vector2.new(389, 402) },
	equip_mushroom_belt = { id = "rbxassetid://113293819629686", size = Vector2.new(390, 325) },
	equip_mushroom_boots = { id = "rbxassetid://81220051702207", size = Vector2.new(382, 366) },
	equip_mushroom_gloves = { id = "rbxassetid://107913780044013", size = Vector2.new(405, 359) },
	equip_mushroom_head = { id = "rbxassetid://116728155472441", size = Vector2.new(378, 401) },
	equip_mushroom_offhand = { id = "rbxassetid://116271018814156", size = Vector2.new(334, 418) },
	equip_mushroom_ring = { id = "rbxassetid://81940984863763", size = Vector2.new(326, 341) },
	equip_mushroom_weapon = { id = "rbxassetid://81732633448009", size = Vector2.new(352, 428) },
	equip_ranger_amulet = { id = "rbxassetid://134983177543974", size = Vector2.new(340, 432) },
	equip_ranger_armor = { id = "rbxassetid://103354532896255", size = Vector2.new(397, 408) },
	equip_ranger_belt = { id = "rbxassetid://99256984267695", size = Vector2.new(392, 328) },
	equip_ranger_boots = { id = "rbxassetid://91060668183898", size = Vector2.new(393, 371) },
	equip_ranger_gloves = { id = "rbxassetid://131611921419159", size = Vector2.new(399, 335) },
	equip_ranger_head = { id = "rbxassetid://117063825877076", size = Vector2.new(383, 415) },
	equip_ranger_offhand = { id = "rbxassetid://79747572253371", size = Vector2.new(353, 435) },
	equip_ranger_ring = { id = "rbxassetid://106995992458510", size = Vector2.new(383, 337) },
	equip_ranger_weapon = { id = "rbxassetid://136886008072498", size = Vector2.new(361, 431) },
	equip_warrior_amulet = { id = "rbxassetid://125945787831575", size = Vector2.new(327, 403) },
	equip_warrior_armor = { id = "rbxassetid://139604112560146", size = Vector2.new(398, 387) },
	equip_warrior_belt = { id = "rbxassetid://75980643415330", size = Vector2.new(378, 331) },
	equip_warrior_boots = { id = "rbxassetid://78309660389639", size = Vector2.new(378, 368) },
	equip_warrior_gloves = { id = "rbxassetid://73648802625756", size = Vector2.new(407, 335) },
	equip_warrior_head = { id = "rbxassetid://126737764875177", size = Vector2.new(357, 401) },
	equip_warrior_offhand = { id = "rbxassetid://133364123221042", size = Vector2.new(379, 400) },
	equip_warrior_ring = { id = "rbxassetid://81208666362815", size = Vector2.new(340, 352) },
	equip_warrior_weapon = { id = "rbxassetid://130340517267174", size = Vector2.new(352, 405) },
	skill_ranger_01_crystalarrow = {
		id = "rbxassetid://113815952953153",
		size = Vector2.new(128, 128),
	},
	skill_ranger_02_arrowvolley = {
		id = "rbxassetid://108151338345031",
		size = Vector2.new(128, 128),
	},
	skill_ranger_03_arrowrain = { id = "rbxassetid://74794222341995", size = Vector2.new(128, 128) },
	skill_ranger_04_trap = { id = "rbxassetid://70439174381773", size = Vector2.new(128, 128) },
	skill_ranger_05_poisonarrow = {
		id = "rbxassetid://83461055307624",
		size = Vector2.new(128, 128),
	},
	skill_ranger_06_bladewhirl = {
		id = "rbxassetid://129507514143623",
		size = Vector2.new(128, 128),
	},
	skill_ranger_07_icearrow = { id = "rbxassetid://134964824717920", size = Vector2.new(128, 128) },
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
	skill_mage_01_arcaneorb = { id = "rbxassetid://130582316644560", size = Vector2.new(128, 128) },
	skill_mage_02_chainlightning = {
		id = "rbxassetid://98732456791700",
		size = Vector2.new(128, 128),
	},
	skill_mage_03_icenova = { id = "rbxassetid://117336520590202", size = Vector2.new(128, 128) },
	skill_mage_04_icelance = { id = "rbxassetid://81362094115269", size = Vector2.new(128, 128) },
	skill_mage_05_thunderstorm = {
		id = "rbxassetid://75878339554775",
		size = Vector2.new(128, 128),
	},
	skill_mage_06_firewall = { id = "rbxassetid://105868487177402", size = Vector2.new(128, 128) },
	skill_mage_07_teleport = { id = "rbxassetid://97292414283224", size = Vector2.new(128, 128) },
	skill_mage_08_magicshield = {
		id = "rbxassetid://100541780096434",
		size = Vector2.new(128, 128),
	},
	skill_mage_09_sprint = { id = "rbxassetid://77220099605869", size = Vector2.new(128, 128) },
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
	pack_frost = { id = "rbxassetid://116112442841872", size = Vector2.new(256, 256) },
	pack_void = { id = "rbxassetid://128183713220709", size = Vector2.new(256, 256) },
	aura_void = { id = "rbxassetid://133312664956652", size = Vector2.new(256, 256) },
	trail_void = { id = "rbxassetid://138884461442290", size = Vector2.new(256, 256) },
	trail_ember = { id = "rbxassetid://134456301548595", size = Vector2.new(256, 256) },
	pet_moss_frog = { id = "rbxassetid://91835194884455", size = Vector2.new(256, 256) },
	pet_firefly = { id = "rbxassetid://117562730191418", size = Vector2.new(256, 256) },
	pet_crystal_beetle = { id = "rbxassetid://104285913069347", size = Vector2.new(256, 256) },
	egg_star = { id = "rbxassetid://139181643847245", size = Vector2.new(256, 256) },
	egg_meadow = { id = "rbxassetid://118770581048716", size = Vector2.new(256, 256) },
	pet_rune_dragon = { id = "rbxassetid://71892848625435", size = Vector2.new(256, 256) },
	pet_cloud_whale = { id = "rbxassetid://91016394026850", size = Vector2.new(256, 256) },
	pet_star_cat = { id = "rbxassetid://99095033077221", size = Vector2.new(256, 256) },
	stone_power = { id = "rbxassetid://94466576394855", size = Vector2.new(256, 256) },
	stone_haste = { id = "rbxassetid://82739987339715", size = Vector2.new(256, 256) },
	stone_wide = { id = "rbxassetid://87007390341297", size = Vector2.new(256, 256) },
	stone_ember = { id = "rbxassetid://83737751991291", size = Vector2.new(256, 256) },
	stone_echo = { id = "rbxassetid://96035592482365", size = Vector2.new(256, 256) },
	stone_link = { id = "rbxassetid://70783158014608", size = Vector2.new(256, 256) },
	stone_split = { id = "rbxassetid://96214412535886", size = Vector2.new(256, 256) },
	stone_pierce = { id = "rbxassetid://115531785353837", size = Vector2.new(256, 256) },
	stone_linger = { id = "rbxassetid://129916315129701", size = Vector2.new(256, 256) },
	buff_rush = { id = "rbxassetid://92423849788133", size = Vector2.new(256, 256) },
	buff_chill = { id = "rbxassetid://78368102043367", size = Vector2.new(256, 256) },
	journey = { id = "rbxassetid://109061225455736", size = Vector2.new(256, 256) },
	season_beta = { id = "rbxassetid://122505326588873", size = Vector2.new(256, 256) },
	starter_pack = { id = "rbxassetid://70917385823543", size = Vector2.new(256, 256) },
	gold_sack = { id = "rbxassetid://82439314099624", size = Vector2.new(256, 256) },
	gold_chest = { id = "rbxassetid://108113113496575", size = Vector2.new(256, 256) },
	gold_hoard = { id = "rbxassetid://72677119328880", size = Vector2.new(256, 256) },
	-- Bag cell "not an upgrade" marker (Flat.cell): red arrow down, recolor of the "upgrade" arrow
	downgrade = { id = "rbxassetid://131358976671714", size = Vector2.new(256, 256) },
}
local iconImage: { [string]: Fixed } = {}
for name, c in ICON_IMAGE do
	if c.id ~= "" then
		iconImage[name] = table.freeze(c)
	end
end
Assets.IconImage = table.freeze(iconImage)

-- Held weapon meshes per class (Shared/Weapons, docs/TECH.md "Weapons"). Paste the ids from
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

-- World VFX textures (assets/vfx/*.png, upload keys "vfx_<name>"): Trail.Texture of the cosmetic
-- trails, ParticleEmitter.Texture of the cosmetic auras (Shared/Cosmetics `texture`) and of the prop
-- and region particles (Kit.vfx). Names in VfxSheet are 2x2 flipbook sheets. Paste the ids from
-- assets/ui-asset-ids.csv after the upload. Empty = the effect keeps its flat/default look.
Assets.Vfx = table.freeze({
	trail_gilded = "rbxassetid://112657872833926",
	trail_ember = "rbxassetid://97154003089217",
	trail_frost = "rbxassetid://133044313718164",
	trail_void = "rbxassetid://137876026395589",
	aura_ember = "rbxassetid://111783282797514",
	aura_frost = "rbxassetid://103713482351017",
	aura_void = "rbxassetid://126053245986660",
	smoke_puff = "rbxassetid://119535922672364",
	spark = "rbxassetid://90015374638811",
	mote_stud = "rbxassetid://114608632708045",
} :: { [string]: string })
Assets.VfxSheet = table.freeze({
	aura_ember = true,
	aura_frost = true,
	aura_void = true,
	smoke_puff = true,
	spark = true,
} :: { [string]: boolean })

-- Robux glyph (Roblox built-in texture). Empty string = the shop writes "R$" instead.
Assets.Robux = "rbxasset://textures/ui/common/robux.png"

return table.freeze(Assets)
