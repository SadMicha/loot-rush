--!strict
-- Class picker (docs/CLASSES.md): opens by itself on the first join (attribute ClassChosen =
-- false) and from the Abilities window ("Change class", hub only). Four cards with the hero,
-- the role and the starting skills; the server (Systems/ClassChoice) validates the choice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Net = require(ReplicatedStorage.Shared.Net)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)

local ClassController = {}

local C = Theme.Color
local player = Players.LocalPlayer
local win: Window.Window
local cards: Frame

local GAP = 24
local CARD_H = 600

local function current(): string
	return Classes.valid(player:GetAttribute("Class"))
end

local function render()
	for _, child in cards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local n = #Classes.List
	local w = (Window.BODY.X - GAP * (n - 1)) / n
	local chosen = player:GetAttribute("ClassChosen") == true
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
		text.Size = UDim2.fromOffset(w - 48, 300)
		text.Position = UDim2.fromOffset(24, 110)
		text.Parent = card

		local mine = chosen and class.id == current()
		local b = Kit.button(
			if mine then "Current class" else "Play " .. class.hero,
			if mine then C.Muted else C.Gold,
			Vector2.new(w - 48, 64),
			nil
		)
		b.Name = "Choose"
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -24)
		Kit.setEnabled(b, not mine)
		b.Activated:Connect(function()
			if b.Active then
				Net.Class:FireServer("choose", class.id)
				win.close()
			end
		end)
		b.Parent = card
		card.Parent = cards
	end
end

-- Opens the picker (Abilities window button); the server refuses changes during a rift
function ClassController.open()
	render()
	if not win.isOpen() then
		win.toggle()
	end
end

function ClassController.init()
	win = Window.new({ name = "Class", title = "Choose your hero", icon = "crown" })
	cards = Window.frame(UDim2.fromOffset(Window.BODY.X, CARD_H))
	cards.AnchorPoint = Vector2.new(0, 0.5)
	cards.Position = UDim2.fromScale(0, 0.5)
	local list = Kit.list(cards, Enum.FillDirection.Horizontal, GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	cards.Parent = win.body
	win.onOpen(render)
end

function ClassController.start()
	local function check()
		if player:GetAttribute("ClassChosen") == false and not win.isOpen() then
			ClassController.open()
		end
	end
	player:GetAttributeChangedSignal("ClassChosen"):Connect(check)
	player:GetAttributeChangedSignal("Class"):Connect(function()
		if win.isOpen() then
			render()
		end
	end)
	check()
end

return ClassController
