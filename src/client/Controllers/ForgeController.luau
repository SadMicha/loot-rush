--!strict
-- Schmiede-Fenster nach Mockup „Glitzer-Schmiede“ (Taste B oder Menü-Button):
--   links Gegenstand wählen und seine Affixe, Mitte der Gegenstand auf dem Amboss mit Status,
--   rechts die Aktionen mit Kosten. Gegenstände kommen aus dem Inventar-Schnappschuss.
-- Geschmiedet wird auf dem Server (Systems/Forge): das Fenster schickt Aktion + Item + Affix (Net.ForgeAct),
-- zeigt Material aus ProgressController und die Rückmeldung (Net.ForgeResult).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Forge = require(ReplicatedStorage.Shared.Forge)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local InventoryController = require(script.Parent.InventoryController)
local ProgressController = require(script.Parent.ProgressController)

local ForgeController = {}

local C = Theme.Color
local PAD = 28
local LEFT_W, SIDE_W = 440, 440
local PICK = 88 -- so hoch wie ein Knopf auf dem Handy mindestens wird, sonst schneidet die Leiste ab
local CENTER_W = 600

local win: Window.Window
local left: Frame
local center: Frame
local side: Frame

local selectedItem: string? = nil -- Item-ID
local selectedAffix: number? = nil
local lastResult: { ok: boolean, text: string }? = nil
local MAT_COLOR: { [string]: Color3 } =
	{ candy = Theme.Rarity.epic, shards = C.Cyan, dust = C.Gold }

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

	-- Leiste zum Wischen: Balken unter den Slots, damit man sieht, dass es weitergeht
	local picker = Instance.new("ScrollingFrame")
	picker.BackgroundTransparency = 1
	picker.BorderSizePixel = 0
	picker.Position = UDim2.fromOffset(PAD, PAD)
	picker.Size = UDim2.fromOffset(w, PICK + 30)
	picker.ScrollingDirection = Enum.ScrollingDirection.X
	picker.ScrollBarThickness = 8
	picker.ScrollBarImageColor3 = C.Gold
	picker.ScrollBarImageTransparency = 0.2
	picker.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	picker.AutomaticCanvasSize = Enum.AutomaticSize.X
	picker.CanvasSize = UDim2.new()
	local inset = Instance.new("UIPadding") -- Platz für den Auswahl-Glanz um den Slot
	inset.PaddingTop = UDim.new(0, 8)
	inset.PaddingLeft = UDim.new(0, 8)
	inset.PaddingRight = UDim.new(0, 8)
	inset.Parent = picker
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
			lastResult = nil
			ForgeController.render()
		end)
		b.Parent = picker
	end
	picker.Parent = left

	if not item then
		local empty =
			wrapLabel("Keine Gegenstände. Sammle Beute im Rift und komm zurück.", 17, C.Muted, w)
		empty.Position = UDim2.fromOffset(PAD, PAD + PICK + 40)
		empty.Parent = left
		return
	end

	-- Darunter alles untereinander, damit ein zweizeiliger Name den Rest nach unten schiebt
	local info = Window.frame(UDim2.fromOffset(w, 0), UDim2.fromOffset(PAD, PAD + PICK + 40))
	info.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(info, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	info.Parent = left

	local divider = Kit.divider(w)
	divider.LayoutOrder = 1
	divider.Parent = info

	local name = Window.heading(item.name, 22, Theme.Rarity[item.rarity] or C.Text)
	name.AutomaticSize = Enum.AutomaticSize.Y
	name.Size = UDim2.fromOffset(w, 0)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.LayoutOrder = 2
	name.Parent = info
	local max = Forge.MaxAffixes[item.rarity] or 0
	local open = Forge.openCount(item)
	local sub = Kit.label(
		string.format(
			"%s · %s · %d/%d Affixe",
			Items.RarityName[item.rarity] or item.rarity,
			Items.SlotName[item.slot] or item.slot,
			open,
			max
		),
		15,
		C.Muted,
		Theme.Font.Body
	)
	sub.LayoutOrder = 3
	sub.Parent = info

	local rows = Window.frame(UDim2.fromOffset(w, 0))
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.LayoutOrder = 4
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
		-- Tier rechts, Schloss bei versiegelten; Grundwerte lassen sich nicht schmieden
		local tag = Kit.label(
			if a.implicit then "Grundwert" else "T" .. tostring(Items.tierOf(a)),
			15,
			if a.implicit then C.Muted else C.Cyan
		)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, if a.sealed then -54 else -18, 0.5, 0)
		tag.ZIndex = 2
		tag.Parent = row
		if a.sealed then
			local lock = Kit.icon("schloss", 26)
			lock.AnchorPoint = Vector2.new(1, 0.5)
			lock.Position = UDim2.new(1, -16, 0.5, 0)
			lock.ZIndex = 2
			lock.Parent = row
		end
		row.Activated:Connect(function()
			if a.implicit then
				return
			end
			selectedAffix = if on then nil else i
			lastResult = nil
			ForgeController.render()
		end)
		row.Parent = rows
	end
	-- Freie Affix-Plätze (mit „Affix hinzufügen“ füllen)
	if open < max then
		local free = Window.frame(UDim2.fromOffset(w, 56))
		free.LayoutOrder = #item.affixes + 1
		Kit.skin(free, "stat_tile", 56, 0.4)
		local plus = Kit.icon("verbessern", 28)
		plus.AnchorPoint = Vector2.new(0, 0.5)
		plus.Position = UDim2.new(0, 14, 0.5, 0)
		plus.ZIndex = 2
		plus.Parent = free
		local t = Kit.label(
			if max - open == 1
				then "Freier Platz"
				else string.format("%d freie Plätze", max - open),
			15,
			C.Muted,
			Theme.Font.Body
		)
		t.AnchorPoint = Vector2.new(0, 0.5)
		t.Position = UDim2.new(0, 52, 0.5, 0)
		t.ZIndex = 2
		t.Parent = free
		free.Parent = rows
	end
	rows.Parent = info
end

-- ------------------------------------------------------------------ Mitte: Amboss und Status
local function renderCenter(item: Items.Item?)
	clear(center)
	-- Material oben: Kapsel mit Menge, Name darunter
	local mats = Window.frame(UDim2.fromOffset(CENTER_W, 70))
	Kit.list(mats, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Top)
	for i, key in { "candy", "shards", "dust" } do
		local have = (ProgressController.materials() :: any)[key] :: number
		local col = Window.frame(UDim2.fromOffset(190, 70))
		col.LayoutOrder = i
		local pill, _, plus = Kit.pill(Forge.MaterialIcon[key], tostring(have), MAT_COLOR[key])
		if plus then
			plus:Destroy()
		end
		pill.Parent = col
		local cap = Kit.label(Forge.MaterialPlural[key], 14, C.Muted, Theme.Font.Body)
		cap.AnchorPoint = Vector2.new(0.5, 1)
		cap.Position = UDim2.fromScale(0.5, 1)
		cap.Parent = col
		col.Parent = mats
	end
	mats.Parent = center
	if item then
		local big = Kit.itemSlot(220, InventoryController.slotIcon(item.slot), {
			rarity = item.rarity,
		})
		big.Active = false
		big.AnchorPoint = Vector2.new(0.5, 0)
		big.Position = UDim2.new(0.5, 0, 0, 100)
		big.Parent = center
	end
	local anvil = Window.art("forge_anvil", Vector2.new(420, 260))
	if anvil then
		anvil.AnchorPoint = Vector2.new(0.5, 0)
		anvil.Position = UDim2.new(0.5, 0, 0, 290)
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
	local charges = if item then Items.chargesOf(item) else 0
	local ready = item ~= nil and charges > 0
	local head = Window.heading(
		if item == nil then "Leer" elseif ready then "Bereit" else "Fertig geschmiedet",
		26,
		if ready then C.Good else C.GoldHi
	)
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.new(0.5, 0, 0, 38)
	head.ZIndex = 2
	head.Parent = plaque
	local subText = if lastResult
		then lastResult.text
		elseif item then string.format(
			"Glitzer-Ladungen: %d · jede Aktion kostet 0–2",
			charges
		)
		else "Wähle einen Gegenstand"
	local sub = Kit.label(
		subText,
		15,
		if lastResult and not lastResult.ok then C.Danger else C.Text,
		Theme.Font.Body
	)
	sub.AutomaticSize = Enum.AutomaticSize.Y
	sub.Size = UDim2.fromOffset(400, 0)
	sub.TextWrapped = true
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0, 84)
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
		-- Text endet vor dem Amboss-Knopf rechts
		local textW = w - 94 - 96
		local n = Kit.label(action.name, 19, C.Text)
		n.Position = UDim2.fromOffset(94, 12)
		n.ZIndex = 2
		n.Parent = row
		local price = Forge.cost(action, item, selectedAffix)
		local cost = Kit.label(
			string.format(
				"%d %s",
				price,
				if price == 1
					then Forge.MaterialName[action.material]
					else Forge.MaterialPlural[action.material]
			),
			14,
			C.Gold,
			Theme.Font.Body
		)
		cost.AutomaticSize = Enum.AutomaticSize.None
		cost.Size = UDim2.fromOffset(textW, 20)
		cost.TextXAlignment = Enum.TextXAlignment.Left
		cost.TextTruncate = Enum.TextTruncate.AtEnd
		cost.Position = UDim2.fromOffset(94, 42)
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
		local ok, why = false, nil
		if item then
			ok, why = Forge.check(action.id, item, selectedAffix, ProgressController.materials())
		end
		Kit.setEnabled(go, ok)
		go.Activated:Connect(function()
			if go.Active and item then
				Net.ForgeAct:FireServer(action.id, item.id, selectedAffix)
			end
		end)
		go.Parent = row
		if why and item then
			-- Grund in eigener Zeile unter den Kosten
			cost.TextColor3 = C.Muted
			local reason = Kit.label(why, 13, C.Danger, Theme.Font.Body)
			reason.AutomaticSize = Enum.AutomaticSize.None
			reason.Size = UDim2.fromOffset(textW, 18)
			reason.TextXAlignment = Enum.TextXAlignment.Left
			reason.TextTruncate = Enum.TextTruncate.AtEnd
			reason.Position = UDim2.fromOffset(94, 66)
			reason.ZIndex = 2
			reason.Parent = row
		end
		row.Parent = rows
	end
	rows.Parent = side

	local note = wrapLabel(
		"Material: Verwerten im Inventar und Bosse. Versiegeln kostet keine Ladung.",
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

	local body = Window.BODY
	left = Kit.panel(Vector2.new(LEFT_W, body.Y))
	left.Parent = win.body

	-- Amboss mittig zwischen den Panels
	center = Window.frame(UDim2.fromOffset(CENTER_W, body.Y))
	center.AnchorPoint = Vector2.new(0.5, 0)
	center.Position = UDim2.fromOffset(LEFT_W + (body.X - LEFT_W - SIDE_W) / 2, 0)
	center.Parent = win.body

	side = Kit.panel(Vector2.new(SIDE_W, body.Y))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Parent = win.body

	win.onOpen(ForgeController.render)
	local function refresh()
		if win.isOpen() then
			ForgeController.render()
		end
	end
	InventoryController.changed:Connect(refresh)
	ProgressController.changed:Connect(refresh)
	Net.ForgeResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" or typeof(data.text) ~= "string" then
			return
		end
		lastResult = { ok = data.ok == true, text = data.text }
		if data.ok == true and data.itemId == selectedItem then
			-- Neues Affix: nichts gewählt lassen; sonst bleibt die Auswahl am selben Platz
			local list = allItems()
			local it = current(list)
			if it and selectedAffix and not it.affixes[selectedAffix] then
				selectedAffix = nil
			end
		end
		refresh()
	end)
	ForgeController.render()
end

return ForgeController
