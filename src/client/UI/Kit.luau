--!strict
-- UI-Kit-Bausteine (Luau-Fassung von tools/lr_ui_kit.py).
-- Jedes UI im Spiel wird hieraus gebaut – nie eigene Farben/Rundungen erfinden.
-- Maße sind in Design-Pixeln (1600×900); das HUD skaliert per UIScale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Standard-Panel: dunkle Fläche, dünne Kante, große Rundung
function Kit.panel(size: Vector2, accent: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
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

-- Icon: generiertes Bild-Icon aus Theme.Icons, sonst neutraler Platzhalter
function Kit.icon(name: string, size: number, color: Color3?): GuiObject
	local id = Theme.Icons[name]
	if id and id ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = id
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

-- Quadratischer Slot (Skills, Items) mit zentriertem Icon und optionalem Tasten-Label
function Kit.slot(size: number, iconName: string, edge: Color3?, key: string?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = Theme.Color.Bg1
	f.BorderSizePixel = 0
	Kit.corner(f, Theme.Radius.M)
	Kit.stroke(f, edge or Theme.Color.Line2)
	local ic = Kit.icon(iconName, math.floor(size * 0.5), edge)
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
	Kit.corner(b, Theme.Radius.M)
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
