--!strict
-- Setting controls in the flat look (Theme.Flat): slider, on/off switch and a segmented choice.
-- Design pixels like the rest of the UI; every hit area is a Kit.touchTarget, so it grows to the
-- touch minimum on phones. Motion: knob and selection spring (Spring), press ripple (Flat.motion).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Flat)
local Kit = require(script.Parent.Kit)
local Spring = require(script.Parent.Spring)

local Controls = {}

local F = Theme.Flat
local C = Theme.Color

Controls.HEIGHT = 52 -- control height (touch devices grow it to Kit.MIN_TOUCH_PX)

-- ------------------------------------------------------------------ Slider
export type Slider = {
	frame: Frame,
	set: (value: number) -> (), -- 0..1, no callback
}

-- Horizontal slider 0..1 with a value label on the right. `onChange` runs while dragging
-- (live preview), `onCommit` once on release. `step` snaps the value (e.g. 0.05).
function Controls.slider(
	width: number,
	step: number,
	format: (value: number) -> string,
	onChange: (value: number) -> (),
	onCommit: (value: number) -> ()
): Slider
	local VALUE_W = 84
	local frame = Flat.frame(UDim2.fromOffset(width, Controls.HEIGHT))
	frame.Name = "Slider"

	local hit = Instance.new("TextButton")
	hit.Name = "Track"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.AnchorPoint = Vector2.new(0, 0.5)
	hit.Position = UDim2.fromScale(0, 0.5)
	hit.Size = UDim2.fromOffset(width - VALUE_W - 12, Controls.HEIGHT)
	Kit.touchTarget(hit)
	hit.Parent = frame

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.AnchorPoint = Vector2.new(0.5, 0.5)
	rail.Position = UDim2.fromScale(0.5, 0.5)
	rail.Size = UDim2.new(1, -28, 0, 8)
	rail.BackgroundColor3 = F.Surface0
	rail.BorderSizePixel = 0
	Flat.corner(rail, 4)
	Flat.stroke(rail, F.Edge)
	rail.Parent = hit

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Flat.corner(fill, 4)
	Flat.gradient(fill, C.GoldHi, C.GoldLo, 0, 0, 0)
	fill.Parent = rail

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(26, 26)
	knob.BackgroundColor3 = C.Text
	knob.BorderSizePixel = 0
	Flat.corner(knob, 13)
	Flat.stroke(knob, C.Gold, 2)
	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob
	knob.Parent = rail

	local valueText = Flat.text("", 15, C.Text, Theme.Font.Number, Enum.TextXAlignment.Right)
	valueText.Name = "Value"
	valueText.AutomaticSize = Enum.AutomaticSize.None
	valueText.AnchorPoint = Vector2.new(1, 0.5)
	valueText.Position = UDim2.fromScale(1, 0.5)
	valueText.Size = UDim2.fromOffset(VALUE_W, Controls.HEIGHT)
	valueText.Parent = frame

	local value = 0
	local function show(v: number, animate: boolean)
		local goals = { Position = UDim2.fromScale(v, 0.5) }
		local fillGoal = { Size = UDim2.fromScale(v, 1) }
		if animate then
			Spring.target(knob, goals, "Snappy")
			Spring.target(fill, fillGoal, "Snappy")
		else
			Spring.snap(knob, goals)
			Spring.snap(fill, fillGoal)
		end
		valueText.Text = format(v)
	end

	local function fromScreen(x: number): number
		local w = rail.AbsoluteSize.X
		if w <= 0 then
			return value
		end
		local v = math.clamp((x - rail.AbsolutePosition.X) / w, 0, 1)
		if step > 0 then
			v = math.floor(v / step + 0.5) * step
		end
		return math.clamp(v, 0, 1)
	end

	local dragging: InputObject? = nil
	local function move(x: number)
		local v = fromScreen(x)
		if v ~= value then
			value = v
			show(v, true)
			onChange(v)
		end
	end
	local function finish()
		if dragging then
			dragging = nil
			Spring.target(knobScale, { Scale = 1 }, "Bouncy")
			onCommit(value)
		end
	end

	hit.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = input
			Spring.target(knobScale, { Scale = 1.2 }, "Bouncy")
			move(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = dragging
		if not d then
			return
		end
		if
			(
				d.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			) or input == d
		then
			move(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = dragging
		-- only the finger (or mouse button) that started the drag ends it; a second finger
		-- lifting (movement stick) must not
		local mouse = d ~= nil
			and d.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if d and (input == d or mouse) then
			finish()
		end
	end)
	frame.AncestryChanged:Connect(function()
		if not frame:IsDescendantOf(game) then
			dragging = nil
		end
	end)

	return {
		frame = frame,
		set = function(v: number)
			value = math.clamp(v, 0, 1)
			show(value, false)
		end,
	}
end

-- ------------------------------------------------------------------ Switch
export type Switch = {
	frame: TextButton,
	set: (on: boolean) -> (),
}

-- On/off pill switch with a caption ("ON" / "OFF") left of it; `onChange` after a tap
function Controls.switch(onChange: (on: boolean) -> ()): Switch
	local b = Instance.new("TextButton")
	b.Name = "Switch"
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(150, Controls.HEIGHT)
	Kit.touchTarget(b)

	local caption = Flat.text("OFF", 14, C.Muted, Theme.Font.UI, Enum.TextXAlignment.Right)
	caption.Name = "State"
	caption.AutomaticSize = Enum.AutomaticSize.None
	caption.AnchorPoint = Vector2.new(1, 0.5)
	caption.Position = UDim2.new(1, -84, 0.5, 0)
	caption.Size = UDim2.fromOffset(60, Controls.HEIGHT)
	caption.Parent = b

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromOffset(72, 36)
	track.BackgroundColor3 = F.Surface0
	track.BorderSizePixel = 0
	Flat.corner(track, 18)
	local edge = Flat.stroke(track, F.Edge)
	track.Parent = b

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 4, 0.5, 0)
	knob.Size = UDim2.fromOffset(28, 28)
	knob.BackgroundColor3 = C.Muted
	knob.BorderSizePixel = 0
	Flat.corner(knob, 14)
	knob.Parent = track

	local on = false
	local function apply(animate: boolean)
		local goals = {
			Position = UDim2.new(0, if on then 40 else 4, 0.5, 0),
			BackgroundColor3 = if on then Color3.new(1, 1, 1) else C.Muted,
		}
		local trackGoal = { BackgroundColor3 = if on then C.Gold else F.Surface0 }
		if animate then
			Spring.target(knob, goals, "Bouncy")
			Spring.target(track, trackGoal, "Soft")
		else
			Spring.snap(knob, goals)
			Spring.snap(track, trackGoal)
		end
		edge.Color = if on then C.GoldHi else F.Edge
		caption.Text = if on then "ON" else "OFF"
		caption.TextColor3 = if on then C.Text else C.Muted
	end
	b.Activated:Connect(function()
		on = not on
		apply(true)
		onChange(on)
	end)
	Flat.motion(b)
	apply(false)
	return {
		frame = b,
		set = function(v: boolean)
			on = v
			apply(false)
		end,
	}
end

-- ------------------------------------------------------------------ Segmented choice
export type Choice = {
	frame: Frame,
	set: (id: string) -> (),
}

-- Row of options; the picked one turns gold. `onPick` runs for taps (not for `set`).
function Controls.choice(
	options: { { id: string, text: string } },
	segmentWidth: number,
	onPick: (id: string) -> ()
): Choice
	local frame = Flat.frame(UDim2.fromOffset(0, Controls.HEIGHT))
	frame.Name = "Choice"
	frame.AutomaticSize = Enum.AutomaticSize.X
	local layout = Kit.list(frame, Enum.FillDirection.Horizontal, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local buttons: { [string]: { b: TextButton, t: TextLabel, edge: UIStroke } } = {}
	local picked = ""
	local function apply(animate: boolean)
		for id, e in buttons do
			local sel = id == picked
			local goal = { BackgroundColor3 = if sel then C.Gold else F.Surface2 }
			if animate then
				Spring.target(e.b, goal, "Soft")
			else
				Spring.snap(e.b, goal)
			end
			e.t.TextColor3 = if sel then F.Surface0 else C.Text
			e.edge.Color = if sel then C.GoldHi else F.Edge
		end
	end

	for i, opt in options do
		local b = Instance.new("TextButton")
		b.Name = "Option_" .. opt.id
		b.Text = ""
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.BackgroundColor3 = F.Surface2
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(segmentWidth, Controls.HEIGHT)
		Kit.touchTarget(b)
		Flat.corner(b, F.Radius.M)
		local edge = Flat.stroke(b, F.Edge)
		local t = Flat.text(opt.text, 14, C.Text, Theme.Font.UI, Enum.TextXAlignment.Center)
		t.Name = "Label"
		t.AutomaticSize = Enum.AutomaticSize.None
		t.Size = UDim2.fromScale(1, 1)
		t.Parent = b
		b.Activated:Connect(function()
			if picked ~= opt.id then
				picked = opt.id
				apply(true)
				onPick(opt.id)
			end
		end)
		Flat.motion(b)
		b.Parent = frame
		buttons[opt.id] = { b = b, t = t, edge = edge }
	end
	apply(false)

	return {
		frame = frame,
		set = function(id: string)
			picked = id
			apply(false)
		end,
	}
end

return Controls
