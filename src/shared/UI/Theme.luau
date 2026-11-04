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
	-- Look v5 "gilded ink": near-black graphite with a cold hint, warm white text, ONE main accent
	-- (gold = action / important) and one secondary (rift cyan = magic / progress).
	Bg0 = hex("#07080D"), -- app background
	Bg1 = hex("#0D0F17"), -- Panel
	Bg2 = hex("#141722"), -- slot / raised surface
	Bg3 = hex("#1C2030"), -- active
	Line = hex("#232838"),
	Line2 = hex("#343A50"),
	Text = hex("#F2EEE4"), -- warm white, easier on the eyes than pure blue-white
	Muted = hex("#9B98A6"),
	Gold = hex("#EBB54A"),
	GoldHi = hex("#FFDC7E"), -- gradient top (primary button)
	GoldLo = hex("#C07E22"), -- gradient bottom
	Cyan = hex("#58E1F0"),
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
-- Tablets (shorter side at least TabletMinSide points) get a larger design area, so the HUD,
-- quest card and result cards do not blow up past phone proportions (iPad 1180×820 ≈ 0.84).
Theme.HudDesignTablet = Vector2.new(1400, 860)
Theme.TabletMinSide = 600

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
		gloves = "gloves",
		belt = "belt",
		boots = "boots",
		weapon = "weapon",
		offhand = "offhand",
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

-- Floating damage numbers: normal hit and crit tiers (tier 1 = crit, 2 = double, 3+ = triple and up)
Theme.Damage = table.freeze({
	NormalSize = 24,
	Tiers = table.freeze({
		table.freeze({ size = 36, color = hex("#E8B04A"), suffix = "!", pop = 1 }),
		table.freeze({ size = 46, color = hex("#FF8A2A"), suffix = "!!", pop = 1.25 }),
		table.freeze({ size = 54, color = hex("#FF3B30"), suffix = "!!!", pop = 1.4 }),
	}),
	Rise = 4, -- studs the number floats up
	PopTime = 0.12, -- seconds of the pop-in scale tween
})

Theme.Radius = table.freeze({ S = 2, M = 3, L = 4 })
Theme.Stroke = 1

-- Type hierarchy (Look v5): a tall condensed display face for titles and numbers, a geometric sans
-- for UI labels and body text. No rounded "friendly" face: it made every window look generic.
--   Title  = window titles, headings (uppercase)        Oswald Bold
--   UI     = buttons, tabs, labels                      Montserrat Bold
--   Body   = descriptions, captions                     Montserrat Medium
--   Number = currencies, stats, damage, counters        Oswald SemiBold
Theme.Font = table.freeze({
	Title = Font.fromName("Oswald", Enum.FontWeight.Bold),
	UI = Font.fromName("Montserrat", Enum.FontWeight.Bold),
	Body = Font.fromName("Montserrat", Enum.FontWeight.Medium),
	Number = Font.fromName("Oswald", Enum.FontWeight.SemiBold),
})

-- Spacing scale (design pixels): every gap/padding should be one of these
Theme.Space = table.freeze({ XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 })

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
	-- Touch (phone / tablet): bigger skill and dash buttons, the arc widens so they never touch
	SkillSizeTouch = 86,
	DashSizeTouch = 136,
	SkillArcTouch = 180,
	SkillPad = 16, -- room around the skill arc for glow and touch growth (the group clips)
	XpBar = 6, -- experience bar along the bottom edge of the screen
	GearSize = 48,
	NoticeDot = 14, -- dot on an icon button (daily reward waits, upgrade in the bag)
	BarIcon = 64, -- hub icon bar: icon edge
	BarCaption = 16,
	BarGap = 8,
	DockPad = 12, -- inner padding of the dock plate behind the hub icon bar
	RingCyan = Color3.fromRGB(150, 215, 255), -- tint of the silver ring for skill buttons
	DashDiamond = 20, -- dash charge diamond edge
	Veil = 0.35, -- cooldown veil transparency
	BuffSize = 40, -- buff/debuff bar: icon cell edge
	BuffTime = 14, -- height of the seconds under a buff cell
	RushBarWidth = 268, -- Stud Rush meter incl. caption and value (= orb row width)
	RushBarHeight = 12,
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
		{ id = "star_net", art = "menu_star_net", icon = "star_net", caption = "Star Web" },
		{ id = "skills", art = "menu_skills", icon = "skills", caption = "Skills" },
		{ id = "hub", art = "menu_hub", icon = "hub", caption = "Hub" },
		{ id = "atlas", art = "menu_atlas", icon = "atlas", caption = "Atlas" },
		{ id = "forge", art = "menu_forge", icon = "forge", caption = "Forge" },
		{ id = "pets", art = "menu_pets", icon = "companion", caption = "Pets" },
		{ id = "shop", art = "menu_shop", icon = "pouch", caption = "Shop" },
	}),
})

-- Minimap terrain view (client/UI/MiniMapView): a top-down ViewportFrame with a light copy of the
-- ground and props around the player.
Theme.MiniMap = table.freeze({
	Range = 70, -- studs from the center to the edge of the map
	Fov = 28, -- narrow field of view from high up = nearly orthographic
	PartCap = 360, -- most parts in the viewport at any time (~270 ground cells and stair steps + props)
	GroundShare = 0.85, -- share of PartCap that ground top slabs may use (nearest first)
	PartCapTouch = 220, -- phones / tablets: fewer parts, the viewport renders much cheaper
	PartCapLow = 140, -- effects quality "low" (settings window)
	RefreshMove = 6, -- studs walked before the part set is refreshed again
	RefreshMax = 2, -- seconds: refresh at least this often while standing (doors, moving parts)
	ViewHz = 15, -- camera + dots refresh rate
	ViewMove = 0.1, -- studs / radians: smaller camera changes are skipped (no viewport re-render)
	ClonesPerRefresh = 30, -- new copies per part refresh (spreads the cost)
	ClonesBurst = 180, -- new copies per refresh while the map is mostly empty (teleport / first load)
	MinPartSize = 1.5, -- studs (Size.Magnitude); smaller parts are skipped
	MaxAbove = 100, -- ignore parts higher than this above the player (sky, ceilings)
	MaxBelow = 60,
	Ambient = Color3.fromRGB(170, 172, 190),
	Light = Color3.fromRGB(255, 242, 220),
	Tint = 0.78, -- transparency of the dark tint over the terrain (pulls it into the UI palette)
})

-- Flat look (v4, from 2026-11): no drawn frames, buttons or slots. Every surface is a Roblox
-- shape (Frame + UICorner/UIStroke/UIGradient); only the item/skill icons are images.
-- Built by client/UI/Flat, animated by client/UI/Spring. Windows move over to this one by one.
Theme.Flat = table.freeze({
	-- Surfaces from back to front (window, card, cell, hover/raised)
	Surface0 = hex("#08090F"),
	Surface1 = hex("#0F1119"),
	Surface2 = hex("#161925"),
	Surface3 = hex("#202434"),
	Edge = hex("#2A2F42"), -- hairline around cards and cells
	EdgeHi = hex("#4A5170"), -- hovered / focused edge
	Faint = hex("#5E6278"), -- tertiary text, empty slot icons
	Scrim = 0.25, -- transparency of the dark layer behind a window (the world stays readable)
	CardTransparency = 0.04,
	-- Light instead of shadows: surfaces are lit from above (gradient top -> bottom) and carry a thin
	-- bright line along the top edge; the bottom edge is darker.
	LightLift = 0.07, -- how much brighter the top of a surface is (Color3:Lerp toward white)
	TopLine = 0.86, -- transparency of the 1 px highlight along the top edge
	SheenTransparency = 0.92, -- (kept for old callers)
	-- Sharp, cut shapes instead of uniform round cards
	Radius = table.freeze({ S = 2, M = 3, L = 4, Pill = 999 }),
	Stroke = 1.25,
	SelectStroke = 2.5,
	-- Corner brackets: L-shaped accents on two opposite corners of panels (asymmetric detail)
	Bracket = table.freeze({ Size = 14, Thick = 2, MinPanel = 140, Transparency = 0.15 }),
	-- Accent rule under titles: gold line that fades out to the right, with a small diamond
	Accent = table.freeze({ Height = 2, Diamond = 7 }),
	-- Rarity glow: halo rings outside the cell edge (thickness, transparency) and its behavior.
	-- pulse = halo breathes; spin = the edge carries a rotating highlight; shine = light sweep.
	Halo = table.freeze({
		table.freeze({ 2, 0.55 }),
		table.freeze({ 5, 0.8 }),
		table.freeze({ 10, 0.92 }),
	}),
	Glow = table.freeze({
		normal = table.freeze({ halo = 0, tint = 0.94, pulse = false, spin = false, shine = false }),
		magic = table.freeze({ halo = 1, tint = 0.84, pulse = false, spin = false, shine = false }),
		rare = table.freeze({ halo = 2, tint = 0.78, pulse = true, spin = false, shine = false }),
		epic = table.freeze({ halo = 3, tint = 0.72, pulse = true, spin = true, shine = true }),
		unique = table.freeze({ halo = 3, tint = 0.7, pulse = true, spin = true, shine = true }),
		legend = table.freeze({ halo = 3, tint = 0.7, pulse = true, spin = true, shine = true }),
	} :: {
		[string]: { halo: number, tint: number, pulse: boolean, spin: boolean, shine: boolean },
	}),
	PulseSpeed = 2.2, -- radians per second of the halo breathing
	PulseDepth = 0.12, -- transparency swing of the halo
	SpinSpeed = 90, -- degrees per second of the rotating edge highlight
	-- Light sweep across primary buttons and top-rarity items: a bright band crosses the shape every
	-- Period seconds (each shape has its own phase), Duration = time of one crossing.
	Shine = table.freeze({ Period = 4.5, Duration = 0.75, Peak = 0.55, Angle = 25 }),
	-- Press ripple: circle from the touch point, grows to Grow x the button width and fades
	Ripple = table.freeze({ Time = 0.45, Start = 0.7, Grow = 2.4 }),
	-- Blur of the world behind fullscreen windows (Lighting BlurEffect)
	Blur = table.freeze({ Size = 14, Time = 0.22 }),
	-- Number ticker (currencies, rewards): counts toward the new value
	Tick = table.freeze({ Time = 0.5 }),
	-- Springs: speed = angular frequency (rad/s), damping 1 = no overshoot, < 1 = bounce
	Spring = table.freeze({
		Snappy = table.freeze({ speed = 30, damping = 0.8 }),
		Soft = table.freeze({ speed = 16, damping = 1 }),
		Bouncy = table.freeze({ speed = 22, damping = 0.55 }),
	}),
	HoverScale = 1.04,
	PressScale = 0.94,
	SelectScale = 1.04,
	OpenScale = 0.96, -- window starts this small and springs to 1
	OpenDrop = 18, -- and this many design pixels lower
	MaxFit = 1.25, -- windows grow up to this factor to fill small screens
})

-- Robux Shop (client/Controllers/StoreController): badges, hero banner, celebration
Theme.Store = table.freeze({
	Badge = table.freeze({
		best = hex("#7FD96A"),
		limited = hex("#E8505A"),
		popular = hex("#EBB54A"),
		new = hex("#58E1F0"),
	} :: { [string]: Color3 }),
	BadgeText = hex("#08090F"),
	HeroTop = hex("#3B1E5C"), -- hero banner gradient (deep violet → ink)
	HeroBottom = hex("#120C1E"),
	Robux = hex("#F2EEE4"), -- tint of the Robux glyph on the gold buy button (multiplied)
	Owned = hex("#7FD96A"),
	CardH = 410,
	Gap = 28,
	HeroH = 340,
	TopH = 80, -- tab row
	ButtonH = 80,
	ArtSize = 112, -- icon on a card
	HeroArt = 190,
	Rays = 12, -- light rays behind featured art
	RaySpin = 14, -- degrees per second
	Bob = 6, -- design pixels the card art floats up and down
	BobSpeed = 2.4, -- radians per second
	BadgePulse = 0.06, -- scale swing of "Limited" badges
	HoverLift = 1.025, -- card scale under the mouse
	Burst = 28, -- stud confetti pieces on a purchase
	CelebrateTime = 3.2, -- seconds the purchase celebration stays (tap closes it sooner)
})

-- Animation vocabulary: the same motions everywhere
Theme.Tween = table.freeze({
	FlyIn = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	FlyOut = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In),
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bar = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
})
Theme.Stagger = 0.06 -- seconds of offset between panels flying in

-- Tutorial callouts (client/UI/Callout, HintsController): a card next to the button it explains and
-- a pulsing ring around that button. Sizes in HUD design px (the callout layer scales like the HUD).
Theme.Callout = table.freeze({
	Width = 300, -- card width
	WidthTouch = 340, -- phones: a little wider, the text is bigger there
	Pad = 14,
	Gap = 18, -- between the target and the card
	Margin = 12, -- min distance to the screen edge
	TitleSize = 20,
	BodySize = 16,
	BodySizeTouch = 18,
	FootSize = 12,
	Ring = 10, -- the pulse ring is this much larger than the target on each side
	RingStroke = 3,
	RingGrow = 1.18, -- pulse: ring scale at the peak
	PulseTime = 0.55, -- seconds per half pulse
	Pointer = 16, -- the little diamond that points at the target
	PopTime = 0.22,
})

-- World nameplates (client/NameplateController, Shared/Nameplate): BillboardGuis in screen px, times
-- the HUD size setting. Player: name + level over a thin life bar (shield = cyan strip on top).
-- Station: uppercase label with a gold diamond; the active quest's station is gold and larger.
Theme.Nameplate = table.freeze({
	Width = 150, -- player plate
	NameSize = 15,
	LevelSize = 13,
	BarWidth = 92,
	BarHeight = 7,
	OwnBarWidth = 64, -- local player's plate: bar only, a bit smaller
	OwnBarHeight = 6,
	ShieldHeight = 3, -- cyan strip on top of the life bar
	BarBack = 0.25, -- background transparency of the bar track
	LowLife = 0.3, -- below this fill the bar flashes brighter
	LabelWidth = 220,
	LabelSize = 18,
	LabelSizeQuest = 22, -- the station the quest waypoint points to
	SubSize = 12, -- "Locked · Clear depth 5" under a locked station
	Stroke = 0.15, -- text outline transparency
	Rule = 2, -- gold rule under a station label (px)
	TouchScale = 1.15, -- phones: a little larger
})

return table.freeze(Theme)
