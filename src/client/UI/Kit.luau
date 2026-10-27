--!strict
-- UI-Kit-Bausteine (Luau-Fassung von tools/lr_ui_kit.py).
-- Jedes UI im Spiel wird hieraus gebaut – nie eigene Farben/Rundungen erfinden.
-- Maße sind in Design-Pixeln (1600×900); das HUD skaliert per UIScale.
-- Look kommt komplett aus den Bildern (Assets.Slice / Assets.Fixed, von ChatGPT gestaltet):
-- Fenster, Buttons, Slots, Tabs, Menü, Kapseln, Chips, Balken. Der Code legt nur Text und Icons darauf.
-- Fehlt ein Bild, bleibt der einfache flache Stil als Notlösung.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
	-- Das Hintergrundbild soll weiter das ganze Panel füllen, nicht nur die gepolsterte Fläche
	local skin = parent:FindFirstChild("Skin")
	if skin and skin:IsA("GuiObject") then
		skin.Position = UDim2.fromOffset(-px, -px)
		skin.Size = UDim2.new(1, 2 * px, 1, 2 * px)
	end
end

function Kit.list(
	parent: GuiObject,
	dir: Enum.FillDirection,
	gap: number,
	align: Enum.VerticalAlignment?
)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = align or Enum.VerticalAlignment.Center
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Parent = parent
end

-- ScreenGui mit Root-Frame, der auf die Design-Auflösung (1600×900) skaliert.
-- UIScale skaliert auch den Root selbst, darum bekommt er die Gegengröße 1/s und füllt den Bildschirm.
function Kit.scaledGui(name: string, order: number): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local function rescale()
		local camera = workspace.CurrentCamera
		if camera then
			local v = camera.ViewportSize
			local s =
				math.clamp(math.min(v.X / Theme.DesignSize.X, v.Y / Theme.DesignSize.Y), 0.55, 1.4)
			scale.Scale = s
			root.Size = UDim2.fromScale(1 / s, 1 / s)
		end
	end
	rescale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	return gui, root
end

-- Rand ≈ ein Drittel der Höhe, höchstens `maxScale` (Roblox rechnet SliceScale auf die Quellpixel)
local function sliceScale(slice: Assets.Slice, height: number?, maxScale: number): number
	if height then
		return math.min(maxScale, height * 0.34 / math.max(1, slice.center.Min.Y))
	end
	return maxScale
end

-- Bild-Eigenschaften eines 9-Slice auf ein Image-Objekt anwenden
local function applySlice(
	img: ImageLabel | ImageButton,
	name: string,
	height: number?,
	maxScale: number
)
	local slice = Assets.Slice[name]
	img.Image = slice.id
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = slice.center
	img.SliceScale = sliceScale(slice, height, maxScale)
end

-- 9-Slice-Bild als unterste Ebene in parent legen (nur für Frames, die selbst keinen Text haben).
-- nil = kein Bild vorhanden.
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

-- Standard-Panel: Fenster mit Goldrahmen (hoch / breit / klein), sonst flache Fläche
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

-- Panel, das ein- und ausfliegen kann (CanvasGroup → ein Fade für alle Kinder)
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

function Kit.label(text: string, size: number, color: Color3?, font: Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color or Theme.Color.Text
	t.FontFace = font or Theme.Font.UI
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.fromOffset(0, 0)
	return t
end

-- Icon aus dem Sammelbild (Assets.Icon), sonst neutraler Platzhalter
function Kit.icon(name: string, size: number, color: Color3?): GuiObject
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
		return img
	end
	local ph = Instance.new("Frame")
	ph.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
	ph.BackgroundTransparency = 1
	Kit.corner(ph, math.floor(size * 0.2))
	Kit.stroke(ph, color or Theme.Color.Muted, 2)
	ph.Name = "Platzhalter_" .. name
	return ph
end

export type SlotOptions = {
	rarity: string?, -- nil = leerer Slot
	count: number?, -- Stapelzahl unten links
	selected: boolean?,
	dim: boolean?, -- Icon abgeschwächt (leerer Ausrüstungsplatz)
}

-- Slot-Bild nach Seltenheit; Rand und Raute stecken im Bild
local function slotImage(rarity: string?): string?
	local fixed = Assets.Fixed["slot_" .. (rarity or "empty")] or Assets.Fixed.slot_normal
	return if fixed then fixed.id else nil
end

-- Flacher Notlösungs-Slot, falls ein Bild fehlt
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
	if dim and ic:IsA("ImageLabel") then
		ic.ImageTransparency = 0.7
	end
	ic.Parent = b
end

-- Item-Slot wie im Inventar-Mockup: Bild je Seltenheit, Icon darauf, Auswahl-Rahmen als Overlay
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

-- Quadratischer Slot (Skills) mit zentriertem Icon und optionalem Tasten-Label
function Kit.slot(size: number, iconName: string, edge: Color3?, key: string?): ImageButton
	local f = slotBase(size, "normal", edge)
	f.Active = false
	slotIcon(f, size, iconName, edge)
	if key then
		local k = Kit.label(key, 12, Theme.Color.Muted)
		k.AnchorPoint = Vector2.new(0.5, 0)
		k.Position = UDim2.new(0.5, 0, 1, 4)
		k.Parent = f
	end
	return f
end

-- Kurzer Druck-Effekt (Button schrumpft kurz)
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

-- Button-Farbe → Bildname (Gold = Hauptaktion, Danger = rot, alles andere blau)
local function buttonSkin(color: Color3): string
	if color == Theme.Color.Gold then
		return "btn_gold"
	elseif color == Theme.Color.Danger then
		return "btn_red"
	end
	return "btn_blue"
end

-- Text des Buttons (liegt in einem Kind-Label, damit das Bild nicht darüber zeichnet)
function Kit.buttonLabel(b: GuiObject): TextLabel
	return b:FindFirstChild("Label") :: TextLabel
end

-- Button an/aus: tauscht auf das Bild "disabled" (Gold, Blau) und sperrt Eingaben
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

-- Text-Button (Gold = Hauptaktion, Danger = rot, sonst blau), optional mit Icon links vom Text.
-- Rückgabe ist ein ImageButton; den Text setzt man über Kit.buttonLabel(b).Text.
function Kit.button(text: string, color: Color3, size: Vector2, iconName: string?): ImageButton
	local skinName = buttonSkin(color)
	local b = Instance.new("ImageButton")
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	b:SetAttribute("Skin", skinName)
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
	label.TextSize = 17
	label.FontFace = Theme.Font.UI
	label.TextColor3 = if color == Theme.Color.Gold then Theme.Color.Bg0 else Theme.Color.Text
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

-- Balken (Leben, Fortschritt). Gibt Rahmen und Füllung zurück; die Füllung wird über Size.X skaliert.
-- Ab 12 px Höhe mit Bildern, darunter (dünne Linien) flach.
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

local PILL_SKIN = { gold = "pill_gold", cyan = "pill_cyan", purple = "pill_purple" }
local PILL_HEIGHT = 40

-- Ressourcen-Anzeige: Kapsel mit Icon-Fassung links, Zahl in der Mitte und +-Knopf rechts (im Bild)
function Kit.pill(iconName: string, text: string, color: Color3?): (Frame, TextLabel)
	local c = color or Theme.Color.Gold
	local skinName = if c == Theme.Color.Cyan
		then PILL_SKIN.cyan
		elseif c == Theme.Rarity.epic then PILL_SKIN.purple
		else PILL_SKIN.gold
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(190, PILL_HEIGHT)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	local slice = Assets.Slice[skinName]
	-- Ränder links/rechts in Anzeigepixeln (Skalierung wie im Bild)
	local s = if slice then sliceScale(slice, PILL_HEIGHT, 0.5) else 1
	local leftW = if slice then slice.center.Min.X * s else 44
	local rightW = if slice then (slice.size.X - slice.center.Max.X) * s else 36
	if slice then
		Kit.skin(f, skinName, PILL_HEIGHT, 0.5)
	else
		Kit.corner(f, PILL_HEIGHT // 2)
		Kit.stroke(f, Theme.Color.Line)
	end
	local ic = Kit.icon(iconName, math.floor(PILL_HEIGHT * 0.62), c)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0, math.floor(PILL_HEIGHT * 0.5), 0.5, 0)
	ic.ZIndex = 2
	ic.Parent = f
	local t = Kit.label(text, 16)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, -(leftW + rightW), 1, 0)
	t.Position = UDim2.fromOffset(leftW, 0)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.ZIndex = 2
	t.Parent = f
	return f, t
end

export type IconButtonKind = "nav" | "tab" | "close"

-- Icon-Button: Menü (nav), Filter-Tab (tab) oder Schließen (close). Text nur als Name.
function Kit.iconButton(
	iconName: string,
	label: string,
	size: number?,
	active: boolean?,
	kind: IconButtonKind?
): ImageButton
	local s = size or 48
	local k = kind or "nav"
	local b = Instance.new("ImageButton")
	b.Name = label
	b.Size = UDim2.fromOffset(s, s)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	if k == "close" then
		local fixed = Assets.Fixed.close_dark
		if fixed then
			b.Image = fixed.id
			b.ScaleType = Enum.ScaleType.Fit
			local hover = Assets.Fixed.close_red
			if hover then
				b.MouseEnter:Connect(function()
					b.Image = hover.id
				end)
				b.MouseLeave:Connect(function()
					b.Image = fixed.id
				end)
			end
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
		math.floor(s * 0.5),
		if active then Theme.Color.Gold else Theme.Color.Muted
	)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = 2
	ic.Parent = b
	return b
end

return Kit
