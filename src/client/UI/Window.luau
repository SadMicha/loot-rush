--!strict
-- Shared frame of the fullscreen windows (Abilities, Star Net, Forge, Atlas):
-- scene image or dimming, title at the top left (next to the Roblox buttons), close at the top right,
-- own hotkey. The content lives in `body` (fixed design area Window.BODY), which is centered below the header
-- and scaled down if needed - so it fits phone, tablet and PC.
-- Only one of these windows is open at a time; opening one closes the previous.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Kit)

local Window = {}

Window.BODY = Vector2.new(1520, 790) -- content area in design pixels
local MARGIN = 40 -- margin left/right
local HEAD = 48 -- height of the header (title, close)

export type Options = {
	name: string,
	title: string,
	icon: string?, -- Assets.Icon before the title
	key: Enum.KeyCode?,
	unlock: string?, -- onboarding unlock id (Shared/Quests): the hotkey does nothing while locked
	background: string?, -- key in Assets.Art
}

export type Window = {
	gui: ScreenGui,
	root: Frame,
	body: Frame,
	isOpen: () -> boolean,
	toggle: () -> (),
	close: () -> (),
	onOpen: (fn: () -> ()) -> (),
}

local current: Window? = nil
local gate: ((unlockId: string) -> boolean)? = nil -- true = locked (set by QuestController)
local others: { () -> () } = {} -- further fullscreen windows (inventory) that close when one opens
local otherOpen: { () -> boolean } = {} -- their "is open" probes

-- Hotkey lock for windows with `unlock` (fn answers true when locked and may show a hint)
function Window.setGate(fn: (unlockId: string) -> boolean)
	gate = fn
end

-- Close the open window (e.g. when the inventory opens)
function Window.closeCurrent()
	if current then
		current.close()
	end
end

-- Also close a window outside this module as soon as one from here opens
function Window.exclusive(close: () -> (), isOpen: (() -> boolean)?)
	table.insert(others, close)
	if isOpen then
		table.insert(otherOpen, isOpen)
	end
end

-- True while any fullscreen window is open (the HUD can pause expensive work behind it)
function Window.anyOpen(): boolean
	if current then
		return true
	end
	for _, probe in otherOpen do
		if probe() then
			return true
		end
	end
	return false
end

function Window.caps(text: string): string
	return string.upper(text)
end

-- Window title in capital letters (title font)
function Window.heading(text: string, size: number?, color: Color3?): TextLabel
	return Kit.label(Window.caps(text), size or 20, color or Theme.Color.Text, Theme.Font.Title)
end

-- Borderless container without background
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

-- Drawn frame pieces from the old art packs: retired with the flat look (callers fall back to shapes).
-- Scene pictures (backgrounds, islands, regions, anvil) stay.
local FRAME_ART: { [string]: boolean } = {
	node_ring = true,
	node_ring_active = true,
	node_ring_locked = true,
	star_small = true,
	star_small_active = true,
	star_big = true,
	star_big_active = true,
	star_core = true,
	plaque_region = true,
	plaque_status = true,
}

-- Image from Assets.Art (fixed size, fitted) or nil while it is missing / a retired frame piece
function Window.art(name: string, size: Vector2): ImageLabel?
	local art = if FRAME_ART[name] then nil else Assets.Art[name]
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

-- Run `fn` as soon as the image has really loaded (keep the code fallback visible until then;
-- an image in moderation or with a wrong ID never loads)
function Window.whenLoaded(img: ImageLabel | ImageButton, fn: () -> ())
	if img.IsLoaded then
		fn()
		return
	end
	local conn: RBXScriptConnection
	conn = img:GetPropertyChangedSignal("IsLoaded"):Connect(function()
		if img.IsLoaded then
			conn:Disconnect()
			fn()
		end
	end)
end

-- Straight line between two points (design pixels), e.g. connections in the tree
function Window.line(parent: GuiObject, a: Vector2, b: Vector2, color: Color3, width: number): Frame
	local d = b - a
	local f = Instance.new("Frame")
	f.Name = "Line"
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
	art: string?, -- ring from Assets.Art; if missing, a slot by `rarity` is used
	rarity: string?,
	dim: boolean?,
	selected: boolean?,
	tint: Color3?, -- tints the ring image (branch color in the Star Net)
}

-- Round tree node (skill bloom, Star Net), centered on `pos`
function Window.node(iconName: string, size: number, pos: Vector2, opts: NodeOptions): ImageButton
	local ring = if opts.art and not FRAME_ART[opts.art] then Assets.Art[opts.art] else nil
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
		if opts.dim then
			Kit.setIconTransparency(ic, 0.6)
		end
		ic.Parent = b
	else
		-- Flat round node: rarity (or branch tint) edge with glow
		b = Kit.itemSlot(size, iconName, {
			rarity = opts.rarity or (if opts.dim then nil else "magic"),
			dim = opts.dim,
			selected = opts.selected,
			round = true,
			tint = if opts.dim then nil else opts.tint,
		})
	end
	b.Name = "Node"
	Kit.touchTarget(b)
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromOffset(pos.X, pos.Y)
	b.ZIndex = 2
	return b
end

-- Centered caption below a point (node name, point count)
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
	Kit.textOutline(t, 0.4)
	t.ZIndex = 3
	t.Parent = parent
	return t
end

-- Roblox buttons at the top left (logo, menu, chat) in screen points: right edge and height
function Window.topbar(): (number, number)
	local inset: any = GuiService.TopbarInset
	if typeof(inset) == "Rect" and inset.Height > 0 then
		return inset.Min.X, inset.Max.Y
	end
	local h = GuiService:GetGuiInset().Y
	return h * 3.2, h
end

function Window.new(opts: Options): Window
	local gui, root = Kit.scaledGui("LootRush" .. opts.name, 6, true)
	gui.Enabled = false

	-- Scene image over the whole screen, otherwise just dim
	local back = Instance.new("ImageLabel")
	back.Name = "Background"
	back.BackgroundColor3 = Theme.Color.Bg0
	back.BackgroundTransparency = 0.1 -- the HUD underneath should not show through
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.ZIndex = 0
	back.Active = true -- do not pass clicks through to the HUD underneath
	local art = if opts.background then Assets.Art[opts.background] else nil
	if art then
		back.Image = art.id
		back.ScaleType = Enum.ScaleType.Crop
		back.BackgroundTransparency = 0
		-- Dark shade over the scene so the flat cards stay readable (darker toward the bottom)
		local shade = Instance.new("Frame")
		shade.Name = "Shade"
		shade.BackgroundColor3 = Theme.Flat.Surface0
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, 1)
		shade.Active = false
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new(0.45, 0.2)
		g.Parent = shade
		shade.Parent = back
	end
	back.Parent = root

	local head = Window.frame(UDim2.fromOffset(600, HEAD))
	head.Name = "Header"
	head.AnchorPoint = Vector2.new(0, 0.5)
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

	local body = Window.frame(UDim2.fromOffset(Window.BODY.X, Window.BODY.Y))
	body.Name = "Content"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	local bodyScale = Instance.new("UIScale")
	bodyScale.Parent = body
	body.Parent = root

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
		for _, closeOther in others do
			closeOther()
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
		body = body,
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

	local x = Kit.iconButton("close", "Close", HEAD, false, "close")
	x.AnchorPoint = Vector2.new(1, 0.5)
	x.Activated:Connect(close)
	x.Parent = root

	-- Header next to the Roblox buttons, fit the content into the rest (all in design pixels)
	local scale = root:FindFirstChildOfClass("UIScale") :: UIScale
	local function arrange()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local s = scale.Scale
		local view = camera.ViewportSize / s
		local barRight, barH = Window.topbar()
		barRight, barH = barRight / s, barH / s
		local mid = math.max(MARGIN + HEAD / 2 - 16, barH / 2)
		local left = math.max(MARGIN, barRight + 16)
		head.Position = UDim2.fromOffset(left, mid)
		head.Size = UDim2.fromOffset(math.max(200, view.X - left - 120), HEAD)
		x.Position = UDim2.new(1, -28, 0, mid)

		local top = math.max(mid + HEAD / 2 + 16, barH + 8)
		local availW, availH = view.X - 2 * MARGIN, view.Y - top - 16
		local k = math.min(availW / Window.BODY.X, availH / Window.BODY.Y, 1.2)
		bodyScale.Scale = k
		body.Position = UDim2.fromOffset(view.X / 2, top + availH / 2)
		Kit.refit(root)
	end
	arrange()
	scale:GetPropertyChangedSignal("Scale"):Connect(arrange)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(arrange)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(arrange)
	end

	if opts.key then
		local key = opts.key
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == key then
				if opts.unlock and gate and not win.isOpen() and gate(opts.unlock) then
					return
				end
				win.toggle()
			end
		end)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return win
end

return Window
