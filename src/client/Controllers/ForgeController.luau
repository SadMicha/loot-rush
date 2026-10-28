--!strict
-- Schmiede-Fenster nach Mockup „Glitzer-Schmiede“ (Taste B oder Menü-Button):
--   links Gegenstand wählen und seine Affixe, Mitte der Gegenstand auf dem Amboss mit Status,
--   rechts die Aktionen mit Kosten. Gegenstände kommen aus dem Inventar-Schnappschuss.
-- Das Schmiede-System fehlt noch: Aktionen sind sichtbar, aber gesperrt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Forge = require(ReplicatedStorage.Shared.Forge)
local Items = require(ReplicatedStorage.Shared.Items)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local InventoryController = require(script.Parent.InventoryController)

local ForgeController = {}

local C = Theme.Color
local PAD = 28
local LEFT_W, SIDE_W, TOP = 440, 440, 100
local PICK = 64
local CENTER_W = 560

local win: Window.Window
local left: Frame
local center: Frame
local side: Frame

local selectedItem: string? = nil -- Item-ID
local selectedAffix: number? = nil

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

-- Angelegte zuerst, dann die Tasche
local function allItems(): { Items.Item }
	local bag, worn = InventoryController.snapshot()
	local list: { Items.Item } = {}
	for _, slot in Items.Slots do
		local it = worn[slot]
		if it then
			table.insert(list, it)
		end
	end
	for _, it in bag do
		table.insert(list, it)
	end
	return list
end

local function current(list: { Items.Item }): Items.Item?
	for _, it in list do
		if it.id == selectedItem then
			return it
		end
	end
	selectedItem = if list[1] then list[1].id else nil
	selectedAffix = nil
	return list[1]
end

local function wrapLabel(text: string, size: number, color: Color3, width: number): TextLabel
	local t = Kit.label(text, size, color, Theme.Font.Body)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromOffset(width, 0)
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	return t
end

-- ------------------------------------------------------------------ Links: Auswahl und Affixe
local function renderLeft(list: { Items.Item }, item: Items.Item?)
	clear(left)
	local w = LEFT_W - 2 * PAD

	local picker = Instance.new("ScrollingFrame")
	picker.BackgroundTransparency = 1
	picker.BorderSizePixel = 0
	picker.Position = UDim2.fromOffset(PAD, PAD)
	picker.Size = UDim2.fromOffset(w, PICK + 16)
	picker.ScrollingDirection = Enum.ScrollingDirection.X
	picker.ScrollBarThickness = 4
	picker.AutomaticCanvasSize = Enum.AutomaticSize.X
	picker.CanvasSize = UDim2.new()
	local pl = Kit.list(picker, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Top)
	pl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for i, it in list do
		local b = Kit.itemSlot(PICK, InventoryController.slotIcon(it.slot), {
			rarity = it.rarity,
			selected = item ~= nil and it.id == item.id,
		})
		b.LayoutOrder = i
		b.Activated:Connect(function()
			selectedItem = it.id
			selectedAffix = nil
			ForgeController.render()
		end)
		b.Parent = picker
	end
	picker.Parent = left

	if not item then
		local empty =
			wrapLabel("Keine Gegenstände. Sammle Beute im Rift und komm zurück.", 17, C.Muted, w)
		empty.Position = UDim2.fromOffset(PAD, PAD + 110)
		empty.Parent = left
		return
	end

	local divider = Kit.divider(w)
	divider.Position = UDim2.fromOffset(PAD, PAD + PICK + 24)
	divider.Parent = left

	local name = Window.heading(item.name, 22, Theme.Rarity[item.rarity] or C.Text)
	name.Position = UDim2.fromOffset(PAD, PAD + PICK + 48)
	name.Parent = left
	local max = Forge.MaxAffixes[item.rarity] or #item.affixes
	local sub = Kit.label(
		string.format(
			"%s · %s · %d/%d Affixe",
			Items.RarityName[item.rarity] or item.rarity,
			Items.SlotName[item.slot] or item.slot,
			#item.affixes,
			max
		),
		15,
		C.Muted,
		Theme.Font.Body
	)
	sub.Position = UDim2.fromOffset(PAD, PAD + PICK + 86)
	sub.Parent = left

	local rows = Window.frame(UDim2.fromOffset(w, 460), UDim2.fromOffset(PAD, PAD + PICK + 124))
	Kit.list(rows, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	for i, a in item.affixes do
		local on = selectedAffix == i
		local row = Instance.new("ImageButton")
		row.AutoButtonColor = false
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(w, 56)
		row.LayoutOrder = i
		Kit.skin(row, if on then "btn_sort" else "stat_tile", 56, 0.4)
		if on then
			Kit.stroke(row, C.Gold, 2)
			Kit.corner(row, Theme.Radius.M)
		end
		local t = Kit.label(Items.affixText(a), 17, if a.implicit then C.Gold else C.Text)
		t.AnchorPoint = Vector2.new(0, 0.5)
		t.Position = UDim2.new(0, 18, 0.5, 0)
		t.ZIndex = 2
		t.Parent = row
		row.Activated:Connect(function()
			selectedAffix = if on then nil else i
			ForgeController.render()
		end)
		row.Parent = rows
	end
	-- Freier Affix-Platz
	if #item.affixes < max then
		local free = Window.frame(UDim2.fromOffset(w, 56))
		free.LayoutOrder = #item.affixes + 1
		Kit.skin(free, "stat_tile", 56, 0.4)
		local plus = Kit.icon("verbessern", 28)
		plus.AnchorPoint = Vector2.new(0.5, 0.5)
		plus.Position = UDim2.fromScale(0.5, 0.5)
		plus.ZIndex = 2
		plus.Parent = free
		free.Parent = rows
	end
	rows.Parent = left
end

-- ------------------------------------------------------------------ Mitte: Amboss und Status
local function renderCenter(item: Items.Item?)
	clear(center)
	if item then
		local big = Kit.itemSlot(220, InventoryController.slotIcon(item.slot), {
			rarity = item.rarity,
		})
		big.Active = false
		big.AnchorPoint = Vector2.new(0.5, 0)
		big.Position = UDim2.new(0.5, 0, 0, 120)
		big.Parent = center
	end
	local anvil = Window.art("forge_anvil", Vector2.new(420, 260))
	if anvil then
		anvil.AnchorPoint = Vector2.new(0.5, 0)
		anvil.Position = UDim2.new(0.5, 0, 0, 300)
		anvil.Parent = center
	end

	-- Status-Tafel
	local plaque = Window.frame(UDim2.fromOffset(460, 158))
	plaque.AnchorPoint = Vector2.new(0.5, 0)
	plaque.Position = UDim2.new(0.5, 0, 0, 560)
	local plaqueArt = Window.art("plaque_status", Vector2.new(460, 158))
	if plaqueArt then
		plaqueArt.ScaleType = Enum.ScaleType.Stretch
		plaqueArt.Size = UDim2.fromScale(1, 1)
		plaqueArt.Parent = plaque
	else
		Kit.skin(plaque, "header_banner", 158, 0.5)
	end
	local ready = item ~= nil and selectedAffix ~= nil
	local head = Window.heading(
		if item == nil then "Leer" elseif ready then "Bereit" else "Wähle ein Affix",
		26,
		if ready then C.Good else C.GoldHi
	)
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.new(0.5, 0, 0, 38)
	head.ZIndex = 2
	head.Parent = plaque
	local sub =
		Kit.label("Die Schmiede öffnet bald – Aktionen folgen.", 15, C.Text, Theme.Font.Body)
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0, 88)
	sub.ZIndex = 2
	sub.Parent = plaque
	plaque.Parent = center
end

-- ------------------------------------------------------------------ Rechts: Aktionen
local function renderSide(item: Items.Item?)
	clear(side)
	local w = SIDE_W - 2 * PAD

	-- Gewähltes Affix oben
	local headBox = Window.frame(UDim2.fromOffset(w, 60), UDim2.fromOffset(PAD, PAD))
	Kit.skin(headBox, "btn_sort", 60, 0.5)
	local a = if item and selectedAffix then item.affixes[selectedAffix] else nil
	local headText = Kit.label(
		if a then Items.affixText(a) else "Kein Affix gewählt",
		18,
		if a then C.Text else C.Muted
	)
	headText.AnchorPoint = Vector2.new(0, 0.5)
	headText.Position = UDim2.new(0, 20, 0.5, 0)
	headText.ZIndex = 2
	headText.Parent = headBox
	headBox.Parent = side

	local rows = Window.frame(UDim2.fromOffset(w, 480), UDim2.fromOffset(PAD, PAD + 80))
	Kit.list(rows, Enum.FillDirection.Vertical, 12, Enum.VerticalAlignment.Top)
	for i, action in Forge.Actions do
		local row = Window.frame(UDim2.fromOffset(w, 96))
		row.LayoutOrder = i
		Kit.skin(row, "stat_tile", 96, 0.4)
		local ic = Kit.itemSlot(68, action.icon, { rarity = "normal" })
		ic.Active = false
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 12, 0.5, 0)
		ic.ZIndex = 2
		ic.Parent = row
		local n = Kit.label(action.name, 19, C.Text)
		n.Position = UDim2.fromOffset(94, 18)
		n.ZIndex = 2
		n.Parent = row
		local cost = Kit.label(
			string.format("%d %s", action.cost, action.currency),
			14,
			C.Gold,
			Theme.Font.Body
		)
		cost.Position = UDim2.fromOffset(94, 54)
		cost.ZIndex = 2
		cost.Parent = row
		local go = Kit.button("", C.Gold, Vector2.new(68, 60), nil)
		local hammer = Kit.icon("schmiede", 36)
		hammer.AnchorPoint = Vector2.new(0.5, 0.5)
		hammer.Position = UDim2.fromScale(0.5, 0.5)
		hammer.ZIndex = 3
		hammer.Parent = go
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -14, 0.5, 0)
		go.ZIndex = 2
		Kit.setEnabled(go, false) -- Schmiede-System folgt
		go.Parent = row
		row.Parent = rows
	end
	rows.Parent = side

	local note = wrapLabel(
		"Vorschau: Schmieden wird mit dem Schmiede-System freigeschaltet.",
		14,
		C.Muted,
		w
	)
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, PAD, 1, -PAD)
	note.Parent = side
end

-- ------------------------------------------------------------------ Ablauf
function ForgeController.render()
	local list = allItems()
	local item = current(list)
	renderLeft(list, item)
	renderCenter(item)
	renderSide(item)
end

function ForgeController.toggle()
	win.toggle()
end

function ForgeController.init()
	win = Window.new({
		name = "Forge",
		title = "Glitzer-Schmiede",
		icon = "schmiede",
		key = Enum.KeyCode.B,
		background = "bg_forge",
	})

	left = Kit.panel(Vector2.new(LEFT_W, 770))
	left.Position = UDim2.fromOffset(40, TOP)
	left.Parent = win.root

	center = Window.frame(UDim2.fromOffset(CENTER_W, 770), UDim2.fromOffset(40 + LEFT_W + 20, TOP))
	center.Parent = win.root

	side = Kit.panel(Vector2.new(SIDE_W, 770))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.new(1, -40, 0, TOP)
	side.Parent = win.root

	win.onOpen(ForgeController.render)
	InventoryController.changed:Connect(function()
		if win.isOpen() then
			ForgeController.render()
		end
	end)
	ForgeController.render()
end

return ForgeController
