--!strict
-- Kampf-HUD nach Mockup „v2 · Kampf-HUD“ und UI-Vorgabe:
--   Im Kampf nur Leben, Ressourcen (oben), Skills (inkl. Tränke + Dash) und Minimap.
--   In Ruhe fliegen Menü (links), Quests (rechts) und Rift-Button (unten) ein.
-- Kampf/Ruhe kommt vom Server (Player-Attribut "InCombat").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Kit = require(script.Parent.Parent.UI.Kit)
local CameraController = require(script.Parent.CameraController)
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
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	return g
end

-- ------------------------------------------------------------------ Leben (oben links)
local lifeFill: Frame
local lifeText: TextLabel
local lvlLabel: TextLabel
local xpFill: Frame

local function buildLife()
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(380, 60)
	place(box, Vector2.new(0, 0), UDim2.fromOffset(28, 24))

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

	local back, fill = Kit.bar(Vector2.new(300, 16), C.Life)
	back.Position = UDim2.fromOffset(66, 12)
	back.Parent = box
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
	local d = dots[i]
	if d then
		return d
	end
	d = Instance.new("Frame")
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
local lifeLiquid: Frame
local cdOverlays: { Frame } = {}
local cdTexts: { TextLabel } = {}
local SLOT_KEYS = { "Q", "E", "R", "F" }

local function flask(color: Color3, fillRatio: number, key: string): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(36, 60)
	f.BackgroundColor3 = C.Bg1
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	Kit.corner(f, 12)
	Kit.stroke(f, C.Line2)
	local liquid = Instance.new("Frame")
	liquid.AnchorPoint = Vector2.new(0, 1)
	liquid.Position = UDim2.fromScale(0, 1)
	liquid.Size = UDim2.fromScale(1, fillRatio)
	liquid.BackgroundColor3 = color
	liquid.BorderSizePixel = 0
	liquid.Parent = f
	local k = Kit.label(key, 12, C.Muted)
	k.AnchorPoint = Vector2.new(0.5, 0)
	k.Position = UDim2.new(0.5, 0, 1, 4)
	k.Parent = f
	return f
end

local function buildSkillbar()
	local bar = Instance.new("Frame")
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

	local lifeFlask = flask(C.Life, 1, "1")
	lifeFlask.Active = true
	lifeFlask.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			SkillController.potion()
		end
	end)
	lifeLiquid = lifeFlask:FindFirstChildOfClass("Frame") :: Frame

	local items: { GuiObject } = { lifeFlask, flask(C.Mana, 0.4, "2") }
	for i, skill in Skills.bar do
		local slot = Kit.slot(72, skill.icon, skill.color, SLOT_KEYS[i])
		slot.Active = true
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
		cdOverlays[i] = cd
		cdTexts[i] = cdText
		slot.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				SkillController.cast(i)
			end
		end)
		table.insert(items, slot)
	end
	table.insert(items, Kit.slot(72, "skill_dash", C.Text, "Leer"))
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
	place(xpBack, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -18))
end

-- ------------------------------------------------------------------ Ruhe-Panels (fliegen ein)
local goldText: TextLabel
local shardText: TextLabel

local function buildCalmPanels()
	-- Ressourcen oben mittig
	local res = clearGroup(Vector2.new(620, 40))
	Kit.list(res, Enum.FillDirection.Horizontal, 8)
	for i, spec in
		{
			{ "gold", Format.big((player:GetAttribute("Gold") or 0) :: number), C.Gold },
			{ "kristall", Format.big((player:GetAttribute("Shards") or 0) :: number), C.Cyan },
			{ "seelenstern", "7", Theme.Rarity.epic },
		}
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
	place(res, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 28)) -- bleibt auch im Kampf sichtbar

	-- Menü links
	local menu = clearGroup(Vector2.new(48, 8 * 48 + 7 * 8))
	Kit.list(menu, Enum.FillDirection.Vertical, 8)
	for i, name in
		{
			"inventar",
			"sternennetz",
			"skills",
			"schmiede",
			"dorf",
			"begleiter",
			"atlas",
			"seelenstern",
		}
	do
		local b = Kit.iconButton(name, name, 48, false)
		b.LayoutOrder = i
		b.Parent = menu
		local open = MENU_ACTION[name]
		if open then
			b.Activated:Connect(open)
		end
	end
	addFly(menu, Vector2.new(0, 0.5), UDim2.new(0, 28, 0.5, 0), UDim2.new(0, -120, 0.5, 0), 2)

	-- Quests rechts
	local quests = Kit.flyPanel(Vector2.new(260, 170))
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
		}
	do
		local t = Kit.label(q[1] :: string, 13, C.Muted, Theme.Font.Body)
		t.LayoutOrder = i * 2 - 1
		t.Parent = list
		local back, fill = Kit.bar(Vector2.new(232, 4), C.Gold)
		fill.Size = UDim2.fromScale(q[2] :: number, 1)
		back.LayoutOrder = i * 2
		back.Parent = list
	end
	addFly(quests, Vector2.new(1, 0), UDim2.new(1, -28, 0, 222), UDim2.new(1, 300, 0, 222), 3)

	-- Rift-Button unten
	local rift = clearGroup(Vector2.new(240, 48))
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
		lifeLiquid.Size = UDim2.fromScale(1, 1 - SkillController.potionRatio())
		acc += dt
		if acc >= 0.15 then
			acc = 0
			updateMinimap()
		end
	end)
end

return HudController
