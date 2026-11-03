--!strict
-- Heroes screen (docs/CLASSES.md): the account's characters and creating new ones.
--  • Setup: opens by itself while the active character is not set up (attribute SetupDone =
--    false, first join): name + class; it reopens until the hero is created.
--  • From the Skills window ("Heroes"): list of characters with "Play" (switch = rejoin) and
--    "New hero" (name + class). The class of a hero never changes.
-- The server (Systems/Characters) validates and filters everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)

local CharacterController = {}

type Entry = { id: string, name: string, class: string, level: number, league: string }

local C = Theme.Color
local player = Players.LocalPlayer
local win: Window.Window
local heroes: ScrollingFrame
local cards: Frame
local nameBox: TextBox
local status: TextLabel
local waiting = false -- a request is out: no second tap until the server answers

-- Sends one hero request and locks the buttons until the answer arrives. The server answers
-- every setup/create/play (also when rate-limited or on an error), so there is no timeout:
-- unlocking early would let a slow, still-running setup lock the class behind the player's back.
local function request(action: string, a: any, b: any)
	waiting = true
	Net.Character:FireServer(action, a, b)
end

local GAP = 24
local HEROES_H = 120
local HERO_W = 236
local NAME_Y = HEROES_H + 20
local NAME_H = 56
local CARDS_Y = NAME_Y + NAME_H + 20
local CARD_H = Window.BODY.Y - CARDS_Y

local state: { active: string, max: number, list: { Entry } } =
	{ active = "", max = Profile.MAX_CHARACTERS, list = {} }

local function setupPending(): boolean
	return player:GetAttribute("SetupDone") == false
end

local function clear(f: Instance)
	for _, child in f:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function say(text: string, color: Color3?)
	status.Text = text
	status.TextColor3 = color or C.Muted
end

local function renderHeroes()
	clear(heroes)
	heroes.CanvasSize = UDim2.fromOffset(0, 0)
	if setupPending() then
		local hint = Kit.label(
			"Name your hero and pick a class. The class stays with this hero - "
				.. "you can create more heroes later.",
			20,
			C.Text,
			Theme.Font.Body
		)
		hint.AutomaticSize = Enum.AutomaticSize.None
		hint.Size = UDim2.fromOffset(Window.BODY.X, HEROES_H)
		hint.TextWrapped = true
		hint.Parent = heroes
		return
	end
	for i, entry in state.list do
		local class = Classes.ById[entry.class]
		local weapon = class and Weapons.ById[class.weapon]
		local accent = if weapon then weapon.accent else C.Gold
		local mine = entry.id == state.active
		local card = Kit.panel(Vector2.new(HERO_W, HEROES_H), if mine then C.Gold else accent)
		card.Name = entry.id
		card.LayoutOrder = i
		local name =
			Kit.label(if entry.name ~= "" then entry.name else player.DisplayName, 22, C.Text)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Size = UDim2.fromOffset(HERO_W - 28, 28)
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(14, 10)
		name.Parent = card
		local info = Kit.label(
			string.format("%s · Lv %d", if class then class.hero else entry.class, entry.level),
			16,
			accent,
			Theme.Font.Body
		)
		info.Position = UDim2.fromOffset(14, 40)
		info.Parent = card
		local b = Kit.button(
			if mine then "Playing" else "Play",
			if mine then C.Muted else C.Gold,
			Vector2.new(HERO_W - 28, 40),
			nil
		)
		b.Name = "Play"
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -10)
		local inRift = (player:GetAttribute("RiftPhase") or "") ~= ""
		Kit.setEnabled(b, not mine and not inRift and not waiting)
		b.Activated:Connect(function()
			if b.Active and not waiting then
				Kit.setEnabled(b, false)
				say("Switching to " .. entry.name .. " …", C.Text)
				request("play", entry.id)
			end
		end)
		b.Parent = card
		card.Parent = heroes
	end
end

local function renderCards()
	clear(cards)
	local n = #Classes.List
	local w = (Window.BODY.X - GAP * (n - 1)) / n
	local pending = setupPending()
	local full = not pending and #state.list >= state.max
	for i, class in Classes.List do
		local weapon = Weapons.ById[class.weapon]
		local accent = if weapon then weapon.accent else C.Gold
		local card = Kit.panel(Vector2.new(w, CARD_H), accent)
		card.Name = class.id
		card.LayoutOrder = i

		local title = Window.heading(class.name, 30, accent)
		title.AutomaticSize = Enum.AutomaticSize.None
		title.Size = UDim2.fromOffset(w - 48, 36)
		title.TextScaled = true
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(24, 20)
		title.Parent = card
		local hero = Kit.label(class.hero .. " · " .. class.role, 18, C.Muted, Theme.Font.Body)
		hero.Position = UDim2.fromOffset(24, 64)
		hero.Parent = card

		local kit = Skills.forClass(class.id)
		local lines = { "Basic: " .. kit.basic.name }
		for _, id in kit.bar do
			local s = Skills.ById[id]
			if s then
				table.insert(lines, "• " .. s.name)
			end
		end
		table.insert(lines, "+ 4 more skills from level 8")
		local text = Kit.label(table.concat(lines, "\n"), 18, C.Text, Theme.Font.Body)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.TextWrapped = true
		text.AutomaticSize = Enum.AutomaticSize.None
		text.Size = UDim2.fromOffset(w - 48, CARD_H - 200)
		text.Position = UDim2.fromOffset(24, 104)
		text.Parent = card

		local b = Kit.button(
			if pending then "Play " .. class.hero else "Create " .. class.hero,
			C.Gold,
			Vector2.new(w - 48, 60),
			nil
		)
		b.Name = "Choose"
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -20)
		Kit.setEnabled(b, not full and not waiting)
		b.Activated:Connect(function()
			if not b.Active or waiting then
				return
			end
			local name = Profile.validName(nameBox.Text)
			if not name then
				say(
					string.format(
						"Pick a name: %d-%d letters or digits",
						Profile.NAME_MIN,
						Profile.NAME_MAX
					),
					C.Danger
				)
				return
			end
			say("Creating " .. name .. " …", C.Text)
			request(if setupPending() then "setup" else "create", name, class.id)
			renderCards() -- every create button off until the answer
		end)
		b.Parent = card
		card.Parent = cards
	end
	if full then
		say("All " .. state.max .. " hero slots are used.", C.Muted)
	end
end

local function render()
	renderHeroes()
	renderCards()
end

-- Opens the heroes screen (Skills window button, or by itself for the first-join setup)
function CharacterController.open()
	say("", nil)
	if nameBox.Text == "" then
		nameBox.Text = Profile.validName(player.DisplayName) or ""
	end
	render()
	if not win.isOpen() then
		win.toggle()
	end
end

function CharacterController.init()
	win = Window.new({ name = "Heroes", title = "Your heroes", icon = "crown" })

	-- Up to 12 heroes: a sideways scrolling row (6 fit at once)
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Heroes"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.fromOffset(Window.BODY.X, HEROES_H + 10)
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.fromOffset(0, 0)
	strip.ScrollBarThickness = 6
	strip.ScrollBarImageColor3 = C.Gold
	strip.HorizontalScrollBarInset = Enum.ScrollBarInset.Always
	strip.ElasticBehavior = Enum.ElasticBehavior.Never
	local row = Kit.list(strip, Enum.FillDirection.Horizontal, 12)
	row.HorizontalAlignment = Enum.HorizontalAlignment.Left
	row.VerticalAlignment = Enum.VerticalAlignment.Top
	strip.Parent = win.body
	heroes = strip

	local box, input = Kit.textBox(Vector2.new(420, NAME_H), "Hero name")
	box.Position = UDim2.fromOffset(0, NAME_Y)
	input.TextSize = Kit.fontSize(20)
	box.Parent = win.body
	nameBox = input
	status = Kit.label("", 18, C.Muted, Theme.Font.Body)
	status.AnchorPoint = Vector2.new(0, 0.5)
	status.Position = UDim2.fromOffset(440, NAME_Y + NAME_H / 2)
	status.Parent = win.body

	cards = Window.frame(UDim2.fromOffset(Window.BODY.X, CARD_H), UDim2.fromOffset(0, CARDS_Y))
	local list = Kit.list(cards, Enum.FillDirection.Horizontal, GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	cards.Parent = win.body
	win.onOpen(render)

	Net.Characters.OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" or typeof(msg.list) ~= "table" then
			return
		end
		state = {
			active = tostring(msg.active or ""),
			max = if typeof(msg.max) == "number" then msg.max else Profile.MAX_CHARACTERS,
			list = msg.list,
		}
		if win.isOpen() then
			render()
		end
	end)
	Net.CharacterResult.OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then
			return
		end
		waiting = false
		if msg.ok then
			if msg.action == "setup" then
				win.close()
			end
		else
			say(tostring(msg.text or "Not possible"), C.Danger)
			if win.isOpen() then
				render()
			end
		end
	end)
end

function CharacterController.start()
	local function check()
		if setupPending() and not win.isOpen() then
			CharacterController.open()
		end
	end
	player:GetAttributeChangedSignal("SetupDone"):Connect(function()
		if win.isOpen() then
			render()
		end
		check()
	end)
	-- The setup cannot be skipped: closing it (or another window replacing it) reopens it
	win.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not win.gui.Enabled and setupPending() then
			task.delay(0.3, check)
		end
	end)
	Net.Character:FireServer("list")
	check()
end

return CharacterController
