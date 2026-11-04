--!strict
-- Heroes screen (docs/GAMEPLAY.md "Classes"): the account's characters and creating new ones.
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
local Shape = require(script.Parent.Parent.UI.Shape)
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
local HERO_W = 320
local PLAY_W = 112 -- Play button on a hero card
local NAME_Y = HEROES_H + 20
local NAME_H = 56
local CARDS_Y = NAME_Y + NAME_H + 20
local CARD_H = Window.BODY.Y - CARDS_Y
-- Class card: emblem + name block on a color wash, then the starting skills as icon rows
local PAD = 22
local EMBLEM = 92
local WASH_H = 170
local SKILLS_Y = PAD + EMBLEM + 44
local ROW_H = 50
local KEYS = { "Q", "E", "R", "F" }

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
		name.Size = UDim2.fromOffset(HERO_W - PLAY_W - 40, 30)
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.AnchorPoint = Vector2.new(0, 1)
		name.Position = UDim2.new(0, 16, 0.5, -2)
		name.Parent = card
		local info = Kit.label(
			string.format("%s - Lv %d", if class then class.hero else entry.class, entry.level),
			16,
			accent,
			Theme.Font.Body
		)
		info.Position = UDim2.new(0, 16, 0.5, 4)
		info.Parent = card
		local b = Kit.button(
			if mine then "Playing" else "Play",
			if mine then C.Muted else C.Gold,
			Vector2.new(PLAY_W, 56),
			nil
		)
		b.Name = "Play"
		-- Right side, vertically centered: grows around its center to touch size on phones
		-- and never covers the name
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -12, 0.5, 0)
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

		-- Class color washes down from the top; the signature skill sits in a glowing emblem
		local wash = Instance.new("Frame")
		wash.Name = "Wash"
		wash.BackgroundColor3 = accent
		wash.BorderSizePixel = 0
		wash.Size = UDim2.new(1, 0, 0, WASH_H)
		wash.ZIndex = 0
		Kit.corner(wash, Theme.Radius.L)
		Shape.gradient(wash, accent, accent, 0.72, 1)
		wash.Parent = card

		local kit = Skills.forClass(class.id)
		local signature = Skills.ById[kit.bar[1]] or kit.basic
		local emblem = Kit.itemSlot(
			EMBLEM,
			Kit.skillIcon(signature.id, signature.icon, class.id),
			{ rarity = "rare", tint = accent }
		)
		emblem.Name = "Emblem"
		emblem.Active = false
		emblem.Position = UDim2.fromOffset(PAD, PAD)
		Shape.glow(emblem, accent, 2, true)
		emblem.Parent = card

		-- Hero name big (short names fit even on phones), class and role below
		local textX = PAD + EMBLEM + 16
		local textW = w - textX - PAD
		local function fixed(t: TextLabel, y: number, h: number)
			t.AutomaticSize = Enum.AutomaticSize.None
			t.Size = UDim2.fromOffset(textW, h)
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Position = UDim2.fromOffset(textX, y)
			t.Parent = card
		end
		fixed(Window.heading(class.hero, 34, accent), PAD + 2, 40)
		fixed(Kit.label(class.name, 18, C.Text), PAD + 46, 26)
		fixed(Kit.label(class.role, 16, C.Muted, Theme.Font.Body), PAD + 74, 22)

		local head = Kit.label("STARTING SKILLS", 15, C.Gold)
		head.Position = UDim2.fromOffset(PAD, SKILLS_Y - 26)
		head.Parent = card
		local skills =
			Window.frame(UDim2.fromOffset(w - 2 * PAD, 5 * ROW_H), UDim2.fromOffset(PAD, SKILLS_Y))
		Kit.list(skills, Enum.FillDirection.Vertical, 0, Enum.VerticalAlignment.Top)
		local rows: { { skill: Skills.Skill, tag: string } } =
			{ { skill = kit.basic, tag = "Basic" } }
		for k, id in kit.bar do
			local sk = Skills.ById[id]
			if sk then
				-- new heroes unlock starting skills 3 and 4 at level 2 and 3 (Skills.StartUnlock)
				local at = Skills.StartUnlock[k] or 1
				table.insert(
					rows,
					{ skill = sk, tag = if at > 1 then "Lv " .. at else KEYS[k] or "" }
				)
			end
		end
		for k, r in rows do
			local row = Window.frame(UDim2.fromOffset(w - 2 * PAD, ROW_H))
			row.Name = r.skill.id
			row.LayoutOrder = k
			local ic = Kit.itemSlot(
				ROW_H - 8,
				Kit.skillIcon(r.skill.id, r.skill.icon, class.id),
				{ rarity = "normal" }
			)
			ic.Active = false
			ic.AnchorPoint = Vector2.new(0, 0.5)
			ic.Position = UDim2.fromScale(0, 0.5)
			ic.Parent = row
			local name = Kit.label(r.skill.name, 18, C.Text)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Size = UDim2.new(1, -(ROW_H + 60), 0, ROW_H)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.new(0, ROW_H + 4, 0.5, 0)
			name.Parent = row
			local tag = Kit.label(r.tag, 15, if k == 1 then C.Muted else accent)
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(1, 0, 0.5, 0)
			tag.Parent = row
			row.Parent = skills
		end
		skills.Parent = card
		local more = Kit.label("+4 more from level 8", 16, C.Muted, Theme.Font.Body)
		more.Position = UDim2.fromOffset(PAD, SKILLS_Y + 5 * ROW_H + 8)
		more.Parent = card

		local b = Kit.button(
			if pending then "Play " .. class.hero else "Create " .. class.hero,
			C.Gold,
			Vector2.new(w - 2 * PAD, 60),
			nil
		)
		b.Name = "Choose"
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -PAD)
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

	-- Up to 12 heroes: a sideways scrolling row (4 fit at once)
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
