--!strict
-- First-open explainer: the first time a window opens, a short card over it says what the window
-- is for in two or three lines, with a "Got it" button. Seen once per account (hidden setting,
-- Shared/Settings `intro*`, saved through Client/Prefs); the Defaults button in the settings window
-- brings it back once. Nothing shows before the saved settings arrived.
--   Intro.attach(win, "introForge", "FORGE", "forge", { "line one", "line two" })

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Prefs = require(script.Parent.Parent.Prefs)
local Flat = require(script.Parent.Flat)
local Kit = require(script.Parent.Kit)
local Window = require(script.Parent.Window)

local Intro = {}

local C = Theme.Color
local CARD_W = 680
local LINE_H = 60 -- room for three wrapped rows (phones raise small text to a minimum size)
local CARD_H = 380
local PAD = Theme.Space.XL
local Z = 40 -- above the window content

-- Builds the card over the window (hidden setting `key` is not set yet). Returns the overlay.
function Intro.show(
	win: Window.Window,
	key: string,
	title: string,
	icon: string?,
	lines: { string }
): Frame
	-- Dim layer over the whole window; swallows taps so the window underneath waits
	local overlay = Instance.new("Frame")
	overlay.Name = "Intro"
	overlay.BackgroundColor3 = C.Bg0
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true
	overlay.ZIndex = Z

	-- Fixed size (no AutomaticSize: the card's Sheen fills it by scale); the rows sit in Body
	local card = Flat.card(UDim2.fromOffset(CARD_W, CARD_H))
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = Z
	local body = Flat.frame(UDim2.new(1, -2 * PAD, 1, -2 * PAD))
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.ZIndex = Z
	local list = Kit.list(body, Enum.FillDirection.Vertical, Theme.Space.M)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	body.Parent = card

	local head = Flat.frame(UDim2.fromOffset(0, 40))
	head.Name = "Head"
	head.AutomaticSize = Enum.AutomaticSize.X
	head.LayoutOrder = 1
	Kit.list(head, Enum.FillDirection.Horizontal, Theme.Space.S)
	if icon then
		local ic = Kit.icon(icon, 36)
		ic.LayoutOrder = 1
		ic.Parent = head
	end
	local t = Window.gilded(title, 28)
	t.LayoutOrder = 2
	t.Parent = head
	head.Parent = body

	for i, line in lines do
		local l = Flat.text(line, 16, C.Text, Theme.Font.Body, Enum.TextXAlignment.Center)
		l.Name = "Line" .. i
		l.AutomaticSize = Enum.AutomaticSize.None
		l.Size = UDim2.new(1, 0, 0, LINE_H)
		l.TextWrapped = true
		l.TextYAlignment = Enum.TextYAlignment.Center
		l.LayoutOrder = 1 + i
		l.Parent = body
	end

	local ok = Flat.button("Got it", "primary", Vector2.new(200, 48))
	ok.Name = "GotIt"
	ok.LayoutOrder = 10 + #lines
	ok.Parent = body
	ok.Activated:Connect(function()
		Prefs.set(key, true)
		overlay:Destroy()
	end)

	card.Parent = overlay
	overlay.Parent = win.root
	Flat.pop(card)
	return overlay
end

-- Shows the card the first time `win` opens (and again after "Defaults" cleared it).
function Intro.attach(
	win: Window.Window,
	key: string,
	title: string,
	icon: string?,
	lines: { string }
)
	local current: Frame? = nil
	win.onOpen(function()
		if not Prefs.loaded() or Prefs.get(key) == true then
			return
		end
		if current and current.Parent then
			return -- still up from the last open (closed without "Got it")
		end
		current = Intro.show(win, key, title, icon, lines)
	end)
end

return Intro
