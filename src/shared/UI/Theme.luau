--!strict
-- Loot Rush UI theme: the Luau version of tools/lr_ui_kit.py.
-- ONLY source for colors, sizes, fonts and icons in the game.
-- Rules: dark, minimalist, sparing accents (gold = important, cyan = magic/progress),
-- icons instead of text, the same building blocks everywhere.

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local Theme = {}

Theme.Color = table.freeze({
	Bg0 = hex("#07091A"), -- app background
	Bg1 = hex("#0C1024"), -- Panel
	Bg2 = hex("#121734"), -- slot / raised surface
	Bg3 = hex("#19204A"), -- active
	Line = hex("#1E2550"),
	Line2 = hex("#2C3668"),
	Text = hex("#E8EBFA"),
	Muted = hex("#8C93B8"),
	Gold = hex("#E8B04A"),
	GoldHi = hex("#FFD86B"), -- gradient top (primary button)
	GoldLo = hex("#E09A2E"), -- gradient bottom
	Cyan = hex("#4FD8F5"),
	Danger = hex("#E8505A"),
	Good = hex("#7FD96A"),
	Life = hex("#D93A4A"),
	Mana = hex("#3E8EF0"),
})

Theme.Rarity = table.freeze({
	normal = hex("#A9AFC8"),
	magic = hex("#5FA8FF"),
	rare = hex("#E8C04A"),
	epic = hex("#B98CFF"),
	unique = hex("#FF9A4A"),
	legend = hex("#7FE8C0"),
})

-- Design resolution of the mockups. The HUD is scaled to it via UIScale.
Theme.DesignSize = Vector2.new(1600, 900)
-- HUD on touch devices: smaller design area so the bar, status and minimap are as large as in
-- the mobile mock-up (tablet ≈ 1.0, phone 844×390 ≈ 0.63 instead of 0.55).
Theme.HudDesignTouch = Vector2.new(1100, 620)

-- Font size: the screen is scaled down to 1600×900, small windows make text tiny.
-- All text therefore goes through Kit.label / Kit.fontSize and is enlarged by this factor.
Theme.FontScale = 1.25

-- Drop shadow for text and icons (Kit.label / Kit.shadowed): text gets a thin dark outline, icons a
-- dark copy of themselves offset down-right by Offset (fraction of the icon size).
Theme.Shadow = table.freeze({
	Color = Color3.new(0, 0, 0),
	Transparency = 0.45, -- icon shadow
	Offset = 0.05,
	TextThickness = 1,
	TextTransparency = 0.35,
})

-- Per-class equipment and skill art (keys of Assets.Class, built by Kit.equipIcon / Kit.skillIcon).
-- The game has no class data yet: everyone is the Default class. Switching classes on later only needs
-- Kit.playerClass to return another name.
Theme.Class = table.freeze({
	Default = "Mage",
	-- Game item slot -> file slot name (Mage_<Slot>.png)
	EquipSlot = table.freeze({
		helmet = "head",
		armor = "armor",
		weapon = "weapon",
		amulet = "amulet",
		ring = "ring",
	} :: { [string]: string }),
	-- Skill id -> "<nn>_<name>" of the class skill icon; shared by every class by position
	SkillSlot = table.freeze({
		basic = 1,
		spark_ball = 1,
		chain_lightning = 2,
		frost_nova = 3,
		thunderstorm = 5,
		dash = 9,
	} :: { [string]: number }),
	-- Position -> icon name per class (assets/ui/icons/skills/Index.csv)
	SkillName = table.freeze({
		mage = {
			"arcaneorb",
			"chainlightning",
			"icenova",
			"icelance",
			"thunderstorm",
			"firewall",
			"teleport",
			"magicshield",
			"sprint",
		},
		mushroom = {
			"mushroomsummon",
			"poisoncloud",
			"healingmushrooms",
			"mushroomtotem",
			"graspingvines",
			"purplemushrooms",
			"sporeburst",
			"rootsnare",
			"sprint",
		},
		ranger = {
			"crystalarrow",
			"arrowvolley",
			"arrowrain",
			"trap",
			"poisonarrow",
			"bladewhirl",
			"icearrow",
			"falcon",
			"sprint",
		},
		warrior = {
			"shieldbash",
			"whirlwind",
			"battlecry",
			"groundslam",
			"charge",
			"taunt",
			"stonearmor",
			"swordslash",
			"sprint",
		},
	} :: { [string]: { string } }),
})

Theme.Radius = table.freeze({ S = 8, M = 12, L = 18 })
Theme.Stroke = 1

-- Roblox has no Cinzel; Merriweather is the closest built-in title font.
Theme.Font = table.freeze({
	Title = Font.fromName("Merriweather", Enum.FontWeight.Bold),
	UI = Font.fromName("Nunito", Enum.FontWeight.ExtraBold),
	Body = Font.fromName("Nunito", Enum.FontWeight.Bold),
})

-- Images (9-slice frames, slots, icons) live in Shared.UI.Assets.

-- HUD layout (design pixels, see Kit.scaledGui) and image keys of the in-game HUD.
Theme.Hud = table.freeze({
	Margin = 16, -- distance to the (safe-area) screen edge
	OrbSize = 132, -- health / experience orb incl. metal frame
	OrbTop = 0.228, -- liquid area inside the 512px orb canvas (fraction of the height)
	OrbBottom = 0.77,
	OrbGap = 4,
	SkillSize = 66,
	DashSize = 124,
	SkillArc = 150, -- distance dash center -> skill centers
	SkillAngles = table.freeze({ 180, 150, 120, 90 }), -- degrees, 180 = left of dash, 90 = above it
	GearSize = 48,
	BarIcon = 64, -- hub icon bar: icon edge
	BarCaption = 16,
	BarGap = 8,
	RingCyan = Color3.fromRGB(150, 215, 255), -- tint of the silver ring for skill buttons
	DashDiamond = 20, -- dash charge diamond edge
	Veil = 0.35, -- cooldown veil transparency
	-- Skill id (Shared.Skills) -> Assets.Hud key; without an image the atlas icon of the skill is used
	SkillArt = table.freeze({
		thunderstorm = "skill_storm",
		spark_ball = "skill_spark",
		chain_lightning = "skill_chain",
		frost_nova = "skill_nova",
	} :: { [string]: string }),
	-- Hub icon bar: menu id, Assets.Hud key, atlas fallback icon, caption
	Bar = table.freeze({
		{ id = "inventory", art = "menu_inventory", icon = "inventory", caption = "Inventory" },
		{ id = "star_net", art = "menu_star_net", icon = "star_net", caption = "Stars" },
		{ id = "skills", art = "menu_skills", icon = "skills", caption = "Skills" },
		{ id = "hub", art = "menu_hub", icon = "hub", caption = "Hub" },
		{ id = "atlas", art = "menu_atlas", icon = "atlas", caption = "Atlas" },
		{ id = "forge", art = "menu_forge", icon = "forge", caption = "Forge" },
		{ id = "shop", art = "menu_shop", icon = "pouch", caption = "Shop" },
	}),
})

-- Minimap terrain view (client/UI/MiniMapView): a top-down ViewportFrame with a light copy of the
-- ground and props around the player.
Theme.MiniMap = table.freeze({
	Range = 70, -- studs from the center to the edge of the map
	Fov = 28, -- narrow field of view from high up = nearly orthographic
	PartCap = 340, -- most parts in the viewport at any time (~240 visible ground cells + props)
	GroundShare = 0.8, -- share of PartCap that ground top slabs may use (nearest first)
	PartHz = 4, -- how often the part set is refreshed
	ViewHz = 15, -- camera + dots refresh rate
	ClonesPerRefresh = 40, -- new copies per part refresh (spreads the cost)
	ClonesBurst = 180, -- new copies per refresh while the map is mostly empty (teleport / first load)
	MinPartSize = 1.5, -- studs (Size.Magnitude); smaller parts are skipped
	MaxAbove = 100, -- ignore parts higher than this above the player (sky, ceilings)
	MaxBelow = 60,
	Ambient = Color3.fromRGB(170, 172, 190),
	Light = Color3.fromRGB(255, 242, 220),
	Tint = 0.78, -- transparency of the dark tint over the terrain (pulls it into the UI palette)
})

-- Animation vocabulary: the same motions everywhere
Theme.Tween = table.freeze({
	FlyIn = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	FlyOut = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In),
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bar = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
})
Theme.Stagger = 0.06 -- seconds of offset between panels flying in

return table.freeze(Theme)
