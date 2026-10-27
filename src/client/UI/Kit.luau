--!strict
-- UI-Kit-Bausteine (Luau-Fassung von tools/lr_ui_kit.py).
-- Jedes UI im Spiel wird hieraus gebaut – nie eigene Farben/Rundungen erfinden.
-- Maße sind in Design-Pixeln (1600×900); das HUD skaliert per UIScale.
-- Hybrid-Stil: große Fenster, Hauptbuttons und Slots bekommen die goldenen Bilder aus Assets,
-- alles Kleine (Listen, Pills, Balken) bleibt flach. Ohne Bild-ID fällt alles auf flach zurück.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Ab dieser Höhe ist ein Panel ein "Fenster" und bekommt den Goldrahmen
local WINDOW_MIN_HEIGHT = 200

-- 9-Slice-Bild als unterste Ebene in parent legen. nil = kein Bild vorhanden.
function Kit.skin(parent: GuiObject, name: string): ImageLabel?
	local slice = Assets.Slice[name]
	if not slice then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Skin"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 0
	img.Image = slice.id
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = slice.center
	img.SliceScale = slice.scale
	img.Parent = parent
	parent.BackgroundTransparency = 1
	return img
end

-- Standard-Panel: große Fenster mit Goldrahmen, sonst dunkle Fläche, dünne Kante, große Rundung
function Kit.panel(size: Vector2, accent: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	if size.Y >= WINDOW_MIN_HEIGHT and Kit.skin(f, "panel_main") then
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
	Kit.corner(g, Theme.Radius.L)
	Kit.stroke(g, Theme.Color.Line)
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

-- Slot-Rahmen je Seltenheit (normal/magic/rare/epic) als unterste Ebene. false = kein Bild.
function Kit.slotSkin(parent: GuiObject, rarity: string?): boolean
	local id = Assets.Slot[rarity or "normal"] or Assets.Slot.normal
	if not id then
		return false
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Skin"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 0
	img.Image = id
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = parent
	parent.BackgroundTransparency = 1
	return true
end

-- Quadratischer Slot (Skills, Items) mit zentriertem Icon und optionalem Tasten-Label
function Kit.slot(size: number, iconName: string, edge: Color3?, key: string?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	Kit.corner(f, Theme.Radius.M)
	if not Kit.slotSkin(f) then
		Kit.stroke(f, edge or Theme.Color.Line2)
	end
	local ic = Kit.icon(iconName, math.floor(size * 0.6), edge)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.Parent = f
	if key then
		local k = Kit.label(key, 12, Theme.Color.Muted)
		k.AnchorPoint = Vector2.new(0.5, 0)
		k.Position = UDim2.new(0.5, 0, 1, 4)
		k.Parent = f
	end
	return f
end

-- Akzentfarbe -> Button-Bild (Gold = Hauptaktion, Cyan = Zweitaktion, Rot = Gefahr)
local function buttonSkinName(color: Color3): string?
	if color == Theme.Color.Gold then
		return "button_gold"
	elseif color == Theme.Color.Cyan then
		return "button_blue"
	elseif color == Theme.Color.Danger then
		return "button_red"
	end
	return nil
end

-- Bestehenden TextButton mit Goldrahmen-Bild versehen (Hover/Druck = _active-Bild).
-- false = für diese Farbe gibt es kein Bild, der Button bleibt flach.
function Kit.buttonSkin(b: TextButton, color: Color3): boolean
	local name = buttonSkinName(color)
	if not name then
		return false
	end
	local img = Kit.skin(b, name)
	if not img then
		return false
	end
	b.AutoButtonColor = false
	b.TextColor3 = if name == "button_gold" then Theme.Color.Bg0 else Theme.Color.Text
	local active = Assets.Slice[name .. "_active"]
	if active then
		local normalId = img.Image
		b.MouseEnter:Connect(function()
			img.Image = active.id
		end)
		b.MouseLeave:Connect(function()
			img.Image = normalId
		end)
	end
	return true
end

-- Text-Button in Akzentfarbe (Gold = Hauptaktion)
function Kit.button(text: string, color: Color3, size: Vector2): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Text = text
	b.TextColor3 = Theme.Color.Bg0
	b.TextSize = 17
	b.FontFace = Theme.Font.UI
	b.BorderSizePixel = 0
	if not Kit.buttonSkin(b, color) then
		Kit.corner(b, Theme.Radius.M)
	end
	return b
end

-- Balken (Leben, Fortschritt). Gibt Rahmen und Füllung zurück.
function Kit.bar(size: Vector2, color: Color3): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(size.X, size.Y)
	back.BackgroundColor3 = Theme.Color.Bg0
	back.BackgroundTransparency = 0.15
	back.BorderSizePixel = 0
	Kit.corner(back, math.floor(size.Y / 2))
	Kit.stroke(back, Theme.Color.Line2)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	Kit.corner(fill, math.floor(size.Y / 2))
	fill.Parent = back
	return back, fill
end

-- Ressourcen-Anzeige: Icon + Zahl in einer Kapsel
function Kit.pill(iconName: string, text: string, color: Color3?): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 34)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	Kit.corner(f, 17)
	Kit.stroke(f, Theme.Color.Line)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 14)
	p.Parent = f
	Kit.list(f, Enum.FillDirection.Horizontal, 8)
	local ic = Kit.icon(iconName, 22, color or Theme.Color.Gold)
	ic.LayoutOrder = 1
	ic.Parent = f
	local t = Kit.label(text, 16)
	t.LayoutOrder = 2
	t.Parent = f
	return f, t
end

-- Icon-Button (Menü, Zweitaktionen). Text nur als Tooltip-Name.
function Kit.iconButton(
	iconName: string,
	label: string,
	size: number?,
	active: boolean?
): ImageButton
	local s = size or 48
	local b = Instance.new("ImageButton")
	b.Name = label
	b.Size = UDim2.fromOffset(s, s)
	b.BackgroundColor3 = if active then Theme.Color.Bg3 else Theme.Color.Bg1
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	Kit.corner(b, Theme.Radius.M)
	Kit.stroke(b, if active then Theme.Color.Gold else Theme.Color.Line)
	local ic = Kit.icon(
		iconName,
		math.floor(s * 0.5),
		if active then Theme.Color.Gold else Theme.Color.Muted
	)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.Parent = b
	return b
end

return Kit
