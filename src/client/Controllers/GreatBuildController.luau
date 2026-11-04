--!strict
-- Great Build window (hub station "GreatBuild" at the donation chute, Systems/GreatBuild,
-- Shared/GreatBuild): the global monument every server raises together.
--   top:          stage, the bar of the current stage, the ten stage cells, the global buff
--   bottom left:  donate buttons (+10, +100, Max), today's cap, personal milestones
--   bottom right: top builders
-- Also a small board above the monument in the hub and a toast on every finished stage.
-- The server checks every donation (Net.GreatBuildState answers); the client only asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.GreatBuild)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Reward = require(script.Parent.Parent.UI.Reward)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)

local GreatBuildController = {}

local C = Theme.Color
local F = Theme.Flat

-- Layout (design pixels inside Window.BODY = 1520 × 790)
local PAD = 28
local TOP_H = 340
local GAP = 20
local LEFT_W = 900
local CELL_GAP = 10
local CELL_H = 60
local BTN_W = 220
local BTN_H = 96 -- ≥ 32 px on the smallest phone
local MILE_H = 54
local ROW_H = 46
local POLL = 5 -- seconds between refreshes while open
local BOARD_SIZE = Vector2.new(320, 92) -- board above the monument (pixels)

type Donor = { name: string, amount: number, me: boolean? }
type Mine = { total: number, today: number, left: number, paid: { [string]: boolean } }
type State = {
	total: number,
	stages: number,
	buffLeft: number,
	mine: Mine,
	shards: number,
	top: { Donor },
	shared: boolean,
}

local win: Window.Window
local state: State? = nil
local stateAt = 0
local sending = false

local stageText: TextLabel
local barSet: (number, boolean?) -> ()
local barText: TextLabel
local totalText: TextLabel
local cells: Frame
local buffText: TextLabel
local haveText: TextLabel
local todayText: TextLabel
local mineText: TextLabel
local statusText: TextLabel
local buttons: { { b: TextButton, amount: number? } } = {}
local miles: Frame
local list: Frame
local listNote: TextLabel

local boardStage: TextLabel? = nil
local boardSet: ((number, boolean?) -> ())? = nil

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	if h > 0 then
		return `{h}h {m}m`
	end
	return `{m}m {seconds % 60}s`
end

local function globalTotal(): number
	local t = ReplicatedStorage:GetAttribute("GreatBuildTotal")
	return if typeof(t) == "number" then t else (if state then state.total else 0)
end

-- Amount the "Max" button sends: what the hero has, capped by today's limit
local function maxAmount(): number
	local s = state
	if not s then
		return 0
	end
	return math.max(0, math.min(s.shards, s.mine.left))
end

-- ------------------------------------------------------------------ Rendering
local function renderTop()
	local total = globalTotal()
	local done, into, size = Rules.stage(total)
	if done >= Rules.STAGES then
		stageText.Text = `{Rules.MONUMENT} complete!`
		barSet(1, true)
		barText.Text = "Every stage stands. Thank you, builders!"
	else
		stageText.Text = `Stage {done + 1} / {Rules.STAGES}`
		barSet(into / size, true)
		barText.Text = `{Format.currency(into)} / {Format.currency(size)} Crystal Shards`
	end
	totalText.Text = `{Format.currency(total)} donated by all servers`
	for i = 1, Rules.STAGES do
		local cell = cells:FindFirstChild("Stage" .. i)
		if cell and cell:IsA("Frame") then
			local isDone = i <= done
			local current = i == done + 1
			cell.BackgroundColor3 = if isDone then C.GoldHi else F.Surface2
			local label = cell:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = if isDone
					then F.Surface0
					elseif current then C.GoldHi
					else C.Muted
			end
			local stroke = cell:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if current then C.GoldHi else F.Edge
				stroke.Thickness = if current then 2 else 1
			end
		end
	end
	local s = state
	local left = if s then s.buffLeft - (os.clock() - stateAt) else 0
	if left > 0 then
		buffText.Text = `Global buff active: {Rules.BUFF_TEXT} - {duration(left)} left`
		buffText.TextColor3 = C.Good
	else
		buffText.Text =
			`Every finished stage gives everyone {Rules.BUFF_TEXT} for {Rules.BUFF_SECONDS // 3600} hours`
		buffText.TextColor3 = C.Muted
	end
end

local function milestoneRow(m: Rules.Milestone, order: number, mine: Mine?): Frame
	local got = mine ~= nil and mine.paid[tostring(m.amount)] == true
	local f = Flat.card(UDim2.new(1, 0, 0, MILE_H), if got then F.Surface2 else nil)
	f.Name = "Milestone" .. m.amount
	f.LayoutOrder = order
	local ic = Kit.icon(m.icon, 40, if got then nil else C.Muted)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 12, 0.5, 0)
	ic.Parent = f
	local name = Flat.text(m.name, 17, if got then C.GoldHi else C.Text, Theme.Font.UI)
	name.Position = UDim2.fromOffset(64, 6)
	name.Parent = f
	local desc =
		Flat.text(`Donate {Format.currency(m.amount)} in total`, 14, C.Muted, Theme.Font.Body)
	desc.Position = UDim2.fromOffset(64, 30)
	desc.Parent = f
	local chips = Reward.row(m.reward, 26, 2)
	chips.AnchorPoint = Vector2.new(0, 0.5)
	chips.Position = UDim2.new(0, 360, 0.5, 0)
	chips.Parent = f
	local have = if mine then mine.total else 0
	local st = Flat.text(
		if got then "Done" else `{Format.currency(math.max(0, m.amount - have))} to go`,
		15,
		if got then C.Good else C.Muted,
		Theme.Font.UI,
		Enum.TextXAlignment.Right
	)
	st.Name = "State"
	st.AnchorPoint = Vector2.new(1, 0.5)
	st.Position = UDim2.new(1, -16, 0.5, 0)
	st.Parent = f
	return f
end

local function renderMine()
	local s = state
	haveText.Text = if s then `{Format.currency(s.shards)} Crystal Shards` else "Loading…"
	todayText.Text = if s
		then `Today {Format.currency(Rules.DAILY_CAP - s.mine.left)} / {Format.currency(
			Rules.DAILY_CAP
		)}`
		else ""
	mineText.Text = if s then `You donated {Format.currency(s.mine.total)} in total` else ""
	local max = maxAmount()
	for _, entry in buttons do
		local amount = entry.amount or max
		local ok = s ~= nil and not sending and amount >= 1 and amount <= max
		Flat.setEnabled(entry.b, ok)
		if not entry.amount then
			local label = entry.b:FindFirstChild("Label", true)
			if label and label:IsA("TextLabel") then
				label.Text = if max > 0 then `Max ({Format.currency(max)})` else "Max"
			end
		end
	end
	clear(miles)
	for i, m in Rules.Milestones do
		milestoneRow(m, i, if s then s.mine else nil).Parent = miles
	end
end

local function renderTop5()
	clear(list)
	local s = state
	if not s then
		listNote.Text = "Loading…"
		return
	end
	listNote.Text = if not s.shared
		then "Offline: this server builds alone (no DataStore access)"
		elseif #s.top == 0 then "Be the first to donate!"
		else "Updated every minute"
	for i, d in s.top do
		local f = Flat.frame(UDim2.new(1, 0, 0, ROW_H))
		f.Name = "Row" .. i
		f.LayoutOrder = i
		local color = if d.me then C.Cyan elseif i <= 3 then C.GoldHi else C.Text
		local left = Flat.text(`#{i}  {d.name}`, 18, color, Theme.Font.UI)
		left.AnchorPoint = Vector2.new(0, 0.5)
		left.Position = UDim2.fromScale(0, 0.5)
		left.Parent = f
		local right = Flat.text(
			Format.currency(d.amount),
			18,
			color,
			Theme.Font.UI,
			Enum.TextXAlignment.Right
		)
		right.AnchorPoint = Vector2.new(1, 0.5)
		right.Position = UDim2.fromScale(1, 0.5)
		right.Parent = f
		f.Parent = list
	end
end

local function render()
	renderTop()
	renderMine()
	renderTop5()
end

-- ------------------------------------------------------------------ Board in the hub
local function renderBoard()
	local st, set = boardStage, boardSet
	if not st or not set or st.Parent == nil then
		return
	end
	local done, into, size = Rules.stage(globalTotal())
	if done >= Rules.STAGES then
		st.Text = "Complete!"
		set(1)
	else
		st.Text = `Stage {done + 1} / {Rules.STAGES} - {math.floor(into / size * 100)}%`
		set(into / size)
	end
end

local function buildBoard(beacon: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LootRushGreatBuildBoard"
	gui.Adornee = beacon
	gui.Size = UDim2.fromOffset(BOARD_SIZE.X, BOARD_SIZE.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local back = Flat.card(UDim2.fromScale(1, 1), F.Surface0)
	back.Parent = gui
	local title = Window.gilded(string.upper(Rules.NAME), 22)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.Parent = back
	local st = Flat.text("", 16, C.Text, Theme.Font.UI, Enum.TextXAlignment.Center)
	st.AnchorPoint = Vector2.new(0.5, 0)
	st.Position = UDim2.new(0.5, 0, 0, 40)
	st.Parent = back
	local bar, set = Flat.bar(Vector2.new(BOARD_SIZE.X - 40, 12), C.GoldHi)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -10)
	bar.Parent = back
	boardStage, boardSet = st, set
	gui.Parent = beacon -- client-side only: every player draws their own copy
	renderBoard()
end

local function bindBeacon(inst: Instance)
	if inst.Name ~= "Beacon" or not inst:IsA("BasePart") then
		return
	end
	local model = inst.Parent
	if not model or model.Name ~= Rules.MODEL then
		return
	end
	if inst:FindFirstChild("LootRushGreatBuildBoard") then
		return
	end
	buildBoard(inst)
end

local function watchHub()
	workspace.DescendantAdded:Connect(bindBeacon)
	local hub = workspace:WaitForChild("Lumenhaven", 60)
	local model = hub and hub:FindFirstChild(Rules.MODEL)
	local beacon = model and model:FindFirstChild("Beacon")
	if beacon then
		bindBeacon(beacon)
	end
end

-- ------------------------------------------------------------------ Build
local function donate(amount: number)
	if sending or amount < 1 then
		return
	end
	sending = true
	renderMine()
	Net.GreatBuild:FireServer("donate", amount)
	task.delay(3, function()
		if sending then -- no answer: let the player try again
			sending = false
			renderMine()
		end
	end)
end

local function build()
	local body = Window.BODY
	local w = body.X - 2 * PAD

	-- Top: stage, bar, stage cells, buff
	local panel = Kit.panel(Vector2.new(body.X, TOP_H))
	panel.Name = "Build"
	panel.Parent = win.body
	Shape.brackets(panel)
	local title = Window.gilded(Rules.NAME, 34)
	title.Position = UDim2.fromOffset(PAD, 18)
	title.Parent = panel
	local sub = Flat.text(
		`Every server builds the same {Rules.MONUMENT}. Donate Crystal Shards to raise it.`,
		16,
		C.Muted,
		Theme.Font.Body
	)
	sub.Position = UDim2.fromOffset(PAD, 66)
	sub.Parent = panel
	stageText = Flat.text("", 26, C.GoldHi, Theme.Font.Title, Enum.TextXAlignment.Right)
	stageText.Name = "Stage"
	stageText.AnchorPoint = Vector2.new(1, 0)
	stageText.Position = UDim2.new(1, -PAD, 0, 22)
	stageText.Parent = panel
	local bar, set = Flat.bar(Vector2.new(w, 22), C.GoldHi)
	bar.Position = UDim2.fromOffset(PAD, 108)
	bar.Parent = panel
	barSet = set
	barText = Flat.text("", 16, C.Text, Theme.Font.UI)
	barText.Name = "Progress"
	barText.Position = UDim2.fromOffset(PAD, 140)
	barText.Parent = panel
	totalText = Flat.text("", 16, C.Muted, Theme.Font.UI, Enum.TextXAlignment.Right)
	totalText.Name = "Total"
	totalText.AnchorPoint = Vector2.new(1, 0)
	totalText.Position = UDim2.new(1, -PAD, 0, 140)
	totalText.Parent = panel
	cells = Flat.frame(UDim2.fromOffset(w, CELL_H), UDim2.fromOffset(PAD, 186))
	cells.Name = "Stages"
	Kit.list(cells, Enum.FillDirection.Horizontal, CELL_GAP)
	local cellW = math.floor((w - (Rules.STAGES - 1) * CELL_GAP) / Rules.STAGES)
	for i = 1, Rules.STAGES do
		local c = Instance.new("Frame")
		c.Name = "Stage" .. i
		c.LayoutOrder = i
		c.Size = UDim2.fromOffset(cellW, CELL_H)
		c.BackgroundColor3 = F.Surface2
		c.BorderSizePixel = 0
		Kit.corner(c, F.Radius.M)
		Kit.stroke(c, F.Edge, 1)
		local label =
			Flat.text(`Stage {i}`, 16, C.Muted, Theme.Font.Title, Enum.TextXAlignment.Center)
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Parent = c
		c.Parent = cells
	end
	cells.Parent = panel
	buffText = Flat.text("", 16, C.Muted, Theme.Font.Body)
	buffText.Name = "Buff"
	buffText.Position = UDim2.fromOffset(PAD, 270)
	buffText.Parent = panel

	-- Bottom left: donate
	local lowH = body.Y - TOP_H - GAP
	local left = Kit.panel(Vector2.new(LEFT_W, lowH))
	left.Name = "Donate"
	left.Position = UDim2.fromOffset(0, TOP_H + GAP)
	left.Parent = win.body
	local head = Window.heading("Your donation", 18, C.Muted)
	head.Position = UDim2.fromOffset(PAD, 18)
	head.Parent = left
	local have = Flat.frame(UDim2.fromOffset(0, 36), UDim2.fromOffset(PAD, 52))
	have.AutomaticSize = Enum.AutomaticSize.X
	local hl = Kit.list(have, Enum.FillDirection.Horizontal, 10)
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local ic = Kit.icon("crystal", 32)
	ic.LayoutOrder = 1
	ic.Parent = have
	haveText = Flat.text("", 20, C.Text, Theme.Font.UI)
	haveText.Name = "Have"
	haveText.LayoutOrder = 2
	haveText.Parent = have
	have.Parent = left
	todayText = Flat.text("", 16, C.Muted, Theme.Font.UI, Enum.TextXAlignment.Right)
	todayText.Name = "Today"
	todayText.AnchorPoint = Vector2.new(1, 0)
	todayText.Position = UDim2.new(1, -PAD, 0, 58)
	todayText.Parent = left
	local row = Flat.frame(UDim2.fromOffset(LEFT_W - 2 * PAD, BTN_H), UDim2.fromOffset(PAD, 100))
	row.Name = "Buttons"
	local rl = Kit.list(row, Enum.FillDirection.Horizontal, 16)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	buttons = {}
	local defs: { { text: string, amount: number? } } = {}
	for _, n in Rules.QUICK do
		table.insert(defs, { text = `+{Format.currency(n)}`, amount = n })
	end
	table.insert(defs, { text = "Max", amount = nil })
	for i, d in defs do
		local b = Flat.button(
			d.text,
			if d.amount then "secondary" else "primary",
			Vector2.new(if d.amount then BTN_W else BTN_W + 80, BTN_H),
			"crystal"
		)
		b.Name = if d.amount then "Donate" .. d.amount else "DonateMax"
		b.LayoutOrder = i
		b.Activated:Connect(function()
			if b:GetAttribute("Enabled") == false then
				return
			end
			donate(d.amount or maxAmount())
		end)
		b.Parent = row
		table.insert(buttons, { b = b, amount = d.amount })
	end
	row.Parent = left
	mineText = Flat.text("", 16, C.Text, Theme.Font.UI)
	mineText.Name = "Mine"
	mineText.Position = UDim2.fromOffset(PAD, 206)
	mineText.Parent = left
	statusText = Flat.text("", 16, C.Danger, Theme.Font.Body, Enum.TextXAlignment.Right)
	statusText.Name = "Status"
	statusText.AnchorPoint = Vector2.new(1, 0)
	statusText.Position = UDim2.new(1, -PAD, 0, 206)
	statusText.Parent = left
	miles =
		Flat.frame(UDim2.fromOffset(LEFT_W - 2 * PAD, lowH - 236 - 12), UDim2.fromOffset(PAD, 236))
	miles.Name = "Milestones"
	Kit.list(miles, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Top)
	miles.Parent = left

	-- Bottom right: top builders
	local rightW = body.X - LEFT_W - GAP
	local right = Kit.panel(Vector2.new(rightW, lowH))
	right.Name = "Builders"
	right.Position = UDim2.fromOffset(LEFT_W + GAP, TOP_H + GAP)
	right.Parent = win.body
	local rh = Window.heading("Top builders", 18, C.Muted)
	rh.Position = UDim2.fromOffset(PAD, 18)
	rh.Parent = right
	list =
		Flat.frame(UDim2.fromOffset(rightW - 2 * PAD, Rules.TOP * ROW_H), UDim2.fromOffset(PAD, 60))
	list.Name = "List"
	Kit.list(list, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Top)
	list.Parent = right
	listNote = Flat.text("", 14, C.Muted, Theme.Font.Body)
	listNote.Name = "Note"
	listNote.AnchorPoint = Vector2.new(0, 1)
	listNote.Position = UDim2.new(0, PAD, 1, -18)
	listNote.Parent = right
end

function GreatBuildController.toggle()
	win.toggle()
end

function GreatBuildController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function GreatBuildController.isOpen(): boolean
	return win.isOpen()
end

local function onState(s: any)
	if
		typeof(s) ~= "table"
		or typeof(s.total) ~= "number"
		or typeof(s.mine) ~= "table"
		or typeof(s.top) ~= "table"
	then
		return
	end
	local paid: { [string]: boolean } = {}
	if typeof(s.mine.paid) == "table" then
		for k, v in s.mine.paid do
			if typeof(k) == "string" and v == true then
				paid[k] = true
			end
		end
	end
	local top: { Donor } = {}
	for _, d in s.top :: { any } do
		if typeof(d) == "table" and typeof(d.name) == "string" and typeof(d.amount) == "number" then
			table.insert(top, { name = d.name, amount = d.amount, me = d.me == true })
		end
	end
	local function num(v: any): number
		return if typeof(v) == "number" and v == v then v else 0
	end
	state = {
		total = num(s.total),
		stages = num(s.stages),
		buffLeft = num(s.buffLeft),
		mine = {
			total = num(s.mine.total),
			today = num(s.mine.today),
			left = num(s.mine.left),
			paid = paid,
		},
		shards = num(s.shards),
		top = top,
		shared = s.shared == true,
	}
	stateAt = os.clock()
	if typeof(s.donated) == "number" then
		sending = false -- only the answer to a donation unlocks the buttons, not a sync poll
	end
	if typeof(s.text) == "string" then
		statusText.Text = s.text
	elseif typeof(s.donated) == "number" and s.donated > 0 then
		statusText.Text = `Donated {Format.currency(s.donated)}. Thank you!`
		Shape.sound("ui_reward")
	end
	if typeof(s.paid) == "table" then
		for _, amount in s.paid :: { any } do
			for _, m in Rules.Milestones do
				if m.amount == amount then
					QuestController.toast(`Great Build milestone: {m.name}`, C.GoldHi)
				end
			end
		end
	end
	if win.isOpen() then
		render()
	end
end

function GreatBuildController.init()
	win = Window.new({ name = "GreatBuild", title = "Great Build", icon = "great_build" })
	build()
	render()
	win.onOpen(function()
		statusText.Text = ""
		render()
		Net.GreatBuild:FireServer("sync")
	end)
	Net.GreatBuildState.OnClientEvent:Connect(onState)
	local lastStages = ReplicatedStorage:GetAttribute("GreatBuildStages")
	local function onStages()
		local n = ReplicatedStorage:GetAttribute("GreatBuildStages")
		if typeof(n) == "number" and typeof(lastStages) == "number" and n > lastStages then
			Shape.sound("ui_reward")
			QuestController.toast(
				`Great Build stage {n} finished! Everyone gets {Rules.BUFF_TEXT}`,
				C.GoldHi
			)
		end
		lastStages = n
		renderBoard()
		if win.isOpen() then
			renderTop()
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("GreatBuildStages"):Connect(onStages)
	ReplicatedStorage:GetAttributeChangedSignal("GreatBuildTotal"):Connect(function()
		renderBoard()
		if win.isOpen() then
			renderTop()
		end
	end)
end

function GreatBuildController.start()
	task.spawn(watchHub)
	task.spawn(function()
		while true do
			task.wait(POLL)
			if win.isOpen() then
				Net.GreatBuild:FireServer("sync")
			end
		end
	end)
end

return GreatBuildController
