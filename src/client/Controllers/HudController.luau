--!strict
-- Combat HUD after the style reference (assets/style_reference):
--   In combat: life orb (bottom center), four round skills in an arc around the dash button (bottom
--   right, bigger on touch screens), compass minimap (top right), resources (top center).
--   At rest: the orbs and skills leave, the icon bar (bottom center), settings gear and quests fly
--   in. The dash button and the minimap stay. Rifts are entered from the Atlas only.
--   Always: buff/debuff bar + Stud Rush meter above the orbs / icon bar (bottom center), experience
--   bar along the bottom edge with the level at its left end.
--   While a menu window is open, a copy of the icon bar sits on top of it (LootRushMenuDock), so
--   every menu can be reached from any other; the open one is marked.
-- Combat/rest comes from the server (player attribute "InCombat").
-- Everything is laid out inside the device safe area (Kit.scaledGui safeArea).

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local Spring = require(script.Parent.Parent.UI.Spring)
local QuestRules = require(ReplicatedStorage.Shared.Quests)
local MiniMapView = require(script.Parent.Parent.UI.MiniMapView)
local CameraController = require(script.Parent.CameraController)
local DashController = require(script.Parent.DashController)
local RushController = require(script.Parent.RushController)
local StatusRules = require(ReplicatedStorage.Shared.Status)
local SkillController = require(script.Parent.SkillController)
local InventoryController = require(script.Parent.InventoryController)
local RiftController = require(script.Parent.RiftController)
local WaypointController = require(script.Parent.WaypointController)
local AbilitiesController = require(script.Parent.AbilitiesController)
local StarNetController = require(script.Parent.StarNetController)
local ForgeController = require(script.Parent.ForgeController)
local AtlasController = require(script.Parent.AtlasController)
local MarketController = require(script.Parent.MarketController)
local StoreController = require(script.Parent.StoreController)
local PetWindowController = require(script.Parent.PetWindowController)
local SeasonController = require(script.Parent.SeasonController)
local QuestController = require(script.Parent.QuestController)
local ProgressController = require(script.Parent.ProgressController)
local SettingsController = require(script.Parent.SettingsController)
local DailyController = require(script.Parent.DailyController)
local JourneyController = require(script.Parent.JourneyController)
local LeaderboardController = require(script.Parent.LeaderboardController)
local Prefs = require(script.Parent.Parent.Prefs)

local HudController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local H = Theme.Hud

type Fly = {
	group: CanvasGroup,
	home: UDim2,
	away: UDim2,
	order: number,
	combat: boolean, -- true = visible in combat, false = visible at rest
	tween: Tween?,
}

-- Hub bar buttons -> windows / actions
local MENU_ACTION: { [string]: () -> () } = {
	inventory = InventoryController.toggle,
	star_net = StarNetController.toggle,
	skills = AbilitiesController.toggle,
	forge = ForgeController.toggle,
	atlas = AtlasController.toggle,
	shop = StoreController.toggle, -- the Robux Shop (the Market is in the Hub)
	pets = PetWindowController.toggle,
	-- "Hub": back to the hub while in a Rift (there is nothing to do when already there)
	hub = function()
		RiftController.leave()
	end,
}

local flies: { Fly } = {}
local flyVersion = 0
local hudGui: ScreenGui
local root: Frame

-- ------------------------------------------------------------------ Build helpers
local function place(obj: GuiObject, anchor: Vector2, pos: UDim2)
	obj.AnchorPoint = anchor
	obj.Position = pos
	obj.Parent = root
end

local function addFly(
	g: CanvasGroup,
	anchor: Vector2,
	home: UDim2,
	away: UDim2,
	order: number,
	combat: boolean
)
	place(g, anchor, home)
	table.insert(
		flies,
		{ group = g, home = home, away = away, order = order, combat = combat, tween = nil }
	)
end

-- Transparent group (one fade for all children); clips its content to its size
local function group(size: Vector2): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Size = UDim2.fromOffset(size.X, size.Y)
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	return g
end

local function clearGroup(size: Vector2): CanvasGroup
	local g = group(size)
	g.AutomaticSize = Enum.AutomaticSize.XY -- grows along when buttons get bigger on touch
	return g
end

-- Fixed-fit image from Assets.Art; flat fallback without an image
local function ring(parent: GuiObject, size: number)
	local img = Window.art("node_ring", Vector2.new(size, size))
	if img then
		img.ZIndex = 1
		img.Parent = parent
	else
		-- Flat ring: transparent center, gold rim with a soft glow
		local f = Instance.new("Frame")
		f.Name = "Ring"
		f.Size = UDim2.fromOffset(size, size)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.ZIndex = 3
		Kit.corner(f, size // 2)
		Kit.stroke(f, C.Gold, 2.5)
		Shape.glow(f, C.Gold, 2, false, size // 2)
		f.Parent = parent
	end
end

-- Plaque (plaque_region) with text; flat capsule without an image
local function plaque(parent: GuiObject, size: Vector2, textSize: number): TextLabel
	local f = Instance.new("Frame")
	f.Name = "Plaque"
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundTransparency = 1
	f.ZIndex = 3
	local img = Window.art("plaque_region", size)
	if img then
		img.ScaleType = Enum.ScaleType.Stretch
		img.ZIndex = 3
		img.Parent = f
	else
		f.BackgroundColor3 = Theme.Flat.Surface1
		f.BackgroundTransparency = 0.1
		Kit.corner(f, Theme.Flat.Radius.M)
		Kit.stroke(f, C.Gold, 1.5)
		Shape.topLine(f)
		Shape.brackets(f, C.GoldHi, 8, 0)
	end
	local t = Kit.label("", textSize, C.GoldHi)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.fromScale(1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.ZIndex = 4
	t.Parent = f
	f.Parent = parent
	return t
end

-- Trigger on press (not on release) for combat responsiveness; works for click and touch
local function onTap(slot: GuiObject, fn: () -> ())
	slot.Active = true
	slot.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			fn()
		end
	end)
end

-- Small caption label above an orb (kept inside the group bounds)
local function orbCaption(parent: GuiObject, x: number, color: Color3): TextLabel
	local t = Kit.label("", 11, color)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.fromOffset(x, 0)
	t.Size = UDim2.fromOffset(H.OrbSize, H.BarCaption)
	t.TextXAlignment = Enum.TextXAlignment.Center
	Kit.textOutline(t, 0.35)
	t.Parent = parent
	return t
end

-- ------------------------------------------------------------------ Life orb (bottom center, combat)
-- Red orb = life (number inside, shield above it). Experience is the thin bar along the bottom edge.
local lifeOrb: Kit.Orb
local shieldText: TextLabel
local lifeHumanoid: Humanoid? = nil

local function buildOrbs()
	local cap = H.BarCaption
	local g = group(Vector2.new(H.OrbSize, H.OrbSize + cap))
	g.Name = "Orbs"

	lifeOrb = Kit.orb(H.OrbSize, "health", C.Life)
	lifeOrb.root.Position = UDim2.fromOffset(0, cap)
	lifeOrb.root.Parent = g
	shieldText = orbCaption(g, H.OrbSize // 2, C.Cyan)
	shieldText.Name = "Shield"

	addFly(
		g,
		Vector2.new(0.5, 1),
		UDim2.new(0.5, 0, 1, -H.Margin),
		UDim2.new(0.5, 0, 1, H.OrbSize + 80),
		1,
		true
	)
end

-- ------------------------------------------------------------------ Experience bar (bottom edge)
-- Full-width thin bar on the bottom edge of the safe area, level + XP in a small chip at its left end.
local xpFill: Frame
local xpTip: Frame
local xpText: TextLabel
local xpChip: Frame

local function buildXpBar()
	local bar = Instance.new("Frame")
	bar.Name = "XpBar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, H.XpBar)
	bar.BackgroundColor3 = Theme.Flat.Surface0
	bar.BackgroundTransparency = 0.35
	bar.BorderSizePixel = 0
	bar.Active = false
	bar.Parent = root
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	Shape.gradient(fill, C.Cyan, C.Mana, 0, 0, 0)
	fill.Parent = bar
	xpFill = fill
	-- Bright tip at the end of the fill
	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(1, 0.5)
	tip.Position = UDim2.fromScale(1, 0.5)
	tip.Size = UDim2.new(0, 3, 1, 0)
	tip.BackgroundColor3 = C.Text
	tip.BorderSizePixel = 0
	tip.Parent = fill
	xpTip = tip

	local chip = Instance.new("Frame")
	chip.Name = "XpChip"
	chip.AnchorPoint = Vector2.new(0, 1)
	chip.Position = UDim2.new(0, 8, 1, -H.XpBar - 2)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, 18)
	chip.BackgroundColor3 = Theme.Flat.Surface1
	chip.BackgroundTransparency = 0.2
	chip.BorderSizePixel = 0
	Kit.corner(chip, Theme.Flat.Radius.S)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = chip
	xpText = Kit.label("", 11, C.Text)
	xpText.Name = "Xp"
	xpText.AnchorPoint = Vector2.new(0, 0.5)
	xpText.Position = UDim2.fromScale(0, 0.5)
	xpText.Parent = chip
	chip.Parent = root
	xpChip = chip
end

local function refreshShield()
	local shield = player:GetAttribute("Shield")
	local amount = if typeof(shield) == "number" then shield else 0
	local max = if lifeHumanoid then lifeHumanoid.MaxHealth else 0
	if amount > 0 and max > 0 then
		shieldText.Text = "+" .. Format.int(amount) .. " Shield"
	else
		shieldText.Text = ""
	end
end

local function bindHumanoid(humanoid: Humanoid)
	lifeHumanoid = humanoid
	local function refresh()
		local ratio = if humanoid.MaxHealth > 0
			then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			else 0
		lifeOrb.setRatio(ratio)
		lifeOrb.text.Text = Format.int(humanoid.Health)
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshShield)
	refresh()
	refreshShield()
end

-- ------------------------------------------------------------------ Minimap (top right)
-- Compass ring (minimap_frame image has the "N" built in) around a top-down view of the real terrain
-- (MiniMapView), enemy dots and the player arrow on top; below it a plaque with the location.
local mapFrame: Frame
local mapPlace: TextLabel
local dots: { Frame } = {}
local MAP_SIZE = 156
local MAP_RANGE = Theme.MiniMap.Range -- studs from the center to the edge
local mapView: MiniMapView.View
local mapBox: Frame -- whole minimap incl. the place plaque ("Minimap" setting hides it)
local mapInner = 0.4 -- radius of the map area inside the ring (fraction of the width)
local mapQuest: Frame -- quest waypoint marker (WaypointController), held at the rim when far

local function buildMinimap()
	local box = Instance.new("Frame")
	box.Name = "Minimap"
	mapBox = box
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE + 18)
	place(box, Vector2.new(1, 0), UDim2.new(1, -H.Margin, 0, 10))

	mapFrame = Instance.new("Frame")
	mapFrame.Name = "Map"
	mapFrame.BackgroundTransparency = 1
	mapFrame.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE)
	mapFrame.Parent = box

	-- Dark disc behind the dots so they stay readable on any ground
	local frameImg = Kit.hudImage("minimap_frame", Vector2.new(MAP_SIZE, MAP_SIZE))
	local discSize = if frameImg then 0.66 else 0.97
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(MAP_SIZE * discSize, MAP_SIZE * discSize)
	disc.BackgroundColor3 = C.Bg0
	disc.BackgroundTransparency = 0.45
	disc.BorderSizePixel = 0
	Kit.corner(disc, MAP_SIZE)
	disc.Parent = mapFrame

	if frameImg then
		mapInner = 0.33
		frameImg.ZIndex = 3
		frameImg.Parent = mapFrame
	else
		-- The map fills the whole circle up to the gold rim; "N" sits on the map at the top
		mapInner = 0.485
		ring(mapFrame, MAP_SIZE)
		local north = Kit.label("N", 14, C.GoldHi, Theme.Font.Title)
		north.AnchorPoint = Vector2.new(0.5, 0)
		north.Position = UDim2.new(0.5, 0, 0, 6)
		Kit.textOutline(north, 0.15)
		north.ZIndex = 4
		north.Parent = mapFrame
	end

	-- Terrain: round view exactly as large as the map area (MAP_RANGE studs from the center to the edge)
	mapView = MiniMapView.new()
	local terrain: GuiObject = mapView.root
	terrain.AnchorPoint = Vector2.new(0.5, 0.5)
	terrain.Position = UDim2.fromScale(0.5, 0.5)
	terrain.Size = UDim2.fromOffset(MAP_SIZE * mapInner * 2, MAP_SIZE * mapInner * 2)
	terrain.ZIndex = 1
	terrain.Parent = mapFrame

	-- Player arrow in the center (the map turns with the camera, so it always points up)
	local me = Kit.label("▲", 16, C.GoldHi)
	me.Name = "Me"
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromScale(0.5, 0.5)
	me.ZIndex = 2
	me.Parent = mapFrame

	-- Quest waypoint: a gold diamond, pulsing, at the rim when the station is out of range
	mapQuest = Instance.new("Frame")
	mapQuest.Name = "Quest"
	mapQuest.AnchorPoint = Vector2.new(0.5, 0.5)
	mapQuest.Size = UDim2.fromOffset(11, 11)
	mapQuest.Rotation = 45
	mapQuest.BackgroundColor3 = C.GoldHi
	mapQuest.BorderSizePixel = 0
	mapQuest.ZIndex = 3
	mapQuest.Visible = false
	local edge = Instance.new("UIStroke")
	edge.Color = C.Bg0
	edge.Thickness = 1.5
	edge.Parent = mapQuest
	mapQuest.Parent = mapFrame

	local plate = Instance.new("Frame")
	plate.Name = "Place"
	plate.BackgroundTransparency = 1
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.fromScale(0.5, 1)
	plate.Size = UDim2.fromOffset(136, 32)
	plate.Parent = box
	mapPlace = plaque(plate, Vector2.new(136, 32), 11)
end

-- Location below the minimap: in a Rift the area + depth, otherwise the Hub
local function refreshPlace()
	local region = player:GetAttribute("RiftRegion")
	local info = if typeof(region) == "string" then Atlas.ById[region] else nil
	if info and RiftController.active() then
		local depth = player:GetAttribute("RiftDepth")
		mapPlace.Text = info.name .. (if typeof(depth) == "number" then " - D" .. depth else "")
	else
		mapPlace.Text = "Lumenhaven"
	end
end

local function dot(i: number): Frame
	local existing = dots[i]
	if existing then
		return existing
	end
	local d = Instance.new("Frame")
	d.Size = UDim2.fromOffset(8, 8)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.BackgroundColor3 = C.Life
	d.BorderSizePixel = 0
	d.ZIndex = 2
	Kit.corner(d, 4)
	d.Parent = mapFrame
	dots[i] = d
	return d
end

local function updateMinimap()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local used = 0
	if rootPart and rootPart:IsA("BasePart") then
		local yaw = CameraController.getYaw()
		local cosY, sinY = math.cos(yaw), math.sin(yaw)
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsA("Model") then
				local d = enemy:GetPivot().Position - rootPart.Position
				-- rotate to camera orientation: top of the map = viewing direction
				local x = d.X * cosY - d.Z * sinY
				local z = d.X * sinY + d.Z * cosY
				if x * x + z * z < MAP_RANGE * MAP_RANGE then -- round, matching the ring
					used += 1
					local dd = dot(used)
					dd.Visible = true
					dd.Position = UDim2.fromScale(
						0.5 + x / MAP_RANGE * mapInner,
						0.5 + z / MAP_RANGE * mapInner
					)
				end
			end
		end
	end
	for i = used + 1, #dots do
		dots[i].Visible = false
	end
	local goal = WaypointController.target()
	if goal and rootPart and rootPart:IsA("BasePart") then
		local yaw = CameraController.getYaw()
		local d = goal - rootPart.Position
		local x = d.X * math.cos(yaw) - d.Z * math.sin(yaw)
		local z = d.X * math.sin(yaw) + d.Z * math.cos(yaw)
		local r = math.sqrt(x * x + z * z) / MAP_RANGE
		if r > 0.92 then -- clamp to the rim
			x, z = x / r * 0.92, z / r * 0.92
		end
		mapQuest.Visible = true
		mapQuest.Position =
			UDim2.fromScale(0.5 + x / MAP_RANGE * mapInner, 0.5 + z / MAP_RANGE * mapInner)
		local pulse = 11 + 3 * math.sin(os.clock() * 5)
		mapQuest.Size = UDim2.fromOffset(pulse, pulse)
	else
		mapQuest.Visible = false
	end
end

-- ------------------------------------------------------------------ Skills + dash (bottom right)
-- Dash = big gold-ringed button in the corner (always there), the four skills sit on a quarter arc
-- around it (combat only).
local updateDashPips: (available: number, max: number) -> ()
local skillVeils: { (number, number) -> () } = {}
local skillButtons: { ImageButton } = {}
local shownSkills: { string } = {} -- art key (or skill id) per slot that is on the button now
local SLOT_KEYS = { "Q", "E", "R", "F" }
local dashButton: ImageButton
local shownDash = ""
local dashSize = H.DashSize -- touch screens use the bigger size (set in buildSkills)

-- Loadout or class changed: new icons (skill art and the sprint icon depend on the class)
local function refreshSkillButtons()
	for i, btn in skillButtons do
		local skill = SkillController.skill(i)
		if skill then
			local art = Kit.skillArt(skill.id) or H.SkillArt[skill.id]
			local key = skill.id .. "|" .. (art or "")
			if shownSkills[i] ~= key then
				shownSkills[i] = key
				Kit.setRoundIcon(btn, art, skill.icon)
			end
		end
	end
	local dashArt = Kit.skillArt("dash") or "skill_dash"
	if dashButton and shownDash ~= dashArt then
		shownDash = dashArt
		Kit.setRoundIcon(dashButton, dashArt, "skill_dash")
	end
end

local function buildSkills()
	local touch = UserInputService.TouchEnabled
	local keyboard = not touch
	local S = if touch then H.SkillSizeTouch else H.SkillSize
	local D = if touch then H.DashSizeTouch else H.DashSize
	local R = if touch then H.SkillArcTouch else H.SkillArc
	local M, P = H.Margin, H.SkillPad
	dashSize = D

	-- Dash (sprint icon of the own class, see refreshSkillButtons)
	shownDash = Kit.skillArt("dash") or "skill_dash"
	local dash =
		Kit.roundButton(D, "gold", shownDash, "skill_dash", if keyboard then "Space" else nil)
	dash.Name = "Dash"
	dashButton = dash
	onTap(dash, DashController.dash)
	-- Sprint art of the played class (each class has its own); the class arrives after the HUD
	player:GetAttributeChangedSignal("Class"):Connect(function()
		Kit.setRoundIcon(dash, Kit.skillArt("dash") or "skill_dash", "skill_dash")
	end)
	-- One diamond per maximum charge above the button: cyan = available, dark = spent
	local pips, setPips = Kit.chargePips(H.DashDiamond)
	pips.AnchorPoint = Vector2.new(0.5, 0.5)
	pips.Position = UDim2.fromScale(0.5, 0.04)
	pips.ZIndex = 7
	pips.Parent = dash
	updateDashPips = setPips
	place(dash, Vector2.new(1, 1), UDim2.new(1, -M, 1, -M))

	-- Skill arc: the group's bottom right corner sits S/2 + P beyond the dash center. P keeps the
	-- glow and the touch growth of the outer buttons inside the group (a CanvasGroup clips)
	local side = R + S + 2 * P
	local arc = group(Vector2.new(side, side))
	arc.Name = "Skills"
	local cx, cy = P + R + S / 2, P + R + S / 2 -- dash center inside the group
	for i, skill in Skills.bar do
		local angle = math.rad(H.SkillAngles[i] or 90)
		local btn, update = Kit.roundButton(
			S,
			"cyan",
			Kit.skillArt(skill.id) or H.SkillArt[skill.id],
			skill.icon,
			if keyboard then SLOT_KEYS[i] else nil
		)
		btn.Name = "Skill" .. i
		shownSkills[i] = skill.id .. "|" .. (Kit.skillArt(skill.id) or H.SkillArt[skill.id] or "")
		skillButtons[i] = btn
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromOffset(cx + R * math.cos(angle), cy - R * math.sin(angle))
		onTap(btn, function()
			SkillController.cast(i)
		end)
		skillVeils[i] = update
		btn.Parent = arc
	end
	local inset = M + D / 2 - S / 2 - P
	addFly(
		arc,
		Vector2.new(1, 1),
		UDim2.new(1, -inset, 1, -inset),
		UDim2.new(1, -inset + side, 1, -inset + side),
		2,
		true
	)
end

-- ------------------------------------------------------------------ Status (bottom center)
-- Buff/debuff bar (Shared/Status, attributes Status_<id>) with the Stud Rush meter under it. The
-- Rush starts on its own when the meter is full (Systems/Rush); the bar then drains with the Rush
-- time. It sits above the orbs (combat) and the icon bar (rest), clear of joystick and skills.
type BuffCell = {
	root: Frame,
	veil: Frame,
	time: TextLabel,
	stacks: TextLabel,
	scale: UIScale,
	total: number, -- full length from the server (StatusFrom_<id>), for the veil and the Rush meter
}
local buffRow: Frame
local buffCells: { [string]: BuffCell } = {}
local rushBox: Frame
local rushFill: Frame
local rushText: TextLabel
local rushStroke: UIStroke
local rushShown = 0 -- displayed fill, eases toward the real value

local function buffCell(def: StatusRules.Def): BuffCell
	local B = H.BuffSize
	local color = if def.debuff then C.Life else C.Gold
	local cell = Instance.new("Frame")
	cell.Name = "Buff_" .. def.id
	cell.BackgroundTransparency = 1
	cell.Size = UDim2.fromOffset(B, B + H.BuffTime)
	cell.LayoutOrder = def.order
	local scale = Instance.new("UIScale")
	scale.Parent = cell

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromOffset(B, B)
	box.BackgroundColor3 = Theme.Flat.Surface1
	box.BackgroundTransparency = 0.15
	box.ClipsDescendants = true
	Kit.corner(box, Theme.Flat.Radius.S)
	Kit.stroke(box, color, 1.5)
	box.Parent = cell
	local icon = Kit.icon(def.icon, B - 8, color)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = box
	-- Dark veil from the top = time already spent
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.BackgroundColor3 = C.Bg0
	veil.BackgroundTransparency = H.Veil
	veil.BorderSizePixel = 0
	veil.Size = UDim2.fromScale(1, 0)
	veil.ZIndex = 3
	veil.Parent = box

	local stacks = Kit.label("", 11, C.Text)
	stacks.Name = "Stacks"
	stacks.AnchorPoint = Vector2.new(1, 0)
	stacks.Position = UDim2.new(1, -2, 0, 0)
	stacks.ZIndex = 4
	Kit.textOutline(stacks, 0.2)
	stacks.Parent = box

	local time = Kit.label("", 11, if def.debuff then C.Life else C.Text)
	time.Name = "Time"
	time.AutomaticSize = Enum.AutomaticSize.None
	time.AnchorPoint = Vector2.new(0.5, 1)
	time.Position = UDim2.fromScale(0.5, 1)
	time.Size = UDim2.fromOffset(B + 8, H.BuffTime)
	time.TextXAlignment = Enum.TextXAlignment.Center
	Kit.textOutline(time, 0.3)
	time.Parent = cell

	-- Tap / click: what it does
	onTap(box, function()
		QuestController.toast(def.name .. " - " .. def.text, color)
	end)
	cell.Parent = buffRow
	scale.Scale = 0.4
	Spring.target(scale, { Scale = 1 }, "Bouncy")
	return {
		root = cell,
		veil = veil,
		time = time,
		stacks = stacks,
		scale = scale,
		total = 0,
	}
end

local function buildStatus()
	local B, W = H.BuffSize, H.RushBarWidth
	local orbsH = H.OrbSize + H.BarCaption
	local barH = H.BarIcon + H.BarCaption + H.DockPad + math.floor(H.DockPad / 2)
	local box = Instance.new("Frame")
	box.Name = "Status"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(W, B + H.BuffTime + 6 + H.RushBarHeight + 10)
	Kit.list(box, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Bottom)
	place(box, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -(H.Margin + math.max(orbsH, barH) + 8)))

	buffRow = Instance.new("Frame")
	buffRow.Name = "Buffs"
	buffRow.BackgroundTransparency = 1
	buffRow.Size = UDim2.fromOffset(W, B + H.BuffTime)
	buffRow.LayoutOrder = 1
	Kit.list(buffRow, Enum.FillDirection.Horizontal, 6, Enum.VerticalAlignment.Bottom)
	buffRow.Parent = box

	-- Rush meter: caption left, bar, value right ("64%" while filling, "6.2s" while rushing)
	rushBox = Instance.new("Frame")
	rushBox.Name = "RushMeter"
	rushBox.BackgroundTransparency = 1
	rushBox.Size = UDim2.fromOffset(W, H.RushBarHeight + 10)
	rushBox.LayoutOrder = 2
	rushBox.Visible = false
	rushBox.Parent = box
	local caption = Kit.label("RUSH", 12, C.GoldHi, Theme.Font.Title)
	caption.AnchorPoint = Vector2.new(0, 0.5)
	caption.Position = UDim2.fromScale(0, 0.5)
	Kit.textOutline(caption, 0.3)
	caption.Parent = rushBox
	local back, fill = Kit.bar(Vector2.new(W - 96, H.RushBarHeight), C.Gold)
	back.Name = "Bar"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Parent = rushBox
	fill.Size = UDim2.fromScale(0, 1)
	rushFill = fill
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Ready"
	stroke.Color = C.GoldHi
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = back
	rushStroke = stroke
	rushText = Kit.label("", 12, C.Text)
	rushText.Name = "Value"
	rushText.AnchorPoint = Vector2.new(1, 0.5)
	rushText.Position = UDim2.fromScale(1, 0.5)
	Kit.textOutline(rushText, 0.3)
	rushText.Parent = rushBox
end

local function seconds(left: number): string
	if left >= 3600 then
		return string.format("%dh", math.ceil(left / 3600)) -- long global buffs (Great Build)
	elseif left >= 600 then
		return string.format("%dm", math.ceil(left / 60))
	end
	return if left >= 10
		then string.format("%ds", math.ceil(left))
		else string.format("%.1fs", left)
end

-- Buff cells: 10 times a second (GetAttributes makes a table)
local function updateBuffs()
	local active = StatusRules.active(player:GetAttributes(), workspace:GetServerTimeNow())
	local seen: { [string]: boolean } = {}
	for _, a in active do
		local id = a.def.id
		seen[id] = true
		local cell = buffCells[id]
		if not cell then
			cell = buffCell(a.def)
			buffCells[id] = cell
		end
		cell.total = a.total
		cell.veil.Size =
			UDim2.fromScale(1, 1 - math.clamp(a.left / math.max(cell.total, 0.01), 0, 1))
		cell.time.Text = seconds(a.left)
		cell.stacks.Text = if a.stacks > 1 then "×" .. a.stacks else ""
	end
	for id, cell in buffCells do
		if not seen[id] then
			cell.root:Destroy()
			buffCells[id] = nil
		end
	end
end

-- Rush meter: every frame (eased fill, pulse while rushing)
local function updateRushMeter(dt: number)
	local left = RushController.remaining()
	local rushing = left > 0
	rushBox.Visible = rushing or RiftController.active()
	if not rushBox.Visible then
		rushShown = 0
		return
	end
	local total = buffCells.rush and buffCells.rush.total or 0
	local goal = if rushing
		then math.clamp(left / math.max(total, left, 0.01), 0, 1)
		else RushController.meter()
	rushShown += (goal - rushShown) * math.min(1, dt * 10)
	rushFill.Size = UDim2.fromScale(math.clamp(rushShown, 0, 1), 1)
	if rushing then
		rushText.Text = seconds(left)
		rushText.TextColor3 = C.GoldHi
		rushStroke.Transparency = 0.35 + 0.35 * math.sin(os.clock() * 8)
	else
		rushText.Text = math.floor(RushController.meter() * 100) .. "%"
		rushText.TextColor3 = C.Text
		rushStroke.Transparency = 1
	end
end

-- ------------------------------------------------------------------ Rest panels (fly in)
local goldText: TextLabel
local shardText: TextLabel
local starText: TextLabel
local resGroup: CanvasGroup
local resList: UIListLayout
local questGroup: CanvasGroup
local resScale: UIScale -- shrinks the capsule row so it fits between the Roblox buttons and the minimap
local hubBar: CanvasGroup
local hubBarW = 0
local hubBarH = 0
local hubBarScale: UIScale -- shrinks the hub icon bar so it stays clear of the dash button
local gearGroup: CanvasGroup
local gearW = 0
local GEAR_CELLS = 5 -- trophy, Journey, season, chest, gear
local GEAR_MIN_SCALE = 0.7 -- smallest share the row may shrink to next to the status block
local gearScale: UIScale
local questTitle: TextLabel
local questCount: TextLabel
local questReward: TextLabel
local barButtons: { { id: string, button: ImageButton } } = {}
local RES_WIDTH = 620 -- three capsules with spacing

-- Small notice dot in the top right corner of an icon button (daily reward waits, upgrade waits)
local function noticeDot(parent: GuiObject, name: string, color: Color3): Frame
	local d = Instance.new("Frame")
	d.Name = name
	d.AnchorPoint = Vector2.new(1, 0)
	d.Position = UDim2.new(1, -4, 0, 2)
	d.Size = UDim2.fromOffset(H.NoticeDot, H.NoticeDot)
	d.BackgroundColor3 = color
	d.BorderSizePixel = 0
	d.ZIndex = 4
	d.Visible = false
	Kit.corner(d, math.floor(H.NoticeDot / 2))
	Kit.stroke(d, C.Bg0, 2)
	d.Parent = parent
	return d
end

-- Red dot on every Inventory button (hub bar and menu dock) while an upgrade waits in the bag
local upgradeDots: { Frame } = {}
local function refreshUpgradeDots()
	local on = InventoryController.upgradeWaiting()
	for _, d in upgradeDots do
		d.Visible = on
	end
end

-- Icon bar (dock with one button per menu). Used by the hub bar and by the menu dock over windows.
local function buildBar(): (CanvasGroup, number)
	local cellW = H.BarIcon + 12
	local barW = #H.Bar * cellW + (#H.Bar - 1) * H.BarGap + 2 * H.DockPad
	local barH = H.BarIcon + H.BarCaption + H.DockPad + math.floor(H.DockPad / 2)
	local bar = group(Vector2.new(barW, barH))
	local barRow = Kit.dock(bar, H.DockPad)
	Kit.list(barRow, Enum.FillDirection.Horizontal, H.BarGap)
	for i, entry in H.Bar do
		local b = Kit.hudIconButton(H.BarIcon, entry.art, entry.icon, entry.caption)
		b.Name = entry.id
		b.LayoutOrder = i
		if entry.id == "inventory" then
			table.insert(upgradeDots, noticeDot(b, "Upgrade", C.Danger))
		end
		local open = MENU_ACTION[entry.id]
		if open then
			local id = entry.id
			b.Activated:Connect(function()
				local hint = QuestController.lockHint(id)
				if hint then
					QuestController.toast("Locked - " .. hint, C.Muted)
					return
				end
				open()
			end)
		end
		b.Parent = barRow
		table.insert(barButtons, { id = entry.id, button = b })
	end
	return bar, barH
end

-- ------------------------------------------------------------------ Menu dock (over open windows)
-- Own ScreenGui above every fullscreen window, shown only while one is open: tap another icon to
-- switch menus directly. The open menu's icon gets a gold marker; windows end above the dock
-- (Window.setReserve).
local WINDOW_OF: { [string]: string } = { -- bar id -> Window name / Window.exclusive name
	inventory = "Inventory",
	star_net = "StarNet",
	skills = "Abilities",
	forge = "Forge",
	atlas = "Atlas",
	pets = "Pets",
	shop = "Shop",
}
local NO_DOCK: { [string]: boolean } = {
	Class = true, -- first-join class picker: no way out
	Settings = true, -- settings window: full screen, closes back to the game
}
local menuGui: ScreenGui
local menuMarks: { [string]: Frame } = {}
local menuShown: string? = nil
local menuBarH = 0
local menuScale: UIScale
local menuBar: CanvasGroup
local menuList: UIListLayout
local menuBarW = 0
local menuVertical: boolean? = nil
-- Phones (short screens): the dock stands as a smaller icon column at the left edge, where the
-- windows have room to spare, instead of taking height from them at the bottom
local PHONE_HEIGHT = 500 -- screen points
local PHONE_DOCK = 0.72
local PHONE_GAP = 2

local function buildMenuDock()
	local gui, r = Kit.scaledGui("LootRushMenuDock", 7, false, Kit.hudDesign, true)
	gui.Enabled = false
	menuGui = gui
	for name in NO_DOCK do
		Window.exempt(name) -- no dock there, so no room kept for it either
	end
	local first = #barButtons
	local bar, barH = buildBar()
	bar.Name = "MenuDock"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -H.Margin)
	bar.Parent = r
	menuBar = bar
	menuBarH = barH
	menuBarW = bar.Size.X.Offset
	local row = bar:FindFirstChild("Row")
	menuList = (row and row:FindFirstChildOfClass("UIListLayout")) :: UIListLayout
	menuScale = Instance.new("UIScale")
	menuScale.Parent = bar
	for i = first + 1, #barButtons do
		local entry = barButtons[i]
		local mark = Instance.new("Frame")
		mark.Name = "Open"
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.new(0.5, 0, 0, H.BarIcon / 2)
		mark.Size = UDim2.fromOffset(H.BarIcon + 8, H.BarIcon + 8)
		mark.BackgroundColor3 = C.Gold
		mark.BackgroundTransparency = 0.82
		mark.BorderSizePixel = 0
		mark.ZIndex = 1
		mark.Visible = false
		Kit.corner(mark, Theme.Flat.Radius.L)
		Kit.stroke(mark, C.GoldHi, 2)
		mark.Parent = entry.button
		menuMarks[entry.id] = mark
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Every frame (cheap): show the dock while a window is open, move the marker to the open one
local function updateMenuDock()
	local name = Window.openName()
	local show = name ~= nil and not NO_DOCK[name :: string]
	if menuGui.Enabled ~= show then
		menuGui.Enabled = show
	end
	-- The whole HUD steps back while a fullscreen window is open: its minimap, quest card and XP
	-- chip would otherwise show through the window's scrim next to its close button and title
	-- (the dock above takes over the navigation)
	if hudGui.Enabled ~= (name == nil) then
		hudGui.Enabled = name == nil
	end
	-- The coin bar would show through behind window titles: hidden while any window is open
	-- (windows that spend currency show their own wallet)
	local res = if resList then resList.Parent :: GuiObject? else nil
	if res and res.Visible ~= (name == nil) then
		res.Visible = name == nil
	end
	if name ~= menuShown then
		menuShown = name
		for id, mark in menuMarks do
			mark.Visible = name ~= nil and WINDOW_OF[id] == name
		end
	end
end

local function buildCalmPanels()
	-- Resources at the top center (stays visible in combat too)
	local res = clearGroup(Vector2.new(RES_WIDTH, 40))
	res.Name = "Resources"
	resList = Kit.list(res, Enum.FillDirection.Horizontal, 8)
	-- Capsule, attribute, color, tab behind the + (Robux Shop; shards only trade in the Market)
	for i, spec in
		{
			{ "gold", "Gold", C.Gold, "gold" },
			{ "crystal", "Shards", C.Cyan, "market:material" },
			{ "soulstar", "Soulstars", Theme.Rarity.epic, "soulstars" },
		} :: { { any } }
	do
		local value = (player:GetAttribute(spec[2] :: string) or 0) :: number
		local pill, pillText, plus =
			Kit.pill(spec[1] :: string, Format.big(value), spec[3] :: Color3)
		if spec[1] == "gold" then
			goldText = pillText
		elseif spec[1] == "crystal" then
			shardText = pillText
		else
			starText = pillText
		end
		if plus then
			plus.Name = "Shop_" .. (spec[1] :: string)
			local tabId = spec[4] :: string
			plus.Activated:Connect(function()
				local market = string.match(tabId, "^market:(.+)$")
				if market then
					MarketController.open(market)
				else
					StoreController.open(tabId)
				end
			end)
		end
		pill.LayoutOrder = i
		pill.Parent = res
	end
	place(res, Vector2.new(0, 0), UDim2.new(0.5, -RES_WIDTH / 2, 0, 18))
	resGroup = res
	Kit.markTopCenter(res)
	resScale = Instance.new("UIScale")
	resScale.Parent = res

	-- Hub icon bar at the bottom center
	local bar, barH = buildBar()
	bar.Name = "HubBar"
	hubBar, hubBarW, hubBarH = bar, bar.Size.X.Offset, barH
	hubBarScale = Instance.new("UIScale")
	hubBarScale.Parent = bar
	addFly(
		bar,
		Vector2.new(0.5, 1),
		UDim2.new(0.5, 0, 1, -H.Margin),
		UDim2.new(0.5, 0, 1, barH + 80),
		2,
		false
	)

	-- Settings gear above the dash button at rest (the skill arc is away then; beside the dash it
	-- would run into the icon bar on tablets with the bigger touch dash). Opens the settings window
	-- (SettingsController; the Roblox menu is one button in there).
	-- Left of it: the leaderboard (trophy), the Journey, the season badge and the daily rewards
	-- (chest); a gold dot while something waits to be claimed. All at rest only.
	local cellW = H.GearSize + 12
	gearGroup = group(Vector2.new(GEAR_CELLS * cellW, H.GearSize))
	gearW = GEAR_CELLS * cellW
	gearScale = Instance.new("UIScale")
	gearScale.Parent = gearGroup
	gearGroup.Name = "Settings"
	local gearList = Kit.list(gearGroup, Enum.FillDirection.Horizontal, 0)
	gearList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local board = Kit.hudIconButton(H.GearSize, "hud_leaderboard", "trophy", nil)
	board.Name = "Leaderboard"
	board.LayoutOrder = 1
	board.Activated:Connect(LeaderboardController.toggle)
	board.Parent = gearGroup
	local journey = Kit.hudIconButton(H.GearSize, "hud_journey", "journey", nil)
	journey.Name = "Journey"
	journey.LayoutOrder = 2
	journey.Activated:Connect(JourneyController.toggle)
	journey.Parent = gearGroup
	local journeyDot = noticeDot(journey, "Ready", C.GoldHi)
	JourneyController.changed.Event:Connect(function()
		journeyDot.Visible = JourneyController.readyCount() > 0
	end)
	local season = Kit.hudIconButton(H.GearSize, "hud_season", "season_beta", nil)
	season.Name = "Season"
	season.LayoutOrder = 3
	season.Activated:Connect(SeasonController.toggle)
	season.Parent = gearGroup
	local seasonDot = noticeDot(season, "Ready", C.GoldHi)
	SeasonController.changed.Event:Connect(function()
		seasonDot.Visible = SeasonController.readyCount() > 0
	end)
	local chest = Kit.hudIconButton(H.GearSize, "hud_daily", "chest", nil)
	chest.Name = "Daily"
	chest.LayoutOrder = 4
	chest.Activated:Connect(DailyController.toggle)
	chest.Parent = gearGroup
	local ready = noticeDot(chest, "Ready", C.GoldHi)
	local function refreshDot()
		ready.Visible = DailyController.claimable()
		-- also catches a Journey/Season state that arrived before these dots existed
		journeyDot.Visible = JourneyController.readyCount() > 0
		seasonDot.Visible = SeasonController.readyCount() > 0
	end
	refreshDot()
	DailyController.changed.Event:Connect(refreshDot)
	task.spawn(function()
		while ready.Parent do
			task.wait(5)
			refreshDot()
		end
	end)
	local gear = Kit.hudIconButton(H.GearSize, "hud_settings", "settings", nil)
	gear.Name = "Gear"
	gear.LayoutOrder = 5
	gear.Activated:Connect(SettingsController.toggle)
	gear.Parent = gearGroup
	local gearX = -(H.Margin + dashSize / 2 - cellW / 2)
	local gearY = -(H.Margin + dashSize + H.DashDiamond + 6)
	addFly(
		gearGroup,
		Vector2.new(1, 1),
		UDim2.new(1, gearX, 1, gearY),
		UDim2.new(1, gearW + 10, 1, gearY), -- fully off the right edge
		3,
		false
	)

	-- Quest tracker on the right: compact card that grows with the text.
	--   QUEST 3 / 12                +250 Gold
	--   Objective text (wraps)
	--   [=========-------]  2 / 5
	local W = 240
	local quests = Kit.flyPanel(Vector2.new(W, 0))
	questGroup = quests
	quests.Name = "Quests"
	quests.AutomaticSize = Enum.AutomaticSize.Y
	-- Content in its own frame (the card's Sheen child must stay out of the list layout)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.fromOffset(W, 0)
	body.ZIndex = 2
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = body
	body.Parent = quests
	local list = Kit.list(body, Enum.FillDirection.Vertical, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.VerticalAlignment = Enum.VerticalAlignment.Top

	local inner = W - 24
	local headRow = Instance.new("Frame")
	headRow.Name = "Head"
	headRow.BackgroundTransparency = 1
	headRow.Size = UDim2.fromOffset(inner, 18)
	headRow.LayoutOrder = 1
	headRow.Parent = body
	local head = Kit.icon("quest", 16, C.Gold)
	head.AnchorPoint = Vector2.new(0, 0.5)
	head.Position = UDim2.fromScale(0, 0.5)
	head.Parent = headRow
	local headText = Kit.label("QUEST", 12, C.GoldHi, Theme.Font.Title)
	headText.Name = "Step"
	headText.AnchorPoint = Vector2.new(0, 0.5)
	headText.Position = UDim2.new(0, 22, 0.5, 0)
	headText.TextXAlignment = Enum.TextXAlignment.Left
	headText.Parent = headRow
	questReward = Kit.label("", 12, C.Gold, Theme.Font.UI)
	questReward.Name = "Reward"
	questReward.AnchorPoint = Vector2.new(1, 0.5)
	questReward.Position = UDim2.fromScale(1, 0.5)
	questReward.TextXAlignment = Enum.TextXAlignment.Right
	questReward.Parent = headRow

	questTitle = Kit.label("", 14, C.Text, Theme.Font.Body)
	questTitle.Name = "QuestText"
	questTitle.AutomaticSize = Enum.AutomaticSize.Y
	questTitle.Size = UDim2.fromOffset(inner, 0)
	questTitle.TextWrapped = true
	questTitle.TextXAlignment = Enum.TextXAlignment.Left
	questTitle.TextYAlignment = Enum.TextYAlignment.Top
	questTitle.LayoutOrder = 2
	questTitle.Parent = body

	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.BackgroundTransparency = 1
	progress.Size = UDim2.fromOffset(inner, 14)
	progress.LayoutOrder = 3
	progress.Parent = body
	local back, fill = Kit.bar(Vector2.new(inner - 64, 5), C.Gold)
	back.AnchorPoint = Vector2.new(0, 0.5)
	back.Position = UDim2.fromScale(0, 0.5)
	back.Parent = progress
	questCount = Kit.label("", 12, C.Muted, Theme.Font.UI)
	questCount.Name = "Count"
	questCount.AnchorPoint = Vector2.new(1, 0.5)
	questCount.Position = UDim2.fromScale(1, 0.5)
	questCount.TextXAlignment = Enum.TextXAlignment.Right
	questCount.Parent = progress
	local function refreshQuest()
		local q = QuestController.state()
		local text, count, reward = QuestController.lines()
		local done = QuestController.ready() and not q.text
		headText.Text = if not QuestController.ready()
			then "QUEST"
			elseif q.text then string.format("QUEST %d / %d", q.step, q.total)
			else "QUESTS DONE"
		questTitle.Text = text
		questCount.Text = count
		questReward.Text = reward
		-- All done: no bar, the best depth stands alone in the footer
		back.Visible = not done
		questCount.AnchorPoint = if done then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
		questCount.Position = if done then UDim2.fromScale(0, 0.5) else UDim2.fromScale(1, 0.5)
		local ratio = if not QuestController.ready()
			then 0
			elseif q.target > 0 then QuestController.count() / q.target
			else 1
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		for _, entry in barButtons do
			local locked = not QuestController.isOpen(entry.id)
			entry.button:SetAttribute("Locked", locked)
			for _, d in entry.button:GetDescendants() do
				if d:IsA("ImageLabel") then
					d.ImageTransparency = if locked then 0.65 else 0
				elseif d:IsA("TextLabel") then
					d.TextTransparency = if locked then 0.5 else 0
				end
			end
		end
	end
	QuestController.changed:Connect(refreshQuest)
	task.defer(refreshQuest)
	addFly(
		quests,
		Vector2.new(1, 0),
		UDim2.new(1, -H.Margin, 0, 200),
		UDim2.new(1, 300, 0, 200),
		4,
		false
	)
end

-- ------------------------------------------------------------------ Layout inside the safe area
-- Change the rest position of a flying panel; if it is currently resting, move there immediately
local function setHome(g: CanvasGroup, anchor: Vector2, home: UDim2, away: UDim2)
	g.AnchorPoint = anchor
	for _, fly in flies do
		if fly.group == g then
			fly.home = home
			fly.away = away
			if not fly.tween or fly.tween.PlaybackState ~= Enum.PlaybackState.Playing then
				g.Position = if g.GroupTransparency < 0.5 then home else away
			end
		end
	end
end

-- Smallest share the capsule row may shrink to before it stacks below the minimap instead
local RES_MIN_SCALE = 0.7
-- Smallest share the hub icon bar may shrink to (narrow phones with a large HUD size)
local BAR_MIN_SCALE = 0.6
local GAP = 8 -- clearance between neighbouring HUD blocks (design pixels)

-- Everything is laid out in design pixels of the HUD root, so it holds for any HUD size setting
-- and any safe area. Top: Roblox buttons | resources | minimap. Right column at rest: minimap,
-- quests, then the trophy/chest/gear row above the dash button. Bottom: XP chip | hub bar | dash.
-- On short screens (phones, large HUD size) the blocks shrink or move instead of overlapping.
local function layoutHud()
	local scale = root:FindFirstChildOfClass("UIScale")
	if not scale then
		return
	end
	local s = scale.Scale
	local camera = workspace.CurrentCamera
	local pixels = hudGui.AbsoluteSize.X
	if pixels <= 0 and camera then
		pixels = camera.ViewportSize.X
	end
	local width = pixels / s
	local height = hudGui.AbsoluteSize.Y / s
	if width <= 0 or height <= 0 then
		return
	end
	-- End of the Roblox buttons (top left) in design pixels, relative to the safe area
	local inset = GuiService.TopbarInset
	local left = 0
	if inset.Height > 0 then
		left = (inset.Min.X - hudGui.AbsolutePosition.X) / s + 10
	end
	local M = H.Margin
	local mapShown = mapBox.Visible
	local mapLeft = if mapShown then width - M - MAP_SIZE else width
	local mapBottom = if mapShown then 10 + MAP_SIZE + 18 else 0

	-- Resources: one row between the Roblox buttons and the minimap, shrunk if needed; only when
	-- even the shrunk row does not fit do the capsules stack right-aligned below the minimap
	local resLeftMin = math.max(left, M)
	local room = mapLeft - GAP - resLeftMin
	local rs = math.clamp(room / RES_WIDTH, 0, 1)
	local stacked = rs < RES_MIN_SCALE
	local rightTop = mapBottom + 12 -- next free y in the right column
	if stacked then
		resScale.Scale = 1
		resList.FillDirection = Enum.FillDirection.Vertical
		resList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		resGroup.AnchorPoint = Vector2.new(1, 0)
		resGroup.Position = UDim2.new(1, -M, 0, mapBottom + 10)
		rightTop = mapBottom + 10 + 3 * 40 + 2 * 8 + 12
	else
		resScale.Scale = rs
		local w = RES_WIDTH * rs
		resList.FillDirection = Enum.FillDirection.Horizontal
		resList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		resGroup.AnchorPoint = Vector2.new(0, 0)
		resGroup.Position = UDim2.fromOffset(math.max((width - w) / 2, resLeftMin), 18)
	end

	-- Trophy/chest/gear row above the dash button (its home from buildCalmPanels)
	local dashTop = height - M - dashSize - H.DashDiamond - 6
	local gearTop = dashTop - H.GearSize
	-- Quest card under the minimap; when it would run into the gear row, the gear row moves to
	-- the left of the quest card instead (phones / large HUD size)
	local questH = questGroup.AbsoluteSize.Y / s
	local questW = questGroup.AbsoluteSize.X / s
	setHome(
		questGroup,
		Vector2.new(1, 0),
		UDim2.new(1, -M, 0, rightTop),
		UDim2.new(1, 300, 0, rightTop)
	)
	local gearCell = H.GearSize + 12
	local gearX = -(M + dashSize / 2 - gearCell / 2)
	local gearY = -(M + dashSize + H.DashDiamond + 6)
	-- The row must not reach the centered status block (Rush meter, buffs): on narrow screens it
	-- shrinks to the room between its right edge and the block
	local function fitGear(rightEdge: number)
		local gearRoom = rightEdge - (width / 2 + H.RushBarWidth / 2 + GAP)
		gearScale.Scale = math.clamp(gearRoom / gearW, GEAR_MIN_SCALE, 1)
	end
	if rightTop + questH + GAP > gearTop then
		local x = -(M + questW + GAP)
		fitGear(width - M - questW - GAP)
		setHome(
			gearGroup,
			Vector2.new(1, 0),
			UDim2.new(1, x, 0, rightTop),
			UDim2.new(1, gearW + 10, 0, rightTop) -- fully off the right edge
		)
	else
		fitGear(width + gearX)
		setHome(
			gearGroup,
			Vector2.new(1, 1),
			UDim2.new(1, gearX, 1, gearY),
			UDim2.new(1, gearW + 10, 1, gearY)
		)
	end

	-- Hub icon bar: centered, but kept between the XP chip (bottom left) and the dash button
	-- (bottom right); shrinks when the gap is narrower than the bar
	local minLeft = 8 + xpChip.AbsoluteSize.X / s + GAP
	local maxRight = width - M - dashSize - GAP
	local bs = math.clamp((maxRight - minLeft) / hubBarW, BAR_MIN_SCALE, 1)
	local half = hubBarW * bs / 2
	local cx = math.clamp(width / 2, minLeft + half, math.max(minLeft + half, maxRight - half))
	hubBarScale.Scale = bs
	-- inner scales changed (capsules, hub bar): touch targets and text minimums follow
	Kit.refit(root)
	setHome(hubBar, Vector2.new(0.5, 1), UDim2.new(0, cx, 1, -M), UDim2.new(0, cx, 1, hubBarH + 80))

	-- Windows keep clear of the menu dock (screen pixels): bottom row, or left column on phones
	if camera then
		local vertical = camera.ViewportSize.Y < PHONE_HEIGHT
		local cellW = H.BarIcon + 12
		local colW = cellW + 2 * H.DockPad
		local btnH = H.BarIcon + H.BarCaption
		local colH = #H.Bar * btnH + (#H.Bar - 1) * PHONE_GAP + H.DockPad + H.DockPad // 2
		-- Phone column: from below the Roblox buttons down to the bottom margin; shrinks further on
		-- short screens / large HUD sizes instead of running under the Roblox buttons
		local barBottom = if inset.Height > 0
			then (inset.Max.Y - hudGui.AbsolutePosition.Y) / s + GAP
			else M
		local colRoom = height - math.max(barBottom, M) - M
		local dockScale = if vertical then math.min(PHONE_DOCK, colRoom / colH) else 1
		menuScale.Scale = dockScale
		if menuVertical ~= vertical then
			menuVertical = vertical
			menuList.FillDirection = if vertical
				then Enum.FillDirection.Vertical
				else Enum.FillDirection.Horizontal
			menuList.Padding = UDim.new(0, if vertical then PHONE_GAP else H.BarGap)
			if vertical then
				menuBar.Size = UDim2.fromOffset(colW, colH)
				menuBar.AnchorPoint = Vector2.new(0, 1)
				menuBar.Position = UDim2.new(0, H.Margin, 1, -H.Margin)
			else
				menuBar.Size = UDim2.fromOffset(menuBarW, menuBarH)
				menuBar.AnchorPoint = Vector2.new(0.5, 1)
				menuBar.Position = UDim2.new(0.5, 0, 1, -H.Margin)
			end
			-- Phone column: icons only (the captions would not fit at the smaller size)
			for _, mark in menuMarks do
				local button = mark.Parent
				local caption = button and button:FindFirstChildOfClass("TextLabel")
				if caption then
					caption.Visible = not vertical
				end
			end
		end
		-- Home bar / rounded corners below the safe area: windows keep clear of it as well
		local safeBottom = hudGui.AbsolutePosition.Y + hudGui.AbsoluteSize.Y
		local below = math.max(0, camera.ViewportSize.Y - safeBottom)
		if vertical then
			local safeLeft = math.max(0, hudGui.AbsolutePosition.X)
			Window.setReserve(below, safeLeft + (H.Margin + colW * dockScale + 6) * s, below)
		else
			Window.setReserve(below + (H.Margin + menuBarH + 6) * s, 0, below)
		end
	end
end

-- ------------------------------------------------------------------ Fly in/out
local function setCalm(calm: boolean, instant: boolean)
	flyVersion += 1
	local version = flyVersion
	for _, fly in flies do
		if fly.tween then
			fly.tween:Cancel()
		end
		local shown = if fly.combat then not calm else calm
		local goal = if shown
			then { Position = fly.home, GroupTransparency = 0 }
			else { Position = fly.away, GroupTransparency = 1 }
		if instant then
			fly.group.Position = goal.Position
			fly.group.GroupTransparency = goal.GroupTransparency
		else
			local delay = if shown then (fly.order - 1) * Theme.Stagger else 0
			task.delay(delay, function()
				if version ~= flyVersion then
					return -- switched in the meantime
				end
				local t = TweenService:Create(
					fly.group,
					if shown then Theme.Tween.FlyIn else Theme.Tween.FlyOut,
					goal
				)
				fly.tween = t
				t:Play()
			end)
		end
	end
end

-- ------------------------------------------------------------------ Lifecycle
function HudController.init()
	-- Our own HUD replaces Roblox's health bar and player list (the list overlaps the minimap).
	-- The game never creates a `leaderstats` folder; rankings live in the Leaderboard window.
	for _, coreGui in { Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList } do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGui, false)
		end)
	end

	hudGui, root = Kit.scaledGui("LootRushHUD", 1, false, Kit.hudDesign, true)

	buildOrbs()
	buildXpBar()
	buildMinimap()
	buildSkills()
	buildStatus()
	buildCalmPanels()
	buildMenuDock()

	hudGui.Parent = player:WaitForChild("PlayerGui")

	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutHud)
	-- After Kit.scaledGui (new scaling): safe area or screen size changed
	hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
	-- HUD size setting (Kit.setHudScale) changes only the scale
	local hudScale = root:FindFirstChildOfClass("UIScale")
	if hudScale then
		hudScale:GetPropertyChangedSignal("Scale"):Connect(layoutHud)
	end
	mapBox.Visible = Prefs.get("minimap") ~= false
	Prefs.changed:Connect(function(key: string, value: any)
		if key == "minimap" then
			mapBox.Visible = value ~= false
			layoutHud()
		end
	end)
	-- The quest card grows with its text and the XP chip with the level: keep the neighbours clear
	questGroup:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
	xpChip:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
	layoutHud()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHud)
	end
end

function HudController.start()
	setCalm(player:GetAttribute("InCombat") ~= true, true)
	player:GetAttributeChangedSignal("InCombat"):Connect(function()
		setCalm(player:GetAttribute("InCombat") ~= true, false)
	end)

	InventoryController.upgradeChanged:Connect(refreshUpgradeDots)
	refreshUpgradeDots()

	ProgressController.changed:Connect(refreshSkillButtons)
	player:GetAttributeChangedSignal("Class"):Connect(refreshSkillButtons)
	refreshSkillButtons()

	player:GetAttributeChangedSignal("Gold"):Connect(function()
		Shape.tickTo(goldText, (player:GetAttribute("Gold") or 0) :: number, Format.big)
	end)
	player:GetAttributeChangedSignal("Shards"):Connect(function()
		Shape.tickTo(shardText, (player:GetAttribute("Shards") or 0) :: number, Format.big)
	end)
	player:GetAttributeChangedSignal("Soulstars"):Connect(function()
		Shape.tickTo(starText, (player:GetAttribute("Soulstars") or 0) :: number, Format.big)
	end)

	local function refreshLevel()
		local need = math.max((player:GetAttribute("XPNext") or 1) :: number, 1)
		local xp = (player:GetAttribute("XP") or 0) :: number
		local ratio = math.clamp(xp / need, 0, 1)
		Spring.target(xpFill, { Size = UDim2.fromScale(ratio, 1) }, "Soft")
		xpTip.Visible = ratio > 0.01
		xpText.Text = "Lv. "
			.. tostring(player:GetAttribute("Level") or 1)
			.. " - "
			.. Format.big(xp)
			.. " / "
			.. Format.big(need)
			.. " XP"
	end
	for _, attr in { "Level", "XP", "XPNext" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshLevel)
	end
	refreshLevel()

	player:GetAttributeChangedSignal("Shield"):Connect(refreshShield)
	for _, attr in { "RiftPhase", "RiftRegion", "RiftDepth" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshPlace)
	end
	refreshPlace()
	local function refreshDash()
		local charges = player:GetAttribute("DashCharges")
		local max = player:GetAttribute("DashMax")
		local maxN = if typeof(max) == "number" then max else 2
		updateDashPips(if typeof(charges) == "number" then charges else maxN, maxN)
	end
	player:GetAttributeChangedSignal("DashCharges"):Connect(refreshDash)
	player:GetAttributeChangedSignal("DashMax"):Connect(refreshDash)
	refreshDash()

	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		bindHumanoid(humanoid)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- First quest ("enter a Rift"): the Atlas button bounces now and then, it is the way in
	task.spawn(function()
		while true do
			task.wait(1.6)
			local q = QuestController.state()
			local quest = QuestRules.Chain[q.step]
			if
				quest
				and quest.id == "enter_rift"
				and QuestController.ready()
				and not RiftController.active()
				and not Window.anyOpen()
			then
				for _, entry in barButtons do
					local motion = entry.button:FindFirstChild("Motion")
					if entry.id == "atlas" and motion and motion:IsA("UIScale") then
						Spring.impulse(motion, "Scale", 3, "Bouncy")
					end
				end
			end
		end
	end)

	local acc = 0
	local buffAcc = 1
	RunService.Heartbeat:Connect(function(dt: number)
		for i, update in skillVeils do
			update(SkillController.cooldownRatio(i), SkillController.remaining(i))
		end
		updateRushMeter(dt)
		updateMenuDock()
		buffAcc += dt
		if buffAcc >= 0.1 then
			buffAcc = 0
			updateBuffs()
		end
		if Window.anyOpen() or not mapBox.Visible then
			return -- a fullscreen window covers the minimap (or it is off): no terrain or dot work
		end
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		mapView.update(
			dt,
			if rootPart and rootPart:IsA("BasePart") then rootPart else nil,
			CameraController.getYaw()
		)
		acc += dt
		if acc >= 1 / Theme.MiniMap.ViewHz then
			acc = 0
			updateMinimap()
		end
	end)
end

return HudController
