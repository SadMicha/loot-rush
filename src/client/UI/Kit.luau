--!strict
-- UI kit building blocks (Luau version of tools/lr_ui_kit.py).
-- Every UI in the game is built from this - never invent your own colors/roundings.
-- Sizes are in design pixels (1600×900); the HUD scales via UIScale.
-- The look comes entirely from the images (Assets.Slice / Assets.Fixed, designed with ChatGPT):
-- windows, buttons, slots, tabs, menu, capsules, chips, bars. The code only places text and icons on top.
-- If an image is missing, the simple flat style remains as a fallback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local Kit = {}

function Kit.corner(parent: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Radius.M)
	c.Parent = parent
end

function Kit.stroke(parent: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.Color.Line
	s.Thickness = thickness or Theme.Stroke
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
		for t in texts do
			fitText(t)
		end
		for b in hits do
			fitHit(b)
		end
	end
end

local refitters: { [Frame]: () -> () } = {}

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
			local d = if design then design() else Theme.DesignSize
			local s = math.clamp(math.min(v.X / d.X, v.Y / d.Y), if fit then 0.3 else 0.55, 1.4)
			scale.Scale = s
			root.Size = UDim2.fromScale(1 / s, 1 / s)
			reapply()
		end
	end
	rescale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	if safeArea then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	end
	return gui, root
end

-- Border ≈ one third of the height, at most `maxScale` (Roblox applies SliceScale to the source pixels)
local function sliceScale(slice: Assets.Slice, height: number?, maxScale: number): number
	if height then
		return math.min(maxScale, height * 0.34 / math.max(1, slice.center.Min.Y))
	end
	return maxScale
end

-- Apply the image properties of a 9-slice to an image object
local function applySlice(
	img: ImageLabel | ImageButton,
	name: string,
	height: number?,
	maxScale: number
)
	local slice = Assets.Slice[name]
	local target = img :: ImageLabel -- same image properties as ImageButton
	target.Image = slice.id
	target.ScaleType = Enum.ScaleType.Slice
	target.SliceCenter = slice.center
	target.SliceScale = sliceScale(slice, height, maxScale)
end

-- Put a 9-slice image as the bottom layer into parent (only for frames that have no text themselves).
-- nil = no image available.
function Kit.skin(parent: GuiObject, name: string, height: number?, maxScale: number?): ImageLabel?
	if not Assets.Slice[name] then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Skin"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 0
	applySlice(img, name, height, maxScale or 0.4)
	img.Parent = parent
	parent.BackgroundTransparency = 1
	return img
end

-- Standard panel: window with gold frame (tall / wide / small), otherwise flat surface
function Kit.panel(size: Vector2, accent: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	local name = if size.Y < 200
		then nil
		elseif size.Y < 330 then "window_small"
		elseif size.X >= size.Y * 1.3 then "window_main"
		else "window_tall"
	if name and Kit.skin(f, name) then
		return f
	end
	Kit.corner(f, Theme.Radius.L)
	Kit.stroke(f, accent or Theme.Color.Line)
	return f
end

-- Panel that can fly in and out (CanvasGroup -> one fade for all children)
function Kit.flyPanel(size: Vector2): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Size = UDim2.fromOffset(size.X, size.Y)
	g.BackgroundColor3 = Theme.Color.Bg1
	g.BorderSizePixel = 0
	if not Kit.skin(g, "window_small") then
		Kit.corner(g, Theme.Radius.L)
		Kit.stroke(g, Theme.Color.Line)
	end
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
	shadow.Parent = t
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

-- Drop shadow for an image icon: `img` becomes the crisp face (child), the returned image is a dark
-- copy of it that sits behind (a child always draws above its parent, so the shadow is the parent and
-- the face is shifted up-left by Theme.Shadow.Offset). The caller sizes/places/parents the result.
function Kit.shadowed(img: ImageLabel): ImageLabel
	local back = img:Clone()
	back.ImageColor3 = Theme.Shadow.Color
	back.ImageTransparency = Theme.Shadow.Transparency
	back.ImageRectOffset = img.ImageRectOffset
	img.Name = "Face"
	img.AnchorPoint = Vector2.zero
	img.Position = UDim2.fromScale(-Theme.Shadow.Offset, -Theme.Shadow.Offset)
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 1
	img.Parent = back
	return back
end

-- Icon transparency incl. its shadow (dimmed / disabled icons)
function Kit.setIconTransparency(icon: GuiObject, transparency: number)
	if not icon:IsA("ImageLabel") then
		return
	end
	local face = icon:FindFirstChild("Face")
	if face and face:IsA("ImageLabel") then
		face.ImageTransparency = transparency
		icon.ImageTransparency = math.max(transparency, Theme.Shadow.Transparency)
	else
		icon.ImageTransparency = transparency
	end
end

-- ------------------------------------------------------------------ Class art
-- Class of the local player. There is no class data yet, so this is Theme.Class.Default; a player
-- attribute "Class" is honored if it ever exists.
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
	local pos = Theme.Class.SkillSlot[skillId]
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
}

-- Slot image by rarity; border and diamond are part of the image
local function slotImage(rarity: string?): string?
	local fixed = Assets.Fixed["slot_" .. (rarity or "empty")] or Assets.Fixed.slot_normal
	return if fixed then fixed.id else nil
end

-- Flat fallback slot in case an image is missing
local function flatSlot(b: GuiObject, edge: Color3?)
	b.BackgroundColor3 = Theme.Color.Bg1
	b.BackgroundTransparency = 0
	Kit.corner(b, Theme.Radius.M)
	Kit.stroke(b, edge or Theme.Color.Line2, 2)
end

local function slotBase(size: number, rarity: string?, edge: Color3?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = "Slot"
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	local id = slotImage(rarity)
	if id then
		b.Image = id
		b.ScaleType = Enum.ScaleType.Fit
	else
		flatSlot(b, edge)
	end
	return b
end

local function slotIcon(b: GuiObject, size: number, iconName: string, edge: Color3?, dim: boolean?)
	local ic = Kit.icon(iconName, math.floor(size * 0.6), edge)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = 2
	if dim then
		Kit.setIconTransparency(ic, 0.7)
	end
	ic.Parent = b
end

-- Item slot like in the inventory mockup: image per rarity, icon on top, selection frame as overlay
function Kit.itemSlot(size: number, iconName: string?, opts: SlotOptions?): ImageButton
	local o: SlotOptions = opts or {}
	local edge = if o.rarity then Theme.Rarity[o.rarity] or Theme.Rarity.normal else nil
	local b = slotBase(size, o.rarity, edge)
	if iconName then
		slotIcon(b, size, iconName, edge, o.dim)
	end
	if o.selected then
		local sel = Assets.Fixed.slot_selected
		if sel then
			local ring = Instance.new("ImageLabel")
			ring.Name = "Selected"
			ring.BackgroundTransparency = 1
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromOffset(size * 224 / 192, size * 224 / 192)
			ring.Image = sel.id
			ring.ScaleType = Enum.ScaleType.Fit
			ring.ZIndex = 1
			ring.Parent = b
		else
			Kit.stroke(b, Theme.Color.Gold, 3)
		end
	end
	if o.count then
		local c = Kit.label(tostring(o.count), math.max(11, size // 6), Theme.Color.Text)
		c.AnchorPoint = Vector2.new(0, 1)
		c.Position = UDim2.new(0, 8, 1, -6)
		c.ZIndex = 4
		c.Parent = b
	end
	return b
end

-- Square slot (skills) with centered icon and optional key label
function Kit.slot(size: number, iconName: string, edge: Color3?, key: string?): ImageButton
	local f = slotBase(size, "normal", edge)
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
		k.TextStrokeTransparency = 0.3
		k.ZIndex = 3
		k.Parent = f
	end
	return f
end

-- Short press effect (button shrinks briefly)
local function pressFeedback(b: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 0.97 }):Play()
	end)
	local function release()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
end

-- Button color -> image name (gold = primary action, danger = red, everything else blue)
local function buttonSkin(color: Color3): string
	if color == Theme.Color.Gold then
		return "btn_gold"
	elseif color == Theme.Color.Danger then
		return "btn_red"
	end
	return "btn_blue"
end

-- Text of the button (lives in a child label so the image does not draw over it)
function Kit.buttonLabel(b: GuiObject): TextLabel
	return b:FindFirstChild("Label") :: TextLabel
end

-- Button on/off: swaps to the "disabled" image (gold, blue) and blocks input
function Kit.setEnabled(b: ImageButton, enabled: boolean)
	local base = b:GetAttribute("Skin") :: string?
	if not base then
		return
	end
	local slice = Assets.Slice[if enabled then base else base .. "_disabled"]
	if slice then
		b.Image = slice.id
	end
	b.Active = enabled
	Kit.buttonLabel(b).TextTransparency = if enabled then 0 else 0.4
end

-- Text button (gold = primary action, danger = red, otherwise blue), optionally with an icon left of the text.
-- Returns an ImageButton; set the text via Kit.buttonLabel(b).Text.
function Kit.button(text: string, color: Color3, size: Vector2, iconName: string?): ImageButton
	local skinName = buttonSkin(color)
	local b = Instance.new("ImageButton")
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	b:SetAttribute("Skin", skinName)
	Kit.touchTarget(b)
	local normal = Assets.Slice[skinName]
	local pressed = Assets.Slice[skinName .. "_pressed"]
	if normal then
		applySlice(b, skinName, size.Y, 0.5)
	else
		b.BackgroundTransparency = 0
		b.BackgroundColor3 = Theme.Color.Bg1
		Kit.corner(b, Theme.Radius.M)
		Kit.stroke(b, color, 2)
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextSize = Kit.fontSize(17)
	label.FontFace = Theme.Font.UI
	label.TextColor3 = if color == Theme.Color.Gold then Theme.Color.Bg0 else Theme.Color.Text
	if color ~= Theme.Color.Gold then
		Kit.textShadow(label) -- dark text on the gold button needs none
	end
	label.ZIndex = 2
	label.Parent = b
	if iconName then
		local s = math.floor(size.Y * 0.5)
		local ic = Kit.icon(iconName, s)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 22, 0.5, 0)
		ic.ZIndex = 2
		ic.Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, s + 22)
		pad.Parent = label
	end

	if pressed then
		b.MouseButton1Down:Connect(function()
			b.Image = pressed.id
		end)
		local function release()
			if normal and b.Active then
				b.Image = normal.id
			end
		end
		b.MouseButton1Up:Connect(release)
		b.MouseLeave:Connect(release)
	end
	pressFeedback(b)
	return b
end

-- Bar (life, progress). Returns frame and fill; the fill is scaled via Size.X.
-- From 12 px height with images, below that (thin lines) flat.
function Kit.bar(size: Vector2, color: Color3): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(size.X, size.Y)
	back.BorderSizePixel = 0
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	local useImages = size.Y >= 12
		and Assets.Slice.bar_frame ~= nil
		and Assets.Slice.bar_fill ~= nil
	if useImages then
		back.BackgroundTransparency = 1
		Kit.skin(back, "bar_frame", size.Y, 0.5)
		fill.BackgroundTransparency = 1
		fill.ClipsDescendants = true
		fill.ZIndex = 2
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(size.X, size.Y)
		applySlice(img, "bar_fill", size.Y, 0.5)
		img.ImageColor3 = if color == Theme.Color.Gold then Color3.new(1, 1, 1) else color
		img.Parent = fill
	else
		back.BackgroundColor3 = Theme.Color.Bg0
		back.BackgroundTransparency = 0.15
		Kit.corner(back, math.floor(size.Y / 2))
		Kit.stroke(back, Theme.Color.Line2)
		fill.BackgroundColor3 = color
		Kit.corner(fill, math.floor(size.Y / 2))
	end
	fill.Parent = back
	return back, fill
end

-- ------------------------------------------------------------------ In-game HUD pieces
-- Image from Assets.Hud at a fixed size; nil if it has not been uploaded yet (-> flat fallback)
function Kit.hudImage(name: string, size: Vector2, shadow: boolean?): ImageLabel?
	local fixed = Assets.Hud[name] or Assets.Class[name]
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
	local frameImg = Kit.hudImage("orb_" .. kind .. "_frame", Vector2.new(size, size), true)
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
	well.BackgroundColor3 = Theme.Color.Bg0
	well.BackgroundTransparency = 0.2
	well.BorderSizePixel = 0
	circle(well)
	if not frameImg then
		Kit.stroke(well, Theme.Color.Gold, 3)
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
		liquid.BackgroundColor3 = color
		liquid.BorderSizePixel = 0
		circle(liquid)
		liquid.Parent = clip
	end
	if frameImg then
		frameImg.ZIndex = 3
		frameImg.Parent = root
	end

	local text = Kit.label("", 13)
	text.Name = "Value"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, (H.OrbTop + H.OrbBottom) / 2)
	text.TextStrokeTransparency = 0.25
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
	text.TextStrokeTransparency = 0.3
	text.ZIndex = 5
	text.Parent = parent

	local lastStep = -1
	return function(ratio: number, remaining: number)
		local step = math.floor(math.clamp(ratio, 0, 1) * 100 + 0.5)
		if step ~= lastStep then
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
		text.Text = if step > 0 then string.format("%.1f", remaining) else ""
	end
end

-- Round HUD button (skill, dash): ring image with icon in the center, optional key label (keyboard only)
-- and cooldown veil. ring = "gold" | "cyan" (cyan = tinted silver ring). Returns button and veil updater.
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
	local ringArt = Assets.Hud[if ring == "gold" then "ring_gold" else "ring_silver"]
	if ringArt then
		b.Image = ringArt.id
		b.ScaleType = Enum.ScaleType.Fit
		if ring ~= "gold" then
			b.ImageColor3 = Theme.Hud.RingCyan
		end
	else
		b.BackgroundTransparency = 0
		b.BackgroundColor3 = Theme.Color.Bg1
		circle(b)
		Kit.stroke(b, if ring == "gold" then Theme.Color.Gold else Theme.Color.Cyan, 3)
	end

	local inner = math.floor(size * 0.66)
	local ic: GuiObject? = nil
	if artName then
		ic = Kit.hudImage(artName, Vector2.new(inner, inner), true)
	end
	if not ic and fallbackIcon then
		ic = Kit.icon(fallbackIcon, inner, Theme.Color.Muted)
	end
	if ic then
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = 2
		ic.Parent = b
	end
	if key then
		local k = Kit.label(key, 11)
		k.Name = "Key"
		k.AnchorPoint = Vector2.new(0.5, 1)
		k.Position = UDim2.new(0.5, 0, 1, -2)
		k.TextStrokeTransparency = 0.3
		k.ZIndex = 6
		k.Parent = b
	end
	local update = Kit.cooldownVeil(b)
	pressFeedback(b)
	return b, update
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
		t.TextStrokeTransparency = 0.3
		t.ZIndex = 3
		t.Parent = b
	end
	pressFeedback(b)
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

	local cyan, dark = Assets.Hud.hud_diamond_cyan, Assets.Hud.hud_diamond_dark
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

local PILL_KEY = { gold = "gold", cyan = "cyan", purple = "purple" }
local PILL_HEIGHT = 40
local PILL_PLUS = 32

-- Resource display: capsule with icon on the left, number in the middle and its own + button on the right.
-- Returns capsule, number label and + button (button is nil without an image).
function Kit.pill(iconName: string, text: string, color: Color3?): (Frame, TextLabel, ImageButton?)
	local c = color or Theme.Color.Gold
	local key = if c == Theme.Color.Cyan
		then PILL_KEY.cyan
		elseif c == Theme.Rarity.epic then PILL_KEY.purple
		else PILL_KEY.gold
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(190, PILL_HEIGHT)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	local skin = Kit.skin(f, "pill3_" .. key, PILL_HEIGHT, 0.5)
	local slice = Assets.Slice["pill3_" .. key]
	local plusFixed = Assets.Fixed["plus_" .. key]
	if skin and slice then
		-- Never distort the capsule: scale = display height / image height
		skin.SliceScale = PILL_HEIGHT / slice.size.Y
	else
		Kit.corner(f, PILL_HEIGHT // 2)
		Kit.stroke(f, Theme.Color.Line)
	end
	local ic = Kit.icon(iconName, math.floor(PILL_HEIGHT * 0.62), c)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0, math.floor(PILL_HEIGHT * 0.5) + 2, 0.5, 0)
	ic.ZIndex = 2
	ic.Parent = f
	local plus: ImageButton? = nil
	if plusFixed then
		-- Invisible hit area (grows on touch), the image sits fixed at the right edge
		local pb = Instance.new("ImageButton")
		pb.Name = "Plus"
		pb.AnchorPoint = Vector2.new(1, 0.5)
		pb.Position = UDim2.new(1, -5, 0.5, 0)
		pb.Size = UDim2.fromOffset(PILL_PLUS, PILL_PLUS)
		pb.BackgroundTransparency = 1
		pb.AutoButtonColor = false
		pb.ZIndex = 3
		Kit.touchTarget(pb)
		local img = Instance.new("ImageLabel")
		img.Name = "Image"
		img.AnchorPoint = Vector2.new(1, 0.5)
		img.Position = UDim2.fromScale(1, 0.5)
		img.Size = UDim2.fromOffset(PILL_PLUS, PILL_PLUS)
		img.BackgroundTransparency = 1
		img.Image = plusFixed.id
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 3
		img.Parent = pb
		pb.MouseButton1Down:Connect(function()
			img.Size = UDim2.fromOffset(PILL_PLUS - 4, PILL_PLUS - 4)
			img.ImageColor3 = Color3.fromRGB(190, 190, 190)
		end)
		local function release()
			img.Size = UDim2.fromOffset(PILL_PLUS, PILL_PLUS)
			img.ImageColor3 = Color3.new(1, 1, 1)
		end
		pb.MouseButton1Up:Connect(release)
		pb.MouseLeave:Connect(release)
		pb.Parent = f
		plus = pb
	end
	local leftW = PILL_HEIGHT + 4
	local rightW = if plus then PILL_PLUS + 10 else 20
	local t = Kit.label(text, 16)
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
		-- Always red: there is no hover on touch, otherwise the button would look different per window
		local fixed = Assets.Fixed.close_red or Assets.Fixed.close_dark
		if fixed then
			b.Image = fixed.id
			b.ScaleType = Enum.ScaleType.Fit
			return b
		end
	end
	local skinName = k .. (if active then "_active" else "_idle")
	if k == "close" then
		skinName = "nav_idle"
	end
	if Assets.Slice[skinName] then
		applySlice(b, skinName, s, 0.5)
	else
		b.BackgroundTransparency = 0
		b.BackgroundColor3 = if active then Theme.Color.Bg3 else Theme.Color.Bg1
		Kit.corner(b, Theme.Radius.M)
		Kit.stroke(b, if active then Theme.Color.Gold else Theme.Color.Line)
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
	if captioned then
		-- Inner glow: gold at the edge, clear toward the center
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = Theme.Color.Gold
		glow.BorderSizePixel = 0
		glow.ZIndex = 1
		Kit.corner(glow, math.floor(s * 0.22))
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

-- Divider with diamond (image, stretched in width only)
function Kit.divider(width: number): GuiObject
	local fixed = Assets.Fixed.divider
	if not fixed then
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(width, 1)
		f.BackgroundColor3 = Theme.Color.Line
		f.BorderSizePixel = 0
		return f
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Divider"
	img.BackgroundTransparency = 1
	img.Image = fixed.id
	img.ScaleType = Enum.ScaleType.Stretch
	img.Size = UDim2.fromOffset(width, math.max(8, math.floor(width * fixed.size.Y / fixed.size.X)))
	return img
end

-- Input field (search) in the look of the sort button with a magnifier on the left. Returns frame and TextBox.
function Kit.textBox(size: Vector2, placeholder: string): (Frame, TextBox)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	if not Kit.skin(f, "btn_sort", size.Y, 0.5) then
		Kit.corner(f, Theme.Radius.M)
		Kit.stroke(f, Theme.Color.Line2)
	end
	local leftW = 14
	local lens = Assets.Fixed.icon_search
	if lens then
		local iconSize = math.floor(size.Y * 0.5)
		local ic = Instance.new("ImageLabel")
		ic.Name = "Magnifier"
		ic.BackgroundTransparency = 1
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 14, 0.5, 0)
		ic.Size = UDim2.fromOffset(iconSize, iconSize)
		ic.Image = lens.id
		ic.ScaleType = Enum.ScaleType.Fit
		ic.ZIndex = 2
		ic.Parent = f
		leftW = 14 + iconSize + 8
	end
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
