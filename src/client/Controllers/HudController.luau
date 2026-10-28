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
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Kit = require(script.Parent.Parent.UI.Kit)
local CameraController = require(script.Parent.CameraController)
local DashController = require(script.Parent.DashController)
local SkillController = require(script.Parent.SkillController)
local InventoryController = require(script.Parent.InventoryController)
local RiftController = require(script.Parent.RiftController)
local AbilitiesController = require(script.Parent.AbilitiesController)
local StarNetController = require(script.Parent.StarNetController)
local ForgeController = require(script.Parent.ForgeController)
local AtlasController = require(script.Parent.AtlasController)

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

-- ------------------------------------------------------------------ Leben (oben links)
local lifeBox: Frame
local lifeBack: Frame
local lifeFill: Frame
local lifeText: TextLabel
local lvlLabel: TextLabel
local xpFill: Frame
local LIFE_BAR = 300 -- Breite des Lebensbalkens (wird schmaler, wenn oben zu wenig Platz ist)
local LIFE_BAR_MIN = 150

local function buildLife()
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(80 + LIFE_BAR, 60)
	box.Name = "Life"
	place(box, Vector2.new(0, 0), UDim2.fromOffset(28, 24))
	lifeBox = box

	local diamond = Instance.new("Frame")
	diamond.Size = UDim2.fromOffset(38, 38)
	diamond.Position = UDim2.fromOffset(8, 8)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = C.Bg1
	diamond.BorderSizePixel = 0
	Kit.corner(diamond, 8)
	Kit.stroke(diamond, C.Gold)
	diamond.Parent = box
	lvlLabel = Kit.label("1", 17)
	lvlLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	lvlLabel.Position = UDim2.fromOffset(27, 27)
	lvlLabel.Parent = box

	local back, fill = Kit.bar(Vector2.new(LIFE_BAR, 16), C.Life)
	back.Position = UDim2.fromOffset(66, 12)
	back.Parent = box
	lifeBack = back
	lifeFill = fill
	lifeText = Kit.label("", 13)
	lifeText.Position = UDim2.fromOffset(66, 34)
	lifeText.Parent = box
end

local function bindHumanoid(humanoid: Humanoid)
	local function refresh()
		local ratio = if humanoid.MaxHealth > 0
			then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			else 0
		TweenService:Create(lifeFill, Theme.Tween.Bar, { Size = UDim2.fromScale(ratio, 1) }):Play()
		lifeText.Text = Format.int(humanoid.Health) .. " / " .. Format.int(humanoid.MaxHealth)
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	refresh()
end

-- ------------------------------------------------------------------ Minimap (oben rechts)
local mapFrame: Frame
local dots: { Frame } = {}
local MAP_SIZE = 180
local MAP_RANGE = 70 -- Studs vom Mittelpunkt bis zum Rand

local function buildMinimap()
	mapFrame = Instance.new("Frame")
	mapFrame.Name = "Minimap"
	mapFrame.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE)
	mapFrame.BackgroundColor3 = Color3.fromHex("#1E3A54")
	mapFrame.BorderSizePixel = 0
	mapFrame.ClipsDescendants = true
	Kit.corner(mapFrame, MAP_SIZE // 2)
	Kit.stroke(mapFrame, C.Line2)
	place(mapFrame, Vector2.new(1, 0), UDim2.new(1, -28, 0, 24))

	local me = Instance.new("Frame")
	me.Size = UDim2.fromOffset(12, 12)
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromScale(0.5, 0.5)
	me.Rotation = 45
	me.BackgroundColor3 = C.Text
	me.BorderSizePixel = 0
	me.ZIndex = 3
	me.Parent = mapFrame
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
				if math.abs(x) < MAP_RANGE and math.abs(z) < MAP_RANGE then
					used += 1
					local dd = dot(used)
					dd.Visible = true
					dd.Position =
						UDim2.fromScale(0.5 + x / MAP_RANGE * 0.5, 0.5 + z / MAP_RANGE * 0.5)
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
local cdOverlays: { Frame } = {}
local cdTexts: { TextLabel } = {}
local SLOT_KEYS = { "Q", "E", "R", "F" }

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
	local bar = Instance.new("Frame")
	bar.Name = "Skillbar"
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Size = UDim2.fromOffset(0, 104)
	bar.BackgroundColor3 = C.Bg0
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	Kit.corner(bar, 20)
	Kit.stroke(bar, C.Line)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = bar
	Kit.list(bar, Enum.FillDirection.Horizontal, 12)
	place(bar, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -30))

	-- Tränke als Slots wie im Mock-up (Reihe 1 · 2 · Q · E · R · F); Manatrank hat noch keine Funktion
	local lifePotion = Kit.slot(72, "trank_leben", C.Life, "1")
	potionCd, potionCdText = cooldownLayer(lifePotion)
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
	dashCount.Parent = items[#items]

	local xpBack, fill = Kit.bar(Vector2.new(520, 4), C.Cyan)
	xpFill = fill
	xpFill.Size = UDim2.fromScale(0, 1)
	xpBack.Name = "XP"
	place(xpBack, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -18))
end

-- ------------------------------------------------------------------ Ruhe-Panels (fliegen ein)
local goldText: TextLabel
local shardText: TextLabel
local resGroup: CanvasGroup
local menuGroup: CanvasGroup
local menuGrid: UIGridLayout
local MENU_ITEMS =
	{ "inventar", "sternennetz", "skills", "schmiede", "dorf", "begleiter", "atlas", "seelenstern" }
local MENU_CELL = 48
local MENU_GAP = 8
local RES_WIDTH = 620 -- drei Kapseln mit Abstand

local function buildCalmPanels()
	-- Ressourcen oben mittig
	local res = clearGroup(Vector2.new(RES_WIDTH, 40))
	res.Name = "Resources"
	Kit.list(res, Enum.FillDirection.Horizontal, 8)
	for i, spec in
		{
			{ "gold", Format.big((player:GetAttribute("Gold") or 0) :: number), C.Gold },
			{ "kristall", Format.big((player:GetAttribute("Shards") or 0) :: number), C.Cyan },
			{ "seelenstern", "7", Theme.Rarity.epic },
		} :: { { any } }
	do
		local pill, pillText = Kit.pill(spec[1] :: string, spec[2] :: string, spec[3] :: Color3)
		if spec[1] == "gold" then
			goldText = pillText
		elseif spec[1] == "kristall" then
			shardText = pillText
		end
		pill.LayoutOrder = i
		pill.Parent = res
	end
	place(res, Vector2.new(0, 0), UDim2.new(0.5, -RES_WIDTH / 2, 0, 28)) -- bleibt auch im Kampf sichtbar
	resGroup = res

	-- Menü links
	-- Raster statt Liste: wird es zu hoch (Handy), bricht es in eine zweite Spalte um (siehe layoutHud)
	local menu = clearGroup(Vector2.new(MENU_CELL, #MENU_ITEMS * (MENU_CELL + MENU_GAP) - MENU_GAP))
	menu.AutomaticSize = Enum.AutomaticSize.None
	menu.Name = "Menu"
	menuGrid = Instance.new("UIGridLayout")
	menuGrid.CellSize = UDim2.fromOffset(MENU_CELL, MENU_CELL)
	menuGrid.CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP)
	menuGrid.FillDirection = Enum.FillDirection.Vertical
	menuGrid.SortOrder = Enum.SortOrder.LayoutOrder
	menuGrid.Parent = menu
	menuGroup = menu
	for i, name in MENU_ITEMS do
		local b = Kit.iconButton(name, name, MENU_CELL, false)
		b.LayoutOrder = i
		b.Parent = menu
		local open = MENU_ACTION[name]
		if open then
			b.Activated:Connect(open)
		end
	end
	addFly(menu, Vector2.new(0, 0), UDim2.fromOffset(28, 200), UDim2.fromOffset(-200, 200), 2)

	-- Quests rechts
	local quests = Kit.flyPanel(Vector2.new(260, 170))
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
	addFly(quests, Vector2.new(1, 0), UDim2.new(1, -28, 0, 236), UDim2.new(1, 300, 0, 236), 3)

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
	addFly(rift, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -160), UDim2.new(0.5, 0, 1, 120), 4)
end

-- ------------------------------------------------------------------ Platz neben der Roblox-Leiste
-- Oben links liegen die Roblox-Knöpfe (Logo, Menü, Chat); GuiService.TopbarInset ist der freie Rest
-- der Leiste. Leben beginnt rechts davon, die Ressourcen rücken bei Bedarf bis vor die Minimap,
-- und erst wenn auch das nicht reicht, wird der Lebensbalken schmaler.
local function layoutHud()
	local camera = workspace.CurrentCamera
	local scale = root:FindFirstChildOfClass("UIScale")
	if not camera or not scale then
		return
	end
	local s = scale.Scale
	local width = camera.ViewportSize.X / s
	local inset = GuiService.TopbarInset
	local left = if inset.Height > 0 then math.max(28, inset.Min.X / s + 12) else 28
	local resMax = width - 28 - MAP_SIZE - 16 - RES_WIDTH -- direkt vor der Minimap
	local resLeft = math.max((width - RES_WIDTH) / 2, left + 80 + LIFE_BAR + 16)
	local bar = LIFE_BAR
	if resLeft > resMax then
		bar = math.max(LIFE_BAR_MIN, LIFE_BAR - (resLeft - resMax))
		resLeft = math.max(resMax, left + 80 + bar + 16)
	end
	lifeBox.Position = UDim2.fromOffset(left, 24)
	lifeBox.Size = UDim2.fromOffset(80 + bar, 60)
	lifeBack.Size = UDim2.fromOffset(bar, 16)
	local fillImage = lifeFill:FindFirstChildOfClass("ImageLabel")
	if fillImage then
		fillImage.Size = UDim2.fromOffset(bar, 16)
	end
	resGroup.Position = UDim2.fromOffset(resLeft, 28)

	-- Menü links: unter der Roblox-Leiste beginnen; auf Touch über dem Bewegungs-Stick enden
	-- (Stick-Bereich ≈ untere 28 % links). Passt es nicht in eine Spalte, zwei Spalten.
	local height = camera.ViewportSize.Y / s
	local cell = if UserInputService.TouchEnabled
		then math.max(MENU_CELL, math.ceil(Kit.MIN_TOUCH_PX / s))
		else MENU_CELL
	local top = math.max(24, if inset.Height > 0 then inset.Max.Y / s + 12 else 0)
	local bottom = if UserInputService.TouchEnabled then height * 0.72 else height - 90
	local count = #MENU_ITEMS
	local rows = math.clamp(math.floor((bottom - top + MENU_GAP) / (cell + MENU_GAP)), 1, count)
	local cols = math.ceil(count / rows)
	rows = math.ceil(count / cols)
	local w = cols * (cell + MENU_GAP) - MENU_GAP
	local h = rows * (cell + MENU_GAP) - MENU_GAP
	menuGrid.CellSize = UDim2.fromOffset(cell, cell)
	menuGrid.FillDirectionMaxCells = rows
	menuGroup.Size = UDim2.fromOffset(w, h)
	local y = math.clamp((height - h) / 2, top, math.max(top, bottom - h))
	for _, fly in flies do
		if fly.group == menuGroup then
			fly.home = UDim2.fromOffset(28, y)
			fly.away = UDim2.fromOffset(-w - 80, y)
			if not fly.tween or fly.tween.PlaybackState ~= Enum.PlaybackState.Playing then
				menuGroup.Position = if menuGroup.GroupTransparency < 0.5
					then fly.home
					else fly.away
			end
		end
	end
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
	gui, root = Kit.scaledGui("LootRushHUD", 1)

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

	local function refreshLevel()
		lvlLabel.Text = tostring(player:GetAttribute("Level") or 1)
		local need = math.max((player:GetAttribute("XPNext") or 1) :: number, 1)
		local ratio = math.clamp(((player:GetAttribute("XP") or 0) :: number) / need, 0, 1)
		TweenService:Create(xpFill, Theme.Tween.Bar, { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
	for _, attr in { "Level", "XP", "XPNext" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshLevel)
	end
	refreshLevel()

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
