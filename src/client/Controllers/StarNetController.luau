--!strict
-- Star Net window (key N or menu button): the 100-star web on the left in a scroll area that
-- opens on the player's class start point (drag to pan, also on touch), points, star details
-- and actions on the right.
-- Allocations are validated and saved by the server (Systems/Progress); the window shows the snapshot
-- from ProgressController and only sends requests (Net.Star).

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
		then " · " .. StarNet.BranchName[s.branch]
		elseif s.kind ~= "core" then " · Bridge"
		else ""
	local kind =
		Kit.label(kindText .. branchText, 16, if s.kind == "core" then C.Gold else colorOf(s))
	kind.AutomaticSize = Enum.AutomaticSize.Y
	kind.Size = UDim2.fromOffset(w - 130, 0) -- ends before the state on the right
	kind.TextXAlignment = Enum.TextXAlignment.Left
	kind.TextTruncate = Enum.TextTruncate.AtEnd
	kind.Position = UDim2.fromOffset(PAD, PAD + 100)
	kind.Parent = side
	local state = if allocated[s.id]
		then "Allocated"
		elseif canAllocate(s) then "Available"
		else "Locked"
	local st = Kit.label(state, 14, if allocated[s.id] then C.Gold else C.Muted)
	st.AnchorPoint = Vector2.new(1, 0)
	st.Position = UDim2.new(1, -PAD, 0, PAD + 102)
	st.Parent = side

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

	-- Cost
	local cost = StarNet.Cost[s.kind]
	if s.id == StarNet.startOf(classId()) then
		local c = Kit.label("Free for your class", 16, C.GoldHi)
		c.Position = UDim2.fromOffset(PAD, y)
		c.Parent = side
	elseif cost > 0 then
		local c = Kit.label(
			string.format("Cost: %d Point%s", cost, if cost == 1 then "" else "s"),
			16,
			C.Text
		)
		c.Position = UDim2.fromOffset(PAD, y)
		c.Parent = side
	end

	local note = Kit.label(
		"One point per level from level 2. Your class starts at its own start point; bridges lead into other sectors. Resetting refunds all points.",
		14,
		C.Muted,
		Theme.Font.Body
	)
	note.AutomaticSize = Enum.AutomaticSize.Y
	note.Size = UDim2.fromOffset(w, 0)
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, PAD, 1, -PAD - 140)
	note.Parent = side

	-- Actions
	local remove = allocated[s.id] == true
	local main = Kit.button(
		if remove then "Remove" else "Allocate",
		C.Gold,
		Vector2.new(w, 60),
		if remove then "reroll" else "upgrade"
	)
	Kit.buttonLabel(main).TextSize = Kit.fontSize(22)
	main.AnchorPoint = Vector2.new(0, 1)
	main.Position = UDim2.new(0, PAD, 1, -PAD - 62)
	Kit.setEnabled(main, if remove then canRemove(s) else canAllocate(s))
	main.Activated:Connect(function()
		if not main.Active then
			return
		end
		Net.Star:FireServer(if remove then "remove" else "alloc", s.id)
	end)
	main.Parent = side

	local reset = Kit.button("Reset", C.Danger, Vector2.new(w, 50), "reroll")
	reset.AnchorPoint = Vector2.new(0, 1)
	reset.Position = UDim2.new(0, PAD, 1, -PAD)
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
		title = "Star Net",
		icon = "star_net",
		key = Enum.KeyCode.N,
		unlock = "star_net",
		background = "bg_starnet",
	})

	-- The web in a pan area left of the panel (drag or swipe to pan, no visible scroll bars)
	local area = Vector2.new(Window.BODY.X - SIDE_W - 20, Window.BODY.Y)
	view = Instance.new("ScrollingFrame")
	view.Name = "Web"
	view.BackgroundTransparency = 1
	view.BorderSizePixel = 0
	view.Size = UDim2.fromOffset(area.X, area.Y)
	view.CanvasSize = UDim2.fromOffset(StarNet.Size.X, StarNet.Size.Y)
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
	net = Window.frame(UDim2.fromOffset(StarNet.Size.X, StarNet.Size.Y))
	net.Parent = view
	-- Mouse drag pans the web too (touch pans the ScrollingFrame natively)
	local dragging = false
	view.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local d = input.Delta
			local scale = view.AbsoluteSize.X / math.max(1, view.Size.X.Offset)
			view.CanvasPosition -= Vector2.new(d.X, d.Y) / math.max(scale, 0.01)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	side = Kit.panel(Vector2.new(SIDE_W, Window.BODY.Y))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Parent = win.body

	-- Opens on the own class start point (or the heart)
	win.onOpen(function()
		local focus = StarNet.ById[StarNet.startOf(classId()) or "heart"]
		selected = focus.id
		StarNetController.render()
		local p = (focus.pos + StarNet.Center) / 2 - area / 2
		view.CanvasPosition = Vector2.new(
			math.clamp(p.X, 0, StarNet.Size.X - area.X),
			math.clamp(p.Y, 0, StarNet.Size.Y - area.Y)
		)
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
