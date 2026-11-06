--!strict
-- "What's New" window: the release notes from Shared/Changelog, newest first. Pops up once after a
-- live release for players who saw an older build (seen-marker: setting `changelogSeen`, saved per
-- account through Client/Prefs). Brand-new players (marker 0) get the marker set silently instead.
-- Settings → About → "What's New" opens it any time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Changelog = require(ReplicatedStorage.Shared.Changelog)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Prefs = require(script.Parent.Parent.Prefs)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)

local ChangelogController = {}

local C = Theme.Color
local player = Players.LocalPlayer

local PANEL = Vector2.new(1080, 790) -- centered in Window.BODY (1520×790)
local PAD = 32
local BUTTON_H = 56
local AUTO_DELAY = 3 -- seconds after the settings arrived before the window may pop up
local POLL = 1

local win: Window.Window
local list: ScrollingFrame
local shownSeen = 0 -- marker before this open: releases above it get the NEW tag

local function clear()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- One release: version + date, headline, bullet lines
local function block(r: Changelog.Release, order: number, isNew: boolean): Frame
	local width = PANEL.X - 2 * PAD - 16 -- room for the scroll bar
	local f = Flat.frame(UDim2.fromOffset(width, 0))
	f.Name = "Release_" .. r.build
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	Kit.list(f, Enum.FillDirection.Vertical, Theme.Space.S, Enum.VerticalAlignment.Top)

	local head = Flat.frame(UDim2.fromOffset(0, 36))
	head.Name = "Head"
	head.AutomaticSize = Enum.AutomaticSize.X
	head.LayoutOrder = 1
	local hl = Kit.list(head, Enum.FillDirection.Horizontal, Theme.Space.M)
	hl.VerticalAlignment = Enum.VerticalAlignment.Center
	local v = Window.gilded(r.version, 26)
	v.LayoutOrder = 1
	v.Parent = head
	local d = Flat.text(r.date, 14, C.Muted, Theme.Font.Body)
	d.LayoutOrder = 2
	d.Parent = head
	if isNew then
		local tag = Flat.text("NEW", 13, C.GoldHi, Theme.Font.UI)
		tag.Name = "New"
		tag.LayoutOrder = 3
		tag.Parent = head
	end
	head.Parent = f

	local title = Flat.text(r.title, 19, C.Text, Theme.Font.UI)
	title.Name = "Title"
	title.LayoutOrder = 2
	title.Parent = f

	for i, note in r.notes do
		local l = Flat.text("•  " .. note, 16, C.Text, Theme.Font.Body)
		l.Name = "Note" .. i
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.Size = UDim2.fromOffset(width, 0)
		l.TextWrapped = true
		l.LayoutOrder = 2 + i
		l.Parent = f
	end

	local rule = Shape.accentRule(180)
	rule.LayoutOrder = 100
	rule.Parent = f
	f.Parent = list
	return f
end

local function render()
	clear()
	for i, r in Changelog.Releases do
		block(r, i, shownSeen > 0 and r.build > shownSeen)
	end
	list.CanvasPosition = Vector2.zero
end

local function build()
	local panel = Kit.panel(PANEL)
	panel.Name = "Notes"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0)
	Shape.brackets(panel)

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(PAD, PAD)
	list.Size = UDim2.fromOffset(PANEL.X - 2 * PAD, PANEL.Y - 3 * PAD - BUTTON_H)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = C.Gold
	Kit.list(list, Enum.FillDirection.Vertical, Theme.Space.XL, Enum.VerticalAlignment.Top)
	list.Parent = panel

	local ok = Flat.button("Got it", "primary", Vector2.new(220, BUTTON_H))
	ok.Name = "GotIt"
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -PAD)
	ok.Activated:Connect(function()
		win.close()
	end)
	ok.Parent = panel

	panel.Parent = win.body
end

-- Marks the newest release as seen (also when opened by hand)
local function markSeen()
	local latest = Changelog.latest().build
	if (Prefs.get("changelogSeen") :: number) < latest then
		Prefs.set("changelogSeen", latest)
	end
end

function ChangelogController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function ChangelogController.isOpen(): boolean
	return win.isOpen()
end

-- Once per session: after the saved settings arrived, pop up for players who saw an older build
local function autoOpen()
	while player.Parent and not Prefs.loaded() do
		task.wait(POLL)
	end
	local seen = Prefs.get("changelogSeen") :: number
	local latest = Changelog.latest().build
	if seen <= 0 then
		markSeen() -- new account (or after Defaults): nothing to catch up on
		return
	end
	if seen >= latest then
		return
	end
	task.wait(AUTO_DELAY)
	while
		player.Parent
		and (
			player:GetAttribute("SetupDone") ~= true
			or not QuestController.ready()
			or player:GetAttribute("RiftRegion") ~= nil
			or Window.anyOpen()
		)
	do
		task.wait(POLL)
	end
	if player.Parent and (Prefs.get("changelogSeen") :: number) < latest then
		ChangelogController.open()
	end
end

function ChangelogController.init()
	win = Window.new({ name = "WhatsNew", title = "What's New", icon = "quest" })
	build()
	win.onOpen(function()
		shownSeen = Prefs.get("changelogSeen") :: number
		render()
		markSeen()
	end)
end

function ChangelogController.start()
	task.spawn(autoOpen)
end

return ChangelogController
