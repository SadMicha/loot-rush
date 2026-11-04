--!strict
-- Star Web window (key N or menu button): the 100-star web on the left in a scroll area that
-- opens on the player's class start point (drag to pan, also on touch; zoom by pinch, mouse wheel,
-- +/- keys or the zoom buttons), points, star details and actions on the right.
-- Allocations are validated and saved by the server (Systems/Progress); the window shows the snapshot
-- from ProgressController and only sends requests (Net.Star).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local StarNet = require(ReplicatedStorage.Shared.StarNet)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local ProgressController = require(script.Parent.ProgressController)

local StarNetController = {}

local C = Theme.Color
local player = Players.LocalPlayer
local PAD = 28
local SIDE_W = 420
local WEB_ORDER = { "wisdom", "finesse", "might", "nature" } -- sector rows in the side panel
local WEB_ROW = 30
-- Empty border around the web inside the pan area: names of the outer stars stand wider than their
-- node and would be cut at the canvas edge ("Overgrowth", "Berserker", "Double Strike")
local WEB_MARGIN = 120
-- Zoom: 1 = design size. The smallest zoom still fills the pan area (computed in init), the largest
-- doubles the web. Buttons and +/- keys step by ZOOM_STEP, one mouse wheel notch by ZOOM_WHEEL.
local ZOOM_MAX = 2
local ZOOM_STEP = 1.25
local ZOOM_WHEEL = 1.12
local ZOOM_BUTTON = Vector2.new(68, 52)
local SIZE: { [string]: number } = { core = 100, small = 46, big = 72, start = 64 }
local BRANCH_COLOR: { [string]: Color3 } = {
	might = Theme.Rarity.unique,
	finesse = Theme.Rarity.magic,
	wisdom = Theme.Rarity.epic,
	nature = Theme.Rarity.legend,
}
local BRIDGE_COLOR = Theme.Rarity.rare

local win: Window.Window
local view: ScrollingFrame
local net: Frame
local side: Frame

local allocated: { [string]: boolean } = { heart = true }
local selected = "heart"

local function classId(): string?
	local c = player:GetAttribute("Class")
	return if typeof(c) == "string" then c else nil
end

local function colorOf(s: StarNet.Star): Color3
	return if s.branch then BRANCH_COLOR[s.branch] else BRIDGE_COLOR
end

-- Snapshot -> lookup table incl. Heart and the own class start point
local function refreshAllocated()
	allocated = { heart = true }
	local own = StarNet.startOf(classId())
	if own then
		allocated[own] = true
	end
	for id in ProgressController.data().stars do
		allocated[id] = true
	end
end

local function level(): number
	return (player:GetAttribute("Level") or 1) :: number
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

local function points(): number
	return Progression.starPoints(ProgressController.data(), level())
end

local function canAllocate(s: StarNet.Star): boolean
	return (Progression.canAllocate(ProgressController.data(), s.id, level(), classId()))
end

local function canRemove(s: StarNet.Star): boolean
	return (Progression.canRemove(ProgressController.data(), s.id, classId()))
end

-- ------------------------------------------------------------------ Net
local function artName(s: StarNet.Star): string
	if s.kind == "core" then
		return "star_core"
	end
	local kind = if s.kind == "start" then "big" else s.kind
	return "star_" .. kind .. (if allocated[s.id] then "_active" else "")
end

local function renderNet()
	clear(net)
	for _, s in StarNet.Stars do
		for _, id in s.links do
			local other = StarNet.ById[id]
			local on = allocated[s.id] == true and allocated[id] == true
			local l = Window.line(net, other.pos, s.pos, colorOf(s), if on then 4 else 2)
			l.BackgroundTransparency = if on then 0 else 0.55
		end
	end
	for _, s in StarNet.Stars do
		local on = allocated[s.id] == true
		local size = SIZE[s.kind]
		local b = Window.node(s.icon, size, s.pos, {
			art = artName(s),
			rarity = if s.kind == "core" or (on and not s.branch)
				then "rare"
				elseif on and s.branch then StarNet.BranchRarity[s.branch]
				else nil,
			dim = not on,
			selected = s.id == selected,
			tint = if on and s.kind ~= "core" then colorOf(s) else nil,
		})
		b.Activated:Connect(function()
			selected = s.id
			StarNetController.render()
		end)
		b.Parent = net
		if s.kind == "big" or s.kind == "start" then
			Window.caption(
				net,
				s.name,
				s.pos + Vector2.new(0, size / 2 + 4),
				16,
				if s.id == selected then C.GoldHi else C.Text
			)
		end
	end
end

-- ------------------------------------------------------------------ Right side
local function renderSide()
	clear(side)
	local w = SIDE_W - 2 * PAD
	local s = StarNet.ById[selected]

	-- Points and progress
	local head = Window.frame(UDim2.fromOffset(w, 60), UDim2.fromOffset(PAD, PAD))
	local ic = Kit.icon("star_net", 44)
	ic.Parent = head
	local p = Kit.label(tostring(points()), 30, C.GoldHi)
	p.Position = UDim2.fromOffset(56, 4)
	p.Parent = head
	local count = 0
	for _ in allocated do
		count += 1
	end
	local prog = Kit.label(
		string.format("%d / %d", count - 1, #StarNet.Stars - 1),
		15,
		C.Muted,
		Theme.Font.Body
	)
	prog.AnchorPoint = Vector2.new(1, 0)
	prog.Position = UDim2.new(1, 0, 0, 2)
	prog.Parent = head
	local back, fill = Kit.bar(Vector2.new(w - 140, 12), C.Gold)
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.new(1, 0, 0, 34)
	fill.Size = UDim2.fromScale((count - 1) / math.max(1, #StarNet.Stars - 1), 1)
	back.Parent = head
	head.Parent = side

	local divider = Kit.divider(w)
	divider.Position = UDim2.fromOffset(PAD, PAD + 76)
	divider.Parent = side

	-- Star card
	local kindText = if s.kind == "core"
		then "Heart"
		elseif s.kind == "start" then "Start Point"
		elseif s.kind == "big" then "Major Star"
		else "Star"
	local branchText = if s.branch
		then " - " .. StarNet.BranchName[s.branch]
		elseif s.kind ~= "core" then " - Bridge"
		else ""
	-- Full panel width: on phones the text grows to its minimum size and a shared row with the
	-- state cut it to "Start Point -..."; the state moved to the cost line below
	local kind =
		Kit.label(kindText .. branchText, 16, if s.kind == "core" then C.Gold else colorOf(s))
	kind.AutomaticSize = Enum.AutomaticSize.None
	kind.Size = UDim2.fromOffset(w, 24)
	kind.TextXAlignment = Enum.TextXAlignment.Left
	kind.TextScaled = false
	kind.TextTruncate = Enum.TextTruncate.AtEnd
	kind.Position = UDim2.fromOffset(PAD, PAD + 100)
	kind.Parent = side
	local state = if allocated[s.id]
		then "Allocated"
		elseif canAllocate(s) then "Available"
		else "Locked"

	local big = Kit.itemSlot(104, s.icon, {
		rarity = if s.branch then StarNet.BranchRarity[s.branch] else "rare",
		tint = if s.kind ~= "core" then colorOf(s) else nil,
	})
	big.Active = false
	big.Position = UDim2.fromOffset(PAD, PAD + 140)
	big.Parent = side
	local name = Window.heading(s.name, 22, C.Text)
	name.Position = UDim2.fromOffset(PAD + 120, PAD + 140)
	name.Parent = side
	local stats =
		Window.frame(UDim2.fromOffset(w - 120, 80), UDim2.fromOffset(PAD + 120, PAD + 184))
	local sl = Kit.list(stats, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Top)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for i, line in s.stats do
		local t = Kit.label(line, 16, C.Text, Theme.Font.Body)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.Size = UDim2.fromOffset(w - 120, 0)
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.LayoutOrder = i
		t.Parent = stats
	end
	stats.Parent = side

	local y = PAD + 270
	if s.flavor then
		local italic = Font.fromName("Nunito", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
		local f = Kit.label(s.flavor, 15, C.Muted, italic)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.Size = UDim2.fromOffset(w, 0)
		f.TextWrapped = true
		f.TextXAlignment = Enum.TextXAlignment.Left
		f.Position = UDim2.fromOffset(PAD, y)
		f.Parent = side
		y += 70
	end

	-- Cost and state in one wrapping line under the star card ("Free for your class · Allocated").
	-- Two labels side by side ran into each other once phones grow the text to its minimum size.
	local cost = StarNet.Cost[s.kind]
	local costText = if s.id == StarNet.startOf(classId())
		then "Free for your class"
		elseif cost > 0 then string.format(
			"Cost: %d Point%s",
			cost,
			if cost == 1 then "" else "s"
		)
		else nil
	local stateColor = if allocated[s.id] then C.Gold else C.Muted
	local line = Kit.label(
		"",
		16,
		if costText and s.id == StarNet.startOf(classId()) then C.GoldHi else C.Text
	)
	line.RichText = true
	line.Text = string.format(
		'%s<font color="#%s">%s</font>',
		if costText then costText .. "  ·  " else "",
		stateColor:ToHex(),
		string.upper(state)
	)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.Size = UDim2.fromOffset(w, 0)
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Position = UDim2.fromOffset(PAD, y)
	line.Parent = side

	-- Your web: allocated stars per sector (fills the panel with the build at a glance)
	local webY = PAD + 400
	local webHead = Kit.label("YOUR WEB", 15, C.Gold)
	webHead.Position = UDim2.fromOffset(PAD, webY)
	webHead.Parent = side
	local total: { [string]: number } = {}
	local taken: { [string]: number } = {}
	for _, star in StarNet.Stars do
		local b = star.branch
		if b and star.kind ~= "start" then
			total[b] = (total[b] or 0) + 1
			if allocated[star.id] then
				taken[b] = (taken[b] or 0) + 1
			end
		end
	end
	local cls = classId()
	local mine = if cls then StarNet.ClassBranch[cls] else nil
	for i, b in WEB_ORDER do
		local rowY = webY + 28 + (i - 1) * WEB_ROW
		local color = BRANCH_COLOR[b] or C.Gold
		local label = Kit.label(StarNet.BranchName[b], 15, if b == mine then color else C.Text)
		label.Position = UDim2.fromOffset(PAD, rowY)
		label.Parent = side
		local back2, fill2 = Kit.bar(Vector2.new(w - 170, 10), color)
		back2.AnchorPoint = Vector2.new(0, 0.5)
		back2.Position = UDim2.fromOffset(PAD + 110, rowY + 11)
		fill2.Size = UDim2.fromScale((taken[b] or 0) / math.max(1, total[b] or 1), 1)
		back2.Parent = side
		local n = Kit.label(
			string.format("%d/%d", taken[b] or 0, total[b] or 0),
			14,
			C.Muted,
			Theme.Font.Body
		)
		n.AnchorPoint = Vector2.new(1, 0)
		n.Position = UDim2.new(1, -PAD, 0, rowY)
		n.Parent = side
	end

	-- Actions
	-- One row: the main action and Reset side by side. Stacked, the touch growth on phones pushed
	-- Reset up into the main button.
	local remove = allocated[s.id] == true
	local resetW = math.floor(w * 0.36)
	local mainW = w - resetW - Theme.Space.S
	local main = Kit.button(
		if remove then "Remove" else "Allocate",
		C.Gold,
		Vector2.new(mainW, 60),
		if remove then "reroll" else "upgrade"
	)
	Kit.buttonLabel(main).TextSize = Kit.fontSize(20)
	main.AnchorPoint = Vector2.new(0, 1)
	main.Position = UDim2.new(0, PAD, 1, -PAD)
	Kit.setEnabled(main, if remove then canRemove(s) else canAllocate(s))
	main.Activated:Connect(function()
		if not main.Active then
			return
		end
		Net.Star:FireServer(if remove then "remove" else "alloc", s.id)
	end)
	main.Parent = side

	local reset = Kit.button("Reset", C.Danger, Vector2.new(resetW, 60), nil)
	reset.AnchorPoint = Vector2.new(1, 1)
	reset.Position = UDim2.new(1, -PAD, 1, -PAD)
	Kit.setEnabled(reset, Progression.starSpent(ProgressController.data()) > 0)
	reset.Activated:Connect(function()
		if reset.Active then
			Net.Star:FireServer("reset")
		end
	end)
	reset.Parent = side
end

-- ------------------------------------------------------------------ Flow
function StarNetController.render()
	refreshAllocated()
	renderNet()
	renderSide()
end

function StarNetController.toggle()
	win.toggle()
end

function StarNetController.init()
	win = Window.new({
		name = "StarNet",
		title = "Star Web",
		icon = "star_net",
		key = Enum.KeyCode.N,
		unlock = "star_net",
		background = "bg_starnet",
	})

	-- The web in a pan area left of the panel (drag or swipe to pan, no visible scroll bars)
	local rail = ZOOM_BUTTON.X + Theme.Space.M -- zoom buttons left of the web
	local area = Vector2.new(Window.BODY.X - SIDE_W - 20 - rail, Window.BODY.Y)
	view = Instance.new("ScrollingFrame")
	view.Name = "Web"
	view.BackgroundTransparency = 1
	view.BorderSizePixel = 0
	view.Size = UDim2.fromOffset(area.X, area.Y)
	view.Position = UDim2.fromOffset(rail, 0)
	local canvas = StarNet.Size + Vector2.new(2 * WEB_MARGIN, 2 * WEB_MARGIN)
	view.CanvasSize = UDim2.fromOffset(canvas.X, canvas.Y)
	view.ScrollingDirection = Enum.ScrollingDirection.XY
	-- Pan by dragging only: no scroll bars over the web on any device (thickness 0 alone still left
	-- a bar on some touch devices, so the bar images are cleared and made transparent as well)
	view.ScrollBarThickness = 0
	view.ScrollBarImageTransparency = 1
	view.TopImage = ""
	view.MidImage = ""
	view.BottomImage = ""
	view.VerticalScrollBarInset = Enum.ScrollBarInset.None
	view.HorizontalScrollBarInset = Enum.ScrollBarInset.None
	view.ElasticBehavior = Enum.ElasticBehavior.Never
	view.Parent = win.body
	-- Zoom layer: a UIScale on the whole canvas (lines, stars, captions); Roblox hit-tests scaled
	-- buttons correctly. Kit's phone minimum sizes count it only above 100% (ZoomLayer): zoomed in
	-- they relax, zoomed out the web is a true-to-scale overview (Kit.refit after every change).
	local holder = Window.frame(UDim2.fromOffset(canvas.X, canvas.Y))
	holder.Name = "Zoom"
	holder.Parent = view
	local zoomScale = Instance.new("UIScale")
	zoomScale:SetAttribute("ZoomLayer", true)
	zoomScale.Parent = holder
	net = Window.frame(
		UDim2.fromOffset(StarNet.Size.X, StarNet.Size.Y),
		UDim2.fromOffset(WEB_MARGIN, WEB_MARGIN)
	)
	net.Parent = holder

	local zoom = 1
	local zoomMin = math.min(1, math.max(area.X / canvas.X, area.Y / canvas.Y))
	local zoomLabel: TextLabel? = nil

	-- Screen pixels -> pan-area units (the window itself is scaled by its own UIScale)
	local function windowScale(): number
		return view.AbsoluteSize.X / math.max(1, area.X)
	end
	local function toLocal(screen: Vector2): Vector2
		return (screen - view.AbsolutePosition) / math.max(windowScale(), 0.01)
	end
	local function inView(screen: Vector2): boolean
		local rel = screen - view.AbsolutePosition
		return rel.X >= 0
			and rel.Y >= 0
			and rel.X <= view.AbsoluteSize.X
			and rel.Y <= view.AbsoluteSize.Y
	end
	-- InputObject.Position leaves out the top bar inset; the window gui ignores it
	local function screenOf(input: InputObject): Vector2
		local inset = GuiService:GetGuiInset()
		return Vector2.new(input.Position.X, input.Position.Y) + inset
	end

	-- Sets the zoom so that `content` (canvas point at zoom 1, default: what is under `anchor`) stays
	-- under `anchor` (point in the pan area)
	local function setZoom(z: number, anchor: Vector2, content: Vector2?)
		if z ~= z then
			return
		end
		local c = content or (view.CanvasPosition + anchor) / zoom
		zoom = math.clamp(z, zoomMin, ZOOM_MAX)
		zoomScale.Scale = zoom
		local size = canvas * zoom
		view.CanvasSize = UDim2.fromOffset(math.ceil(size.X), math.ceil(size.Y))
		local p = c * zoom - anchor
		view.CanvasPosition = Vector2.new(
			math.clamp(p.X, 0, math.max(0, size.X - area.X)),
			math.clamp(p.Y, 0, math.max(0, size.Y - area.Y))
		)
		if zoomLabel then
			zoomLabel.Text = string.format("%d%%", math.floor(zoom * 100 + 0.5))
		end
		Kit.refit(win.root)
	end

	-- Mouse: the wheel zooms instead of scrolling, so native scrolling is only on for touch/gamepad
	-- (and off while two fingers pinch)
	local lastInput = UserInputService:GetLastInputType()
	local touchPan = UserInputService.TouchEnabled
		and lastInput ~= Enum.UserInputType.MouseMovement
		and lastInput ~= Enum.UserInputType.MouseButton1
	local touches: { [InputObject]: true } = {}
	local pinchDist = 0 -- finger distance when the pinch started (0 = no pinch)
	local pinchZoom = 1
	local pinchContent = Vector2.zero

	local function updateScrolling()
		view.ScrollingEnabled = touchPan and pinchDist == 0
	end
	updateScrolling()

	local function pinchPair(): (InputObject?, InputObject?)
		local a = next(touches)
		local b = a and next(touches, a)
		if not a or not b or next(touches, b) ~= nil then
			return nil, nil
		end
		return a, b
	end
	-- Exactly two fingers on the web pinch; the midpoint is the zoom center and pans along
	local function refreshPinch()
		local a, b = pinchPair()
		pinchDist = 0
		if a and b then
			local pa, pb = screenOf(a), screenOf(b)
			local dist = (pa - pb).Magnitude
			if dist > 1 then
				pinchDist = dist
				pinchZoom = zoom
				pinchContent = (view.CanvasPosition + toLocal((pa + pb) / 2)) / zoom
			end
		end
		updateScrolling()
	end

	-- Mouse drag pans the web too (touch pans the ScrollingFrame natively)
	local dragging = false
	view.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			if not touchPan then
				touchPan = true
				updateScrolling()
			end
			if win.isOpen() and inView(screenOf(input)) then
				touches[input] = true
				refreshPinch()
			end
		elseif t == Enum.UserInputType.MouseButton1 then
			if touchPan then
				touchPan = false
				updateScrolling()
			end
		elseif t == Enum.UserInputType.Keyboard and not processed and win.isOpen() then
			local k = input.KeyCode
			if k == Enum.KeyCode.Equals or k == Enum.KeyCode.KeypadPlus then
				setZoom(zoom * ZOOM_STEP, area / 2)
			elseif k == Enum.KeyCode.Minus or k == Enum.KeyCode.KeypadMinus then
				setZoom(zoom / ZOOM_STEP, area / 2)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		if dragging and t == Enum.UserInputType.MouseMovement then
			local d = input.Delta
			view.CanvasPosition -= Vector2.new(d.X, d.Y) / math.max(windowScale(), 0.01)
		elseif t == Enum.UserInputType.MouseWheel then
			local m = UserInputService:GetMouseLocation()
			if win.isOpen() and inView(m) then
				if touchPan then
					touchPan = false
					updateScrolling()
				end
				setZoom(zoom * ZOOM_WHEEL ^ input.Position.Z, toLocal(m))
			end
		elseif touches[input] and pinchDist > 0 then
			local a, b = pinchPair()
			if a and b then
				local pa, pb = screenOf(a), screenOf(b)
				setZoom(
					pinchZoom * (pa - pb).Magnitude / pinchDist,
					toLocal((pa + pb) / 2),
					pinchContent
				)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		elseif touches[input] then
			touches[input] = nil
			refreshPinch()
		end
	end)

	-- Zoom rail left of the web (not over it, so it never covers star names): current zoom, +, -
	-- and Reset (back to 100%)
	local zoomBar = Window.frame(UDim2.fromOffset(ZOOM_BUTTON.X, area.Y), UDim2.fromOffset(0, 0))
	zoomBar.Name = "ZoomBar"
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom -- touch growth on phones goes upward
	list.Padding = UDim.new(0, Theme.Space.S)
	list.Parent = zoomBar
	local percent = Kit.label("100%", 16, C.GoldHi, Theme.Font.Title)
	percent.Name = "ZoomLevel"
	percent.Size = UDim2.fromOffset(ZOOM_BUTTON.X, 24)
	percent.TextXAlignment = Enum.TextXAlignment.Center
	percent.LayoutOrder = 0
	percent.Parent = zoomBar
	zoomLabel = percent
	local function zoomButton(
		name: string,
		text: string,
		order: number,
		onTap: () -> ()
	): ImageButton
		local b = Kit.button(text, C.Muted, ZOOM_BUTTON)
		b.Name = name
		b.LayoutOrder = order
		b.Activated:Connect(onTap)
		b.Parent = zoomBar
		Kit.buttonLabel(b).TextSize = Kit.fontSize(28)
		return b
	end
	zoomButton("ZoomIn", "+", 1, function()
		setZoom(zoom * ZOOM_STEP, area / 2)
	end)
	zoomButton("ZoomOut", "-", 2, function()
		setZoom(zoom / ZOOM_STEP, area / 2)
	end)
	local reset = zoomButton("ZoomReset", "Reset", 3, function()
		setZoom(1, area / 2)
	end)
	Kit.buttonLabel(reset).TextSize = Kit.fontSize(15)
	zoomBar.Parent = win.body

	side = Kit.panel(Vector2.new(SIDE_W, Window.BODY.Y))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Parent = win.body

	-- Opens on the own class start point (or the heart)
	win.onOpen(function()
		local focus = StarNet.ById[StarNet.startOf(classId()) or "heart"]
		selected = focus.id
		StarNetController.render()
		-- Every open starts at 100%, centered between the class start point and the heart
		touches = {}
		refreshPinch()
		setZoom(1, area / 2, (focus.pos + StarNet.Center) / 2 + Vector2.new(WEB_MARGIN, WEB_MARGIN))
	end)
	local function refresh()
		if win.isOpen() then
			StarNetController.render()
		end
	end
	player:GetAttributeChangedSignal("Level"):Connect(refresh)
	ProgressController.changed:Connect(refresh)
	StarNetController.render()
end

return StarNetController
