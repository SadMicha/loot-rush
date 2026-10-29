--!strict
-- Kampf-HUD nach Mockup „v2 · Kampf-HUD“ und UI-Vorgabe:
--   Im Kampf nur Leben, Ressourcen (oben), Skills (inkl. Tränke + Dash) und Minimap.
--   In Ruhe fliegen Menü (links), Quests (rechts) und Rift-Button (unten) ein.
-- Kampf/Ruhe kommt vom Server (Player-Attribut "InCombat").

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local CameraController = require(script.Parent.CameraController)
local DashController = require(script.Parent.DashController)
local SkillController = require(script.Parent.SkillController)
local InventoryController = require(script.Parent.InventoryController)
local RiftController = require(script.Parent.RiftController)
local AbilitiesController = require(script.Parent.AbilitiesController)
local StarNetController = require(script.Parent.StarNetController)
local ForgeController = require(script.Parent.ForgeController)
local AtlasController = require(script.Parent.AtlasController)
local ShopController = require(script.Parent.ShopController)

local HudController = {}

local player = Players.LocalPlayer
local C = Theme.Color

type Fly = {
	group: CanvasGroup,
	home: UDim2,
	away: UDim2,
	order: number,
	tween: Tween?,
}

-- Menü-Buttons → Fenster
local MENU_ACTION: { [string]: () -> () } = {
	inventar = InventoryController.toggle,
	sternennetz = StarNetController.toggle,
	skills = AbilitiesController.toggle,
	schmiede = ForgeController.toggle,
	atlas = AtlasController.toggle,
}

local flies: { Fly } = {}
local flyVersion = 0
local root: Frame

-- ------------------------------------------------------------------ Aufbau-Helfer
local function place(obj: GuiObject, anchor: Vector2, pos: UDim2)
	obj.AnchorPoint = anchor
	obj.Position = pos
	obj.Parent = root
end

local function addFly(group: CanvasGroup, anchor: Vector2, home: UDim2, away: UDim2, order: number)
	place(group, anchor, home)
	table.insert(flies, { group = group, home = home, away = away, order = order, tween = nil })
end

local function clearGroup(size: Vector2): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Size = UDim2.fromOffset(size.X, size.Y)
	g.AutomaticSize = Enum.AutomaticSize.XY -- wächst mit, wenn Knöpfe auf Touch größer werden
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	return g
end

-- ------------------------------------------------------------------ Status (oben links)
-- Wie hud_player_status im Mobile-Mock-up: Porträt im Goldring, Stufen-Plakette darunter,
-- rechts daneben Lebensbalken (Zahl im Balken) und darunter der Erfahrungsbalken.
local lifeBox: Frame
local lifeBack: Frame
local lifeFill: Frame
local lifeText: TextLabel
local xpBack: Frame
local xpText: TextLabel
local shieldFill: Frame
local shieldText: TextLabel
local lifeHumanoid: Humanoid? = nil
local lvlLabel: TextLabel
local xpFill: Frame
local PORTRAIT = 96 -- Goldring mit Avatar
local LIFE_BAR = 300 -- Breite des Lebensbalkens (wird schmaler, wenn oben zu wenig Platz ist)
local LIFE_BAR_MIN = 150
local LIFE_H = 24
local XP_H = 16
local BAR_X = PORTRAIT + 4
local STATUS_H = PORTRAIT + 14 -- Plakette ragt unten aus dem Ring

-- Zahl mittig im Balken
local function barText(back: Frame, size: number): TextLabel
	local t = Kit.label("", size)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.fromScale(1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextStrokeTransparency = 0.35
	t.ZIndex = 5
	t.Parent = back
	return t
end

-- Fest eingepasstes Bild aus Assets.Art; ohne Bild flacher Ersatz
local function ring(parent: GuiObject, size: number)
	local img = Window.art("node_ring", Vector2.new(size, size))
	if img then
		img.ZIndex = 1
		img.Parent = parent
	else
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(size, size)
		f.BackgroundColor3 = C.Bg1
		f.BorderSizePixel = 0
		Kit.corner(f, size // 2)
		Kit.stroke(f, C.Gold, 2)
		f.Parent = parent
	end
end

-- Plakette (plaque_region) mit Text; ohne Bild flache Kapsel
local function plaque(parent: GuiObject, size: Vector2, textSize: number): TextLabel
	local f = Instance.new("Frame")
	f.Name = "Plakette"
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundTransparency = 1
	f.ZIndex = 3
	local img = Window.art("plaque_region", size)
	if img then
		img.ScaleType = Enum.ScaleType.Stretch
		img.ZIndex = 3
		img.Parent = f
	else
		f.BackgroundColor3 = C.Bg1
		f.BackgroundTransparency = 0
		Kit.corner(f, size.Y // 2)
		Kit.stroke(f, C.Gold)
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

local function buildLife()
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(BAR_X + LIFE_BAR, STATUS_H)
	box.Name = "Life"
	place(box, Vector2.new(0, 0), UDim2.fromOffset(16, 10))
	lifeBox = box

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.Size = UDim2.fromOffset(PORTRAIT, PORTRAIT)
	portrait.Parent = box
	ring(portrait, PORTRAIT)
	local face = Instance.new("ImageLabel")
	face.Name = "Avatar"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromOffset(PORTRAIT * 0.7, PORTRAIT * 0.7)
	face.BackgroundTransparency = 1
	face.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
	face.ZIndex = 2
	Kit.corner(face, PORTRAIT)
	face.Parent = portrait

	local plate = Instance.new("Frame")
	plate.Name = "Stufe"
	plate.BackgroundTransparency = 1
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0, PORTRAIT // 2, 1, 0)
	plate.Size = UDim2.fromOffset(84, 30)
	plate.Parent = box
	lvlLabel = plaque(plate, Vector2.new(84, 30), 13)
	lvlLabel.Text = "Lv. 1"

	local back, fill = Kit.bar(Vector2.new(LIFE_BAR, LIFE_H), C.Life)
	back.Name = "Leben"
	back.Position = UDim2.fromOffset(BAR_X, 18)
	back.Parent = box
	lifeBack = back
	lifeFill = fill
	lifeText = barText(back, 13)

	local xb, xf = Kit.bar(Vector2.new(LIFE_BAR - 30, XP_H), C.Mana)
	xb.Name = "XP"
	xb.Position = UDim2.fromOffset(BAR_X, 18 + LIFE_H + 6)
	xb.Parent = box
	xpBack = xb
	xpFill = xf
	xpFill.Size = UDim2.fromScale(0, 1)
	xpText = barText(xb, 10)

	-- Arkaner Schild (Player-Attribut „Shield“, setzt Systems/Combat): Kristall-Streifen über dem
	-- Lebensbalken, Breite = Schild im Verhältnis zum maximalen Leben, Zahl unter dem XP-Balken
	shieldFill = Instance.new("Frame")
	shieldFill.Name = "Schild"
	shieldFill.Size = UDim2.fromScale(0, 0.3)
	shieldFill.BackgroundColor3 = C.Cyan
	shieldFill.BorderSizePixel = 0
	shieldFill.ZIndex = 4
	shieldFill.Visible = false
	Kit.corner(shieldFill, 4)
	shieldFill.Parent = back
	shieldText = Kit.label("", 12, C.Cyan)
	shieldText.Name = "SchildText"
	shieldText.Position = UDim2.fromOffset(BAR_X + 4, 18 + LIFE_H + 6 + XP_H + 4)
	shieldText.Visible = false
	shieldText.Parent = box
end

local function refreshShield()
	local shield = player:GetAttribute("Shield")
	local amount = if typeof(shield) == "number" then shield else 0
	local max = if lifeHumanoid then lifeHumanoid.MaxHealth else 0
	local show = amount > 0 and max > 0
	shieldFill.Visible = show
	shieldText.Visible = show
	if show then
		TweenService:Create(
			shieldFill,
			Theme.Tween.Bar,
			{ Size = UDim2.fromScale(math.clamp(amount / max, 0.04, 1), 0.3) }
		):Play()
		shieldText.Text = "+" .. Format.int(amount) .. " Schild"
	end
end

local function bindHumanoid(humanoid: Humanoid)
	lifeHumanoid = humanoid
	local function refresh()
		local ratio = if humanoid.MaxHealth > 0
			then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			else 0
		TweenService:Create(lifeFill, Theme.Tween.Bar, { Size = UDim2.fromScale(ratio, 1) }):Play()
		lifeText.Text = Format.int(humanoid.Health) .. " / " .. Format.int(humanoid.MaxHealth)
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshShield)
	refresh()
	refreshShield()
end

-- ------------------------------------------------------------------ Minimap (oben rechts)
-- Wie hud_minimap: runder Goldring mit „N“ oben, darunter eine Plakette mit dem Ort.
local mapFrame: Frame
local mapPlace: TextLabel
local dots: { Frame } = {}
local MAP_SIZE = 156
local MAP_INNER = 0.4 -- Radius der Kartenfläche im Ring (Anteil der Breite)
local MAP_RANGE = 70 -- Studs vom Mittelpunkt bis zum Rand

local function buildMinimap()
	local box = Instance.new("Frame")
	box.Name = "Minimap"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE + 18)
	place(box, Vector2.new(1, 0), UDim2.new(1, -16, 0, 10))

	mapFrame = Instance.new("Frame")
	mapFrame.Name = "Karte"
	mapFrame.BackgroundTransparency = 1
	mapFrame.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE)
	mapFrame.Parent = box
	ring(mapFrame, MAP_SIZE)

	local north = Kit.label("N", 14, C.GoldHi, Theme.Font.Title)
	north.AnchorPoint = Vector2.new(0.5, 0)
	north.Position = UDim2.new(0.5, 0, 0, 22)
	north.TextStrokeTransparency = 0.4
	north.ZIndex = 4
	north.Parent = mapFrame

	local me = Instance.new("Frame")
	me.Size = UDim2.fromOffset(12, 12)
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromScale(0.5, 0.5)
	me.Rotation = 45
	me.BackgroundColor3 = C.Text
	me.BorderSizePixel = 0
	me.ZIndex = 3
	me.Parent = mapFrame

	local plate = Instance.new("Frame")
	plate.Name = "Ort"
	plate.BackgroundTransparency = 1
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.fromScale(0.5, 1)
	plate.Size = UDim2.fromOffset(136, 32)
	plate.Parent = box
	mapPlace = plaque(plate, Vector2.new(136, 32), 11)
end

-- Ort unter der Minimap: im Rift Gebiet + Tiefe, sonst der Hub
local function refreshPlace()
	local region = player:GetAttribute("RiftRegion")
	local info = if typeof(region) == "string" then Atlas.ById[region] else nil
	if info and RiftController.active() then
		local depth = player:GetAttribute("RiftDepth")
		mapPlace.Text = info.name .. (if typeof(depth) == "number" then " · T" .. depth else "")
	else
		mapPlace.Text = "Lumenhafen"
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
				-- in Kamera-Ausrichtung drehen: oben auf der Karte = Blickrichtung
				local x = d.X * cosY - d.Z * sinY
				local z = d.X * sinY + d.Z * cosY
				if x * x + z * z < MAP_RANGE * MAP_RANGE then -- rund, passend zum Ring
					used += 1
					local dd = dot(used)
					dd.Visible = true
					dd.Position = UDim2.fromScale(
						0.5 + x / MAP_RANGE * MAP_INNER,
						0.5 + z / MAP_RANGE * MAP_INNER
					)
				end
			end
		end
	end
	for i = used + 1, #dots do
		dots[i].Visible = false
	end
end

-- ------------------------------------------------------------------ Skillleiste (unten)
local dashCount: TextLabel
local potionCd: Frame
local potionCdText: TextLabel
local potionCount: TextLabel
local cdOverlays: { Frame } = {}
local cdTexts: { TextLabel } = {}
local SLOT_KEYS = { "Q", "E", "R", "F" }
local SKILLBAR_H = 100

-- Abklingzeit-Schleier (wächst von unten) und Restzeit über einem Slot
local function cooldownLayer(slot: GuiObject): (Frame, TextLabel)
	local cd = Instance.new("Frame")
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = C.Bg0
	cd.BackgroundTransparency = 0.3
	cd.BorderSizePixel = 0
	Kit.corner(cd, Theme.Radius.M)
	cd.Parent = slot
	local cdText = Kit.label("", 18, C.Text)
	cdText.AnchorPoint = Vector2.new(0.5, 0.5)
	cdText.Position = UDim2.fromScale(0.5, 0.5)
	cdText.ZIndex = 2
	cdText.Parent = slot
	return cd, cdText
end

-- Slot auf Klick oder Tipp auslösen
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

local function buildSkillbar()
	-- Goldrahmen wie hud_hotbar (bis das Leisten-Bild da ist: kleines Fenster-9-Slice direkt am
	-- Leisten-Bild, damit die Liste es nicht als Slot einreiht)
	local bar = Instance.new("ImageLabel")
	bar.Name = "Skillbar"
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Size = UDim2.fromOffset(0, SKILLBAR_H)
	bar.BackgroundColor3 = C.Bg0
	bar.BorderSizePixel = 0
	local frame = Assets.Slice.window_small
	if frame then
		bar.BackgroundTransparency = 1
		bar.Image = frame.id
		bar.ScaleType = Enum.ScaleType.Slice
		bar.SliceCenter = frame.center
		bar.SliceScale = 0.3
	else
		bar.BackgroundTransparency = 0.3
		Kit.corner(bar, 20)
		Kit.stroke(bar, C.Line)
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = bar
	Kit.list(bar, Enum.FillDirection.Horizontal, 8)
	place(bar, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12))

	-- Tränke als Slots wie im Mock-up (Reihe 1 · 2 · Q · E · R · F); Manatrank hat noch keine Funktion
	local lifePotion = Kit.slot(72, "trank_leben", C.Life, "1")
	potionCd, potionCdText = cooldownLayer(lifePotion)
	potionCount = Kit.label("", 14, C.Text)
	potionCount.Name = "Anzahl"
	potionCount.AnchorPoint = Vector2.new(1, 0)
	potionCount.Position = UDim2.new(1, -6, 0, 4)
	potionCount.TextStrokeTransparency = 0.3
	potionCount.ZIndex = 3
	potionCount.Parent = lifePotion
	onTap(lifePotion, SkillController.potion)
	local items: { GuiObject } = { lifePotion, Kit.slot(72, "trank_mana", C.Mana, "2") }

	for i, skill in Skills.bar do
		local slot = Kit.slot(72, skill.icon, skill.color, SLOT_KEYS[i])
		cdOverlays[i], cdTexts[i] = cooldownLayer(slot)
		onTap(slot, function()
			SkillController.cast(i)
		end)
		table.insert(items, slot)
	end
	-- Dash-Slot ist auf Touch der Dash-Knopf (statt des runden Roblox-Knopfs)
	local dash = Kit.slot(72, "skill_dash", C.Text, "Leer")
	onTap(dash, DashController.dash)
	table.insert(items, dash)
	for i, it in items do
		it.LayoutOrder = i
		it.Parent = bar
	end
	dashCount = Kit.label(tostring(player:GetAttribute("DashCharges") or 2), 14, C.Cyan)
	dashCount.AnchorPoint = Vector2.new(1, 0)
	dashCount.Position = UDim2.new(1, -6, 0, 4)
	dashCount.TextStrokeTransparency = 0.3
	dashCount.ZIndex = 3
	dashCount.Parent = items[#items]
end

-- ------------------------------------------------------------------ Ruhe-Panels (fliegen ein)
local goldText: TextLabel
local shardText: TextLabel
local starText: TextLabel
local resGroup: CanvasGroup
local resList: UIListLayout
local questGroup: CanvasGroup
local menuGroup: CanvasGroup
local menuGrid: UIGridLayout
local MENU_ITEMS =
	{ "inventar", "sternennetz", "skills", "schmiede", "dorf", "begleiter", "atlas", "seelenstern" }
-- Beschriftung unter dem Knopf wie im Mobile-Mock-up (kurz, passt unter den Slot)
local MENU_CAPTION: { [string]: string } = {
	inventar = "Inventar",
	sternennetz = "Sterne",
	skills = "Skills",
	schmiede = "Schmiede",
	dorf = "Dorf",
	begleiter = "Begleiter",
	atlas = "Atlas",
	seelenstern = "Seelen",
}
local MENU_CELL = 66 -- Slot-Kante
local MENU_LABEL = 18 -- Platz für die Beschriftung
local MENU_W = MENU_CELL + 14 -- Knopf etwas breiter als der Slot, damit lange Namen passen
local MENU_GAP = 8
local RES_WIDTH = 620 -- drei Kapseln mit Abstand

-- Seitenleisten-Knopf: Slot-Bild mit Icon, Name darunter (Knopf = ganze Fläche)
local function menuButton(name: string, cell: number): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = name
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(MENU_W, cell + MENU_LABEL)
	-- Slot-Rahmen als Bild (wie die Knöpfe im Mobile-Mock-up), sonst flacher Rahmen
	local slot = Instance.new("ImageLabel")
	slot.Name = "Slot"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(cell, cell)
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.fromScale(0.5, 0)
	local frame = Assets.Fixed.slot_normal
	if frame then
		slot.Image = frame.id
		slot.ScaleType = Enum.ScaleType.Fit
	else
		slot.BackgroundColor3 = C.Bg1
		slot.BackgroundTransparency = 0
		Kit.corner(slot, Theme.Radius.M)
		Kit.stroke(slot, C.Gold, 2)
	end
	local icon = Kit.icon(name, math.floor(cell * 0.6), C.Muted)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 2
	icon.Parent = slot
	slot.Parent = b
	local t = Kit.label(MENU_CAPTION[name] or name, 10, C.Text)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.fromScale(0.5, 1)
	t.Size = UDim2.new(1, 0, 0, MENU_LABEL)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextStrokeTransparency = 0.3
	t.ZIndex = 3
	t.Parent = b
	return b
end

local function buildCalmPanels()
	-- Ressourcen oben mittig
	local res = clearGroup(Vector2.new(RES_WIDTH, 40))
	res.Name = "Resources"
	resList = Kit.list(res, Enum.FillDirection.Horizontal, 8)
	-- Kapsel, Attribut, Farbe, Shop-Reiter hinter dem +
	for i, spec in
		{
			{ "gold", "Gold", C.Gold, "gold" },
			{ "kristall", "Shards", C.Cyan, "material" },
			{ "seelenstern", "Soulstars", Theme.Rarity.epic, "seelensterne" },
		} :: { { any } }
	do
		local value = (player:GetAttribute(spec[2] :: string) or 0) :: number
		local pill, pillText, plus =
			Kit.pill(spec[1] :: string, Format.big(value), spec[3] :: Color3)
		if spec[1] == "gold" then
			goldText = pillText
		elseif spec[1] == "kristall" then
			shardText = pillText
		else
			starText = pillText
		end
		if plus then
			plus.Name = "Shop_" .. (spec[1] :: string)
			local tabId = spec[4] :: string
			plus.Activated:Connect(function()
				ShopController.open(tabId)
			end)
		end
		pill.LayoutOrder = i
		pill.Parent = res
	end
	place(res, Vector2.new(0, 0), UDim2.new(0.5, -RES_WIDTH / 2, 0, 18)) -- bleibt auch im Kampf sichtbar
	resGroup = res

	-- Menü links
	-- Raster statt Liste: wird es zu hoch (Handy), bricht es in eine zweite Spalte um (siehe layoutHud)
	local menu = clearGroup(
		Vector2.new(MENU_W, #MENU_ITEMS * (MENU_CELL + MENU_LABEL + MENU_GAP) - MENU_GAP)
	)
	menu.AutomaticSize = Enum.AutomaticSize.None
	menu.Name = "Menu"
	menuGrid = Instance.new("UIGridLayout")
	menuGrid.CellSize = UDim2.fromOffset(MENU_W, MENU_CELL + MENU_LABEL)
	menuGrid.CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP)
	menuGrid.FillDirection = Enum.FillDirection.Vertical
	menuGrid.SortOrder = Enum.SortOrder.LayoutOrder
	menuGrid.Parent = menu
	menuGroup = menu
	for i, name in MENU_ITEMS do
		local b = menuButton(name, MENU_CELL)
		b.LayoutOrder = i
		b.Parent = menu
		local open = MENU_ACTION[name]
		if open then
			b.Activated:Connect(open)
		end
	end
	addFly(menu, Vector2.new(0, 0), UDim2.fromOffset(16, 200), UDim2.fromOffset(-200, 200), 2)

	-- Quests rechts
	local quests = Kit.flyPanel(Vector2.new(260, 170))
	questGroup = quests
	quests.Name = "Quests"
	Kit.padding(quests, 14)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = quests
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = list
	local head = Kit.icon("quest", 20, C.Muted)
	head.LayoutOrder = 0
	head.Parent = list
	for i, q in
		{
			{ "Besiege 50 Kristallschleime", 0.64 },
			{ "Sammle 20 Kristalle", 0.25 },
			{ "Erreiche die Ruinen", 0.04 },
		} :: { { any } }
	do
		local t = Kit.label(q[1] :: string, 13, C.Muted, Theme.Font.Body)
		t.LayoutOrder = i * 2 - 1
		t.Parent = list
		local back, fill = Kit.bar(Vector2.new(232, 4), C.Gold)
		fill.Size = UDim2.fromScale(q[2] :: number, 1)
		back.LayoutOrder = i * 2
		back.Parent = list
	end
	addFly(quests, Vector2.new(1, 0), UDim2.new(1, -16, 0, 200), UDim2.new(1, 300, 0, 200), 3)

	-- Rift-Button unten
	local rift = clearGroup(Vector2.new(240, 48))
	rift.Name = "Rift"
	local btn = Kit.button("Rift betreten", C.Gold, Vector2.new(240, 48))
	btn.Activated:Connect(RiftController.toggle)
	player:GetAttributeChangedSignal("RiftPhase"):Connect(function()
		Kit.buttonLabel(btn).Text = if RiftController.active()
			then "Rift verlassen"
			else "Rift betreten"
	end)
	btn.Parent = rift
	addFly(rift, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -124), UDim2.new(0.5, 0, 1, 120), 4)
end

-- ------------------------------------------------------------------ Platz neben der Roblox-Leiste
-- Oben links liegen die Roblox-Knöpfe (Logo, Menü, Chat); GuiService.TopbarInset ist der freie Rest
-- der Leiste. Leben beginnt rechts davon, die Ressourcen rücken bei Bedarf bis vor die Minimap,
-- und erst wenn auch das nicht reicht, wird der Lebensbalken schmaler.
-- Ruhe-Position eines einfliegenden Panels ändern; steht es gerade, sofort dorthin
local function setHome(group: CanvasGroup, home: UDim2, away: UDim2)
	for _, fly in flies do
		if fly.group == group then
			fly.home = home
			fly.away = away
			if not fly.tween or fly.tween.PlaybackState ~= Enum.PlaybackState.Playing then
				group.Position = if group.GroupTransparency < 0.5 then home else away
			end
		end
	end
end

local function layoutHud()
	local camera = workspace.CurrentCamera
	local scale = root:FindFirstChildOfClass("UIScale")
	if not camera or not scale then
		return
	end
	local s = scale.Scale
	local width = camera.ViewportSize.X / s
	local inset = GuiService.TopbarInset
	local left = if inset.Height > 0 then math.max(16, inset.Min.X / s + 10) else 16
	-- Ressourcen oben mittig; reicht der Platz zwischen Status und Minimap nicht (Tablet, Handy),
	-- stehen die Kapseln rechtsbündig untereinander unter der Minimap und die Quests rücken nach unten.
	local resMax = width - 16 - MAP_SIZE - 16 - RES_WIDTH -- direkt vor der Minimap
	local resLeft = math.max((width - RES_WIDTH) / 2, left + BAR_X + LIFE_BAR + 16)
	local bar = LIFE_BAR
	if resLeft > resMax then
		bar = math.max(LIFE_BAR_MIN, LIFE_BAR - (resLeft - resMax))
		resLeft = math.max(resMax, left + BAR_X + bar + 16)
	end
	local stacked = resLeft > resMax
	if stacked then
		bar = math.clamp(width - 16 - MAP_SIZE - 24 - left - BAR_X, LIFE_BAR_MIN, LIFE_BAR)
	end
	local mapBottom = 10 + MAP_SIZE + 18
	local questTop = mapBottom + 12
	if stacked then
		resList.FillDirection = Enum.FillDirection.Vertical
		resList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		resGroup.AnchorPoint = Vector2.new(1, 0)
		resGroup.Position = UDim2.new(1, -16, 0, mapBottom + 10)
		questTop = mapBottom + 10 + 3 * 40 + 2 * 8 + 12
	else
		resList.FillDirection = Enum.FillDirection.Horizontal
		resList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		resGroup.AnchorPoint = Vector2.new(0, 0)
		resGroup.Position = UDim2.fromOffset(resLeft, 18)
	end
	setHome(questGroup, UDim2.new(1, -16, 0, questTop), UDim2.new(1, 300, 0, questTop))
	lifeBox.Position = UDim2.fromOffset(left, 10)
	lifeBox.Size = UDim2.fromOffset(BAR_X + bar, STATUS_H)
	for _, spec in { { lifeBack, bar, LIFE_H }, { xpBack, bar - 30, XP_H } } :: { { any } } do
		local back = spec[1] :: Frame
		local size = Vector2.new(spec[2] :: number, spec[3] :: number)
		back.Size = UDim2.fromOffset(size.X, size.Y)
		for _, child in back:GetChildren() do
			local fillImage = child:FindFirstChildOfClass("ImageLabel")
			if child:IsA("Frame") and fillImage then
				fillImage.Size = UDim2.fromOffset(size.X, size.Y)
			end
		end
	end

	-- Menü links: unter dem Status beginnen; auf Touch über dem Bewegungs-Stick enden
	-- (Stick-Bereich ≈ untere 28 % links). Passt es nicht in eine Spalte, mehrere Spalten.
	local height = camera.ViewportSize.Y / s
	local cellH = MENU_CELL + MENU_LABEL
	local top = math.max(10 + STATUS_H + 12, if inset.Height > 0 then inset.Max.Y / s + 12 else 0)
	local bottom = if UserInputService.TouchEnabled then height * 0.72 else height - 90
	local count = #MENU_ITEMS
	local rows = math.clamp(math.floor((bottom - top + MENU_GAP) / (cellH + MENU_GAP)), 1, count)
	local cols = math.ceil(count / rows)
	rows = math.ceil(count / cols)
	local w = cols * (MENU_W + MENU_GAP) - MENU_GAP
	local h = rows * (cellH + MENU_GAP) - MENU_GAP
	menuGrid.FillDirectionMaxCells = rows
	menuGroup.Size = UDim2.fromOffset(w, h)
	local y = math.clamp((height - h) / 2, top, math.max(top, bottom - h))
	setHome(menuGroup, UDim2.fromOffset(16, y), UDim2.fromOffset(-w - 80, y))
end

-- ------------------------------------------------------------------ Ein-/Ausflug
local function setCalm(calm: boolean, instant: boolean)
	flyVersion += 1
	local version = flyVersion
	for _, fly in flies do
		if fly.tween then
			fly.tween:Cancel()
		end
		local goal = if calm
			then { Position = fly.home, GroupTransparency = 0 }
			else { Position = fly.away, GroupTransparency = 1 }
		if instant then
			fly.group.Position = goal.Position
			fly.group.GroupTransparency = goal.GroupTransparency
		else
			local delay = if calm then (fly.order - 1) * Theme.Stagger else 0
			task.delay(delay, function()
				if version ~= flyVersion then
					return -- inzwischen umgeschaltet
				end
				local t = TweenService:Create(
					fly.group,
					if calm then Theme.Tween.FlyIn else Theme.Tween.FlyOut,
					goal
				)
				fly.tween = t
				t:Play()
			end)
		end
	end
end

-- ------------------------------------------------------------------ Lebenszyklus
function HudController.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local gui: ScreenGui
	gui, root = Kit.scaledGui("LootRushHUD", 1, false, function()
		return if UserInputService.TouchEnabled then Theme.HudDesignTouch else Theme.DesignSize
	end)

	buildLife()
	buildMinimap()
	buildSkillbar()
	buildCalmPanels()

	gui.Parent = player:WaitForChild("PlayerGui")

	layoutHud()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutHud)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHud) -- nach Kit.scaledGui (neue Skalierung)
	end
end

function HudController.start()
	setCalm(player:GetAttribute("InCombat") ~= true, true)
	player:GetAttributeChangedSignal("InCombat"):Connect(function()
		setCalm(player:GetAttribute("InCombat") ~= true, false)
	end)

	player:GetAttributeChangedSignal("Gold"):Connect(function()
		goldText.Text = Format.big((player:GetAttribute("Gold") or 0) :: number)
	end)
	player:GetAttributeChangedSignal("Shards"):Connect(function()
		shardText.Text = Format.big((player:GetAttribute("Shards") or 0) :: number)
	end)
	player:GetAttributeChangedSignal("Soulstars"):Connect(function()
		starText.Text = Format.big((player:GetAttribute("Soulstars") or 0) :: number)
	end)
	local function refreshPotions()
		local n = player:GetAttribute("Potions")
		potionCount.Text = if typeof(n) == "number" then tostring(n) else ""
		potionCount.TextColor3 = if n == 0 then C.Danger else C.Text
	end
	player:GetAttributeChangedSignal("Potions"):Connect(refreshPotions)
	refreshPotions()

	local function refreshLevel()
		lvlLabel.Text = "Lv. " .. tostring(player:GetAttribute("Level") or 1)
		local need = math.max((player:GetAttribute("XPNext") or 1) :: number, 1)
		local xp = (player:GetAttribute("XP") or 0) :: number
		local ratio = math.clamp(xp / need, 0, 1)
		xpText.Text = Format.big(xp) .. " / " .. Format.big(need) .. " XP"
		TweenService:Create(xpFill, Theme.Tween.Bar, { Size = UDim2.fromScale(ratio, 1) }):Play()
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
	player:GetAttributeChangedSignal("DashCharges"):Connect(function()
		dashCount.Text = tostring(player:GetAttribute("DashCharges") or 0)
	end)

	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		bindHumanoid(humanoid)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		for i, cd in cdOverlays do
			local ratio = SkillController.cooldownRatio(i)
			cd.Size = UDim2.fromScale(1, ratio)
			cdTexts[i].Text = if ratio > 0
				then string.format("%.1f", SkillController.remaining(i))
				else ""
		end
		local potion = SkillController.potionRatio()
		potionCd.Size = UDim2.fromScale(1, potion)
		potionCdText.Text = if potion > 0
			then string.format("%.1f", SkillController.potionRemaining())
			else ""
		acc += dt
		if acc >= 0.15 then
			acc = 0
			updateMinimap()
		end
	end)
end

return HudController
