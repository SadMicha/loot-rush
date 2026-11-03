--!strict
-- UI kit building blocks (Luau version of tools/lr_ui_kit.py).
-- Every UI in the game is built from this - never invent your own colors/roundings.
-- Sizes are in design pixels (1600×900); the HUD scales via UIScale.
-- Look (since 2026-11): the flat code style of Theme.Flat (UI/Shape): rounded shapes, gradients,
-- programmed rarity glow and springs. Drawn 9-slice frames/buttons/slots are retired (Kit.skin returns nil);
-- only icons and scene pictures are images. New windows use UI/Flat directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Skills = require(ReplicatedStorage.Shared.Skills)
local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Shape = require(script.Parent.Shape)
local Spring = require(script.Parent.Spring)

local Kit = {}

function Kit.corner(parent: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Radius.M)
	c.Parent = parent
end

function Kit.stroke(parent: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.Flat.Edge
	s.Thickness = thickness or Theme.Flat.Stroke
	s.Parent = parent
end

function Kit.padding(parent: GuiObject, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	-- The background image should still fill the whole panel, not just the padded area
	local skin = parent:FindFirstChild("Skin")
	if skin and skin:IsA("GuiObject") then
		skin.Position = UDim2.fromOffset(-px, -px)
		skin.Size = UDim2.new(1, 2 * px, 1, 2 * px)
	end
end

-- Font size in design pixels -> actual TextSize (Theme.FontScale)
function Kit.fontSize(size: number): number
	return math.floor(size * Theme.FontScale + 0.5)
end

function Kit.list(
	parent: GuiObject,
	dir: Enum.FillDirection,
	gap: number,
	align: Enum.VerticalAlignment?
): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = align or Enum.VerticalAlignment.Center
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Parent = parent
	return l
end

-- Minimum sizes in real screen pixels (after UIScale). On small screens
-- small text always grows, buttons marked with Kit.touchTarget only on touch devices.
Kit.MIN_TEXT_PX = 9.5
Kit.MIN_TOUCH_PX = 33

-- Make a button at least Kit.MIN_TOUCH_PX large on touch devices (offset sizes only)
function Kit.touchTarget(b: GuiButton)
	b:SetAttribute("TouchTarget", true)
end

-- Keeps text and marked buttons under `root` above the minimum sizes; returns the re-apply function.
-- Each object remembers its design size itself (attributes) so it survives re-parenting and later changes.
local function minimums(root: Frame, scale: UIScale): () -> ()
	local texts: { [Instance]: true } = {}
	local hits: { [GuiButton]: true } = {}

	-- Total scale incl. further UIScales under the root (e.g. window content)
	local function scaleOf(d: Instance): number
		local s = scale.Scale
		local node: Instance? = d
		while node and node ~= root do
			local inner = node:FindFirstChildOfClass("UIScale")
			if inner then
				s *= inner.Scale
			end
			node = node.Parent
		end
		return s
	end

	local function fitText(t: any)
		if t.TextScaled then
			return
		end
		if t.TextSize ~= t:GetAttribute("FitTextSize") then
			t:SetAttribute("BaseTextSize", t.TextSize) -- size was set anew from outside
		end
		local want =
			math.max(t:GetAttribute("BaseTextSize"), math.ceil(Kit.MIN_TEXT_PX / scaleOf(t)))
		t:SetAttribute("FitTextSize", want)
		t.TextSize = want
	end

	local function fitHit(b: GuiButton)
		local base = b:GetAttribute("BaseSize") :: Vector2
		local min = if UserInputService.TouchEnabled
			then math.ceil(Kit.MIN_TOUCH_PX / scaleOf(b))
			else 0
		b.Size = UDim2.fromOffset(math.max(base.X, min), math.max(base.Y, min))
	end

	local function track(d: Instance)
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			if d:GetAttribute("BaseTextSize") == nil then
				local t: any = d
				d:SetAttribute("BaseTextSize", t.TextSize)
				d:GetPropertyChangedSignal("TextSize"):Connect(function()
					if texts[d] and t.TextSize ~= d:GetAttribute("FitTextSize") then
						fitText(t)
					end
				end)
			end
			texts[d] = true
			fitText(d)
		end
		if d:IsA("GuiButton") and d:GetAttribute("TouchTarget") then
			local size = d.Size
			if d:GetAttribute("BaseSize") == nil and size.X.Scale == 0 and size.Y.Scale == 0 then
				d:SetAttribute("BaseSize", Vector2.new(size.X.Offset, size.Y.Offset))
			end
			if d:GetAttribute("BaseSize") ~= nil then
				hits[d] = true
				fitHit(d)
			end
		end
	end
	root.DescendantAdded:Connect(track)
	root.DescendantRemoving:Connect(function(d: Instance)
		texts[d] = nil
		hits[d :: GuiButton] = nil
	end)

	return function()
		-- Skip (and forget) anything already destroyed: a parent's Destroy does not always fire
		-- DescendantRemoving for every nested child before the next refit
		for t in texts do
			if t.Parent then
				fitText(t)
			else
				texts[t] = nil
			end
		end
		for b in hits do
			if b.Parent then
				fitHit(b)
			else
				hits[b] = nil
			end
		end
	end
end

local refitters: { [Frame]: () -> () } = {}
local hudScale = 1 -- "HUD scale" setting: layers with their own design area grow/shrink by it
local hudRescalers: { () -> () } = {}

-- Sets the HUD scale (settings window) and rescales every HUD-like layer at once
function Kit.setHudScale(s: number)
	if typeof(s) ~= "number" or s ~= s or s <= 0 then
		return
	end
	if math.abs(s - hudScale) < 1e-3 then
		return
	end
	hudScale = s
	for _, fn in hudRescalers do
		fn()
	end
end

function Kit.hudScale(): number
	return hudScale
end

-- Re-apply minimum sizes after an inner UIScale has changed
function Kit.refit(root: Frame)
	local fn = refitters[root]
	if fn then
		fn()
	end
end

-- ScreenGui with a root frame that scales to the design resolution (1600×900).
-- UIScale also scales the root itself, so it gets the inverse size 1/s and fills the screen.
-- fit = true (fullscreen window): never smaller than the design area, even if the screen
-- has to be scaled down further for it (phone); the HUD stays at 0.55 minimum.
-- design = supplies its own design area instead of Theme.DesignSize (HUD on touch: smaller area =
-- larger elements); asked again on every size change.
-- Design area for HUD-like layers: desktop mock-up size, the compact touch size on phones and a
-- larger one on tablets so their HUD keeps phone proportions instead of growing past them
function Kit.hudDesign(): Vector2
	if not UserInputService.TouchEnabled then
		return Theme.DesignSize
	end
	local camera = workspace.CurrentCamera
	local v = if camera then camera.ViewportSize else Vector2.zero
	return if math.min(v.X, v.Y) >= Theme.TabletMinSide
		then Theme.HudDesignTablet
		else Theme.HudDesignTouch
end

function Kit.scaledGui(
	name: string,
	order: number,
	fit: boolean?,
	design: (() -> Vector2)?,
	safeArea: boolean?
): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	if safeArea then
		-- Notch / rounded corners: the root only covers the area that is safe on this device
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local reapply = minimums(root, scale)
	refitters[root] = reapply

	local function rescale()
		local camera = workspace.CurrentCamera
		if camera then
			local v = camera.ViewportSize
			if safeArea and gui.AbsoluteSize.X > 0 then
				v = gui.AbsoluteSize -- smaller than the viewport by the device insets
			end
			-- HUD scale: a smaller design area makes every element larger
			local d = if design then design() / hudScale else Theme.DesignSize
			local s = math.clamp(math.min(v.X / d.X, v.Y / d.Y), if fit then 0.3 else 0.55, 1.4)
			scale.Scale = s
			root.Size = UDim2.fromScale(1 / s, 1 / s)
			reapply()
		end
	end
	rescale()
	if design then
		table.insert(hudRescalers, rescale)
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	if safeArea then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	end
	return gui, root
end

-- Former 9-slice skin (drawn frames). With the flat look it styles `parent` as a flat surface instead
-- (tile / raised / banner by the old image name) and returns an invisible "Skin" marker, so call sites
-- that only add a fallback when nil keep working unchanged. The UIStroke is named "Edge".
local RAISED: { [string]: boolean } = { btn_sort = true, header_banner = true }

function Kit.skin(
	parent: GuiObject,
	name: string,
	_height: number?,
	_maxScale: number?
): ImageLabel?
	local F = Theme.Flat
	local raised = RAISED[name] == true
	parent.BackgroundColor3 = if raised then F.Surface3 else F.Surface2
	parent.BackgroundTransparency = if raised then 0.05 else 0.25
	parent.BorderSizePixel = 0
	if not parent:FindFirstChildOfClass("UICorner") then
		Shape.corner(parent, F.Radius.M)
	end
	if not parent:FindFirstChildOfClass("UIStroke") then
		local edge = Shape.stroke(parent, if raised then F.EdgeHi else F.Edge)
		edge.Name = "Edge"
	end
	local marker = Instance.new("ImageLabel")
	marker.Name = "Skin"
	marker.BackgroundTransparency = 1
	marker.ImageTransparency = 1
	marker.Size = UDim2.fromScale(1, 1)
	marker.ZIndex = 0
	marker.Parent = parent
	return marker
end

-- Standard panel: flat card (Theme.Flat), `accent` tints the edge
function Kit.panel(size: Vector2, accent: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size.X, size.Y)
	Shape.card(f, nil, accent)
	return f
end

-- Panel that can fly in and out (CanvasGroup -> one fade for all children)
function Kit.flyPanel(size: Vector2): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Size = UDim2.fromOffset(size.X, size.Y)
	Shape.card(g)
	return g
end

-- Drop shadow for text: thin dark outline (Theme.Shadow)
function Kit.textShadow(t: TextLabel)
	local shadow = Instance.new("UIStroke")
	shadow.Name = "Shadow"
	shadow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	shadow.LineJoinMode = Enum.LineJoinMode.Round
	shadow.Color = Theme.Shadow.Color
	shadow.Thickness = Theme.Shadow.TextThickness
	shadow.Transparency = Theme.Shadow.TextTransparency
	shadow:SetAttribute("Base", shadow.Transparency)
	shadow.Parent = t
	t.TextStrokeTransparency = 1 -- one outline only (the UIStroke); no second built-in text stroke
end

-- Outline strength of a label made by Kit.label / Kit.textShadow (0 = solid, 1 = none)
function Kit.textOutline(t: TextLabel, transparency: number)
	local shadow = t:FindFirstChild("Shadow")
	if shadow and shadow:IsA("UIStroke") then
		shadow.Transparency = transparency
		shadow:SetAttribute("Base", transparency)
	else
		t.TextStrokeTransparency = transparency
	end
end

-- Text transparency incl. its outline (the outline fades with the text)
function Kit.setTextTransparency(t: TextLabel, transparency: number)
	t.TextTransparency = transparency
	local shadow = t:FindFirstChild("Shadow")
	if shadow and shadow:IsA("UIStroke") then
		local base = shadow:GetAttribute("Base")
		local b = if typeof(base) == "number" then base else Theme.Shadow.TextTransparency
		shadow.Transparency = 1 - (1 - b) * (1 - transparency)
	end
end

function Kit.label(text: string, size: number, color: Color3?, font: Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = Kit.fontSize(size)
	t.TextColor3 = color or Theme.Color.Text
	t.FontFace = font or Theme.Font.UI
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.fromOffset(0, 0)
	Kit.textShadow(t)
	return t
end

-- Drop shadow for an image icon: the returned image is an invisible holder (the caller sizes, places and
-- parents it) with two children: "Shadow" (dark copy, offset down-right by Theme.Shadow.Offset) and
-- "Face" (the crisp icon exactly at the holder's position, so it stays centered in slots and rings).
function Kit.shadowed(img: ImageLabel): ImageLabel
	local holder = img:Clone()
	holder.Image = ""
	holder.ImageRectOffset = Vector2.zero
	holder.ImageRectSize = Vector2.zero
	holder.BackgroundTransparency = 1
	local back = img:Clone()
	back.Name = "Shadow"
	back.ImageColor3 = Theme.Shadow.Color
	back.ImageTransparency = Theme.Shadow.Transparency
	back.AnchorPoint = Vector2.zero
	back.Position = UDim2.fromScale(Theme.Shadow.Offset, Theme.Shadow.Offset)
	back.Size = UDim2.fromScale(1, 1)
	back.ZIndex = 1
	back.Parent = holder
	img.Name = "Face"
	img.AnchorPoint = Vector2.zero
	img.Position = UDim2.fromScale(0, 0)
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 2
	img.Parent = holder
	return holder
end

-- Icon transparency incl. its shadow (dimmed / disabled icons)
function Kit.setIconTransparency(icon: GuiObject, transparency: number)
	if not icon:IsA("ImageLabel") then
		return
	end
	local face = icon:FindFirstChild("Face")
	if face and face:IsA("ImageLabel") then
		face.ImageTransparency = transparency
		local back = icon:FindFirstChild("Shadow")
		if back and back:IsA("ImageLabel") then
			back.ImageTransparency = math.max(transparency, Theme.Shadow.Transparency)
		end
	else
		icon.ImageTransparency = transparency
	end
end

-- ------------------------------------------------------------------ Class art
-- Class of the local player (attribute "Class", Systems/Characters); Theme.Class.Default before load.
function Kit.playerClass(): string
	local value = Players.LocalPlayer:GetAttribute("Class")
	if typeof(value) == "string" and Theme.Class.SkillName[string.lower(value)] then
		return string.lower(value)
	end
	return string.lower(Theme.Class.Default)
end

-- Icon name for an item slot (helmet, armor, ...): class art if uploaded, otherwise the atlas icon
function Kit.equipIcon(slot: string, fallback: string): string
	local file = Theme.Class.EquipSlot[slot]
	local key = if file then "equip_" .. Kit.playerClass() .. "_" .. file else ""
	return if Assets.Class[key] then key else fallback
end

-- Class art key of a skill ("dash" for the dash button) or nil without uploaded art
function Kit.skillArt(skillId: string): string?
	local skill = Skills.ById[skillId]
	local pos = Theme.Class.SkillSlot[skillId] or (if skill then skill.art else nil)
	local class = Kit.playerClass()
	local names = Theme.Class.SkillName[class]
	if not pos or not names then
		return nil
	end
	local key = string.format("skill_%s_%02d_%s", class, pos, names[pos])
	return if Assets.Class[key] then key else nil
end

-- Icon name of a skill for Kit.icon / Kit.itemSlot: class art if uploaded, otherwise the atlas icon
function Kit.skillIcon(skillId: string, fallback: string): string
	return Kit.skillArt(skillId) or fallback
end

-- Icon from the atlas image (Assets.Icon), otherwise a neutral placeholder
function Kit.icon(name: string, size: number, color: Color3?): GuiObject
	local classArt = Assets.Class[name]
	if classArt then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon_" .. name
		img.BackgroundTransparency = 1
		img.Image = classArt.id
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromOffset(size, size)
		return Kit.shadowed(img)
	end
	local icon = Assets.Icon[name]
	if icon then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon_" .. name
		img.BackgroundTransparency = 1
		img.Image = icon.id
		img.ImageRectOffset = icon.offset
		img.ImageRectSize = Assets.IconSize
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromOffset(size, size)
		return Kit.shadowed(img)
	end
	local ph = Instance.new("Frame")
	ph.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
	ph.BackgroundTransparency = 1
	Kit.corner(ph, math.floor(size * 0.2))
	Kit.stroke(ph, color or Theme.Color.Muted, 2)
	ph.Name = "Placeholder_" .. name
	return ph
end

export type SlotOptions = {
	rarity: string?, -- nil = empty slot
	count: number?, -- stack count bottom left
	selected: boolean?,
	dim: boolean?, -- icon dimmed (empty equipment slot)
	round: boolean?, -- circle (tree nodes)
	tint: Color3?, -- edge/glow color instead of the rarity color
}

local function slotBase(size: number, rarity: string?, opts: SlotOptions?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = "Slot"
	b.Image = ""
	b.Size = UDim2.fromOffset(size, size)
	b.AutoButtonColor = false
	local o: SlotOptions = opts or {}
	Shape.cell(b, size, { rarity = rarity, selected = o.selected, round = o.round, tint = o.tint })
	return b
end

local function slotIcon(b: GuiObject, size: number, iconName: string, edge: Color3?, dim: boolean?)
	local ic = Kit.icon(iconName, math.floor(size * 0.64), edge)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = 2
	if dim then
		Kit.setIconTransparency(ic, 0.7)
	end
	ic.Parent = b
end

-- Item slot: flat cell with rarity tint, edge and glow (UI/Shape), icon on top, hover/press springs
function Kit.itemSlot(size: number, iconName: string?, opts: SlotOptions?): ImageButton
	local o: SlotOptions = opts or {}
	local edge = if o.rarity then Theme.Rarity[o.rarity] or Theme.Rarity.normal else nil
	local b = slotBase(size, o.rarity, o)
	if iconName then
		slotIcon(b, size, iconName, edge, o.dim)
	end
	if o.count then
		local c = Kit.label(tostring(o.count), math.max(11, size // 6), Theme.Color.Text)
		c.AnchorPoint = Vector2.new(1, 1)
		c.Position = UDim2.new(1, -6, 1, -4)
		c.ZIndex = 4
		c.Parent = b
	end
	-- Hover/press springs only for clickable slots (callers turn display slots off with Active = false)
	task.defer(function()
		if b.Active and b.Parent then
			Shape.motion(b, if o.selected then Theme.Flat.SelectScale else 1)
		end
	end)
	return b
end

-- Square slot (skills) with centered icon and optional key label
function Kit.slot(size: number, iconName: string, edge: Color3?, key: string?): ImageButton
	local f = slotBase(size, "normal", { tint = edge })
	f.Active = false
	slotIcon(f, size, iconName, edge)
	if key then
		-- Key at the bottom of the slot like in hud_hotbar; the icon moves up a bit for it
		local ic = f:FindFirstChild("Icon_" .. iconName)
		if ic and ic:IsA("GuiObject") then
			ic.Position = UDim2.fromScale(0.5, 0.42)
		end
		local k = Kit.label(key, 11, Theme.Color.Text)
		k.AnchorPoint = Vector2.new(0.5, 1)
		k.Position = UDim2.new(0.5, 0, 1, -2)
		Kit.textOutline(k, 0.3)
		k.ZIndex = 3
		k.Parent = f
	end
	return f
end

-- Button color -> flat style: gold = primary (gold gradient, dark text), danger = red, otherwise a dark
-- surface whose edge and sheen carry the color
local function buttonStyle(color: Color3): (Color3, Color3, Color3, Color3)
	local F = Theme.Flat
	if color == Theme.Color.Gold then
		return Theme.Color.GoldHi, Theme.Color.GoldLo, Theme.Color.GoldHi, F.Surface0
	elseif color == Theme.Color.Danger then
		return Theme.Color.Danger, Theme.Color.Life, Theme.Color.Danger, Theme.Color.Text
	end
	return F.Surface3:Lerp(color, 0.18), F.Surface2, color, Theme.Color.Text
end

-- Text of the button (lives in a child label)
function Kit.buttonLabel(b: GuiObject): TextLabel
	return b:FindFirstChild("Label") :: TextLabel
end

-- Button on/off: dims it and blocks input
function Kit.setEnabled(b: ImageButton, enabled: boolean)
	b.Active = enabled
	b:SetAttribute("Enabled", enabled)
	b.BackgroundTransparency = if enabled then 0 else 0.1
	Shape.setDisabledLook(b, enabled)
	local edge = b:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Transparency = if enabled then 0.25 else 0.3
	end
	local label = Kit.buttonLabel(b)
	if label then
		local base = label:GetAttribute("BaseColor")
		if typeof(base) ~= "Color3" then
			label:SetAttribute("BaseColor", label.TextColor3)
			base = label.TextColor3
		end
		label.TextColor3 = if enabled then base :: Color3 else Theme.Color.Muted
		Kit.setTextTransparency(label, if enabled then 0 else 0.25)
	end
end

-- Text button (gold = primary action, danger = red, otherwise the color tints a dark button), optionally
-- with an icon left of the text. Returns an ImageButton; set the text via Kit.buttonLabel(b).Text.
function Kit.button(text: string, color: Color3, size: Vector2, iconName: string?): ImageButton
	local top, bottom, edgeColor, textColor = buttonStyle(color)
	local b = Instance.new("ImageButton")
	b.Image = ""
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BackgroundTransparency = 0
	Kit.touchTarget(b)
	Shape.corner(b, Theme.Flat.Radius.M)
	Shape.gradient(b, top, bottom)
	local edge = Shape.stroke(b, edgeColor, Theme.Flat.Stroke, 0.25)
	edge.Name = "Edge"
	if color == Theme.Color.Gold then
		Shape.topLine(b, 0.45)
		Shape.shine(b, Theme.Flat.Radius.M)
	else
		Shape.topLine(b)
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextSize = Kit.fontSize(17)
	label.FontFace = Theme.Font.UI
	label.TextColor3 = textColor
	label.ZIndex = 2
	label.Parent = b
	if iconName then
		local s = math.floor(size.Y * 0.5)
		local ic = Kit.icon(iconName, s)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 18, 0.5, 0)
		ic.ZIndex = 2
		ic.Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, s + 18)
		pad.Parent = label
	end
	Shape.motion(b)
	return b
end

-- Bar (life, progress). Returns frame and fill; the fill is scaled via Size.X.
function Kit.bar(size: Vector2, color: Color3): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(size.X, size.Y)
	back.BorderSizePixel = 0
	back.BackgroundColor3 = Theme.Flat.Surface0
	back.BackgroundTransparency = 0.1
	Shape.corner(back, Theme.Flat.Radius.S)
	Shape.stroke(back, Theme.Flat.Edge, 1)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	Shape.corner(fill, Theme.Flat.Radius.S)
	Shape.gradient(fill, color:Lerp(Color3.new(1, 1, 1), 0.25), color, 0, 0, 0)
	Shape.topLine(fill, 0.55, 0)
	fill.Parent = back
	return back, fill
end

-- ------------------------------------------------------------------ In-game HUD pieces
-- Image from Assets.Hud at a fixed size; nil if it has not been uploaded yet (-> flat fallback)
-- Drawn HUD frames (orb glass, rings, minimap frame, charge diamonds) are retired with the flat look;
-- skill and menu icons stay images.
local HUD_FRAME: { [string]: boolean } = {
	orb_health_frame = true,
	orb_health_fill = true,
	orb_mana_frame = true,
	orb_mana_fill = true,
	minimap_frame = true,
	ring_gold = true,
	ring_silver = true,
	hud_diamond_cyan = true,
	hud_diamond_dark = true,
}

function Kit.hudImage(name: string, size: Vector2, shadow: boolean?): ImageLabel?
	local fixed = if HUD_FRAME[name] then nil else Assets.Hud[name] or Assets.Class[name]
	if not fixed then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = fixed.id
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.fromOffset(size.X, size.Y)
	if shadow then
		return Kit.shadowed(img)
	end
	return img
end

local function circle(f: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
end

export type Orb = {
	root: Frame,
	setRatio: (ratio: number) -> (),
	text: TextLabel,
}

-- Orb (life / experience): metal frame on top, liquid below that is clipped from the top as the value
-- drops (frame and fill share one canvas, see Assets.Hud). kind = "health" | "mana".
function Kit.orb(size: number, kind: string, color: Color3): Orb
	local H = Theme.Hud
	local span = H.OrbBottom - H.OrbTop
	local diameter = math.floor(size * span)
	local frameImg = Kit.hudImage("orb_" .. kind .. "_frame", Vector2.new(size, size)) -- no shadow: must stay aligned with the liquid
	local fillImg = Kit.hudImage("orb_" .. kind .. "_fill", Vector2.new(size, size))

	local root = Instance.new("Frame")
	root.Name = "Orb_" .. kind
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)

	-- Dark well behind the liquid, so an empty orb still reads as an orb
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.AnchorPoint = Vector2.new(0.5, 0.5)
	well.Position = UDim2.fromScale(0.5, (H.OrbTop + H.OrbBottom) / 2)
	well.Size = UDim2.fromOffset(diameter, diameter)
	well.BackgroundColor3 = Theme.Flat.Surface0
	well.BackgroundTransparency = 0.15
	well.BorderSizePixel = 0
	circle(well)
	if not frameImg then
		-- Flat orb: colored rim with a soft glow
		Shape.stroke(well, color, 2.5, 0.1)
		Shape.glow(well, color, 2, true, diameter // 2)
	end
	well.Parent = root

	-- Clip window from the bottom edge of the orb upward
	local clip = Instance.new("Frame")
	clip.Name = "Fill"
	clip.AnchorPoint = Vector2.new(0, 1)
	clip.Position = UDim2.fromScale(0, H.OrbBottom)
	clip.Size = UDim2.fromOffset(size, 0)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.ZIndex = 2
	clip.Parent = root
	if fillImg and frameImg then
		-- The image stays aligned to the canvas, only the window shrinks
		fillImg.AnchorPoint = Vector2.new(0, 1)
		fillImg.Position = UDim2.new(0, 0, 1, math.floor(size * (1 - H.OrbBottom)))
		fillImg.Parent = clip
	else
		local liquid = Instance.new("Frame")
		liquid.Name = "Liquid"
		liquid.AnchorPoint = Vector2.new(0.5, 1)
		liquid.Position = UDim2.fromScale(0.5, 1)
		liquid.Size = UDim2.fromOffset(diameter, diameter)
		liquid.BackgroundColor3 = Color3.new(1, 1, 1)
		liquid.BorderSizePixel = 0
		circle(liquid)
		Shape.gradient(
			liquid,
			color:Lerp(Color3.new(1, 1, 1), 0.25),
			color:Lerp(Theme.Flat.Surface0, 0.35)
		)
		liquid.Parent = clip
		-- Glass highlight at the top left
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.AnchorPoint = Vector2.new(0.5, 0.5)
		gloss.Position = UDim2.fromScale(0.5, H.OrbTop + span * 0.24)
		gloss.Size = UDim2.fromOffset(diameter * 0.55, diameter * 0.22)
		gloss.BackgroundColor3 = Color3.new(1, 1, 1)
		gloss.BorderSizePixel = 0
		gloss.ZIndex = 4
		circle(gloss)
		Shape.gradient(gloss, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0.7, 1)
		gloss.Parent = root
	end
	if frameImg then
		frameImg.ZIndex = 3
		frameImg.Parent = root
	end

	local text = Kit.label("", 13)
	text.Name = "Value"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, (H.OrbTop + H.OrbBottom) / 2)
	Kit.textOutline(text, 0.25)
	text.ZIndex = 5
	text.Parent = root

	local function setRatio(ratio: number)
		local r = math.clamp(ratio, 0, 1)
		TweenService:Create(
			clip,
			Theme.Tween.Bar,
			{ Size = UDim2.fromOffset(size, math.floor(diameter * r + 0.5)) }
		):Play()
	end
	return { root = root, setRatio = setRatio, text = text }
end

-- Round cooldown veil over a button: dark layer that shrinks from the top down (ratio 1 = just started)
-- with the remaining seconds as text. Returns the update function.
function Kit.cooldownVeil(parent: GuiObject): (number, number) -> ()
	local veil = Instance.new("Frame")
	veil.Name = "CooldownVeil"
	veil.AnchorPoint = Vector2.new(0.5, 0.5)
	veil.Position = UDim2.fromScale(0.5, 0.5)
	veil.Size = UDim2.fromScale(0.84, 0.84)
	veil.BackgroundColor3 = Theme.Color.Bg0
	veil.BorderSizePixel = 0
	veil.ZIndex = 4
	veil.Visible = false
	circle(veil)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90 -- top (0) to bottom (1)
	gradient.Parent = veil
	veil.Parent = parent
	local text = Kit.label("", 18)
	text.Name = "CooldownText"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	Kit.textOutline(text, 0.3)
	text.ZIndex = 5
	text.Parent = parent

	-- Ready flash: a bright disc that fades out and a small bounce when the cooldown ends
	local flash = Instance.new("Frame")
	flash.Name = "ReadyFlash"
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = UDim2.fromScale(0.5, 0.5)
	flash.Size = UDim2.fromScale(0.84, 0.84)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 5
	circle(flash)
	flash.Parent = parent

	local lastStep = -1
	return function(ratio: number, remaining: number)
		local step = math.floor(math.clamp(ratio, 0, 1) * 100 + 0.5)
		if step ~= lastStep then
			if step == 0 and lastStep > 0 then
				flash.BackgroundTransparency = 0.45
				Spring.target(flash, { BackgroundTransparency = 1 }, "Soft")
				local motion = parent:FindFirstChild("Motion")
				if motion and motion:IsA("UIScale") then
					Spring.impulse(motion, "Scale", 2.5, "Bouncy")
				end
			end
			lastStep = step
			veil.Visible = step > 0
			-- Hard edge: clear above, veil below; the veil covers the lower `ratio` part
			local edge = math.clamp(1 - ratio, 0.001, 0.998)
			local veilT = Theme.Hud.Veil
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(edge, 1),
				NumberSequenceKeypoint.new(edge + 0.001, veilT),
				NumberSequenceKeypoint.new(1, veilT),
			})
		end
		-- Whole seconds while long, tenths for the last moments (easier to read at a glance)
		text.Text = if step <= 0
			then ""
			elseif remaining >= 3 then tostring(math.ceil(remaining))
			else string.format("%.1f", remaining)
	end
end

-- Round HUD button (skill, dash): ring image with icon in the center, optional key label (keyboard only)
-- and cooldown veil. ring = "gold" | "cyan" (cyan = tinted silver ring). Returns button and veil updater.
-- Swaps the picture inside a Kit.roundButton (e.g. the skill bar after a loadout change)
function Kit.setRoundIcon(b: GuiObject, artName: string?, fallbackIcon: string?)
	local old = b:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	local inner = math.floor(b.Size.X.Offset * 0.66)
	local ic: GuiObject? = nil
	if artName then
		ic = Kit.hudImage(artName, Vector2.new(inner, inner), true)
	end
	if not ic and fallbackIcon then
		ic = Kit.icon(fallbackIcon, inner, Theme.Color.Muted)
	end
	if ic then
		ic.Name = "Icon"
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = 2
		ic.Parent = b
	end
end

function Kit.roundButton(
	size: number,
	ring: string,
	artName: string?,
	fallbackIcon: string?,
	key: string?
): (ImageButton, (number, number) -> ())
	local b = Instance.new("ImageButton")
	b.Name = "RoundButton"
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	Kit.touchTarget(b)
	local ringName = if ring == "gold" then "ring_gold" else "ring_silver"
	local ringArt = if HUD_FRAME[ringName] then nil else Assets.Hud[ringName]
	if ringArt then
		b.Image = ringArt.id
		b.ScaleType = Enum.ScaleType.Fit
		if ring ~= "gold" then
			b.ImageColor3 = Theme.Hud.RingCyan
		end
	else
		-- Flat ring: dark disc with a gradient, colored rim and glow
		local rim = if ring == "gold" then Theme.Color.Gold else Theme.Color.Cyan
		b.BackgroundTransparency = 0.05
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		circle(b)
		Shape.gradient(b, Theme.Flat.Surface3, Theme.Flat.Surface0)
		Shape.stroke(b, rim, 2.5, 0.05)
		Shape.glow(b, rim, if ring == "gold" then 2 else 1, false, size // 2)
	end

	Kit.setRoundIcon(b, artName, fallbackIcon)
	if key then
		local k = Kit.label(key, 11)
		k.Name = "Key"
		k.AnchorPoint = Vector2.new(0.5, 1)
		k.Position = UDim2.new(0.5, 0, 1, -2)
		Kit.textOutline(k, 0.3)
		k.ZIndex = 6
		k.Parent = b
	end
	local update = Kit.cooldownVeil(b)
	Shape.motion(b)
	return b, update
end

-- Dock plate inside a container (hub bar): dark glass that gets denser toward the bottom, a gold
-- hairline that glows in the middle and fades to the ends, light along the top. The plate is inset
-- a little so its edge also shows inside a CanvasGroup. Returns the "Row" frame (inner padding
-- `pad` left/right/top, half of it at the bottom; the container needs that much extra room)
-- where the caller puts its layout and buttons.
function Kit.dock(f: GuiObject, pad: number): Frame
	local F = Theme.Flat
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Active = false
	plate.BorderSizePixel = 0
	plate.BackgroundColor3 = F.Surface0
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.new(1, -4, 1, -4)
	plate.ZIndex = 0
	Shape.corner(plate, F.Radius.L)
	Shape.gradient(plate, F.Surface1, F.Surface0, 0.5, 0.1)
	local edge = Shape.stroke(plate, Color3.new(1, 1, 1), 1.5, 0)
	edge.Name = "Edge"
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, F.EdgeHi),
		ColorSequenceKeypoint.new(0.5, Theme.Color.Gold),
		ColorSequenceKeypoint.new(1, F.EdgeHi),
	})
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0.75),
	})
	g.Parent = edge
	Shape.topLine(plate, 0.8)
	plate.Parent = f
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 1
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, pad)
	p.PaddingRight = UDim.new(0, pad)
	p.PaddingTop = UDim.new(0, pad)
	p.PaddingBottom = UDim.new(0, math.floor(pad / 2))
	p.Parent = row
	row.Parent = f
	return row
end

-- Bare icon button (hub bar, settings): no frame, caption below. artName = Assets.Hud key,
-- fallbackIcon = atlas icon while the image is missing. Hit area = whole cell.
function Kit.hudIconButton(
	size: number,
	artName: string,
	fallbackIcon: string,
	caption: string?
): ImageButton
	local captionH = if caption then Theme.Hud.BarCaption else 0
	local b = Instance.new("ImageButton")
	b.Name = fallbackIcon
	b.Size = UDim2.fromOffset(size + 12, size + captionH)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	Kit.touchTarget(b)
	local ic: GuiObject = Kit.hudImage(artName, Vector2.new(size, size), true)
		or Kit.icon(fallbackIcon, size, Theme.Color.Muted)
	ic.AnchorPoint = Vector2.new(0.5, 0)
	ic.Position = UDim2.fromScale(0.5, 0)
	ic.ZIndex = 2
	ic.Parent = b
	if caption then
		local t = Kit.label(caption, 10, Theme.Color.Text)
		t.AutomaticSize = Enum.AutomaticSize.None
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.fromScale(0.5, 1)
		t.Size = UDim2.new(1, 0, 0, captionH)
		t.TextXAlignment = Enum.TextXAlignment.Center
		Kit.textOutline(t, 0.3)
		t.ZIndex = 3
		t.Parent = b
	end
	Shape.motion(b)
	return b
end

-- Charge diamonds (dash): one per maximum charge, cyan = available, dark = spent. Images
-- hud_diamond_cyan / hud_diamond_dark, flat rotated squares until they are uploaded.
-- Returns the row and its updater (available charges, maximum charges).
function Kit.chargePips(size: number): (Frame, (available: number, max: number) -> ())
	local row = Instance.new("Frame")
	row.Name = "ChargePips"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.fromOffset(0, size)
	local layout = Kit.list(row, Enum.FillDirection.Horizontal, 2)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local cyan: Assets.Fixed?, dark: Assets.Fixed? = nil, nil -- drawn diamonds retired (flat look)
	local pips: { GuiObject } = {}
	local function paint(pip: GuiObject, on: boolean)
		if pip:IsA("ImageLabel") then
			if cyan and dark then
				pip.Image = if on then cyan.id else dark.id
			end
			return
		end
		local flat = pip:FindFirstChild("Diamond")
		if flat and flat:IsA("Frame") then
			flat.BackgroundColor3 = if on then Theme.Color.Cyan else Theme.Color.Bg2
		end
	end
	local function newPip(): GuiObject
		if cyan and dark then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.ScaleType = Enum.ScaleType.Fit
			img.Size = UDim2.fromOffset(size, size)
			return img
		end
		-- Flat fallback: rotated square in a cell
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromOffset(size, size)
		local f = Instance.new("Frame")
		f.Name = "Diamond"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(size * 0.6, size * 0.6)
		f.BorderSizePixel = 0
		f.Rotation = 45
		Kit.stroke(f, Theme.Color.Cyan, 1)
		f.Parent = cell
		return cell
	end
	local function update(available: number, max: number)
		while #pips > max do
			local last = table.remove(pips)
			if last then
				last:Destroy()
			end
		end
		while #pips < max do
			local pip = newPip()
			pip.Name = "Pip"
			pip.LayoutOrder = #pips + 1
			pip.Parent = row
			table.insert(pips, pip)
		end
		for i, pip in pips do
			paint(pip, i <= available)
		end
	end
	return row, update
end

local PILL_HEIGHT = 40
local PILL_PLUS = 30

-- Resource display: capsule with icon on the left, number in the middle and its own + button on the right.
-- Returns capsule, number label and + button.
function Kit.pill(iconName: string, text: string, color: Color3?): (Frame, TextLabel, ImageButton?)
	local c = color or Theme.Color.Gold
	local F = Theme.Flat
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(190, PILL_HEIGHT)
	f.BackgroundColor3 = F.Surface1
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
	Shape.corner(f, F.Radius.M)
	Shape.stroke(f, F.Edge)
	-- Faint color wash from the icon side, a colored accent bar on the left edge and top light
	local wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.BackgroundColor3 = c
	wash.BorderSizePixel = 0
	wash.Size = UDim2.fromScale(1, 1)
	wash.Active = false
	Shape.corner(wash, F.Radius.M)
	Shape.gradient(wash, c, c, 0.78, 1, 0)
	wash.Parent = f
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = c
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 3, 1, -10)
	accent.Position = UDim2.fromOffset(0, 5)
	accent.Active = false
	accent.Parent = f
	Shape.topLine(f)
	local ic = Kit.icon(iconName, math.floor(PILL_HEIGHT * 0.66), c)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0, math.floor(PILL_HEIGHT * 0.5) + 2, 0.5, 0)
	ic.ZIndex = 2
	ic.Parent = f

	-- Invisible hit area (grows on touch); the round + sits fixed at the right edge
	local plus = Instance.new("ImageButton")
	plus.Name = "Plus"
	plus.Image = ""
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.new(1, -5, 0.5, 0)
	plus.Size = UDim2.fromOffset(PILL_PLUS, PILL_PLUS)
	plus.AutoButtonColor = false
	plus.BackgroundTransparency = 1
	plus.BorderSizePixel = 0
	plus.ZIndex = 3
	Kit.touchTarget(plus)
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(1, 0.5)
	disc.Position = UDim2.fromScale(1, 0.5)
	disc.Size = UDim2.fromOffset(PILL_PLUS, PILL_PLUS)
	disc.BackgroundColor3 = Color3.new(1, 1, 1)
	disc.BorderSizePixel = 0
	disc.ZIndex = 3
	Shape.corner(disc, F.Radius.M)
	Shape.gradient(disc, c:Lerp(Color3.new(1, 1, 1), 0.2), c:Lerp(F.Surface0, 0.25))
	Shape.topLine(disc, 0.5, 0)
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = "+"
	glyph.TextColor3 = F.Surface0
	glyph.FontFace = Theme.Font.UI
	glyph.TextSize = Kit.fontSize(18)
	glyph.ZIndex = 4
	glyph.Parent = disc
	disc.Parent = plus
	plus.MouseButton1Down:Connect(function()
		Spring.target(disc, { Size = UDim2.fromOffset(PILL_PLUS - 4, PILL_PLUS - 4) }, "Snappy")
	end)
	local function release()
		Spring.target(disc, { Size = UDim2.fromOffset(PILL_PLUS, PILL_PLUS) }, "Bouncy")
	end
	plus.MouseButton1Up:Connect(release)
	plus.MouseLeave:Connect(release)
	plus.Parent = f

	local leftW = PILL_HEIGHT + 4
	local rightW = PILL_PLUS + 10
	local t = Kit.label(text, 17, Theme.Color.Text, Theme.Font.Number)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, -(leftW + rightW), 1, 0)
	t.Position = UDim2.fromOffset(leftW, 0)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.ZIndex = 2
	t.Parent = f
	return f, t, plus
end

export type IconButtonKind = "nav" | "tab" | "close"

-- Icon button: menu (nav), filter tab (tab) or close (close). Text only as a name.
function Kit.iconButton(
	iconName: string,
	label: string,
	size: number?,
	active: boolean?,
	kind: IconButtonKind?,
	caption: string?
): ImageButton
	local s = size or 48
	local k = kind or "nav"
	-- An active tab with a caption gets wider and shows the name below the icon
	local captioned = k == "tab" and active == true and caption ~= nil
	local b = Instance.new("ImageButton")
	b.Name = label
	b.Size = UDim2.fromOffset(if captioned then math.floor(s * 1.35) else s, s)
	Kit.touchTarget(b)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	if k == "close" then
		local close = Shape.close(s)
		close.Name = label
		return close
	end
	local F = Theme.Flat
	b.BackgroundTransparency = if active then 0 else 0.15
	b.BackgroundColor3 = if active then F.Surface3 else F.Surface1
	Shape.corner(b, F.Radius.M)
	local edge = Shape.stroke(b, if active then Theme.Color.Gold else F.Edge)
	edge.Name = "Edge"
	if active then
		Shape.glow(b, Theme.Color.Gold, 1, false, F.Radius.M)
	end
	local ic = Kit.icon(
		iconName,
		math.floor(s * (if k == "tab" then 0.6 else 0.5)),
		if active then Theme.Color.Gold else Theme.Color.Muted
	)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, if captioned then 0.4 else 0.5)
	ic.ZIndex = 2
	ic.Parent = b
	Shape.motion(b)
	if captioned then
		-- Inner glow: gold at the edge, clear toward the center
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = Theme.Color.Gold
		glow.BorderSizePixel = 0
		glow.ZIndex = 1
		Kit.corner(glow, F.Radius.M)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.88),
			NumberSequenceKeypoint.new(1, 0.45),
		})
		fade.Rotation = 90
		fade.Parent = glow
		glow.Parent = b
		local t = Kit.label(caption :: string, 15, Theme.Color.GoldHi, Theme.Font.Title)
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.new(0.5, 0, 1, -5)
		t.ZIndex = 3
		t.Parent = b
	end
	return b
end

-- Divider: thin line that fades out at both ends
function Kit.divider(width: number): GuiObject
	local f = Instance.new("Frame")
	f.Name = "Divider"
	f.Size = UDim2.fromOffset(width, 1)
	f.BackgroundColor3 = Theme.Flat.EdgeHi
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f
end

-- Input field (search) in the look of the sort button with a magnifier on the left. Returns frame and TextBox.
function Kit.textBox(size: Vector2, placeholder: string): (Frame, TextBox)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = Theme.Flat.Surface0
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	Shape.corner(f, Theme.Flat.Radius.M)
	Shape.stroke(f, Theme.Flat.Edge)
	local leftW = 14
	local t = Instance.new("TextBox")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -(leftW + 14), 1, 0)
	t.Position = UDim2.fromOffset(leftW, 0)
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = Theme.Color.Muted
	t.Text = ""
	t.ClearTextOnFocus = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextSize = Kit.fontSize(16)
	t.FontFace = Theme.Font.UI
	t.TextColor3 = Theme.Color.Text
	t.ZIndex = 2
	t.Parent = f
	return f, t
end

return Kit
