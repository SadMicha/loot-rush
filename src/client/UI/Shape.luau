--!strict
-- Low-level pieces of the flat look (Theme.Flat), shared by Kit (all older windows) and Flat (new ones):
-- corners, strokes, gradients, card surface, rarity glow (halo rings + pulse + spinning edge),
-- hover/press motion and the item cell skin. Only Theme and Spring are required here, so both Kit
-- and Flat can use it without a require cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Spring = require(script.Parent.Spring)

local Shape = {}

local F = Theme.Flat
local C = Theme.Color

function Shape.corner(parent: GuiObject, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Shape.stroke(
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

-- Gradient from `top` to `bottom` (rotation 90 = top to bottom, 0 = left to right)
function Shape.gradient(
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

-- Card surface on an existing frame: rounded, hairline edge, faint sheen at the top
function Shape.card(f: GuiObject, color: Color3?, edge: Color3?)
	f.BackgroundColor3 = color or F.Surface1
	f.BackgroundTransparency = F.CardTransparency
	f.BorderSizePixel = 0
	Shape.corner(f, F.Radius.L)
	Shape.stroke(f, edge or F.Edge)
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BorderSizePixel = 0
	sheen.Size = UDim2.new(1, 0, 0, 56)
	sheen.ZIndex = 0
	Shape.corner(sheen, F.Radius.L)
	Shape.gradient(sheen, Color3.new(1, 1, 1), Color3.new(1, 1, 1), F.SheenTransparency, 1)
	sheen.Parent = f
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
function Shape.glow(
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
		Shape.corner(ring, (radius or F.Radius.M) + spec[1] / 2)
		local s = Shape.stroke(ring, color, spec[1], spec[2])
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
function Shape.spin(stroke: UIStroke, color: Color3)
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
function Shape.motion(b: GuiButton, rest: number?): UIScale
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

-- ------------------------------------------------------------------ Item cell skin
export type CellLook = {
	rarity: string?, -- nil = empty cell
	selected: boolean?,
	marked: boolean?, -- salvage mark: red edge
	round: boolean?, -- circle instead of rounded square (tree nodes)
	tint: Color3?, -- edge/glow color instead of the rarity color (Star Net branches)
}

-- Background, rarity tint from the top left corner, rarity edge (UIStroke "Edge"), halo glow by
-- rarity (Theme.Flat.Glow) on an existing button/frame. Returns the edge stroke.
function Shape.cell(b: GuiObject, size: number, look: CellLook): UIStroke
	local rarity = look.rarity
	local color = look.tint
		or (if rarity then Theme.Rarity[rarity] or Theme.Rarity.normal else F.Edge)
	local glow = if rarity then F.Glow[rarity] or F.Glow.normal else nil
	local radius = if look.round then math.floor(size / 2) else F.Radius.M

	b.BorderSizePixel = 0
	b.BackgroundColor3 = F.Surface2
	b.BackgroundTransparency = if rarity or look.round then 0 else 0.45
	Shape.corner(b, radius)

	if glow then
		local tint = Instance.new("Frame")
		tint.Name = "Tint"
		tint.BackgroundColor3 = color
		tint.BorderSizePixel = 0
		tint.Size = UDim2.fromScale(1, 1)
		tint.ZIndex = 1
		tint.Active = false
		Shape.corner(tint, radius)
		Shape.gradient(tint, color, color, glow.tint - 0.3, 1, 45)
		tint.Parent = b
		if glow.halo > 0 then
			Shape.glow(b, color, glow.halo, glow.pulse, radius)
		end
	end

	local edgeColor = if look.marked then C.Danger elseif look.selected then C.GoldHi else color
	local edge = Shape.stroke(
		b,
		edgeColor,
		if look.selected or look.marked then F.SelectStroke else F.Stroke,
		if rarity or look.selected then 0 else 0.4
	)
	edge.Name = "Edge"
	if glow and glow.spin and not look.selected and not look.marked then
		Shape.spin(edge, color)
	end
	return edge
end

-- Round close button (×) on an ImageButton, so every window closes with the same look
function Shape.close(size: number): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = "Close"
	b.Image = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = F.Surface2
	b.BackgroundTransparency = 0
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(size, size)
	b:SetAttribute("TouchTarget", true)
	Shape.corner(b, math.floor(size / 2))
	Shape.stroke(b, F.EdgeHi)
	local x = Instance.new("TextLabel")
	x.Name = "Glyph"
	x.BackgroundTransparency = 1
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.45)
	x.Size = UDim2.fromScale(1, 1)
	x.Text = "×"
	x.TextColor3 = C.Text
	x.FontFace = Theme.Font.UI
	x.TextSize = math.floor(size * 0.62)
	x.Parent = b
	Shape.motion(b)
	return b
end

return Shape
