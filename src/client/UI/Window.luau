--!strict
-- Gemeinsamer Rahmen der Vollbild-Fenster (Fähigkeiten, Sternennetz, Schmiede, Atlas):
-- Szenenbild oder Abdunklung, Titel oben links, Schließen oben rechts, eigene Taste.
-- Es ist immer nur eines dieser Fenster offen; Öffnen schließt das vorige.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Kit)

local Window = {}

export type Options = {
	name: string,
	title: string,
	icon: string?, -- Assets.Icon vor dem Titel
	key: Enum.KeyCode?,
	background: string?, -- Schlüssel in Assets.Art
}

export type Window = {
	gui: ScreenGui,
	root: Frame,
	isOpen: () -> boolean,
	toggle: () -> (),
	close: () -> (),
	onOpen: (fn: () -> ()) -> (),
}

local current: Window? = nil

-- upper() kennt keine Umlaute
function Window.caps(text: string): string
	return (string.upper(text):gsub("ü", "Ü"):gsub("ö", "Ö"):gsub("ä", "Ä"))
end

-- Fenstertitel in Großbuchstaben (Titel-Schrift)
function Window.heading(text: string, size: number?, color: Color3?): TextLabel
	return Kit.label(Window.caps(text), size or 20, color or Theme.Color.Text, Theme.Font.Title)
end

-- Rahmenloser Container ohne Hintergrund
function Window.frame(size: UDim2, pos: UDim2?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = size
	if pos then
		f.Position = pos
	end
	return f
end

-- Bild aus Assets.Art (feste Größe, eingepasst) oder nil, solange es fehlt
function Window.art(name: string, size: Vector2): ImageLabel?
	local art = Assets.Art[name]
	if not art then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = art.id
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.fromOffset(size.X, size.Y)
	return img
end

-- Gerade Linie zwischen zwei Punkten (Design-Pixel), z. B. Verbindungen im Baum
function Window.line(parent: GuiObject, a: Vector2, b: Vector2, color: Color3, width: number): Frame
	local d = b - a
	local f = Instance.new("Frame")
	f.Name = "Linie"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude, width)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.ZIndex = 0
	f.Parent = parent
	return f
end

export type NodeOptions = {
	art: string?, -- Ring aus Assets.Art; fehlt er, wird ein Slot nach `rarity` genommen
	rarity: string?,
	dim: boolean?,
	selected: boolean?,
	tint: Color3?, -- färbt das Ring-Bild (Ast-Farbe im Sternennetz)
}

-- Runder Baum-Knoten (Skill-Blüte, Sternennetz), mittig auf `pos` gesetzt
function Window.node(iconName: string, size: number, pos: Vector2, opts: NodeOptions): ImageButton
	local ring = if opts.art then Assets.Art[opts.art] else nil
	local b: ImageButton
	if ring then
		b = Instance.new("ImageButton")
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Image = ring.id
		b.ImageColor3 = opts.tint or Color3.new(1, 1, 1)
		b.ScaleType = Enum.ScaleType.Fit
		b.Size = UDim2.fromOffset(size, size)
		local ic = Kit.icon(iconName, math.floor(size * 0.55))
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = 2
		if opts.dim and ic:IsA("ImageLabel") then
			ic.ImageTransparency = 0.6
		end
		ic.Parent = b
	else
		b = Kit.itemSlot(size, iconName, {
			rarity = opts.rarity,
			dim = opts.dim,
			selected = opts.selected,
		})
	end
	b.Name = "Knoten"
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromOffset(pos.X, pos.Y)
	b.ZIndex = 2
	return b
end

-- Zentrierte Beschriftung unter einem Punkt (Knotenname, Punktestand)
function Window.caption(
	parent: GuiObject,
	text: string,
	pos: Vector2,
	size: number,
	color: Color3?
): TextLabel
	local t = Kit.label(text, size, color or Theme.Color.Text)
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.fromOffset(pos.X, pos.Y)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextStrokeTransparency = 0.4
	t.ZIndex = 3
	t.Parent = parent
	return t
end

function Window.new(opts: Options): Window
	local gui, root = Kit.scaledGui("LootRush" .. opts.name, 6)
	gui.Enabled = false

	-- Szenenbild über den ganzen Bildschirm, sonst nur abdunkeln
	local back = Instance.new("ImageLabel")
	back.Name = "Hintergrund"
	back.BackgroundColor3 = Theme.Color.Bg0
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.ZIndex = 0
	local art = if opts.background then Assets.Art[opts.background] else nil
	if art then
		back.Image = art.id
		back.ScaleType = Enum.ScaleType.Crop
		back.BackgroundTransparency = 0
	end
	back.Parent = root

	local head = Window.frame(UDim2.fromOffset(600, 48), UDim2.fromOffset(40, 24))
	local hl = Kit.list(head, Enum.FillDirection.Horizontal, 12)
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	if opts.icon then
		local ic = Kit.icon(opts.icon, 44)
		ic.LayoutOrder = 1
		ic.Parent = head
	end
	local t = Window.heading(opts.title, 30, Theme.Color.GoldHi)
	t.LayoutOrder = 2
	t.Parent = head
	head.Parent = root

	local openFns: { () -> () } = {}
	local win: Window

	local function close()
		gui.Enabled = false
		if current == win then
			current = nil
		end
	end

	local function open()
		if current and current ~= win then
			current.close()
		end
		current = win
		gui.Enabled = true
		for _, fn in openFns do
			task.spawn(fn)
		end
	end

	win = {
		gui = gui,
		root = root,
		isOpen = function()
			return gui.Enabled
		end,
		toggle = function()
			if gui.Enabled then
				close()
			else
				open()
			end
		end,
		close = close,
		onOpen = function(fn: () -> ())
			table.insert(openFns, fn)
		end,
	}

	local x = Kit.iconButton("schliessen", "Schließen", 48, false, "close")
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -28, 0, 24)
	x.Activated:Connect(close)
	x.Parent = root

	if opts.key then
		local key = opts.key
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == key then
				win.toggle()
			end
		end)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return win
end

return Window
