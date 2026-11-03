--!strict
-- Combat HUD after the style reference (assets/style_reference):
--   In combat: life orb + experience orb (bottom center), four round skills in an arc around the
--   dash button (bottom right), compass minimap (top right), resources (top center).
--   At rest: the orbs and skills leave, the icon bar (bottom center), settings gear and quests fly
--   in. The dash button and the minimap stay. Rifts are entered from the Atlas only.
--   Always: buff/debuff bar + Stud Rush meter above the orbs / icon bar (bottom center).
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
local AbilitiesController = require(script.Parent.AbilitiesController)
local StarNetController = require(script.Parent.StarNetController)
local ForgeController = require(script.Parent.ForgeController)
local AtlasController = require(script.Parent.AtlasController)
local ShopController = require(script.Parent.ShopController)
local PetWindowController = require(script.Parent.PetWindowController)
local QuestController = require(script.Parent.QuestController)
local ProgressController = require(script.Parent.ProgressController)

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
	shop = ShopController.toggle,
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

-- ------------------------------------------------------------------ Orbs (bottom center, combat)
-- Red orb = life (number inside, shield above it), blue orb = experience (level inside, XP above it).
-- There is no mana resource in the game, so the blue orb shows level progress instead.
local lifeOrb: Kit.Orb
local xpOrb: Kit.Orb
local shieldText: TextLabel
local xpText: TextLabel
local lifeHumanoid: Humanoid? = nil

local function buildOrbs()
	local cap = H.BarCaption
	local g = group(Vector2.new(2 * H.OrbSize + H.OrbGap, H.OrbSize + cap))
	g.Name = "Orbs"

	lifeOrb = Kit.orb(H.OrbSize, "health", C.Life)
	lifeOrb.root.Position = UDim2.fromOffset(0, cap)
	lifeOrb.root.Parent = g
	shieldText = orbCaption(g, H.OrbSize // 2, C.Cyan)
	shieldText.Name = "Shield"

	xpOrb = Kit.orb(H.OrbSize, "mana", C.Mana)
	xpOrb.root.Position = UDim2.fromOffset(H.OrbSize + H.OrbGap, cap)
	xpOrb.root.Parent = g
	xpText = orbCaption(g, H.OrbSize + H.OrbGap + H.OrbSize // 2, C.Muted)
	xpText.Name = "Xp"

	addFly(
		g,
		Vector2.new(0.5, 1),
		UDim2.new(0.5, 0, 1, -H.Margin),
		UDim2.new(0.5, 0, 1, H.OrbSize + 80),
		1,
		true
	)
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
local mapInner = 0.4 -- radius of the map area inside the ring (fraction of the width)

local function buildMinimap()
	local box = Instance.new("Frame")
	box.Name = "Minimap"
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
	local discSize = if frameImg then 0.66 else 0.8
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
		mapInner = 0.4
		ring(mapFrame, MAP_SIZE)
		local north = Kit.label("N", 14, C.GoldHi, Theme.Font.Title)
		north.AnchorPoint = Vector2.new(0.5, 0)
		north.Position = UDim2.new(0.5, 0, 0, 22)
		Kit.textOutline(north, 0.4)
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
		mapPlace.Text = info.name .. (if typeof(depth) == "number" then " · D" .. depth else "")
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
end

-- ------------------------------------------------------------------ Skills + dash (bottom right)
-- Dash = big gold-ringed button in the corner (always there), the four skills sit on a quarter arc
-- around it (combat only).
local updateDashPips: (available: number, max: number) -> ()
local skillVeils: { (number, number) -> () } = {}
local skillButtons: { ImageButton } = {}
local shownSkills: { string } = {}
local SLOT_KEYS = { "Q", "E", "R", "F" }

-- Loadout changed: new icons
local function refreshSkillButtons()
	for i, btn in skillButtons do
		local skill = SkillController.skill(i)
		if skill and shownSkills[i] ~= skill.id then
			shownSkills[i] = skill.id
			Kit.setRoundIcon(btn, Kit.skillArt(skill.id) or H.SkillArt[skill.id], skill.icon)
		end
	end
end

local function buildSkills()
	local keyboard = not UserInputService.TouchEnabled
	local S, D, R, M = H.SkillSize, H.DashSize, H.SkillArc, H.Margin

	-- Dash
	local dash = Kit.roundButton(
		D,
		"gold",
		Kit.skillArt("dash") or "skill_dash",
		"skill_dash",
		if keyboard then "Space" else nil
	)
	dash.Name = "Dash"
	onTap(dash, DashController.dash)
	-- One diamond per maximum charge above the button: cyan = available, dark = spent
	local pips, setPips = Kit.chargePips(H.DashDiamond)
	pips.AnchorPoint = Vector2.new(0.5, 0.5)
	pips.Position = UDim2.fromScale(0.5, 0.04)
	pips.ZIndex = 7
	pips.Parent = dash
	updateDashPips = setPips
	place(dash, Vector2.new(1, 1), UDim2.new(1, -M, 1, -M))

	-- Skill arc: the group's bottom right corner sits S/2 beyond the dash center
	local side = R + S
	local arc = group(Vector2.new(side, side))
	arc.Name = "Skills"
	local cx, cy = side - S / 2, side - S / 2 -- dash center inside the group
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
		shownSkills[i] = skill.id
		skillButtons[i] = btn
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromOffset(cx + R * math.cos(angle), cy - R * math.sin(angle))
		onTap(btn, function()
			SkillController.cast(i)
		end)
		skillVeils[i] = update
		btn.Parent = arc
	end
	local inset = M + D / 2 - S / 2
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
		QuestController.toast(def.name .. " · " .. def.text, color)
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
local questTitle: TextLabel
local questCount: TextLabel
local questReward: TextLabel
local barButtons: { { id: string, button: ImageButton } } = {}
local RES_WIDTH = 620 -- three capsules with spacing

local function buildCalmPanels()
	-- Resources at the top center (stays visible in combat too)
	local res = clearGroup(Vector2.new(RES_WIDTH, 40))
	res.Name = "Resources"
	resList = Kit.list(res, Enum.FillDirection.Horizontal, 8)
	-- Capsule, attribute, color, shop tab behind the +
	for i, spec in
		{
			{ "gold", "Gold", C.Gold, "gold" },
			{ "crystal", "Shards", C.Cyan, "material" },
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
				ShopController.open(tabId)
			end)
		end
		pill.LayoutOrder = i
		pill.Parent = res
	end
	place(res, Vector2.new(0, 0), UDim2.new(0.5, -RES_WIDTH / 2, 0, 18))
	resGroup = res

	-- Hub icon bar at the bottom center
	local cellW = H.BarIcon + 12
	local barW = #H.Bar * cellW + (#H.Bar - 1) * H.BarGap + 2 * H.DockPad
	local barH = H.BarIcon + H.BarCaption + H.DockPad + math.floor(H.DockPad / 2)
	local bar = group(Vector2.new(barW, barH))
	bar.Name = "HubBar"
	local barRow = Kit.dock(bar, H.DockPad)
	Kit.list(barRow, Enum.FillDirection.Horizontal, H.BarGap)
	for i, entry in H.Bar do
		local b = Kit.hudIconButton(H.BarIcon, entry.art, entry.icon, entry.caption)
		b.Name = entry.id
		b.LayoutOrder = i
		local open = MENU_ACTION[entry.id]
		if open then
			local id = entry.id
			b.Activated:Connect(function()
				local hint = QuestController.lockHint(id)
				if hint then
					QuestController.toast("Locked · " .. hint, C.Muted)
					return
				end
				open()
			end)
		end
		b.Parent = barRow
		table.insert(barButtons, { id = entry.id, button = b })
	end
	addFly(
		bar,
		Vector2.new(0.5, 1),
		UDim2.new(0.5, 0, 1, -H.Margin),
		UDim2.new(0.5, 0, 1, barH + 80),
		2,
		false
	)

	-- Settings gear next to the dash button (opens the Roblox menu)
	local gearGroup = group(Vector2.new(H.GearSize + 12, H.GearSize))
	gearGroup.Name = "Settings"
	local gear = Kit.hudIconButton(H.GearSize, "hud_settings", "settings", nil)
	gear.Name = "Gear"
	gear.Activated:Connect(function()
		pcall(function()
			GuiService:SetMenuIsOpen(true)
		end)
	end)
	gear.Parent = gearGroup
	local gearX = -(H.Margin + H.DashSize + 8)
	addFly(
		gearGroup,
		Vector2.new(1, 1),
		UDim2.new(1, gearX, 1, -H.Margin),
		UDim2.new(1, gearX + 200, 1, -H.Margin + 120),
		3,
		false
	)

	-- Quests on the right
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
	local headRow = Instance.new("Frame")
	headRow.BackgroundTransparency = 1
	headRow.Size = UDim2.new(1, 0, 0, 20)
	headRow.LayoutOrder = 0
	headRow.Parent = list
	local head = Kit.icon("quest", 20, C.Muted)
	head.Parent = headRow
	local headText = Kit.label("Quest", 12, C.Muted)
	headText.Name = "Step"
	headText.Position = UDim2.fromOffset(26, 2)
	headText.Parent = headRow
	questTitle = Kit.label("", 15, C.Text, Theme.Font.Body)
	questTitle.Name = "QuestText"
	questTitle.AutomaticSize = Enum.AutomaticSize.None
	questTitle.Size = UDim2.new(1, 0, 0, 40)
	questTitle.TextWrapped = true
	questTitle.TextYAlignment = Enum.TextYAlignment.Top
	questTitle.LayoutOrder = 1
	questTitle.Parent = list
	local back, fill = Kit.bar(Vector2.new(232, 6), C.Gold)
	back.LayoutOrder = 2
	back.Parent = list
	local foot = Instance.new("Frame")
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, 18)
	foot.LayoutOrder = 3
	foot.Parent = list
	questCount = Kit.label("", 13, C.Muted, Theme.Font.Body)
	questCount.Parent = foot
	questReward = Kit.label("", 13, C.Gold, Theme.Font.Body)
	questReward.AnchorPoint = Vector2.new(1, 0)
	questReward.Position = UDim2.fromScale(1, 0)
	questReward.TextXAlignment = Enum.TextXAlignment.Right
	questReward.Parent = foot
	local function refreshQuest()
		local q = QuestController.state()
		local text, count, reward = QuestController.lines()
		headText.Text = if not QuestController.ready()
			then "Quest"
			elseif q.text then string.format("Quest %d / %d", q.step, q.total)
			else "Quests done"
		questTitle.Text = text
		questCount.Text = count
		questReward.Text = reward
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
local function setHome(g: CanvasGroup, home: UDim2, away: UDim2)
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

-- Resources sit at the top center, right of the Roblox buttons; if there is not enough room before the
-- minimap (small / narrow screens) the capsules stack right-aligned below it and the quests move down.
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
	if width <= 0 then
		return
	end
	-- End of the Roblox buttons (top left) in design pixels, relative to the safe area
	local inset = GuiService.TopbarInset
	local left = 0
	if inset.Height > 0 then
		left = (inset.Min.X - hudGui.AbsolutePosition.X) / s + 10
	end
	local M = H.Margin
	local resMax = width - M - MAP_SIZE - M - RES_WIDTH -- directly before the minimap
	local resLeft = math.max((width - RES_WIDTH) / 2, left)
	local stacked = resLeft > resMax
	local mapBottom = 10 + MAP_SIZE + 18
	local questTop = mapBottom + 12
	if stacked then
		resList.FillDirection = Enum.FillDirection.Vertical
		resList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		resGroup.AnchorPoint = Vector2.new(1, 0)
		resGroup.Position = UDim2.new(1, -M, 0, mapBottom + 10)
		questTop = mapBottom + 10 + 3 * 40 + 2 * 8 + 12
	else
		resList.FillDirection = Enum.FillDirection.Horizontal
		resList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		resGroup.AnchorPoint = Vector2.new(0, 0)
		resGroup.Position = UDim2.fromOffset(resLeft, 18)
	end
	setHome(questGroup, UDim2.new(1, -M, 0, questTop), UDim2.new(1, 300, 0, questTop))
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
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	hudGui, root = Kit.scaledGui("LootRushHUD", 1, false, function()
		return if UserInputService.TouchEnabled then Theme.HudDesignTouch else Theme.DesignSize
	end, true)

	buildOrbs()
	buildMinimap()
	buildSkills()
	buildStatus()
	buildCalmPanels()

	hudGui.Parent = player:WaitForChild("PlayerGui")

	layoutHud()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutHud)
	-- After Kit.scaledGui (new scaling): safe area or screen size changed
	hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
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

	ProgressController.changed:Connect(refreshSkillButtons)
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
		xpOrb.text.Text = "Lv. " .. tostring(player:GetAttribute("Level") or 1)
		local need = math.max((player:GetAttribute("XPNext") or 1) :: number, 1)
		local xp = (player:GetAttribute("XP") or 0) :: number
		xpOrb.setRatio(math.clamp(xp / need, 0, 1))
		xpText.Text = Format.big(xp) .. " / " .. Format.big(need) .. " XP"
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
		buffAcc += dt
		if buffAcc >= 0.1 then
			buffAcc = 0
			updateBuffs()
		end
		if Window.anyOpen() then
			return -- a fullscreen window covers the minimap: no terrain or dot work behind it
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
