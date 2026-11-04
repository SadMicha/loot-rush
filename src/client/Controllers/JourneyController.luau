--!strict
-- Journey window (Shared/Journey, Systems/Journey): the hero's permanent milestone track.
--  • Left: the next goal with its progress and reward, the hero's facts, overall progress.
--  • Right: every milestone as a row (ready ones first), with a Claim button when finished.
-- Opens from the Journey button on the HUD. The server owns the facts (Net.JourneyState); the
-- client only asks to claim a milestone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Journey)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Reward = require(script.Parent.Parent.UI.Reward)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)

local JourneyController = {
	changed = Instance.new("BindableEvent"), -- fires when the state arrives (HUD dot)
}

local C = Theme.Color
local F = Theme.Flat

local PAD = 28
local SIDE_W = 470
local GAP = 20
local ROW_H = 112
local ICON = 64

type State = { facts: Rules.Facts, claimed: { string }, paid: string? }

local win: Window.Window
local facts: Rules.Facts = {}
local claimed: Rules.Data = {}
local loaded = false
local list: ScrollingFrame
local side: Frame -- dynamic content of the side panel (cleared on render)
local status: TextLabel

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function bestDepth(): number
	return facts.depth or 1
end

-- Milestones ready to claim (HUD dot)
function JourneyController.readyCount(): number
	return if loaded then Rules.readyCount(facts, claimed) else 0
end

local function factText(key: string): string
	local v = facts[key] or 0
	if key == "tier" then
		return WorldTiers.get(v).name
	elseif key == "bosses" then
		return `{Format.int(v)} / {#Atlas.Regions}`
	elseif key == "guide" then
		return if v >= 1 then "Complete" else "In progress"
	end
	return Format.int(v)
end

local function progressText(ms: Rules.Milestone): string
	return `{Format.int(Rules.progress(ms, facts))} / {Format.int(ms.target)}`
end

-- One milestone row
local function row(ms: Rules.Milestone, order: number, width: number): Frame
	local st = Rules.status(ms, facts, claimed)
	local ready = st == "ready"
	local f = Flat.card(UDim2.fromOffset(width, ROW_H), if ready then F.Surface2 else nil)
	f.Name = "Milestone_" .. ms.id
	f.LayoutOrder = order
	if ready then
		Shape.brackets(f, C.GoldHi)
	end
	local ic = Kit.icon(ms.icon, ICON, if st == "open" then C.Muted else nil)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 20, 0.5, 0)
	ic.Parent = f
	local x = 20 + ICON + 20
	local name = Flat.text(ms.name, 20, if ready then C.GoldHi else C.Text, Theme.Font.UI)
	name.Position = UDim2.fromOffset(x, 14)
	name.Parent = f
	local desc = Flat.text(ms.desc, 15, C.Muted, Theme.Font.Body)
	desc.Position = UDim2.fromOffset(x, 44)
	desc.Parent = f
	local barW = 300
	local bar, set = Flat.bar(Vector2.new(barW, 12), if st == "open" then C.Cyan else C.GoldHi)
	bar.Position = UDim2.fromOffset(x, 80)
	bar.Parent = f
	set(Rules.progress(ms, facts) / ms.target)
	local count = Flat.text(progressText(ms), 14, C.Muted, Theme.Font.UI)
	count.AnchorPoint = Vector2.new(0, 0.5)
	count.Position = UDim2.fromOffset(x + barW + 12, 86)
	count.Parent = f
	local reward = Reward.row(Rules.scaled(ms.reward, bestDepth()), 30, 2)
	reward.AnchorPoint = Vector2.new(0, 0.5)
	reward.Position = UDim2.new(0, 560, 0.5, 0)
	reward.Parent = f
	if ready then
		local b = Flat.button("Claim", "primary", Vector2.new(150, 56), "chest")
		b.Name = "Claim"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -20, 0.5, 0)
		b.Activated:Connect(function()
			if b:GetAttribute("Enabled") == false then
				return
			end
			Flat.setEnabled(b, false)
			Net.Journey:FireServer("claim", ms.id)
		end)
		b.Parent = f
	else
		local t = Flat.text(
			if st == "claimed" then "Claimed" else "In progress",
			15,
			if st == "claimed" then C.Good else C.Muted,
			Theme.Font.UI,
			Enum.TextXAlignment.Right
		)
		t.Name = "State"
		t.AnchorPoint = Vector2.new(1, 0.5)
		t.Position = UDim2.new(1, -24, 0.5, 0)
		t.Parent = f
	end
	if st == "claimed" then
		f.BackgroundTransparency = math.max(f.BackgroundTransparency, 0.35)
	end
	return f
end

local function renderSide()
	clear(side)
	local w = SIDE_W - 2 * PAD
	local y = PAD
	local function put(g: GuiObject, height: number)
		g.Position = UDim2.fromOffset(PAD, y)
		g.Parent = side
		y += height
	end
	put(Window.heading("Next goal", 18, C.Muted), 40)
	local goal = Rules.nextGoal(facts, claimed)
	if goal then
		local head = Flat.frame(UDim2.fromOffset(w, 88))
		head.Name = "Goal"
		local ic = Kit.icon(goal.icon, 80)
		ic.Parent = head
		local name = Window.gilded(goal.name, 24)
		name.Position = UDim2.fromOffset(100, 6)
		name.Parent = head
		local desc = Flat.text(goal.desc, 16, C.Text, Theme.Font.Body)
		desc.Position = UDim2.fromOffset(100, 50)
		desc.Parent = head
		put(head, 104)
		local bar, set = Flat.bar(Vector2.new(w, 16), C.Cyan)
		put(bar, 26)
		set(Rules.progress(goal, facts) / goal.target)
		put(Flat.text(progressText(goal), 15, C.Muted, Theme.Font.UI), 40)
		put(Reward.row(Rules.scaled(goal.reward, bestDepth()), 32), 52)
	else
		put(Flat.text("Every milestone reached!", 18, C.GoldHi, Theme.Font.UI), 52)
	end
	put(Flat.rule(w, F.Edge), 20)
	put(Window.heading("Your hero", 18, C.Muted), 40)
	for _, key in { "depth", "tier", "level", "bosses", "stars", "guide" } do
		local line = Flat.frame(UDim2.fromOffset(w, 34))
		line.Name = "Fact_" .. key
		local k = Flat.text(Rules.FactNames[key], 16, C.Muted, Theme.Font.Body)
		k.Parent = line
		local v = Flat.text(factText(key), 16, C.Text, Theme.Font.UI, Enum.TextXAlignment.Right)
		v.AnchorPoint = Vector2.new(1, 0)
		v.Position = UDim2.fromScale(1, 0)
		v.Parent = line
		put(line, 36)
	end
	-- Overall progress at the bottom
	local done = 0
	for _, ms in Rules.List do
		if claimed[ms.id] then
			done += 1
		end
	end
	local total = #Rules.List
	local foot = Flat.text(`{done} / {total} milestones claimed`, 16, C.Text, Theme.Font.UI)
	foot.Name = "Total"
	foot.Position = UDim2.fromOffset(PAD, Window.BODY.Y - PAD - 50)
	foot.Parent = side
	local bar, set = Flat.bar(Vector2.new(w, 14), C.GoldHi)
	bar.Position = UDim2.fromOffset(PAD, Window.BODY.Y - PAD - 14)
	bar.Parent = side
	set(done / total)
end

local function render()
	clear(list)
	if not loaded then
		status.Text = "Loading…"
		clear(side)
		return
	end
	status.Text = ""
	renderSide()
	local width = Window.BODY.X - SIDE_W - GAP - 2 * PAD - 16
	-- Ready first, then the open ones in track order, claimed last
	local rank = { ready = 0, open = 1, claimed = 2 }
	for i, ms in Rules.List do
		local st = Rules.status(ms, facts, claimed)
		row(ms, rank[st] * 1000 + i, width).Parent = list
	end
end

local function build()
	local body = Window.BODY
	local panel = Kit.panel(Vector2.new(SIDE_W, body.Y))
	panel.Name = "Side"
	panel.Parent = win.body
	Shape.brackets(panel)
	side = Flat.frame(UDim2.fromOffset(SIDE_W, body.Y))
	side.Name = "Content"
	side.Parent = panel

	local main = Kit.panel(Vector2.new(body.X - SIDE_W - GAP, body.Y))
	main.Name = "Track"
	main.Position = UDim2.fromOffset(SIDE_W + GAP, 0)
	main.Parent = win.body
	local head = Window.heading("Milestones", 18, C.Muted)
	head.Position = UDim2.fromOffset(PAD, PAD)
	head.Parent = main
	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(PAD, PAD + 44)
	list.Size = UDim2.fromOffset(main.Size.X.Offset - 2 * PAD, body.Y - 2 * PAD - 44)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = C.Gold
	list.ScrollBarImageTransparency = 0.2
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local ll = Kit.list(list, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.Parent = main

	status = Flat.text("", 18, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 140)
	status.Parent = main
end

function JourneyController.toggle()
	win.toggle()
end

function JourneyController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function JourneyController.isOpen(): boolean
	return win.isOpen()
end

function JourneyController.init()
	win = Window.new({ name = "Journey", title = "Journey", icon = "journey" })
	build()
	render()
	win.onOpen(function()
		render()
		Net.Journey:FireServer("sync")
	end)
	Net.JourneyState.OnClientEvent:Connect(function(s: any)
		if typeof(s) ~= "table" or typeof(s.facts) ~= "table" or typeof(s.claimed) ~= "table" then
			return
		end
		local state = s :: State
		facts = state.facts
		claimed = {}
		for _, id in state.claimed do
			if typeof(id) == "string" then
				claimed[id] = true
			end
		end
		loaded = true
		local paid = if typeof(state.paid) == "string" then Rules.ById[state.paid] else nil
		if paid then
			Shape.sound("ui_reward")
			QuestController.toast(`Milestone claimed: {paid.name}`, C.GoldHi)
		end
		if win.isOpen() then
			render()
		end
		JourneyController.changed:Fire()
	end)
end

return JourneyController
