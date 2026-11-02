--!strict
-- Flat UI building blocks (Theme.Flat): everything is a Roblox shape, no drawn frames/buttons/slots.
-- Only icons are images (Kit.icon). Motion comes from Spring (hover, press, selection, toggles, tabs)
-- and one shared clock for the rarity glow (pulse + rotating edge highlight).
-- Sizes are design pixels like the rest of the UI (Kit.scaledGui scales the root).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Kit)
local Spring = require(script.Parent.Spring)

local Flat = {}

local F = Theme.Flat
local C = Theme.Color

-- ------------------------------------------------------------------ Basics
function Flat.corner(parent: GuiObject, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Flat.stroke(
	parent: GuiObject,
	color: Color3,
	thickness: number?,
	transparency: number?
): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness or F.Stroke
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

-- Vertical gradient: `top` color/transparency fading to `bottom`
function Flat.gradient(
	parent: Instance,
	top: Color3,
	bottom: Color3,
	topT: number?,
	bottomT: number?,
	rotation: number?
): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Transparency = NumberSequence.new(topT or 0, bottomT or 0)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function Flat.frame(size: UDim2, pos: UDim2?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = size
	if pos then
		f.Position = pos
	end
	return f
end

-- Plain text without outline (the flat look stays crisp); size in design pixels like Kit.label
function Flat.text(
	text: string,
	size: number,
	color: Color3?,
	font: Font?,
	align: Enum.TextXAlignment?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Text = text
	t.TextSize = Kit.fontSize(size)
	t.TextColor3 = color or C.Text
	t.FontFace = font or Theme.Font.UI
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.fromOffset(0, 0)
	return t
end

-- Card: rounded surface with a hairline edge and a faint sheen at the top
function Flat.card(size: UDim2, color: Color3?, edge: Color3?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or F.Surface1
	f.BackgroundTransparency = F.CardTransparency
	f.BorderSizePixel = 0
	f.Size = size
	Flat.corner(f, F.Radius.L)
	Flat.stroke(f, edge or F.Edge)
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BorderSizePixel = 0
	sheen.Size = UDim2.new(1, 0, 0, 56)
	sheen.ZIndex = 0
	Flat.corner(sheen, F.Radius.L)
	Flat.gradient(sheen, Color3.new(1, 1, 1), Color3.new(1, 1, 1), F.SheenTransparency, 1)
	sheen.Parent = f
	return f
end

-- Thin line
function Flat.rule(width: number, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = "Rule"
	f.BackgroundColor3 = color or F.Edge
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(width, 1)
	return f
end

-- ------------------------------------------------------------------ Glow clock
-- Halo strokes breathe and edge gradients spin; one Heartbeat for all of them, only while their
-- ScreenGui is enabled. Entries vanish with their instances (weak keys).
type Pulse = { base: number, phase: number }
local pulses: { [UIStroke]: Pulse } = setmetatable({}, { __mode = "k" }) :: any
local spins: { [UIGradient]: number } = setmetatable({}, { __mode = "k" }) :: any
local clock: RBXScriptConnection? = nil

local function visible(inst: Instance): boolean
	local gui = inst:FindFirstAncestorOfClass("ScreenGui")
	return gui ~= nil and gui.Enabled
end

local function tick()
	local t = os.clock()
	local any = false
	for stroke, p in pulses do
		if not stroke.Parent then
			pulses[stroke] = nil
			continue
		end
		any = true
		if visible(stroke) then
			local wave = (math.sin(t * F.PulseSpeed + p.phase) + 1) / 2
			stroke.Transparency = math.clamp(p.base + (wave - 0.5) * 2 * F.PulseDepth, 0, 1)
		end
	end
	for g, phase in spins do
		if not g.Parent then
			spins[g] = nil
			continue
		end
		any = true
		if visible(g) then
			g.Rotation = (t * F.SpinSpeed + phase) % 360
		end
	end
	if not any and clock then
		clock:Disconnect()
		clock = nil
	end
end

local function runClock()
	if not clock then
		clock = RunService.Heartbeat:Connect(tick)
	end
end

-- Glow around a shape: up to three halo rings outside its edge (Theme.Flat.Halo), optional breathing
function Flat.glow(
	target: GuiObject,
	color: Color3,
	rings: number,
	pulse: boolean?,
	radius: number?
)
	for i = 1, math.min(rings, #F.Halo) do
		local spec = F.Halo[i]
		local ring = Instance.new("Frame")
		ring.Name = "Halo" .. i
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.Size = UDim2.fromScale(1, 1)
		ring.ZIndex = 0
		ring.Active = false
		Flat.corner(ring, (radius or F.Radius.M) + spec[1] / 2)
		local s = Flat.stroke(ring, color, spec[1], spec[2])
		s.LineJoinMode = Enum.LineJoinMode.Round
		if pulse then
			pulses[s] = { base = spec[2], phase = (os.clock() * 7 + i) % (2 * math.pi) }
		end
		ring.Parent = target
	end
	if pulse then
		runClock()
	end
end

-- Rotating highlight along a stroke (white streak passing around the edge)
function Flat.spin(stroke: UIStroke, color: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.45, color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, color),
		ColorSequenceKeypoint.new(1, color),
	})
	g.Parent = stroke
	spins[g] = math.random() * 360
	runClock()
end

-- ------------------------------------------------------------------ Motion
-- Hover grows, press shrinks, release springs back (UIScale "Motion" on the button)
function Flat.motion(b: GuiButton, rest: number?): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "Motion"
	local base = rest or 1
	scale.Scale = base
	scale.Parent = b
	local hovering = false
	b.MouseEnter:Connect(function()
		hovering = true
		Spring.target(scale, { Scale = base * F.HoverScale }, "Snappy")
	end)
	b.MouseLeave:Connect(function()
		hovering = false
		Spring.target(scale, { Scale = base }, "Snappy")
	end)
	b.MouseButton1Down:Connect(function()
		Spring.target(scale, { Scale = base * F.PressScale }, "Snappy")
	end)
	b.MouseButton1Up:Connect(function()
		Spring.target(scale, { Scale = if hovering then base * F.HoverScale else base }, "Bouncy")
	end)
	return scale
end

-- ------------------------------------------------------------------ Buttons
export type ButtonKind = "primary" | "secondary" | "danger" | "ghost"

local BUTTON: { [string]: { fill: Color3, fill2: Color3, edge: Color3, text: Color3, t: number } } =
	{
		primary = { fill = C.GoldHi, fill2 = C.GoldLo, edge = C.GoldHi, text = F.Surface0, t = 0 },
		secondary = { fill = F.Surface3, fill2 = F.Surface2, edge = F.EdgeHi, text = C.Text, t = 0 },
		danger = { fill = C.Danger, fill2 = C.Life, edge = C.Danger, text = C.Text, t = 0.1 },
		ghost = { fill = F.Surface2, fill2 = F.Surface2, edge = F.Edge, text = C.Muted, t = 0.3 },
	}

-- Text button with optional icon on the left. Returns the button and its label.
function Flat.button(
	text: string,
	kind: ButtonKind,
	size: Vector2,
	iconName: string?
): (TextButton, TextLabel)
	local style = BUTTON[kind]
	local b = Instance.new("TextButton")
	b.Name = "Button"
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BackgroundTransparency = style.t
	b.Size = UDim2.fromOffset(size.X, size.Y)
	Kit.touchTarget(b)
	Flat.corner(b, F.Radius.M)
	Flat.gradient(b, style.fill, style.fill2)
	Flat.stroke(b, style.edge, F.Stroke, 0.3)
	local row = Flat.frame(UDim2.fromScale(1, 1))
	row.Name = "Row"
	Kit.list(row, Enum.FillDirection.Horizontal, 8)
	if iconName then
		local ic = Kit.icon(iconName, math.floor(size.Y * 0.5))
		ic.LayoutOrder = 1
		ic.Parent = row
	end
	local t = Flat.text(
		text,
		math.min(16, size.Y * 0.36),
		style.text,
		Theme.Font.UI,
		Enum.TextXAlignment.Center
	)
	t.Name = "Label"
	t.LayoutOrder = 2
	t.Parent = row
	row.Parent = b
	Flat.motion(b)
	return b, t
end

-- Dim a button and ignore clicks (Active stays for touch hits, the caller checks `Enabled` attribute)
function Flat.setEnabled(b: GuiButton, enabled: boolean)
	b:SetAttribute("Enabled", enabled)
	b.AutoButtonColor = false
	b.BackgroundTransparency = if enabled then 0 else 0.6
	local label = b:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.TextTransparency = if enabled then 0 else 0.5
	end
end

-- ------------------------------------------------------------------ Tabs with sliding marker
export type Tabs = {
	frame: Frame,
	select: (id: string) -> (),
}

-- Text tabs in a row; the active one has a gold marker that springs under it.
-- `onSelect` runs for clicks (not for `select` from code).
function Flat.tabs(
	defs: { { id: string, text: string } },
	height: number,
	onSelect: (id: string) -> ()
): Tabs
	local frame = Flat.frame(UDim2.fromOffset(0, height))
	frame.Name = "Tabs"
	frame.AutomaticSize = Enum.AutomaticSize.X
	local row = Flat.frame(UDim2.fromScale(0, 1))
	row.AutomaticSize = Enum.AutomaticSize.X
	local layout = Kit.list(row, Enum.FillDirection.Horizontal, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	row.Parent = frame

	-- Marker: pill behind the active tab (gold tint + bright edge)
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.BackgroundColor3 = C.Gold
	marker.BackgroundTransparency = 0.82
	marker.BorderSizePixel = 0
	marker.Size = UDim2.fromOffset(0, height)
	marker.ZIndex = 0
	Flat.corner(marker, F.Radius.M)
	Flat.stroke(marker, C.Gold, F.Stroke, 0.1)
	marker.Parent = frame

	local buttons: { [string]: TextButton } = {}
	local labels: { [string]: TextLabel } = {}
	local current: string? = nil

	local function place(id: string, animate: boolean)
		local b = buttons[id]
		if not b then
			return
		end
		local goal = {
			Position = UDim2.fromOffset(b.AbsolutePosition.X - frame.AbsolutePosition.X, 0),
			Size = UDim2.fromOffset(b.AbsoluteSize.X, height),
		}
		-- Absolute sizes are screen pixels; convert back to design pixels of this frame
		local k = if frame.AbsoluteSize.Y > 0 then height / frame.AbsoluteSize.Y else 1
		goal.Position = UDim2.fromOffset((b.AbsolutePosition.X - frame.AbsolutePosition.X) * k, 0)
		goal.Size = UDim2.fromOffset(b.AbsoluteSize.X * k, height)
		if animate then
			Spring.target(marker, goal, "Bouncy")
		else
			Spring.snap(marker, goal)
		end
	end

	local function choose(id: string, animate: boolean)
		current = id
		for key, label in labels do
			label.TextColor3 = if key == id then C.GoldHi else C.Muted
		end
		place(id, animate)
	end

	for i, def in defs do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. def.id
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.fromOffset(0, height)
		b.LayoutOrder = i
		Kit.touchTarget(b)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 16)
		pad.PaddingRight = UDim.new(0, 16)
		pad.Parent = b
		local t = Flat.text(
			string.upper(def.text),
			14,
			C.Muted,
			Theme.Font.UI,
			Enum.TextXAlignment.Center
		)
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromScale(0, 1)
		t.Parent = b
		labels[def.id] = t
		buttons[def.id] = b
		b.Activated:Connect(function()
			if current ~= def.id then
				choose(def.id, true)
				onSelect(def.id)
			end
		end)
		b:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if current == def.id then
				place(def.id, false)
			end
		end)
		b.Parent = row
	end
	frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if current then
			place(current, false)
		end
	end)

	return {
		frame = frame,
		select = function(id: string)
			choose(id, false)
		end,
	}
end

-- ------------------------------------------------------------------ Toggle switch
export type Toggle = {
	frame: TextButton,
	set: (on: boolean) -> (),
}

-- Pill switch with a knob that springs across; `color` tints the track when on
function Flat.toggle(
	text: string,
	iconName: string?,
	color: Color3,
	onChange: (on: boolean) -> ()
): Toggle
	local b = Instance.new("TextButton")
	b.Name = "Toggle"
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = F.Surface2
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, 44)
	Kit.touchTarget(b)
	Flat.corner(b, F.Radius.M)
	local edge = Flat.stroke(b, F.Edge)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = b
	local layout = Kit.list(b, Enum.FillDirection.Horizontal, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	if iconName then
		local ic = Kit.icon(iconName, 24)
		ic.LayoutOrder = 1
		ic.Parent = b
	end
	local t = Flat.text(string.upper(text), 13, C.Text)
	t.LayoutOrder = 2
	t.Parent = b

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.LayoutOrder = 3
	track.Size = UDim2.fromOffset(46, 24)
	track.BackgroundColor3 = F.Surface0
	track.BorderSizePixel = 0
	Flat.corner(track, 12)
	Flat.stroke(track, F.Edge)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 3, 0.5, 0)
	knob.Size = UDim2.fromOffset(18, 18)
	knob.BackgroundColor3 = C.Muted
	knob.BorderSizePixel = 0
	Flat.corner(knob, 9)
	knob.Parent = track
	track.Parent = b

	local on = false
	local function apply(animate: boolean)
		local goals = {
			Position = UDim2.new(0, if on then 25 else 3, 0.5, 0),
			BackgroundColor3 = if on then Color3.new(1, 1, 1) else C.Muted,
		}
		local trackGoal = { BackgroundColor3 = if on then color else F.Surface0 }
		if animate then
			Spring.target(knob, goals, "Bouncy")
			Spring.target(track, trackGoal, "Soft")
		else
			Spring.snap(knob, goals)
			Spring.snap(track, trackGoal)
		end
		edge.Color = if on then color else F.Edge
	end
	b.Activated:Connect(function()
		on = not on
		apply(true)
		onChange(on)
	end)
	Flat.motion(b)
	return {
		frame = b,
		set = function(v: boolean)
			on = v
			apply(false)
		end,
	}
end

-- ------------------------------------------------------------------ Bars
-- Horizontal bar: track + gradient fill. Returns track and a setter (0..1, springs when animate)
function Flat.bar(
	size: Vector2,
	color: Color3
): (Frame, (fraction: number, animate: boolean?) -> ())
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.BackgroundColor3 = F.Surface0
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(size.X, size.Y)
	Flat.corner(track, math.ceil(size.Y / 2))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Flat.corner(fill, math.ceil(size.Y / 2))
	Flat.gradient(fill, color:Lerp(Color3.new(1, 1, 1), 0.25), color, 0, 0, 0)
	fill.Parent = track
	local function set(fraction: number, animate: boolean?)
		local goal = { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }
		if animate then
			Spring.target(fill, goal, "Soft")
		else
			Spring.snap(fill, goal)
		end
	end
	return track, set
end

-- ------------------------------------------------------------------ Item cell
export type CellOptions = {
	rarity: string?, -- nil = empty cell
	count: number?, -- stack count bottom right
	selected: boolean?,
	marked: boolean?, -- salvage mark (red edge + cross)
	dim: boolean?, -- icon faded (empty equipment slot)
	caption: string?, -- equipment slot name next to the cell
	captionSide: "left" | "right" | "below" | nil, -- where the caption sits (default below)
}

-- Square item cell: rarity tint (gradient from the corner), rarity edge, halo glow by rarity
-- (Theme.Flat.Glow), icon, optional count. Hover/press/selection spring via UIScale.
function Flat.cell(size: number, iconName: string?, opts: CellOptions?): TextButton
	local o: CellOptions = opts or {}
	local rarity = o.rarity
	local color = if rarity then Theme.Rarity[rarity] or Theme.Rarity.normal else F.Edge
	local glow = if rarity then F.Glow[rarity] or F.Glow.normal else nil

	local b = Instance.new("TextButton")
	b.Name = "Cell"
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = F.Surface2
	b.BackgroundTransparency = if rarity then 0 else 0.45
	b.Size = UDim2.fromOffset(size, size)
	Kit.touchTarget(b)
	Flat.corner(b, F.Radius.M)

	if glow then
		-- Rarity light from the top left corner into the cell
		local tint = Instance.new("Frame")
		tint.Name = "Tint"
		tint.BackgroundColor3 = color
		tint.BorderSizePixel = 0
		tint.Size = UDim2.fromScale(1, 1)
		tint.ZIndex = 1
		Flat.corner(tint, F.Radius.M)
		Flat.gradient(tint, color, color, glow.tint - 0.3, 1, 45)
		tint.Parent = b
		if glow.halo > 0 then
			Flat.glow(b, color, glow.halo, glow.pulse, F.Radius.M)
		end
	end

	local edgeColor = if o.marked then C.Danger elseif o.selected then C.GoldHi else color
	local edge = Flat.stroke(
		b,
		edgeColor,
		if o.selected or o.marked then F.SelectStroke else F.Stroke,
		if rarity or o.selected then 0 else 0.4
	)
	edge.Name = "Edge"
	if glow and glow.spin and not o.selected and not o.marked then
		Flat.spin(edge, color)
	end

	if iconName then
		local ic = Kit.icon(iconName, math.floor(size * 0.66))
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = 2
		if o.dim then
			Kit.setIconTransparency(ic, 0.7)
		end
		ic.Parent = b
	end

	if o.count then
		local n = Flat.text(tostring(o.count), 13, C.Text, Theme.Font.UI, Enum.TextXAlignment.Right)
		n.AnchorPoint = Vector2.new(1, 1)
		n.Position = UDim2.new(1, -6, 1, -3)
		n.ZIndex = 3
		local s = Instance.new("UIStroke")
		s.Color = F.Surface0
		s.Thickness = 1.5
		s.Parent = n
		n.Parent = b
	end

	if o.marked then
		local veil = Instance.new("Frame")
		veil.Name = "Mark"
		veil.BackgroundColor3 = C.Danger
		veil.BackgroundTransparency = 0.72
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = 4
		Flat.corner(veil, F.Radius.M)
		local x = Flat.text("×", 26, C.Text, Theme.Font.UI, Enum.TextXAlignment.Center)
		x.AnchorPoint = Vector2.new(1, 0)
		x.Position = UDim2.new(1, -5, 0, 0)
		x.ZIndex = 5
		x.Parent = veil
		veil.Parent = b
	end

	if o.caption then
		local side = o.captionSide or "below"
		local cap = Flat.text(o.caption, 11, C.Muted, Theme.Font.Body)
		if side == "right" then
			cap.AnchorPoint = Vector2.new(0, 0.5)
			cap.Position = UDim2.new(1, 8, 0.5, 0)
		elseif side == "left" then
			cap.AnchorPoint = Vector2.new(1, 0.5)
			cap.Position = UDim2.new(0, -8, 0.5, 0)
			cap.TextXAlignment = Enum.TextXAlignment.Right
		else
			cap.AnchorPoint = Vector2.new(0.5, 0)
			cap.Position = UDim2.new(0.5, 0, 1, 3)
			cap.TextXAlignment = Enum.TextXAlignment.Center
		end
		cap.Parent = b
	end

	Flat.motion(b, if o.selected then F.SelectScale else 1)
	return b
end

-- Small pill with an icon and a number (currencies in window headers). Returns frame and label.
function Flat.currency(iconName: string, color: Color3): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.Name = "Currency"
	f.BackgroundColor3 = F.Surface1
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 40)
	Flat.corner(f, 20)
	Flat.stroke(f, F.Edge)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = f
	local layout = Kit.list(f, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local ic = Kit.icon(iconName, 28)
	ic.LayoutOrder = 1
	ic.Parent = f
	local t = Flat.text("0", 16, color)
	t.LayoutOrder = 2
	t.Parent = f
	return f, t
end

-- Round close button (×)
function Flat.close(size: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Close"
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = F.Surface2
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(size, size)
	Kit.touchTarget(b)
	Flat.corner(b, math.floor(size / 2))
	Flat.stroke(b, F.EdgeHi)
	local x = Flat.text("×", size * 0.5, C.Text, Theme.Font.UI, Enum.TextXAlignment.Center)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.45)
	x.Parent = b
	Flat.motion(b)
	return b
end

-- Window pop: scale from Theme.Flat.OpenScale to 1 with a bounce (UIScale "Pop" on the frame)
function Flat.pop(target: GuiObject)
	local scale = target:FindFirstChild("Pop")
	if not scale then
		local s = Instance.new("UIScale")
		s.Name = "Pop"
		s.Parent = target
		scale = s
	end
	if scale and scale:IsA("UIScale") then
		Spring.snap(scale, { Scale = F.OpenScale })
		Spring.target(scale, { Scale = 1 }, "Bouncy")
	end
end

return Flat
