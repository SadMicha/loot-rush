--!strict
-- Season window (Shared/Seasons, Systems/Seasons): the Beta Season's clock, the reward track
-- (points steps with a Claim button each) and the Season Journey challenges below.
-- Opens from the season badge on the HUD. The server counts everything (Net.SeasonState); the
-- client only asks to claim a track step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Seasons)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Reward = require(script.Parent.Parent.UI.Reward)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)

local SeasonController = {
	changed = Instance.new("BindableEvent"), -- fires when the state arrives (HUD dot)
}

local C = Theme.Color
local F = Theme.Flat
local SEASON = Rules.Current

local PAD = 28
local TOP_H = 374
local GAP = 20
local STEP_GAP = 16
local STEP_H = 200
local CELL_H = 100
-- Smallest phones (shorter side under Theme.SmallPhoneMaxSide): the window is scaled down a lot and Kit keeps
-- texts at a minimum pixel size, so they grow relative to the layout. The compact layout flows
-- top-down (no texts over each other) and gives the cards more room.
local COMPACT_STEP_H = 310
local COMPACT_CELL_H = 170
local CARD_PAD = 14
local POINTS_W = 110 -- right column of a compact challenge cell (reward / done)
local POLL = 5 -- seconds between refreshes (counts, countdown) while open

type State = {
	id: string,
	phase: Rules.Phase,
	secondsLeft: number,
	counts: { [string]: number },
	claimed: { number },
	paid: number?,
	finished: { string }?,
}

local win: Window.Window
local data: Rules.Data = Rules.fresh()
local phase: Rules.Phase = "soon"
local secondsLeft = 0
local stateAt = 0
local loaded = false
local top: Frame -- dynamic content of the track panel (cleared on render)
local grid: ScrollingFrame
local clock: TextLabel
local points: TextLabel
local trackPanel: Frame
local challengePanel: Frame
local compact = false
local topH = TOP_H
local stepH = STEP_H
local cellH = CELL_H

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Track steps ready to claim (HUD dot)
function SeasonController.readyCount(): number
	return if loaded then Rules.readyCount(data) else 0
end

local function clockText(): string
	local left = math.max(0, secondsLeft - (os.clock() - stateAt))
	if phase == "soon" then
		return `Starts in {Rules.countdown(left)}`
	elseif phase == "live" then
		return if Rules.hasEnd()
			then `Ends in {Rules.countdown(left)}`
			else "Open season - runs until Season 1 arrives"
	end
	return "Season over - claim the rewards you earned"
end

-- One reward step of the track
local function stepCard(index: number, s: Rules.Step, width: number, have: number): Frame
	local isClaimed = data.claimed[tostring(index)] == true
	local ready = Rules.canClaim(data, index)
	local f = Kit.panel(Vector2.new(width, stepH), if ready then C.GoldHi else nil)
	f.Name = "Step" .. index
	f.LayoutOrder = index
	if compact then
		-- Top-down flow: header, reward chips, then the Claim button / state line below them
		local inner = width - 2 * CARD_PAD
		local flow = Flat.frame(UDim2.fromOffset(inner, stepH - 2 * CARD_PAD))
		flow.Name = "Flow"
		flow.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD)
		local layout = Kit.list(flow, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local reached = have >= s.points
		local need = Flat.text(
			`{Format.int(s.points)} PTS`,
			16,
			if reached then C.GoldHi else C.Muted,
			Theme.Font.UI
		)
		need.LayoutOrder = 1
		need.Parent = flow
		local line = Flat.frame(UDim2.fromOffset(inner, 0))
		line.Name = "Title"
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.LayoutOrder = 2
		local row = Kit.list(line, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Top)
		row.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local ic = Kit.icon(s.icon, 48, if reached then nil else C.Muted)
		ic.LayoutOrder = 1
		ic.Parent = line
		local name = Flat.text(s.name, 17, C.Text, Theme.Font.UI)
		name.LayoutOrder = 2
		name.AutomaticSize = Enum.AutomaticSize.Y
		name.Size = UDim2.fromOffset(inner - 48 - 8, 0)
		name.TextWrapped = true
		name.Parent = line
		line.Parent = flow
		local chips = Reward.row(s.reward, 28, 3, inner)
		chips.LayoutOrder = 3
		chips.Parent = flow
		local foot: GuiObject
		if ready then
			Shape.brackets(f, C.GoldHi)
			local b = Flat.button("Claim", "primary", Vector2.new(inner, 44), "chest")
			b.Name = "Claim"
			b.Activated:Connect(function()
				if b:GetAttribute("Enabled") == false then
					return
				end
				Flat.setEnabled(b, false)
				Net.Season:FireServer("claim", index)
			end)
			foot = b
		else
			local t = Flat.text(
				if isClaimed
					then "Claimed"
					else `{Format.int(math.max(0, s.points - have))} points to go`,
				15,
				if isClaimed then C.Good else C.Muted,
				Theme.Font.UI,
				Enum.TextXAlignment.Center
			)
			t.Name = "State"
			t.AutomaticSize = Enum.AutomaticSize.Y
			t.Size = UDim2.fromOffset(inner, 0)
			t.TextWrapped = true
			foot = t
		end
		foot.LayoutOrder = 4
		foot.Parent = flow
		flow.Parent = f
		return f
	end
	local need = Flat.text(
		`{Format.int(s.points)} PTS`,
		16,
		if have >= s.points then C.GoldHi else C.Muted,
		Theme.Font.UI
	)
	need.Position = UDim2.fromOffset(16, 14)
	need.Parent = f
	local ic = Kit.icon(s.icon, 56, if have >= s.points then nil else C.Muted)
	ic.Position = UDim2.fromOffset(16, 46)
	ic.Parent = f
	local name = Flat.text(s.name, 17, C.Text, Theme.Font.UI)
	name.Position = UDim2.fromOffset(84, 62)
	name.Parent = f
	local chips = Reward.row(s.reward, 28, 3)
	chips.Position = UDim2.fromOffset(16, 112)
	chips.Parent = f
	if ready then
		Shape.brackets(f, C.GoldHi)
		local b = Flat.button("Claim", "primary", Vector2.new(width - 32, 44), "chest")
		b.Name = "Claim"
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -14)
		b.Activated:Connect(function()
			if b:GetAttribute("Enabled") == false then
				return
			end
			Flat.setEnabled(b, false)
			Net.Season:FireServer("claim", index)
		end)
		b.Parent = f
	else
		local t = Flat.text(
			if isClaimed
				then "Claimed"
				else `{Format.int(math.max(0, s.points - have))} points to go`,
			15,
			if isClaimed then C.Good else C.Muted,
			Theme.Font.UI,
			Enum.TextXAlignment.Center
		)
		t.Name = "State"
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.new(0.5, 0, 1, -24)
		t.Parent = f
	end
	return f
end

-- One challenge cell
local function challengeCell(ch: Rules.Challenge, order: number, cellW: number): Frame
	local done = Rules.done(data, ch)
	local f = Flat.card(UDim2.fromOffset(0, cellH), if done then F.Surface2 else nil)
	f.Name = "Challenge_" .. ch.id
	f.LayoutOrder = order
	if compact then
		-- Text column (title, description, bar + counter) left, reward / Done on the right
		local ic = Kit.icon(ch.icon, 52, if done then nil else C.Muted)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 16, 0.5, 0)
		ic.Parent = f
		local colW = cellW - 84 - POINTS_W
		local col = Flat.frame(UDim2.fromOffset(colW, cellH - 20), UDim2.fromOffset(84, 10))
		col.Name = "Text"
		local colLayout = Kit.list(col, Enum.FillDirection.Vertical, 4)
		colLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local name = Flat.text(ch.name, 18, if done then C.GoldHi else C.Text, Theme.Font.UI)
		name.LayoutOrder = 1
		name.AutomaticSize = Enum.AutomaticSize.Y
		name.Size = UDim2.fromOffset(colW, 0)
		name.TextWrapped = true
		name.Parent = col
		local desc = Flat.text(ch.desc, 14, C.Muted, Theme.Font.Body)
		desc.LayoutOrder = 2
		desc.AutomaticSize = Enum.AutomaticSize.Y
		desc.Size = UDim2.fromOffset(colW, 0)
		desc.TextWrapped = true
		desc.Parent = col
		local meter = Flat.frame(UDim2.fromOffset(colW, 0))
		meter.Name = "Meter"
		meter.AutomaticSize = Enum.AutomaticSize.Y
		meter.LayoutOrder = 3
		local meterLayout = Kit.list(meter, Enum.FillDirection.Horizontal, 10)
		meterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local bar, set =
			Flat.bar(Vector2.new(math.max(40, colW - 100), 10), if done then C.GoldHi else C.Cyan)
		bar.LayoutOrder = 1
		bar.Parent = meter
		set(Rules.progress(data, ch) / ch.target)
		local count = Flat.text(
			`{Format.int(Rules.progress(data, ch))} / {Format.int(ch.target)}`,
			14,
			C.Muted,
			Theme.Font.UI
		)
		count.LayoutOrder = 2
		count.Parent = meter
		meter.Parent = col
		col.Parent = f
		local pts = Flat.text(
			if done then "Done" else `+{ch.points}`,
			18,
			if done then C.Good else C.GoldHi,
			Theme.Font.UI,
			Enum.TextXAlignment.Right
		)
		pts.Name = "Points"
		pts.AnchorPoint = Vector2.new(1, 0.5)
		pts.Position = UDim2.new(1, -16, 0.5, 0)
		pts.Parent = f
		return f
	end
	local ic = Kit.icon(ch.icon, 52, if done then nil else C.Muted)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 16, 0.5, 0)
	ic.Parent = f
	local name = Flat.text(ch.name, 18, if done then C.GoldHi else C.Text, Theme.Font.UI)
	name.Position = UDim2.fromOffset(84, 12)
	name.Parent = f
	local desc = Flat.text(ch.desc, 14, C.Muted, Theme.Font.Body)
	desc.Position = UDim2.fromOffset(84, 40)
	desc.Parent = f
	local bar, set = Flat.bar(Vector2.new(300, 10), if done then C.GoldHi else C.Cyan)
	bar.Position = UDim2.fromOffset(84, 74)
	bar.Parent = f
	set(Rules.progress(data, ch) / ch.target)
	local count = Flat.text(
		`{Format.int(Rules.progress(data, ch))} / {Format.int(ch.target)}`,
		14,
		C.Muted,
		Theme.Font.UI
	)
	count.AnchorPoint = Vector2.new(0, 0.5)
	count.Position = UDim2.fromOffset(396, 79)
	count.Parent = f
	local pts = Flat.text(
		if done then "Done" else `+{ch.points}`,
		18,
		if done then C.Good else C.GoldHi,
		Theme.Font.UI,
		Enum.TextXAlignment.Right
	)
	pts.Name = "Points"
	pts.AnchorPoint = Vector2.new(1, 0.5)
	pts.Position = UDim2.new(1, -20, 0.5, 0)
	pts.Parent = f
	return f
end

-- Picks the phone or the regular layout and resizes the two panels to it
local function applyLayout()
	local camera = workspace.CurrentCamera
	compact = camera ~= nil
		and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < Theme.SmallPhoneMaxSide
	stepH = if compact then COMPACT_STEP_H else STEP_H
	cellH = if compact then COMPACT_CELL_H else CELL_H
	topH = TOP_H + stepH - STEP_H
	local body = Window.BODY
	trackPanel.Size = UDim2.fromOffset(body.X, topH)
	top.Size = UDim2.fromOffset(body.X, topH)
	challengePanel.Size = UDim2.fromOffset(body.X, body.Y - topH - GAP)
	challengePanel.Position = UDim2.fromOffset(0, topH + GAP)
	grid.Size = UDim2.fromOffset(body.X - 2 * PAD, challengePanel.Size.Y.Offset - 60 - 20)
	local layout = grid:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
	layout.CellSize = UDim2.fromOffset(math.floor((body.X - 2 * PAD - 16 - 12) / 2), cellH)
end

local function render()
	applyLayout()
	clock.Text = if loaded then clockText() else "Loading…"
	local have = Rules.points(data)
	points.Text = `{Format.int(have)} / {Format.int(Rules.TOTAL_POINTS)} season points`
	clear(top)
	clear(grid)
	if not loaded then
		return
	end
	local body = Window.BODY
	local trackW = body.X - 2 * PAD
	-- Points bar with a tick per step
	local bar, set = Flat.bar(Vector2.new(trackW, 14), C.GoldHi)
	bar.Position = UDim2.fromOffset(PAD, 112)
	bar.Parent = top
	local last = SEASON.track[#SEASON.track].points
	set(have / last)
	for i, s in SEASON.track do
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. i
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(s.points / last, 0, 0.5, 0)
		tick.Size = UDim2.fromOffset(4, 22)
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = if have >= s.points then C.GoldHi else F.EdgeHi
		tick.Parent = bar
	end
	local steps = Flat.frame(UDim2.fromOffset(trackW, stepH), UDim2.fromOffset(PAD, 146))
	steps.Name = "Steps"
	Kit.list(steps, Enum.FillDirection.Horizontal, STEP_GAP)
	local n = #SEASON.track
	local stepW = math.floor((trackW - (n - 1) * STEP_GAP) / n)
	for i, s in SEASON.track do
		stepCard(i, s, stepW, have).Parent = steps
	end
	steps.Parent = top
	-- Challenges: open ones first, finished ones last
	for i, ch in SEASON.challenges do
		local cellW = math.floor((Window.BODY.X - 2 * PAD - 16 - 12) / 2)
		challengeCell(ch, (if Rules.done(data, ch) then 1000 else 0) + i, cellW).Parent = grid
	end
end

local function build()
	local body = Window.BODY
	local panel = Kit.panel(Vector2.new(body.X, TOP_H))
	panel.Name = "Track"
	trackPanel = panel
	panel.Parent = win.body
	Shape.brackets(panel)
	top = Flat.frame(UDim2.fromOffset(body.X, TOP_H))
	top.Name = "Content"
	top.Parent = panel
	-- Header lines that stay between renders
	local fixed = Flat.frame(UDim2.fromOffset(body.X - 2 * PAD, 90), UDim2.fromOffset(PAD, 20))
	fixed.Name = "Fixed"
	fixed.Parent = panel
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(92, 34)
	badge.Position = UDim2.fromOffset(0, 8)
	badge.BackgroundColor3 = C.GoldHi
	badge.BorderSizePixel = 0
	Kit.corner(badge, F.Radius.M)
	local bt = Flat.text(SEASON.short, 16, F.Surface0, Theme.Font.Title, Enum.TextXAlignment.Center)
	bt.AnchorPoint = Vector2.new(0.5, 0.5)
	bt.Position = UDim2.fromScale(0.5, 0.5)
	bt.Parent = badge
	badge.Parent = fixed
	local title = Window.gilded(SEASON.name, 34)
	title.Position = UDim2.fromOffset(110, 0)
	title.Parent = fixed
	clock = Flat.text("", 16, C.Muted, Theme.Font.Body)
	clock.Name = "Clock"
	clock.Position = UDim2.fromOffset(110, 50)
	clock.Parent = fixed
	points = Flat.text("", 18, C.Text, Theme.Font.UI, Enum.TextXAlignment.Right)
	points.Name = "Points"
	points.AnchorPoint = Vector2.new(1, 0)
	points.Position = UDim2.new(1, 0, 0, 50)
	points.Parent = fixed

	local bottom = Kit.panel(Vector2.new(body.X, body.Y - TOP_H - GAP))
	bottom.Name = "Challenges"
	challengePanel = bottom
	bottom.Position = UDim2.fromOffset(0, TOP_H + GAP)
	bottom.Parent = win.body
	local head = Window.heading("Season challenges", 18, C.Muted)
	head.Position = UDim2.fromOffset(PAD, 20)
	head.Parent = bottom
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(PAD, 60)
	local gridW = body.X - 2 * PAD
	grid.Size = UDim2.fromOffset(gridW, bottom.Size.Y.Offset - 60 - 20)
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = C.Gold
	grid.ScrollBarImageTransparency = 0.2
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(12, 10)
	layout.CellSize = UDim2.fromOffset(math.floor((gridW - 16 - 12) / 2), CELL_H)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = bottom
end

function SeasonController.toggle()
	win.toggle()
end

function SeasonController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function SeasonController.isOpen(): boolean
	return win.isOpen()
end

function SeasonController.init()
	win = Window.new({ name = "Season", title = "Season", icon = "season_beta" })
	build()
	render()
	win.onOpen(function()
		render()
		Net.Season:FireServer("sync")
	end)
	Net.SeasonState.OnClientEvent:Connect(function(s: any)
		if typeof(s) ~= "table" or typeof(s.counts) ~= "table" or typeof(s.claimed) ~= "table" then
			return
		end
		local state = s :: State
		local claimed = {}
		for _, i in state.claimed do
			if typeof(i) == "number" then
				claimed[tostring(i)] = true
			end
		end
		data = Rules.reconcile({ id = state.id, counts = state.counts, claimed = claimed })
		phase = if state.phase == "live" or state.phase == "over" then state.phase else "soon"
		secondsLeft = if typeof(state.secondsLeft) == "number" then state.secondsLeft else 0
		stateAt = os.clock()
		loaded = true
		if typeof(state.paid) == "number" then
			local step = SEASON.track[state.paid]
			if step then
				Shape.sound("ui_reward")
				QuestController.toast(`Season reward claimed: {step.name}`, C.GoldHi)
			end
		end
		if typeof(state.finished) == "table" then
			for _, id in state.finished :: { any } do
				local ch = if typeof(id) == "string" then Rules.ChallengeById[id] else nil
				if ch then
					QuestController.toast(
						`Season challenge done: {ch.name} (+{ch.points})`,
						C.GoldHi
					)
				end
			end
		end
		if win.isOpen() then
			render()
		end
		SeasonController.changed:Fire()
	end)
	task.spawn(function()
		while true do
			task.wait(POLL)
			if win.isOpen() and loaded then
				clock.Text = clockText()
				Net.Season:FireServer("sync") -- live counts while the window is open
			end
		end
	end)
end

return SeasonController
