--!strict
-- World nameplates (Shared/Nameplate):
--   players: hero name + level over a thin life bar with the shield as a cyan strip (Path of Exile
--     style). Other players always; the local player only gets the bar, and only while hurt or
--     shielded (the HUD already shows the name).
--   stations: floating uppercase labels ("STASH", "FORGE", "RIFT GATE", ...) above the hub's
--     station triggers (tag "Station"), shown in range and faded out near the ProximityPrompt. The
--     active quest's station is gold and larger, matching the quest beam (WaypointController).
--     Decluttered on screen: a label that would overlap a nearer one (or the quest station's) or a
--     HUD block (Kit.markHudBlock: minimap, quest card, icon rows) fades out until it is clear.
-- Cheap on phones: one BillboardGui per player / station, engine culling via MaxDistance, one
-- shared fade loop every Nameplate.TICK seconds, property writes only when a value changed.
-- Purely client-side; the BillboardGuis live under the character / station part, so a respawn or
-- a stream-out removes them together with their parent.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Nameplate = require(ReplicatedStorage.Shared.Nameplate)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local QuestController = require(script.Parent.QuestController)

local NameplateController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local N = Theme.Nameplate

-- One faded property of an element: final = 1 - (1 - base) * alpha
type Fade = { inst: Instance, prop: string, base: number }

type Plate = {
	owner: Player,
	gui: BillboardGui,
	root: Frame,
	name: TextLabel?,
	bar: Frame,
	fill: Frame,
	shield: Frame,
	fades: { Fade },
	conns: { RBXScriptConnection },
	humanoid: Humanoid,
	alpha: number,
	own: boolean,
	barShown: boolean,
}

type Label = {
	part: BasePart,
	gui: BillboardGui,
	text: TextLabel,
	sub: TextLabel,
	rule: Frame,
	fades: { Fade },
	subFades: { Fade },
	window: string?,
	alpha: number,
	subShown: number, -- applied alpha of the "Locked" line
	clear: number, -- declutter share 0..1 (eases towards 1 while nothing is in the way)
	quest: boolean,
	locked: string?,
}

local screenRect: (camera: Camera, l: Label, withSub: boolean) -> Nameplate.Rect?
local plates: { [Player]: Plate } = {}
local labels: { [BasePart]: Label } = {}
local scale = 1 -- HUD size setting × touch factor, applied to every billboard

local function currentScale(): number
	return Kit.hudScale() * (if UserInputService.TouchEnabled then N.TouchScale else 1)
end

local function setAlpha(fades: { Fade }, a: number)
	for _, f in fades do
		(f.inst :: any)[f.prop] = 1 - (1 - f.base) * a
	end
end

local function fade(list: { Fade }, inst: Instance, prop: string)
	table.insert(list, { inst = inst, prop = prop, base = (inst :: any)[prop] })
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	color: Color3,
	font: Font
): TextLabel
	local t = Kit.label(value, size, color, font)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.TextSize = size
	t.TextScaled = false
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	Kit.textOutline(t, N.Stroke)
	t.Parent = parent
	return t
end

local function escape(s: string): string
	return (
		string.gsub(s, "[<>&\"']", {
			["<"] = "&lt;",
			[">"] = "&gt;",
			["&"] = "&amp;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

---------------------------------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------------------------------

local function plateSize(own: boolean): UDim2
	if own then
		return UDim2.fromOffset(N.OwnBarWidth * scale, (N.OwnBarHeight + 4) * scale)
	end
	return UDim2.fromOffset(N.Width * scale, (N.NameSize + N.BarHeight + 10) * scale)
end

local function layoutPlate(p: Plate)
	p.gui.Size = plateSize(p.own)
	local barW = (if p.own then N.OwnBarWidth else N.BarWidth) * scale
	local barH = (if p.own then N.OwnBarHeight else N.BarHeight) * scale
	p.bar.Size = UDim2.fromOffset(barW, barH)
	p.shield.Size = UDim2.new(p.shield.Size.X.Scale, 0, 0, math.max(1, N.ShieldHeight * scale))
	if p.name then
		p.name.TextSize = N.NameSize * scale
		p.name.Size = UDim2.new(1, 0, 0, (N.NameSize + 3) * scale)
	end
end

local function refreshName(p: Plate)
	local name = p.name
	if not name then
		return
	end
	local shown = Nameplate.displayName(p.owner:GetAttribute("CharacterName"), p.owner.DisplayName)
	local level = Nameplate.levelText(p.owner:GetAttribute("Level"))
	if level == "" then
		name.Text = escape(shown)
	else
		name.Text = string.format(
			'<font color="#%s" size="%d">%s</font>  %s',
			C.Gold:ToHex(),
			math.floor(N.LevelSize * scale + 0.5),
			level,
			escape(shown)
		)
	end
end

local function refreshBar(p: Plate)
	local h = p.humanoid
	local shield = p.owner:GetAttribute("Shield")
	local life = Nameplate.fill(h.Health, h.MaxHealth)
	local sh = Nameplate.fill(shield, h.MaxHealth)
	p.fill.Size = UDim2.fromScale(life, 1)
	p.fill.BackgroundColor3 = if life < N.LowLife then C.Danger else C.Life
	p.shield.Size = UDim2.new(sh, 0, 0, math.max(1, N.ShieldHeight * scale))
	p.shield.Visible = sh > 0
	if p.own then
		p.barShown = Nameplate.showOwnBar(
			h.Health,
			h.MaxHealth,
			if typeof(shield) == "number" then shield else 0
		)
	end
	p.gui.Enabled = h.Health > 0 and (not p.own or p.barShown) and p.alpha > 0
end

local function dropPlate(owner: Player)
	local p = plates[owner]
	if not p then
		return
	end
	plates[owner] = nil
	for _, c in p.conns do
		c:Disconnect()
	end
	if p.gui.Parent ~= nil then
		p.gui:Destroy()
	end
end

local function buildPlate(owner: Player, character: Model)
	dropPlate(owner)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local head = character:WaitForChild("Head", 10) or character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid:IsA("Humanoid") and head and head:IsA("BasePart")) then
		return
	end
	if owner.Character ~= character or not owner.Parent then
		return
	end
	local own = owner == player

	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.MaxDistance = Nameplate.PLAYER_FAR
	gui.StudsOffsetWorldSpace = Vector3.new(0, Nameplate.PLAYER_OFFSET, 0)
	gui.ClipsDescendants = false

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local fades: { Fade } = {}
	local nameLabel: TextLabel? = nil
	if not own then
		local t = text(root, "", N.NameSize, C.Text, Theme.Font.Title)
		t.Name = "Name"
		t.RichText = true
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.fromScale(0.5, 0)
		fade(fades, t, "TextTransparency")
		local stroke = t:FindFirstChild("Shadow")
		if stroke then
			fade(fades, stroke, "Transparency")
		end
		nameLabel = t
	end

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 1)
	bar.BackgroundColor3 = C.Bg0
	bar.BackgroundTransparency = N.BarBack
	bar.BorderSizePixel = 0
	bar.Parent = root
	Kit.corner(bar, 2)
	Kit.stroke(bar, C.Line2, 1)
	local edge = bar:FindFirstChildOfClass("UIStroke")
	fade(fades, bar, "BackgroundTransparency")
	if edge then
		fade(fades, edge, "Transparency")
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = C.Life
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	Kit.corner(fill, 2)
	fade(fades, fill, "BackgroundTransparency")

	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.BackgroundColor3 = C.Cyan
	shield.BorderSizePixel = 0
	shield.Size = UDim2.new(0, 0, 0, N.ShieldHeight)
	shield.Visible = false
	shield.ZIndex = 2
	shield.Parent = bar
	fade(fades, shield, "BackgroundTransparency")

	local p: Plate = {
		owner = owner,
		gui = gui,
		root = root,
		name = nameLabel,
		bar = bar,
		fill = fill,
		shield = shield,
		fades = fades,
		conns = {},
		humanoid = humanoid,
		alpha = 1,
		own = own,
		barShown = not own,
	}
	plates[owner] = p
	layoutPlate(p)
	refreshName(p)
	refreshBar(p)
	gui.Parent = head

	local function bar_()
		if plates[owner] == p then
			refreshBar(p)
		end
	end
	local function name_()
		if plates[owner] == p then
			refreshName(p)
		end
	end
	table.insert(p.conns, humanoid.HealthChanged:Connect(bar_))
	table.insert(p.conns, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(bar_))
	table.insert(p.conns, owner:GetAttributeChangedSignal("Shield"):Connect(bar_))
	table.insert(p.conns, owner:GetAttributeChangedSignal("CharacterName"):Connect(name_))
	table.insert(p.conns, owner:GetAttributeChangedSignal("Level"):Connect(name_))
	table.insert(
		p.conns,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) and plates[owner] == p then
				dropPlate(owner)
			end
		end)
	)
end

local function watchPlayer(owner: Player)
	owner.CharacterAdded:Connect(function(character: Model)
		buildPlate(owner, character)
	end)
	if owner.Character then
		task.spawn(buildPlate, owner, owner.Character)
	end
end

---------------------------------------------------------------------------------------------------
-- Stations
---------------------------------------------------------------------------------------------------

local function layoutLabel(l: Label)
	local size = (if l.quest then N.LabelSizeQuest else N.LabelSize) * scale
	local sub = N.SubSize * scale
	l.gui.Size = UDim2.fromOffset(N.LabelWidth * scale, size + sub + 12 * scale)
	l.text.TextSize = size
	l.text.Size = UDim2.new(1, 0, 0, size + 4 * scale)
	l.rule.Size =
		UDim2.fromOffset((if l.quest then 64 else 40) * scale, math.max(1, N.Rule * scale))
	l.rule.Position = UDim2.new(0.5, 0, 0, size + 5 * scale)
	l.sub.TextSize = sub
	l.sub.Size = UDim2.new(1, 0, 0, sub + 2 * scale)
	l.sub.Position = UDim2.new(0.5, 0, 0, size + 8 * scale)
end

local function styleLabel(l: Label)
	l.text.TextColor3 = if l.locked then C.Muted elseif l.quest then C.GoldHi else C.Text
	l.rule.BackgroundColor3 = if l.locked then C.Line2 else C.Gold
	local gem = l.rule:FindFirstChild("Gem")
	if gem and gem:IsA("Frame") then
		gem.BackgroundColor3 = if l.locked then C.Line2 elseif l.quest then C.GoldHi else C.Gold
		local g = math.max(4, 6 * scale)
		gem.Size = UDim2.fromOffset(g, g)
	end
	l.sub.Text = if l.locked then Nameplate.lockText(l.locked) else ""
	l.sub.Visible = l.locked ~= nil
	layoutLabel(l)
end

local function dropLabel(part: Instance)
	local l = labels[part :: BasePart]
	if not l then
		return
	end
	labels[part :: BasePart] = nil
	if l.gui.Parent ~= nil then
		l.gui:Destroy()
	end
end

local function buildLabel(inst: Instance)
	if not inst:IsA("BasePart") or labels[inst] then
		return
	end
	local title = inst:GetAttribute(Nameplate.LABEL_ATTR)
	if typeof(title) ~= "string" or title == "" then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Adornee = inst
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.MaxDistance = Nameplate.LABEL_FAR
	gui.StudsOffsetWorldSpace = Vector3.new(0, Nameplate.LABEL_OFFSET, 0)
	gui.Enabled = false

	local fades: { Fade } = {}
	local t = text(gui, string.upper(title), N.LabelSize, C.Text, Theme.Font.Title)
	t.Name = "Title"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.fromScale(0.5, 0)
	fade(fades, t, "TextTransparency")
	local stroke = t:FindFirstChild("Shadow")
	if stroke then
		fade(fades, stroke, "Transparency")
	end

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.BackgroundColor3 = C.Gold
	rule.BorderSizePixel = 0
	rule.Parent = gui
	fade(fades, rule, "BackgroundTransparency")
	-- small gold diamond in the middle of the rule (Gilded Ink accent)
	local gem = Instance.new("Frame")
	gem.Name = "Gem"
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = UDim2.fromScale(0.5, 0.5)
	gem.Rotation = 45
	gem.BorderSizePixel = 0
	gem.Parent = rule
	fade(fades, gem, "BackgroundTransparency")

	local subFades: { Fade } = {}
	local sub = text(gui, "", N.SubSize, C.Muted, Theme.Font.Body)
	sub.Name = "Sub"
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Visible = false
	fade(subFades, sub, "TextTransparency")
	local subStroke = sub:FindFirstChild("Shadow")
	if subStroke then
		fade(subFades, subStroke, "Transparency")
	end

	local l: Label = {
		part = inst,
		gui = gui,
		text = t,
		sub = sub,
		rule = rule,
		fades = fades,
		subFades = subFades,
		window = Nameplate.windowOf(inst),
		alpha = -1,
		subShown = -1,
		clear = 1,
		quest = false,
		locked = nil,
	}
	labels[inst] = l
	styleLabel(l)
	gui.Parent = inst
end

---------------------------------------------------------------------------------------------------
-- Shared fade loop
---------------------------------------------------------------------------------------------------

-- Rough text width when the engine has not measured the label yet (disabled billboard)
local function textWidth(t: TextLabel, factor: number): number
	local measured = t.TextBounds.X
	if measured > 0 then
		return measured
	end
	return (utf8.len(t.Text) or #t.Text) * t.TextSize * factor
end

-- Where a station label lands on the screen (pixels, viewport space like the HUD's IgnoreGuiInset
-- guis): the billboard is centered on its world point. nil behind the camera / off screen.
function screenRect(camera: Camera, l: Label, withSub: boolean): Nameplate.Rect?
	local world = l.part.Position + Vector3.new(0, Nameplate.LABEL_OFFSET, 0)
	local p, onScreen = camera:WorldToViewportPoint(world)
	if not onScreen or p.Z <= 0 then
		return nil
	end
	local h = l.gui.Size.Y.Offset
	local top = p.Y - h / 2
	local w = textWidth(l.text, 0.5)
	local bottom = top + l.text.Size.Y.Offset + 4 * scale -- title and its gold rule
	if withSub then
		w = math.max(w, textWidth(l.sub, 0.55))
		bottom = top + h
	end
	return { p.X - w / 2, top, p.X + w / 2, bottom }
end

local function eye(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	local d = a - b
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

local function questWindow(): string?
	if player:GetAttribute("RiftRegion") ~= nil then
		return nil
	end
	return Quests.waypoint(QuestController.state().step)
end

local function lockOf(window: string?): string?
	if window == "Forge" then
		return QuestController.lockHint("forge")
	elseif window == "Pets" then
		return QuestController.lockHint("pets")
	end
	return nil
end

function NameplateController.tick()
	local s = currentScale()
	local rescaled = math.abs(s - scale) > 1e-3
	scale = s
	local from = eye()

	for owner, p in plates do
		if p.gui.Parent == nil or not owner.Parent then
			dropPlate(owner)
			continue
		end
		if rescaled then
			layoutPlate(p)
			refreshName(p)
		end
		local a = 1
		if not p.own then
			local adornee = p.gui.Adornee
			a = if from
					and adornee
					and adornee:IsA("BasePart")
				then Nameplate.playerAlpha(flatDistance(from, adornee.Position))
				else 0
		end
		if math.abs(a - p.alpha) > 0.02 or (a == 0) ~= (p.alpha == 0) then
			p.alpha = a
			setAlpha(p.fades, a)
			refreshBar(p)
		end
	end

	local quest = questWindow()
	local inRift = player:GetAttribute("RiftRegion") ~= nil
	local camera = workspace.CurrentCamera
	local list: { Label } = {}
	local base: { number } = {}
	local subs: { number } = {}
	local rects: { Nameplate.Rect | false } = {}
	local priority: { number } = {}
	for part, l in labels do
		if l.gui.Parent == nil or part.Parent == nil then
			dropLabel(part)
			continue
		end
		local isQuest = quest ~= nil and l.window == quest
		local locked = lockOf(l.window)
		if isQuest ~= l.quest or locked ~= l.locked or rescaled then
			l.quest, l.locked = isQuest, locked
			styleLabel(l)
		end
		local dist = if from then flatDistance(from, part.Position) else math.huge
		local a = if from and not inRift then Nameplate.labelAlpha(dist) else 0
		local sa = if l.locked then Nameplate.subAlpha(dist) else 0
		table.insert(list, l)
		table.insert(base, a)
		table.insert(subs, sa)
		local rect = if a > 0 and camera then screenRect(camera, l, sa > 0) else nil
		table.insert(rects, rect or false)
		-- the quest station first, then the nearest
		table.insert(priority, (if isQuest then 1e6 else 0) - dist)
	end

	local free = Nameplate.declutter(rects, priority, Kit.hudBlockRects(), Nameplate.LABEL_GAP)
	for i, l in list do
		local goal = if free[i] then 1 else 0
		if l.clear < goal then
			l.clear = math.min(goal, l.clear + Nameplate.DECLUTTER_STEP)
		elseif l.clear > goal then
			l.clear = math.max(goal, l.clear - Nameplate.DECLUTTER_STEP)
		end
		local a = base[i] * l.clear
		if math.abs(a - l.alpha) > 0.02 or (a == 0) ~= (l.alpha == 0) then
			l.alpha = a
			setAlpha(l.fades, a)
			l.gui.Enabled = a > 0
		end
		local sa = a * subs[i]
		if math.abs(sa - l.subShown) > 0.02 or (sa == 0) ~= (l.subShown == 0) then
			l.subShown = sa
			setAlpha(l.subFades, sa)
		end
	end
end

function NameplateController.init()
	scale = currentScale()
end

function NameplateController.start()
	for _, owner in Players:GetPlayers() do
		watchPlayer(owner)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(dropPlate)

	for _, part in CollectionService:GetTagged(Nameplate.STATION_TAG) do
		buildLabel(part)
	end
	CollectionService:GetInstanceAddedSignal(Nameplate.STATION_TAG):Connect(buildLabel)
	CollectionService:GetInstanceRemovedSignal(Nameplate.STATION_TAG):Connect(dropLabel)

	while true do
		NameplateController.tick()
		task.wait(Nameplate.TICK)
	end
end

return NameplateController
