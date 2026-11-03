--!strict
-- Rift display, kept out of the way of the fight:
--   top left (below the Roblox buttons): a small run card with region · depth, variant, wave and
--     enemies left, plus a two-tap "Leave" while a run is active
--   top center: a slim boss bar while the boss lives
--   after the boss: a centered card with the run so far and "Deeper" / "Back to Hub"
-- The state comes from the server as player attributes (see Types.luau) and Net.RiftResult; this
-- only displays it and requests "deeper" or "leave" via Net.Rift. Entering happens in the Atlas.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local RiftVariants = require(ReplicatedStorage.Shared.RiftVariants)
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
local CHOICE_W, CHOICE_H = 420, 168 -- card after the boss
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
local choice: Frame
local choiceTitle: TextLabel
local choiceStats: TextLabel
local deeperLabel: TextLabel
local lastSummary: { [string]: any }? = nil

local function phase(): string
	return (player:GetAttribute("RiftPhase") or "") :: string
end

-- "In Rift" = run is active or waiting for the choice (not when "failed")
function RiftController.active(): boolean
	local p = phase()
	return p == "wave" or p == "boss" or p == "clear"
end

-- Leave the running Rift (the Atlas is the only way in)
function RiftController.leave()
	if RiftController.active() then
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
		"%s kills  ·  +%s Gold  ·  %d items  ·  %s",
		Format.int(tonumber(s.kills) or 0),
		Format.big(tonumber(s.gold) or 0),
		items,
		clock(tonumber(s.seconds) or 0)
	)
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
	local variant = RiftVariants.ById[(player:GetAttribute("RiftVariant") or "") :: string]
	local regionName = if region then region.name else "Rift"

	info.Visible = p ~= "" and p ~= "clear"
	if p ~= "boss" then
		bossBox.Visible = false
	end
	leaveButton.Visible = p == "wave" or p == "boss"
	if not leaveButton.Visible then
		setLeaveArmed(false)
	end
	infoVariant.Text = if variant then variant.name else ""
	infoVariant.Visible = variant ~= nil
	infoTitle.Text = string.format("%s · D%d", regionName, depth)
	infoTitle.TextColor3 = if p == "failed" then C.Danger else C.GoldHi
	if p == "wave" then
		local wave = (player:GetAttribute("RiftWave") or 1) :: number
		local waves = (player:GetAttribute("RiftWaves") or 1) :: number
		local left = (player:GetAttribute("RiftLeft") or 0) :: number
		infoLine.Text = string.format("Wave %d/%d  ·  %d left", wave, waves, left)
	elseif p == "boss" then
		infoLine.Text = "Boss"
	elseif p == "failed" then
		infoLine.Text = "Rift failed"
	else
		infoLine.Text = ""
	end

	local showChoice = p == "clear"
	if showChoice and not choice.Visible then
		Flat.pop(choice)
	end
	choice.Visible = showChoice
	if showChoice then
		choiceTitle.Text = string.format("%s · Depth %d cleared", regionName, depth)
		deeperLabel.Text = string.format("Deeper · D%d", depth + 1)
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
	info.Position = UDim2.fromOffset(Theme.Hud.Margin, math.max(12, barH / s + 8))
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
	bossBox = Flat.frame(UDim2.fromOffset(BOSS_W, 30))
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
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.fromScale(0.5, 1)
	back.Parent = bossBox
	bossFill = fill
	bossBox.Parent = root
end

local function buildChoice()
	choice = Flat.card(UDim2.fromOffset(CHOICE_W, CHOICE_H), nil, C.Gold)
	choice.Name = "RiftClear"
	choice.AnchorPoint = Vector2.new(0.5, 0.5)
	choice.Position = UDim2.fromScale(0.5, 0.64) -- below the hero, above the hub bar
	choice.Visible = false
	Shape.brackets(choice, C.GoldHi, 10, 0)
	local body = content(choice, 16, 8, Enum.HorizontalAlignment.Center)

	choiceTitle = Flat.text("", 17, C.GoldHi, Theme.Font.Title, Enum.TextXAlignment.Center)
	choiceTitle.LayoutOrder = 1
	choiceTitle.Parent = body
	choiceStats = Flat.text("", 12, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	choiceStats.LayoutOrder = 2
	choiceStats.Parent = body
	local rule = Flat.rule(CHOICE_W - 64)
	rule.LayoutOrder = 3
	rule.Parent = body

	local row = Flat.frame(UDim2.fromOffset(CHOICE_W - 32, 52))
	row.LayoutOrder = 4
	local rl = Kit.list(row, Enum.FillDirection.Horizontal, 12)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local btnW = (CHOICE_W - 32 - 12) / 2
	local deeper
	deeper, deeperLabel = Flat.button("Deeper", "primary", Vector2.new(btnW, 48))
	deeper.Name = "Deeper"
	deeper.LayoutOrder = 1
	deeper.Activated:Connect(function()
		Net.Rift:FireServer("deeper")
	end)
	deeper.Parent = row
	local home = Flat.button("Back to Hub", "secondary", Vector2.new(btnW, 48))
	home.Name = "Home"
	home.LayoutOrder = 2
	home.Activated:Connect(function()
		Net.Rift:FireServer("leave")
	end)
	home.Parent = row
	row.Parent = body
	choice.Parent = root
end

function RiftController.init()
	local gui: ScreenGui
	-- Same design size as the HUD so touch screens get the larger touch layout
	gui, root = Kit.scaledGui("LootRushRift", 3, false, function()
		return if UserInputService.TouchEnabled then Theme.HudDesignTouch else Theme.DesignSize
	end, true)
	buildInfo()
	buildBoss()
	buildChoice()
	gui.Parent = player:WaitForChild("PlayerGui")
	layout()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
end

function RiftController.start()
	for _, attr in { "RiftPhase", "RiftRegion", "RiftDepth", "RiftWave", "RiftWaves", "RiftLeft" } do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	Net.RiftResult.OnClientEvent:Connect(function(summary: any)
		if typeof(summary) ~= "table" then
			return
		end
		lastSummary = if summary.kind == "clear" then summary else nil
		refresh()
	end)
	-- Announce the variant of each new depth (name in the run card, rule as a toast). Keyed on
	-- region + depth + variant and checked one frame later, so a repeated roll still toasts and
	-- the attributes the server sets one after another are read together.
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
		local id = (player:GetAttribute("RiftVariant") or "") :: string
		local key = string.format(
			"%s|%d|%s",
			(player:GetAttribute("RiftRegion") or "") :: string,
			(player:GetAttribute("RiftDepth") or 0) :: number,
			id
		)
		local variant = RiftVariants.ById[id]
		if key ~= announced and variant then
			QuestController.toast(variant.name .. ": " .. variant.text, C.Gold)
		end
		announced = key
	end
	for _, attr in { "RiftVariant", "RiftDepth", "RiftRegion", "RiftPhase" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if not pending then
				pending = true
				task.defer(announce)
			end
		end)
	end
	player:GetAttributeChangedSignal("RiftVariant"):Connect(refresh)
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
