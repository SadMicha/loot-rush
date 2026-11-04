--!strict
-- Low-level pieces of the flat look (Theme.Flat, look v5 "gilded ink"), shared by Kit (all older
-- windows) and Flat (new ones): corners, strokes, gradients, lit card surface with corner brackets,
-- rarity glow (halo rings + pulse + spinning edge + light sweep), hover/press motion with a ripple
-- and UI sounds, the item cell skin and a number ticker. Only Theme and Spring are required
-- here, so both Kit and Flat can use it without a require cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Spring = require(script.Parent.Spring)

local Shape = {}

local F = Theme.Flat
local C = Theme.Color
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

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

local function plain(name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	return f
end

-- Thin bright line along the top edge (light from above). Fades out toward both ends.
function Shape.topLine(parent: GuiObject, transparency: number?, inset: number?): Frame
	local l = plain("TopLine")
	l.BackgroundColor3 = WHITE
	l.BackgroundTransparency = 0
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, inset or 1)
	l.Size = UDim2.new(1, -2 * (inset or 1) - 4, 0, 1)
	l.ZIndex = parent.ZIndex
	local t = transparency or F.TopLine
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, t),
		NumberSequenceKeypoint.new(0.82, t),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = l
	l.Parent = parent
	return l
end

-- Corner brackets: L-shaped accents on the top left and bottom right corner (asymmetric, gives the
-- flat cards a forged look). `color` defaults to gold.
function Shape.brackets(parent: GuiObject, color: Color3?, size: number?, transparency: number?)
	local c = color or C.Gold
	local n = size or F.Bracket.Size
	local th = F.Bracket.Thick
	local tr = transparency or F.Bracket.Transparency
	local holder = plain("Brackets")
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = parent.ZIndex
	local function bar(anchor: Vector2, pos: UDim2, w: number, h: number)
		local b = Instance.new("Frame")
		b.Name = "Bar"
		b.BorderSizePixel = 0
		b.BackgroundColor3 = c
		b.BackgroundTransparency = tr
		b.AnchorPoint = anchor
		b.Position = pos
		b.Size = UDim2.fromOffset(w, h)
		b.Active = false
		b.ZIndex = holder.ZIndex
		b.Parent = holder
	end
	-- top left
	bar(Vector2.new(0, 0), UDim2.fromOffset(0, 0), n, th)
	bar(Vector2.new(0, 0), UDim2.fromOffset(0, 0), th, n)
	-- bottom right
	bar(Vector2.new(1, 1), UDim2.fromScale(1, 1), n, th)
	bar(Vector2.new(1, 1), UDim2.fromScale(1, 1), th, n)
	holder.Parent = parent
end

-- Accent rule (under titles / section heads): small gold diamond, then a line that fades out
function Shape.accentRule(width: number, color: Color3?): Frame
	local c = color or C.Gold
	local d = F.Accent.Diamond
	local f = plain("AccentRule")
	f.Size = UDim2.fromOffset(width, d + 2)
	local dia = Instance.new("Frame")
	dia.Name = "Diamond"
	dia.BorderSizePixel = 0
	dia.BackgroundColor3 = c
	dia.AnchorPoint = Vector2.new(0.5, 0.5)
	dia.Position = UDim2.new(0, d / 2 + 2, 0.5, 0)
	dia.Size = UDim2.fromOffset(d, d)
	dia.Rotation = 45
	dia.Parent = f
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = c
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, d + 6, 0.5, 0)
	line.Size = UDim2.new(1, -(d + 6), 0, F.Accent.Height)
	Shape.gradient(line, c, c, 0, 1, 0)
	line.Parent = f
	return f
end

-- Card surface on an existing frame: dark surface lit from above (child "Sheen": top light, darker
-- bottom, bright top line), hairline edge, gold corner brackets on panels large enough for them.
function Shape.card(f: GuiObject, color: Color3?, edge: Color3?)
	f.BackgroundColor3 = color or F.Surface1
	f.BackgroundTransparency = F.CardTransparency
	f.BorderSizePixel = 0
	Shape.corner(f, F.Radius.L)
	local s = Shape.stroke(f, edge or F.Edge)
	s.Name = "Edge"
	local sheen = plain("Sheen")
	sheen.BackgroundColor3 = WHITE
	sheen.BackgroundTransparency = 0
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.ZIndex = 0
	Shape.corner(sheen, F.Radius.L)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.45, WHITE),
		ColorSequenceKeypoint.new(0.46, BLACK),
		ColorSequenceKeypoint.new(1, BLACK),
	})
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.93),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(0.46, 1),
		NumberSequenceKeypoint.new(1, 0.72),
	})
	g.Parent = sheen
	Shape.topLine(sheen)
	local big = f.Size.X.Scale > 0 or f.Size.X.Offset >= F.Bracket.MinPanel
	if big then
		Shape.brackets(sheen, edge or C.Gold)
	end
	sheen.Parent = f
end

-- ------------------------------------------------------------------ Glow clock
-- Halo strokes breathe, edge gradients spin and light bands sweep; one Heartbeat for all of them,
-- only while their ScreenGui is enabled. Entries are dropped by the clock once their instance has
-- no parent any more. Strong keys on purpose: Roblox may collect the Lua handle of a living
-- Instance from a weak table, and a light band then froze mid-sweep or stopped for good.
type Pulse = { base: number, phase: number }
local pulses: { [UIStroke]: Pulse } = {}
local spins: { [UIGradient]: number } = {}
local shines: { [Frame]: number } = {}
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
	local S = F.Shine
	for band, phase in shines do
		if not band.Parent then
			shines[band] = nil
			continue
		end
		any = true
		if visible(band) then
			local k = ((t + phase) % S.Period) / S.Duration -- 0..1 while crossing
			local g = band:FindFirstChildOfClass("UIGradient")
			if k <= 1 and g then
				band.Visible = true
				g.Offset = Vector2.new(-1.2 + 2.4 * k, 0)
			else
				band.Visible = false
			end
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
		local ring = plain("Halo" .. i)
		ring.Size = UDim2.fromScale(1, 1)
		ring.ZIndex = 0
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
		ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(0.55, color),
		ColorSequenceKeypoint.new(1, color),
	})
	g.Name = "Spin"
	g.Parent = stroke
	spins[g] = math.random() * 360
	runClock()
end

-- Light sweep: a slanted bright band crosses the shape every Theme.Flat.Shine.Period seconds.
-- Hidden between sweeps (so still pictures and screenshots stay clean).
function Shape.shine(target: GuiObject, radius: number?, peak: number?): Frame
	local band = plain("Shine")
	band.BackgroundColor3 = WHITE
	band.BackgroundTransparency = 0
	band.Size = UDim2.fromScale(1, 1)
	band.ZIndex = target.ZIndex + 1
	band.Visible = false
	Shape.corner(band, radius or F.Radius.M)
	local p = peak or F.Shine.Peak
	local g = Instance.new("UIGradient")
	g.Rotation = F.Shine.Angle
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, p),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1.2, 0)
	g.Parent = band
	band.Parent = target
	shines[band] = math.random() * F.Shine.Period
	runClock()
	return band
end

-- Loot reveal: the cell springs up from small, a light band sweeps across it once and a small
-- gold "new" diamond sits in its corner (gone with the next render). Plays "ui_reward".
function Shape.reveal(cell: GuiObject)
	if not cell.Parent then
		return
	end
	local motion = cell:FindFirstChild("Motion")
	if motion and motion:IsA("UIScale") then
		local rest = motion.Scale
		Spring.snap(motion, { Scale = rest * 0.55 })
		Spring.target(motion, { Scale = rest }, "Bouncy")
	end
	local band = Shape.shine(cell, F.Radius.M, 0.35)
	shines[band] = F.Shine.Period - (os.clock() % F.Shine.Period) -- sweep starts right now
	task.delay(F.Shine.Duration + 0.05, function()
		shines[band] = nil
		if band.Parent then
			band:Destroy()
		end
	end)
	local dia = Instance.new("Frame")
	dia.Name = "New"
	dia.BorderSizePixel = 0
	dia.BackgroundColor3 = C.GoldHi
	dia.AnchorPoint = Vector2.new(0.5, 0.5)
	dia.Position = UDim2.fromOffset(9, 9)
	dia.Size = UDim2.fromOffset(9, 9)
	dia.Rotation = 45
	dia.ZIndex = cell.ZIndex + 4
	dia.Active = false
	Shape.stroke(dia, F.Surface0, 1.5)
	dia.Parent = cell
	Shape.sound("ui_reward")
end

-- ------------------------------------------------------------------ Sounds
-- UI sounds by hook name in Shared/Sounds.Hooks ("ui_click", "ui_open", ...): played by the
-- SoundController (pooled, rate limited, "ui" volume channel). Unknown or empty ids stay silent.
function Shape.sound(key: string)
	local Controllers = script.Parent.Parent:FindFirstChild("Controllers")
	local mod = Controllers and Controllers:FindFirstChild("SoundController")
	if mod and mod:IsA("ModuleScript") then
		(require(mod) :: any).play(key)
	end
end

-- ------------------------------------------------------------------ Disabled look
-- A disabled button turns into a dark slab (no dimmed gold mud): its gradient and edge switch to the
-- surface colors and its light sweep stops; enabling restores the original look.
local saved: { [GuiObject]: { color: ColorSequence?, edge: Color3? } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

function Shape.setDisabledLook(b: GuiObject, enabled: boolean)
	local g = b:FindFirstChildOfClass("UIGradient")
	local edge = b:FindFirstChild("Edge") or b:FindFirstChildOfClass("UIStroke")
	local shine = b:FindFirstChild("Shine")
	local keep = saved[b]
	if not keep then
		keep = {
			color = if g then g.Color else nil,
			edge = if edge and edge:IsA("UIStroke") then edge.Color else nil,
		}
		saved[b] = keep
	end
	if g then
		g.Color = if enabled
			then keep.color or g.Color
			else ColorSequence.new(F.Surface3, F.Surface2)
	end
	if edge and edge:IsA("UIStroke") then
		edge.Color = if enabled then keep.edge or edge.Color else F.Edge
	end
	if shine and shine:IsA("Frame") then
		if enabled then
			shines[shine] = shines[shine] or math.random() * F.Shine.Period
			runClock()
		else
			shines[shine] = nil
			shine.Visible = false
		end
	end
end

-- ------------------------------------------------------------------ Motion
local RIPPLE_IN = TweenInfo.new(F.Ripple.Time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Ripple from the press point (screen pixels): a soft circle that grows and fades inside the button
function Shape.ripple(b: GuiObject, at: Vector2?)
	local size = b.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local clip = b:FindFirstChild("RippleClip")
	if not clip then
		local c = plain("RippleClip")
		c.Size = UDim2.fromScale(1, 1)
		c.ClipsDescendants = true
		c.ZIndex = b.ZIndex + 2
		c.Parent = b
		clip = c
	end
	local rel = if at then (at - b.AbsolutePosition) else size / 2
	local dot = Instance.new("Frame")
	dot.Name = "Ripple"
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = WHITE
	dot.BackgroundTransparency = F.Ripple.Start
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(rel.X / size.X, rel.Y / size.Y)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeXX
	dot.Size = UDim2.fromScale(0, 0)
	dot.Active = false
	dot.ZIndex = b.ZIndex + 2
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = dot
	dot.Parent = clip
	local k = F.Ripple.Grow * math.max(size.X, size.Y) / size.X
	local tw = TweenService:Create(dot, RIPPLE_IN, {
		Size = UDim2.fromScale(k, k),
		BackgroundTransparency = 1,
	})
	tw.Completed:Connect(function()
		if dot.Parent then
			dot:Destroy()
		end
	end)
	tw:Play()
end

-- Hover grows, press shrinks + ripple + click sound, release springs back (UIScale "Motion")
function Shape.motion(b: GuiButton, rest: number?): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "Motion"
	scale.Scale = rest or 1
	scale:SetAttribute("Rest", rest or 1)
	scale.Parent = b
	local hovering = false
	local function base(): number
		local r = scale:GetAttribute("Rest")
		return if typeof(r) == "number" then r else 1
	end
	b.MouseEnter:Connect(function()
		hovering = true
		Spring.target(scale, { Scale = base() * F.HoverScale }, "Snappy")
	end)
	b.MouseLeave:Connect(function()
		hovering = false
		Spring.target(scale, { Scale = base() }, "Snappy")
	end)
	b.MouseButton1Down:Connect(function(x: number, y: number)
		Spring.target(scale, { Scale = base() * F.PressScale }, "Snappy")
		if b:GetAttribute("Enabled") ~= false then
			Shape.ripple(b, Vector2.new(x, y))
			Shape.sound("ui_click")
		end
	end)
	b.MouseButton1Up:Connect(function()
		Spring.target(
			scale,
			{ Scale = if hovering then base() * F.HoverScale else base() },
			"Bouncy"
		)
	end)
	return scale
end

-- New resting scale of a button made by Shape.motion (selection grows a cell); springs there
function Shape.setRest(b: GuiObject, rest: number)
	local scale = b:FindFirstChild("Motion")
	if not scale or not scale:IsA("UIScale") then
		return
	end
	local was = scale:GetAttribute("Rest")
	if was == rest then
		return
	end
	scale:SetAttribute("Rest", rest)
	local k = if typeof(was) == "number" and was > 0 then scale.Scale / was else 1
	Spring.target(scale, { Scale = rest * k }, "Snappy")
end

-- ------------------------------------------------------------------ Number ticker
-- Counts a label toward `value` (Theme.Flat.Tick.Time) and gives it a small pop when it grows.
-- `format` turns the number into text (default: whole number with thousands separators).
-- strong keys: a running count must not lose its entry (it removes itself when done)
local tickers: { [TextLabel]: { from: number, to: number, start: number } } = {}
local tickConn: RBXScriptConnection? = nil
local formats: { [TextLabel]: (number) -> string } = setmetatable({}, { __mode = "k" }) :: any

function Shape.thousands(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if n < 0 then "-" .. out else out
end

local function tickStep()
	local now = os.clock()
	for label, t in tickers do
		local k = math.clamp((now - t.start) / F.Tick.Time, 0, 1)
		local eased = 1 - (1 - k) ^ 3
		local fmt = formats[label] or Shape.thousands
		label.Text = fmt(t.from + (t.to - t.from) * eased)
		if k >= 1 then
			tickers[label] = nil
		end
	end
	if next(tickers) == nil and tickConn then
		tickConn:Disconnect()
		tickConn = nil
	end
end

function Shape.tickTo(label: TextLabel, value: number, format: ((number) -> string)?)
	if format then
		formats[label] = format
	end
	local fmt = formats[label] or Shape.thousands
	local last = label:GetAttribute("TickValue")
	label:SetAttribute("TickValue", value)
	if typeof(last) ~= "number" or last == value then
		tickers[label] = nil
		label.Text = fmt(value)
		return
	end
	local running = tickers[label]
	local from = last
	if running then
		local k = math.clamp((os.clock() - running.start) / F.Tick.Time, 0, 1)
		from = running.from + (running.to - running.from) * (1 - (1 - k) ^ 3)
	end
	tickers[label] = { from = from, to = value, start = os.clock() }
	if value > last then
		local pop = label:FindFirstChild("TickPop")
		if not pop then
			local s = Instance.new("UIScale")
			s.Name = "TickPop"
			s.Parent = label
			pop = s
		end
		if pop and pop:IsA("UIScale") then
			Spring.impulse(pop, "Scale", 3, "Bouncy")
		end
	end
	if not tickConn then
		tickConn = RunService.Heartbeat:Connect(tickStep)
	end
end

-- ------------------------------------------------------------------ Item cell skin
export type CellLook = {
	rarity: string?, -- nil = empty cell
	selected: boolean?,
	marked: boolean?, -- salvage mark: red edge
	round: boolean?, -- circle instead of a square tile (tree nodes)
	tint: Color3?, -- edge/glow color instead of the rarity color (Star Web branches)
}

-- Background, rarity light rising from the bottom, rarity strip along the bottom edge, rarity edge
-- (UIStroke "Edge"), halo glow by rarity (Theme.Flat.Glow) on an existing button/frame.
-- Returns the edge stroke.
function Shape.cell(b: GuiObject, size: number, look: CellLook): UIStroke
	local rarity = look.rarity
	local color = look.tint
		or (if rarity then Theme.Rarity[rarity] or Theme.Rarity.normal else F.Edge)
	local glow = if rarity then F.Glow[rarity] or F.Glow.normal else nil
	local radius = if look.round then math.floor(size / 2) else F.Radius.M

	b.BorderSizePixel = 0
	b.BackgroundColor3 = F.Surface2
	b.BackgroundTransparency = if rarity or look.round then 0 else 0.5
	Shape.corner(b, radius)

	if glow then
		local tint = plain("Tint")
		tint.BackgroundColor3 = color
		tint.BackgroundTransparency = 0
		tint.Size = UDim2.fromScale(1, 1)
		tint.ZIndex = 1
		Shape.corner(tint, radius)
		-- light rises from the bottom (rarity color), the top stays dark
		Shape.gradient(tint, color, color, 1, glow.tint - 0.25, 90)
		tint.Parent = b
		if not look.round then
			local strip = plain("Strip")
			strip.BackgroundColor3 = color
			strip.BackgroundTransparency = 0.05
			strip.AnchorPoint = Vector2.new(0.5, 1)
			strip.Position = UDim2.new(0.5, 0, 1, 0)
			strip.Size = UDim2.new(1, 0, 0, math.max(2, math.floor(size / 22)))
			strip.ZIndex = 1
			strip.Parent = b
		end
		if glow.halo > 0 then
			Shape.glow(b, color, glow.halo, glow.pulse, radius)
		end
		if glow.shine and not look.round then
			Shape.shine(b, radius, 0.6)
		end
	elseif not look.round then
		Shape.topLine(b, 0.93)
	end

	local edge = Shape.stroke(b, color)
	edge.Name = "Edge"
	Shape.cellState(b, look)
	return edge
end

-- Selection / salvage mark of a cell made by Shape.cell, changed in place: edge color, width and
-- the rotating highlight. The cell keeps its tint, halo and light sweep (no rebuild, no restart).
function Shape.cellState(b: GuiObject, look: CellLook)
	local edge = b:FindFirstChild("Edge")
	if not edge or not edge:IsA("UIStroke") then
		return
	end
	local rarity = look.rarity
	local color = look.tint
		or (if rarity then Theme.Rarity[rarity] or Theme.Rarity.normal else F.Edge)
	local glow = if rarity then F.Glow[rarity] or F.Glow.normal else nil
	edge.Color = if look.marked then C.Danger elseif look.selected then C.GoldHi else color
	edge.Thickness = if look.selected or look.marked then F.SelectStroke else F.Stroke
	edge.Transparency = if rarity or look.selected then 0 else 0.35
	local wantSpin = glow ~= nil and glow.spin and not look.selected and not look.marked
	local g = edge:FindFirstChild("Spin")
	if wantSpin and not g then
		Shape.spin(edge, color)
	elseif not wantSpin and g then
		spins[g :: UIGradient] = nil
		g:Destroy()
	end
end

-- Close button (×): dark square tile with a hairline, turns red on hover; same in every window
function Shape.close(size: number): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = "Close"
	b.Image = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = F.Surface2
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(size, size)
	b:SetAttribute("TouchTarget", true)
	Shape.corner(b, F.Radius.M)
	local edge = Shape.stroke(b, F.EdgeHi)
	Shape.topLine(b)
	local x = Instance.new("TextLabel")
	x.Name = "Glyph"
	x.BackgroundTransparency = 1
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.46)
	x.Size = UDim2.fromScale(1, 1)
	x.Text = "×"
	x.TextColor3 = C.Text
	x.FontFace = Theme.Font.UI
	x.TextSize = math.floor(size * 0.66)
	x.Parent = b
	b.MouseEnter:Connect(function()
		edge.Color = C.Danger
		x.TextColor3 = C.Danger
	end)
	b.MouseLeave:Connect(function()
		edge.Color = F.EdgeHi
		x.TextColor3 = C.Text
	end)
	Shape.motion(b)
	return b
end

return Shape
