--!strict
-- UI-Kit-Bausteine (Luau-Fassung von tools/lr_ui_kit.py).
-- Jedes UI im Spiel wird hieraus gebaut – nie eigene Farben/Rundungen erfinden.
-- Maße sind in Design-Pixeln (1600×900); das HUD skaliert per UIScale.
-- Look kommt komplett aus den Bildern (Assets.Slice / Assets.Fixed, von ChatGPT gestaltet):
-- Fenster, Buttons, Slots, Tabs, Menü, Kapseln, Chips, Balken. Der Code legt nur Text und Icons darauf.
-- Fehlt ein Bild, bleibt der einfache flache Stil als Notlösung.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	-- Das Hintergrundbild soll weiter das ganze Panel füllen, nicht nur die gepolsterte Fläche
	local skin = parent:FindFirstChild("Skin")
	if skin and skin:IsA("GuiObject") then
		skin.Position = UDim2.fromOffset(-px, -px)
		skin.Size = UDim2.new(1, 2 * px, 1, 2 * px)
	end
end

-- Schriftgröße in Design-Pixeln → tatsächliche TextSize (Theme.FontScale)
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

-- Mindestgrößen in echten Bildschirmpixeln (nach UIScale). Auf kleinen Bildschirmen wächst
-- kleine Schrift immer, mit Kit.touchTarget markierte Knöpfe nur auf Touch-Geräten.
Kit.MIN_TEXT_PX = 9.5
Kit.MIN_TOUCH_PX = 33

-- Knopf auf Touch-Geräten mindestens Kit.MIN_TOUCH_PX groß machen (nur Offset-Größen)
function Kit.touchTarget(b: GuiButton)
	b:SetAttribute("TouchTarget", true)
end

-- Hält Schrift und markierte Knöpfe unter `root` über den Mindestgrößen; gibt die Neu-Anwenden-Funktion zurück.
-- Die Design-Größe merkt sich jedes Objekt selbst (Attribute), damit sie Umhängen und spätere Änderungen übersteht.
local function minimums(root: Frame, scale: UIScale): () -> ()
	local texts: { [Instance]: true } = {}
	local hits: { [GuiButton]: true } = {}

	-- Gesamtskalierung inkl. weiterer UIScales unter dem Root (z. B. Fenster-Inhalt)
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
			t:SetAttribute("BaseTextSize", t.TextSize) -- Größe wurde von außen neu gesetzt
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

-- Mindestgrößen neu anwenden, nachdem sich eine innere UIScale geändert hat
function Kit.refit(root: Frame)
	local fn = refitters[root]
	if fn then
		fn()
	end
end

-- ScreenGui mit Root-Frame, der auf die Design-Auflösung (1600×900) skaliert.
-- UIScale skaliert auch den Root selbst, darum bekommt er die Gegengröße 1/s und füllt den Bildschirm.
-- fit = true (Vollbild-Fenster): nie kleiner als die Design-Fläche, auch wenn der Bildschirm
-- dafür stärker verkleinert werden muss (Handy); das HUD bleibt bei mindestens 0.55.
function Kit.scaledGui(name: string, order: number, fit: boolean?): (ScreenGui, Frame)
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
	local reapply = minimums(root, scale)
	refitters[root] = reapply

	local function rescale()
		local camera = workspace.CurrentCamera
		if camera then
			local v = camera.ViewportSize
			local s = math.clamp(
				math.min(v.X / Theme.DesignSize.X, v.Y / Theme.DesignSize.Y),
				if fit then 0.3 else 0.55,
				1.4
			)
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
	local target = img :: ImageLabel -- gleiche Bild-Properties wie ImageButton
	target.Image = slice.id
	target.ScaleType = Enum.ScaleType.Slice
	target.SliceCenter = slice.center
	target.SliceScale = sliceScale(slice, height, maxScale)
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
	t.TextSize = Kit.fontSize(size)
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

local PILL_KEY = { gold = "gold", cyan = "cyan", purple = "purple" }
local PILL_HEIGHT = 40
local PILL_PLUS = 32

-- Ressourcen-Anzeige: Kapsel mit Icon links, Zahl in der Mitte und eigenem +-Knopf rechts.
-- Gibt Kapsel, Zahlen-Label und +-Knopf zurück (Knopf nil ohne Bild).
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
		-- Kapsel nie verzerren: Skalierung = Anzeigehöhe / Bildhöhe
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
		-- Unsichtbare Trefferfläche (wächst auf Touch), das Bild sitzt fest am rechten Rand
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
		img.Name = "Bild"
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

-- Icon-Button: Menü (nav), Filter-Tab (tab) oder Schließen (close). Text nur als Name.
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
	-- Aktiver Tab mit Beschriftung wird breiter und zeigt den Namen unter dem Icon
	local captioned = k == "tab" and active == true and caption ~= nil
	local b = Instance.new("ImageButton")
	b.Name = label
	b.Size = UDim2.fromOffset(if captioned then math.floor(s * 1.35) else s, s)
	Kit.touchTarget(b)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	if k == "close" then
		-- Immer rot: Hover gibt es auf Touch nicht, sonst wirkt der Knopf je Fenster anders
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
		-- Inneres Leuchten: Gold am Rand, zur Mitte hin klar
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

-- Trennlinie mit Raute (Bild, nur in der Breite gezogen)
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

-- Eingabefeld (Suche) im Look des Sortier-Buttons mit Lupe links. Gibt Rahmen und TextBox zurück.
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
		ic.Name = "Lupe"
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
