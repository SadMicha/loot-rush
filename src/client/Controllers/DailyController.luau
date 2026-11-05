--!strict
-- Daily rewards window (Shared/Daily, Systems/Daily): seven day cards and one Claim button.
-- Opens by itself once per session when a reward is waiting (after the hero setup and the player's
-- first fight (Daily.popupAllowed), when no other window is open and the player is not in a Rift);
-- any time from the chest button on the HUD.
-- The server owns the calendar (Net.DailyState); the client only asks to claim.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Daily = require(ReplicatedStorage.Shared.Daily)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)

local DailyController = {
	changed = Instance.new("BindableEvent"), -- fires when the state arrives (HUD marker)
}

local player = Players.LocalPlayer
local C = Theme.Color
local F = Theme.Flat

local CARD_W = 196
local CARD_H = 470
local GAP = 16
local AUTO_DELAY = 2 -- seconds after the state arrives before the card may pop up
local POLL = 1

type State = {
	claimed: number,
	index: number,
	canClaim: boolean,
	secondsLeft: number,
	rewards: { Daily.Reward },
	paid: number?,
}

local win: Window.Window
local state: State? = nil
local stateAt = 0 -- os.clock() when the state arrived (countdown)
local cards: Frame
local summary: TextLabel
local claim: TextButton
local claimLabel: TextLabel
local autoShown = false

-- Reward lines of one card: icon name, amount, colour
local function lines(r: Daily.Reward): { { any } }
	local out: { { any } } = {}
	local function add(icon: string, n: number, color: Color3)
		if n > 0 then
			table.insert(out, { icon, n, color } :: { any })
		end
	end
	add("gold", r.gold, C.Gold)
	add("soulstar", r.soulstars, Theme.Rarity.epic)
	add("skills", r.stones, C.Cyan)
	add("crystal", r.shards, C.Cyan)
	add("candy", r.candy, C.Text)
	add("glitter_dust", r.dust, C.Text)
	return out
end

local function countdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm %02ds", m, s % 60)
end

local function secondsLeft(): number
	local s = state
	if not s then
		return 0
	end
	return math.max(0, s.secondsLeft - (os.clock() - stateAt))
end

-- Is a reward waiting right now?
function DailyController.claimable(): boolean
	local s = state
	return s ~= nil and (s.canClaim or secondsLeft() <= 0)
end

local function card(index: number, reward: Daily.Reward, s: State): Frame
	-- Days of this cycle before the next claim are taken; the next one is "today" when open
	local taken = index < s.index
	local today = index == s.index
	local big = index == Daily.CYCLE
	local f = Kit.panel(Vector2.new(CARD_W, CARD_H), if big then C.Gold else nil)
	f.Name = "Day" .. index
	f.LayoutOrder = index
	local head = Flat.text(
		`DAY {index}`,
		20,
		if today then C.GoldHi else C.Text,
		Theme.Font.UI,
		Enum.TextXAlignment.Center
	)
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.new(0.5, 0, 0, 18)
	head.Parent = f
	local list = Flat.frame(UDim2.fromOffset(CARD_W - 24, CARD_H - 120), UDim2.fromOffset(12, 64))
	local layout = Kit.list(list, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, line in lines(reward) do
		local row = Flat.frame(UDim2.fromOffset(CARD_W - 24, 44))
		row.LayoutOrder = i
		local rl = Kit.list(row, Enum.FillDirection.Horizontal, 8)
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local ic = Kit.icon(line[1] :: string, 36)
		ic.LayoutOrder = 1
		ic.Parent = row
		local n =
			Flat.text(Format.currency(line[2] :: number), 18, line[3] :: Color3, Theme.Font.UI)
		n.LayoutOrder = 2
		n.Parent = row
		row.Parent = list
	end
	list.Parent = f
	local foot = Flat.text(
		if taken
			then "Claimed"
			elseif today and s.canClaim then "Today"
			elseif big then "Big reward"
			else "",
		15,
		if taken then C.Muted else C.GoldHi,
		Theme.Font.UI,
		Enum.TextXAlignment.Center
	)
	foot.AnchorPoint = Vector2.new(0.5, 1)
	foot.Position = UDim2.new(0.5, 0, 1, -18)
	foot.Parent = f
	if taken then
		local veil = Instance.new("Frame")
		veil.Name = "Veil"
		veil.BackgroundColor3 = F.Surface0
		veil.BackgroundTransparency = 0.45
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = 5
		Kit.corner(veil, F.Radius.L)
		veil.Parent = f
	elseif today and s.canClaim then
		Shape.brackets(f, C.GoldHi)
		Shape.shine(f, F.Radius.L)
	end
	return f
end

local function render()
	for _, child in cards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local s = state
	if not s then
		summary.Text = "Loading…"
		Flat.setEnabled(claim, false)
		return
	end
	for i = 1, Daily.CYCLE do
		local r = s.rewards[i]
		if r then
			card(i, r, s).Parent = cards
		end
	end
	local days = if s.claimed == 1 then "1 day" else `{Format.int(s.claimed)} days`
	summary.Text = `Claimed {days} so far. Missing a day never resets your calendar.`
	local open = DailyController.claimable()
	Flat.setEnabled(claim, open)
	claimLabel.Text = if open then "Claim" else `Next reward in {countdown(secondsLeft())}`
end

local function build()
	local body = Window.BODY
	summary = Flat.text("", 18, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	summary.Name = "Summary"
	summary.AnchorPoint = Vector2.new(0.5, 0)
	summary.Position = UDim2.new(0.5, 0, 0, 40)
	summary.Parent = win.body
	local rowW = Daily.CYCLE * CARD_W + (Daily.CYCLE - 1) * GAP
	cards = Flat.frame(UDim2.fromOffset(rowW, CARD_H), UDim2.fromOffset((body.X - rowW) / 2, 110))
	cards.Name = "Cards"
	Kit.list(cards, Enum.FillDirection.Horizontal, GAP)
	cards.Parent = win.body
	local b, label = Flat.button("Claim", "primary", Vector2.new(420, 72), "chest")
	claim, claimLabel = b, label
	claim.Name = "Claim"
	claim.AnchorPoint = Vector2.new(0.5, 1)
	claim.Position = UDim2.new(0.5, 0, 1, -40)
	claim.Activated:Connect(function()
		if claim:GetAttribute("Enabled") == false then
			return
		end
		Flat.setEnabled(claim, false)
		Net.Daily:FireServer("claim")
	end)
	claim.Parent = win.body
end

function DailyController.toggle()
	win.toggle()
end

function DailyController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function DailyController.isOpen(): boolean
	return win.isOpen()
end

-- First claimable state of the session: pop the window up once the player is free
local function autoOpen()
	if autoShown then
		return
	end
	autoShown = true
	task.wait(AUTO_DELAY)
	while
		player.Parent
		and (
			player:GetAttribute("SetupDone") ~= true
			or not QuestController.ready()
			or not Daily.popupAllowed(
				QuestController.state().step,
				player:GetAttribute("RiftRegion") ~= nil
			)
			or Window.anyOpen()
		)
	do
		task.wait(POLL)
	end
	if player.Parent and DailyController.claimable() then
		DailyController.open()
	end
end

function DailyController.init()
	win = Window.new({ name = "Daily", title = "Daily Rewards", icon = "chest" })
	build()
	render()
	win.onOpen(render)
	Net.DailyState.OnClientEvent:Connect(function(s: any)
		if typeof(s) ~= "table" then
			return
		end
		state = s :: State
		stateAt = os.clock()
		if s.paid then
			Shape.sound("ui_reward")
			QuestController.toast(`Day {s.paid} reward claimed!`, C.GoldHi)
		end
		if win.isOpen() then
			render()
		end
		DailyController.changed:Fire()
		if s.canClaim and not autoShown then
			task.spawn(autoOpen)
		end
	end)
	-- The countdown on the button ticks while the window is open
	task.spawn(function()
		while true do
			task.wait(POLL)
			if win.isOpen() and state and claim:GetAttribute("Enabled") == false then
				local open = DailyController.claimable()
				Flat.setEnabled(claim, open)
				claimLabel.Text = if open
					then "Claim"
					else `Next reward in {countdown(secondsLeft())}`
			end
		end
	end)
end

return DailyController
