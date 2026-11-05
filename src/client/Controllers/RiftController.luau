--!strict
-- Rift display, kept out of the way of the fight:
--   top left (below the Roblox buttons): a small run card with region · depth, variant, wave and
--     enemies left, plus a two-tap "Leave" while a run is active
--   top center: a slim boss bar while the boss lives, with its Break meter (Shared/Bosses) below
--   boss down: a big "Victory" banner with the fight stats (Net.Fx "victory")
--   after the boss: a centered card with the run so far and "Deeper" / "Back to Hub"; from
--     PathCards.FROM_DEPTH on "Deeper" becomes three Path Cards (affixes + reward, Shared/PathCards)
-- The state comes from the server as player attributes (see Types.luau) and Net.RiftResult; this
-- only displays it and requests "deeper" or "leave" via Net.Rift. Entering happens in the Atlas.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local PathCards = require(ReplicatedStorage.Shared.PathCards)
local RiftAffixes = require(ReplicatedStorage.Shared.RiftAffixes)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Spring = require(script.Parent.Parent.UI.Spring)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)

local RiftController = {}

local player = Players.LocalPlayer
local C = Theme.Color

local INFO_W, INFO_H = 230, 68 -- run card (top left)
local BOSS_W = 360 -- boss bar (top center)
local CHOICE_W, CHOICE_BTN = 330, 38 -- compact card after the boss (width, button height)
local PATH_H = 46 -- one Path Card row
local CONFIRM_TIME = 3 -- seconds the "Leave" button stays armed after the first tap

local root: Frame
local info: Frame
local infoTitle: TextLabel
local infoLine: TextLabel
local infoVariant: TextLabel
local leaveButton: TextButton
local leaveLabel: TextLabel
local leaveArmed = false
local bossBox: Frame
local bossFill: Frame
local bossName: TextLabel
local poiseFill: Frame
local bossState: TextLabel
local banner: Frame
local bannerTitle: TextLabel
local bannerLine: TextLabel
local bannerToken = 0
local fightLine = "" -- stats of the last boss fight for the cleared card ("" = none)
local fightDepth = -1
local choice: Frame
local choiceTitle: TextLabel
local choiceStats: TextLabel
local deeperLabel: TextLabel
local deeperButton: TextButton
local pathBox: Frame
type PathRow = {
	button: TextButton,
	icon: Frame,
	title: TextLabel,
	rule: TextLabel,
	reward: TextLabel,
}
local pathRows: { PathRow } = {}
local lastSummary: { [string]: any }? = nil

local function phase(): string
	return (player:GetAttribute("RiftPhase") or "") :: string
end

-- "In Rift" = run is active or waiting for the choice (not when "failed")
function RiftController.active(): boolean
	local p = phase()
	return p == "wave" or p == "boss" or p == "clear"
end

-- Standing outside Lumenhaven without a run (a stale teleport): "leave" brings the player home
local function awayFromHub(): boolean
	local character = player.Character
	local body = character and character:FindFirstChild("HumanoidRootPart")
	if not (body and body:IsA("BasePart")) then
		return false
	end
	local d = body.Position - Config.HUB_ORIGIN
	return math.max(math.abs(d.X), math.abs(d.Z)) > Config.HUB_HALF + Config.FALL_MARGIN
end

-- Leave the running Rift (the Atlas is the only way in)
function RiftController.leave()
	-- also after a run (phase "" or "failed"): a living body outside the Hub is brought home
	if RiftController.active() or awayFromHub() then
		Net.Rift:FireServer("leave")
	end
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function refreshChoiceStats()
	local s = lastSummary
	-- Only the summary of this depth's clear (no matter which arrives first, it or the phase)
	if not s or s.depth ~= player:GetAttribute("RiftDepth") then
		choiceStats.Text = ""
		return
	end
	local items = if typeof(s.items) == "table" then #s.items else 0
	choiceStats.Text = string.format(
		"%s kills - +%s Gold - %d items - %s",
		Format.int(tonumber(s.kills) or 0),
		Format.currency(tonumber(s.gold) or 0),
		items,
		clock(tonumber(s.seconds) or 0)
	) .. (if fightLine ~= "" and fightDepth == s.depth then "\n" .. fightLine else "")
end

-- Path Cards of this depth's clear (empty = plain "Deeper")
local function currentCards(): { PathCards.Card }
	local s = lastSummary
	local out = {}
	if not s or s.depth ~= player:GetAttribute("RiftDepth") or typeof(s.cards) ~= "table" then
		return out
	end
	for _, raw in s.cards do
		local card = PathCards.sanitize(raw)
		if card then
			table.insert(out, card)
		end
	end
	return out
end

local function showCards(cards: { PathCards.Card })
	for i, row in pathRows do
		local card = cards[i]
		row.button.Visible = card ~= nil
		if card then
			local first = RiftAffixes.ById[card.affixes[1] or ""]
			row.title.Text = if first then RiftAffixes.names(card.affixes) else "Safe Path"
			local rules = {}
			for _, id in card.affixes do
				table.insert(rules, RiftAffixes.ById[id].text)
			end
			row.rule.Text = if #rules > 0 then table.concat(rules, " - ") else "No twist"
			row.reward.Text = PathCards.describe(card)
			row.reward.TextColor3 = if card.reward == "cache"
				then C.GoldHi
				elseif card.reward == "items" then C.Cyan
				else C.Gold
			for _, child in row.icon:GetChildren() do
				child:Destroy()
			end
			local ic = Kit.icon(if first then first.icon else "gold", 26)
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.Parent = row.icon
		end
	end
end

local function setLeaveArmed(armed: boolean)
	leaveArmed = armed
	leaveLabel.Text = if armed then "Sure?" else "Leave"
	leaveLabel.TextColor3 = if armed then C.Danger else C.Muted
end

local function refresh()
	local p = phase()
	local depth = (player:GetAttribute("RiftDepth") or 1) :: number
	local region = Atlas.ById[(player:GetAttribute("RiftRegion") or "") :: string]
	local affixes = RiftAffixes.decode(player:GetAttribute("RiftAffixes"))
	local reward = (player:GetAttribute("RiftReward") or "") :: string
	local regionName = if region then region.name else "Rift"

	local downed = player:GetAttribute("RiftDowned") == true
	info.Visible = p ~= "" and (p ~= "clear" or downed)
	if p ~= "boss" then
		bossBox.Visible = false
	end
	leaveButton.Visible = p == "wave" or p == "boss"
	if not leaveButton.Visible then
		setLeaveArmed(false)
	end
	local twist = RiftAffixes.names(affixes)
	infoVariant.Text = if twist ~= "" and reward ~= ""
		then twist .. " - " .. reward
		elseif twist ~= "" then twist
		else reward
	infoVariant.Visible = infoVariant.Text ~= ""
	infoTitle.Text = string.format("%s - D%d", regionName, depth)
	infoTitle.TextColor3 = if p == "failed" then C.Danger else C.GoldHi
	if downed and (p == "wave" or p == "boss" or p == "clear") then
		infoLine.Text = "Respawning at the waypoint…"
	elseif p == "wave" then
		local wave = (player:GetAttribute("RiftWave") or 1) :: number
		local waves = (player:GetAttribute("RiftWaves") or 1) :: number
		local left = (player:GetAttribute("RiftLeft") or 0) :: number
		infoLine.Text = string.format("Area %d/%d - %d left", wave, waves, left)
	elseif p == "boss" then
		infoLine.Text = "Boss"
	elseif p == "failed" then
		infoLine.Text = "Rift failed"
	else
		infoLine.Text = ""
	end

	local showChoice = p == "clear" and not downed -- the choice waits for the respawn
	if showChoice and not choice.Visible then
		Flat.pop(choice)
	end
	choice.Visible = showChoice
	if showChoice then
		local cards = currentCards()
		choiceTitle.Text = if #cards > 0
			then string.format("Choose your path to D%d", depth + 1)
			else string.format("%s - Depth %d cleared", regionName, depth)
		deeperLabel.Text = string.format("Deeper - D%d", depth + 1)
		deeperButton.Visible = #cards == 0
		pathBox.Visible = #cards > 0
		showCards(cards)
		refreshChoiceStats()
	end
end

-- true while a boss lives (the bar hides in the short pause between boss death and the choice)
local function refreshBoss(): boolean
	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy:GetAttribute("Boss") == true then
			local max = math.max((enemy:GetAttribute("MaxHealth") or 1) :: number, 1)
			local ratio = math.clamp(((enemy:GetAttribute("Health") or 0) :: number) / max, 0, 1)
			Spring.target(bossFill, { Size = UDim2.fromScale(ratio, 1) }, "Soft")
			bossName.Text = enemy.Name
			-- Break meter: full = hard to stagger; drains with every hit, empty = Broken
			local pmax = math.max((enemy:GetAttribute("PoiseMax") or Bosses.POISE) :: number, 1)
			local poise = math.clamp(((enemy:GetAttribute("Poise") or pmax) :: number) / pmax, 0, 1)
			local broken = enemy:GetAttribute("Broken") == true
			Spring.target(
				poiseFill,
				{ Size = UDim2.fromScale(if broken then 0 else poise, 1) },
				"Soft"
			)
			if broken then
				bossState.Text = string.format("BROKEN - +%d%% damage", Bosses.BREAK_DAMAGE * 100)
				bossState.TextColor3 = C.GoldHi
			elseif enemy:GetAttribute("Opening") == true then
				bossState.Text =
					string.format("OPENING - +%d%% damage", Bosses.OPENING_DAMAGE * 100)
				bossState.TextColor3 = C.Cyan
			else
				bossState.Text = "Break"
				bossState.TextColor3 = C.Muted
			end
			return true
		end
	end
	return false
end

-- Keep the run card below the Roblox buttons (top left) whatever the device inset is
local function layout()
	local scale = root:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	local _, barH = Window.topbar()
	-- The Leave button grows to touch size around its middle and reaches above the card's top edge
	local grow = if UserInputService.TouchEnabled
		then math.max(0, (Kit.MIN_TOUCH_PX / s - 28) / 2)
		else 0
	info.Position = UDim2.fromOffset(Theme.Hud.Margin, math.max(12, barH / s + 8 + grow))
end

-- Padded content frame with a vertical list inside a card
local function content(
	card: Frame,
	pad: number,
	gap: number,
	align: Enum.HorizontalAlignment
): Frame
	local body = Flat.frame(UDim2.fromScale(1, 1))
	body.Name = "Body"
	body.ZIndex = 2
	Kit.padding(body, pad)
	local list = Kit.list(body, Enum.FillDirection.Vertical, gap)
	list.HorizontalAlignment = align
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	body.Parent = card
	return body
end

local function buildInfo()
	info = Flat.card(UDim2.fromOffset(INFO_W, INFO_H))
	info.Name = "RunInfo"
	info.BackgroundTransparency = 0.25
	info.Visible = false
	-- Content in its own frame: the card's sheen child must stay out of the list layout
	local body = content(info, 8, 2, Enum.HorizontalAlignment.Left)

	local head = Flat.frame(UDim2.new(1, 0, 0, 20))
	head.LayoutOrder = 1
	head.Parent = body
	infoTitle = Flat.text("", 13, C.GoldHi)
	infoTitle.Parent = head
	local leave
	leave, leaveLabel = Flat.button("Leave", "ghost", Vector2.new(64, 24))
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.fromScale(1, 0.5)
	leaveLabel.TextSize = Kit.fontSize(11)
	leave.Activated:Connect(function()
		if not leaveArmed then
			setLeaveArmed(true)
			task.delay(CONFIRM_TIME, function()
				setLeaveArmed(false)
			end)
			return
		end
		setLeaveArmed(false)
		RiftController.leave()
	end)
	leave.Parent = head
	leaveButton = leave

	infoVariant = Flat.text("", 11, C.Gold, Theme.Font.Body)
	infoVariant.LayoutOrder = 2
	infoVariant.Parent = body
	infoLine = Flat.text("", 12, C.Text, Theme.Font.Body)
	infoLine.LayoutOrder = 3
	infoLine.Parent = body
	info.Parent = root
end

local function buildBoss()
	bossBox = Flat.frame(UDim2.fromOffset(BOSS_W, 48))
	bossBox.Name = "BossBar"
	bossBox.AnchorPoint = Vector2.new(0.5, 0)
	bossBox.Position = UDim2.new(0.5, 0, 0, 68) -- just below the resource capsules
	bossBox.Visible = false
	bossName = Flat.text("", 12, C.Text)
	bossName.AnchorPoint = Vector2.new(0.5, 0)
	bossName.Position = UDim2.fromScale(0.5, 0)
	Kit.textOutline(bossName, 0.4)
	bossName.Parent = bossBox
	local back, fill = Kit.bar(Vector2.new(BOSS_W, 10), C.Danger)
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 20)
	back.Parent = bossBox
	bossFill = fill
	-- Break meter: thin gold bar under the life bar, state text on its left
	local pback, pfill = Kit.bar(Vector2.new(BOSS_W * 0.6, 5), C.Gold)
	pback.Name = "Poise"
	pback.AnchorPoint = Vector2.new(1, 0)
	pback.Position = UDim2.new(1, 0, 0, 34)
	pback.Parent = bossBox
	poiseFill = pfill
	bossState = Flat.text("Break", 10, C.Muted, Theme.Font.Body)
	bossState.Name = "BreakState"
	bossState.Position = UDim2.fromOffset(0, 30)
	Kit.textOutline(bossState, 0.4)
	bossState.Parent = bossBox
	bossBox.Parent = root
	Kit.markTopCenter(bossBox)
end

-- "Victory" banner after a boss kill: pops in the middle, fades after a moment
local BANNER_TIME = 2.6

local function buildBanner()
	banner = Flat.frame(UDim2.fromOffset(420, 90))
	banner.Name = "Victory"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.36)
	banner.Visible = false
	local list = Kit.list(banner, Enum.FillDirection.Vertical, 2)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bannerTitle = Flat.text("VICTORY", 44, C.GoldHi, Theme.Font.Title, Enum.TextXAlignment.Center)
	bannerTitle.LayoutOrder = 1
	Kit.textOutline(bannerTitle, 0.2)
	bannerTitle.Parent = banner
	bannerLine = Flat.text("", 13, C.Text, Theme.Font.Body, Enum.TextXAlignment.Center)
	bannerLine.LayoutOrder = 2
	Kit.textOutline(bannerLine, 0.3)
	bannerLine.Parent = banner
	banner.Parent = root
end

local function plural(n: number, word: string): string
	return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

local function showVictory(d: { [string]: any })
	local seconds = tonumber(d.seconds) or 0
	local breaks = math.floor(tonumber(d.breaks) or 0)
	local counters = math.floor(tonumber(d.counters) or 0)
	local name = if typeof(d.name) == "string" then d.name else "Boss"
	fightLine = string.format(
		"Boss %s - %s - %s",
		clock(seconds),
		plural(breaks, "Break"),
		plural(counters, "Counter")
	)
	fightDepth = (player:GetAttribute("RiftDepth") or 0) :: number
	bannerTitle.Text = "VICTORY"
	bannerLine.Text = name .. " defeated - " .. fightLine
	for _, t in { bannerTitle, bannerLine } do
		t.TextTransparency = 0
	end
	banner.Visible = true
	Flat.pop(banner)
	bannerToken += 1
	local token = bannerToken
	task.delay(BANNER_TIME, function()
		if token ~= bannerToken then
			return
		end
		local fade = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
		for _, t in { bannerTitle, bannerLine } do
			TweenService:Create(t, fade, { TextTransparency = 1 }):Play()
		end
		task.delay(0.5, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
	refreshChoiceStats()
end

local function buildChoice()
	-- Height follows the content (no empty strip at the bottom)
	choice = Flat.card(UDim2.fromOffset(CHOICE_W, 0), nil, C.Gold)
	choice.AutomaticSize = Enum.AutomaticSize.Y
	choice.Name = "RiftClear"
	-- Top center, under the resource capsules: keeps the hero, the Rush bar and the skills free
	choice.AnchorPoint = Vector2.new(0.5, 0)
	choice.Position = UDim2.new(0.5, 0, 0, 84)
	choice.Visible = false
	Shape.brackets(choice, C.GoldHi, 8, 0)
	local body = content(choice, 12, 6, Enum.HorizontalAlignment.Center)
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y

	choiceTitle = Flat.text("", 14, C.GoldHi, Theme.Font.Title, Enum.TextXAlignment.Center)
	choiceTitle.LayoutOrder = 1
	choiceTitle.Parent = body
	choiceStats = Flat.text("", 10, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	choiceStats.LayoutOrder = 2
	choiceStats.Parent = body
	local rule = Flat.rule(CHOICE_W - 48)
	rule.LayoutOrder = 3
	rule.Parent = body

	-- Path Cards: three rows, tap = go deeper with that card
	local inner = CHOICE_W - 24
	pathBox = Flat.frame(UDim2.fromOffset(inner, 0))
	pathBox.Name = "PathCards"
	pathBox.AutomaticSize = Enum.AutomaticSize.Y
	pathBox.LayoutOrder = 4
	pathBox.Visible = false
	Kit.list(pathBox, Enum.FillDirection.Vertical, 6)
	for i = 1, PathCards.COUNT do
		local b =
			Flat.button("", if i == 1 then "ghost" else "secondary", Vector2.new(inner, PATH_H))
		b.Name = "Card" .. i
		b.LayoutOrder = i
		local label = b:FindFirstChild("Row")
		if label then
			label:Destroy()
		end
		local icon = Flat.frame(UDim2.fromOffset(30, 30))
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		icon.Parent = b
		local textW = inner - 46 - 92
		local title = Flat.text("", 12, C.GoldHi, Theme.Font.Title)
		title.AutomaticSize = Enum.AutomaticSize.None
		title.Size = UDim2.fromOffset(textW, 16)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.Position = UDim2.fromOffset(46, 6)
		title.Parent = b
		local ruleText = Flat.text("", 9.5, C.Muted, Theme.Font.Body)
		ruleText.AutomaticSize = Enum.AutomaticSize.None
		ruleText.Size = UDim2.fromOffset(textW, 14)
		ruleText.TextTruncate = Enum.TextTruncate.AtEnd
		ruleText.Position = UDim2.fromOffset(46, 25)
		ruleText.Parent = b
		local rewardText = Flat.text("", 11, C.Gold, Theme.Font.UI, Enum.TextXAlignment.Right)
		rewardText.AutomaticSize = Enum.AutomaticSize.None
		rewardText.Size = UDim2.fromOffset(84, 16)
		rewardText.TextTruncate = Enum.TextTruncate.AtEnd
		rewardText.AnchorPoint = Vector2.new(1, 0.5)
		rewardText.Position = UDim2.new(1, -8, 0.5, 0)
		rewardText.Parent = b
		b.Activated:Connect(function()
			Net.Rift:FireServer("deeper", i)
		end)
		b.Parent = pathBox
		table.insert(
			pathRows,
			{ button = b, icon = icon, title = title, rule = ruleText, reward = rewardText }
		)
	end
	pathBox.Parent = body

	local row = Flat.frame(UDim2.fromOffset(CHOICE_W - 24, CHOICE_BTN))
	row.LayoutOrder = 5
	local rl = Kit.list(row, Enum.FillDirection.Horizontal, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local btnW = (CHOICE_W - 24 - 8) / 2
	local deeper
	deeper, deeperLabel = Flat.button("Deeper", "primary", Vector2.new(btnW, CHOICE_BTN))
	deeper.Name = "Deeper"
	deeper.LayoutOrder = 1
	deeper.Activated:Connect(function()
		Net.Rift:FireServer("deeper")
	end)
	deeper.Parent = row
	deeperButton = deeper
	local home = Flat.button("Back to Hub", "secondary", Vector2.new(btnW, CHOICE_BTN))
	home.Name = "Home"
	home.LayoutOrder = 2
	home.Activated:Connect(function()
		Net.Rift:FireServer("leave")
	end)
	home.Parent = row
	row.Parent = body
	choice.Parent = root
	Kit.markTopCenter(choice)
end

function RiftController.init()
	local gui: ScreenGui
	-- Same design size as the HUD so touch screens get the larger touch layout
	gui, root = Kit.scaledGui("LootRushRift", 3, false, Kit.hudDesign, true)
	buildInfo()
	buildBoss()
	buildChoice()
	buildBanner()
	gui.Parent = player:WaitForChild("PlayerGui")
	layout()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	-- HUD size setting: only the root's scale changes, the card must stay below the Roblox buttons
	local scale = root:FindFirstChildOfClass("UIScale")
	if scale then
		scale:GetPropertyChangedSignal("Scale"):Connect(layout)
	end
end

function RiftController.start()
	for _, attr in
		{
			"RiftPhase",
			"RiftRegion",
			"RiftDepth",
			"RiftWave",
			"RiftWaves",
			"RiftLeft",
			"RiftDowned",
		}
	do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	Net.Fx.OnClientEvent:Connect(function(kind: any, d: any)
		if kind == "victory" and typeof(d) == "table" and d.by == player.UserId then
			showVictory(d)
		end
	end)
	Net.RiftResult.OnClientEvent:Connect(function(summary: any)
		if typeof(summary) ~= "table" then
			return
		end
		lastSummary = if summary.kind == "clear" then summary else nil
		refresh()
	end)
	-- Announce the affixes of each new depth (names in the run card, rules as toasts). Keyed on
	-- region + depth + affixes and checked one frame later, so the same twist twice in a row
	-- still toasts and the attributes the server sets one after another are read together.
	local announced = ""
	local pending = false
	local function announce()
		pending = false
		local p = phase()
		if p == "" or p == "failed" or player:GetAttribute("RiftRegion") == nil then
			announced = "" -- run over: the next run announces again
			return
		end
		if p ~= "wave" then
			return -- a depth always starts with its waves; boss/clear never announce
		end
		local ids = RiftAffixes.decode(player:GetAttribute("RiftAffixes"))
		local key = string.format(
			"%s|%d|%s",
			(player:GetAttribute("RiftRegion") or "") :: string,
			(player:GetAttribute("RiftDepth") or 0) :: number,
			RiftAffixes.encode(ids)
		)
		if key ~= announced then
			for _, id in ids do
				local a = RiftAffixes.ById[id]
				QuestController.toast(a.name .. ": " .. a.text, C.Gold)
			end
		end
		announced = key
	end
	for _, attr in { "RiftAffixes", "RiftDepth", "RiftRegion", "RiftPhase" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if not pending then
				pending = true
				task.defer(announce)
			end
		end)
	end
	player:GetAttributeChangedSignal("RiftAffixes"):Connect(refresh)
	player:GetAttributeChangedSignal("RiftReward"):Connect(refresh)
	refresh()
	-- Boss bar (the fill springs, so hits drain it smoothly)
	while true do
		if phase() == "boss" then
			bossBox.Visible = refreshBoss()
		end
		task.wait(0.15)
	end
end

return RiftController
