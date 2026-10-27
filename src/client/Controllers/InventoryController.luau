--!strict
-- Inventar-Fenster nach Mockup „Inventar“ (Taste I oder Menü-Button):
--   links Ausrüstung mit 3D-Figur und Werten, Mitte Raster mit Filter/Sortierung, rechts Details.
-- Zeigt nur den Schnappschuss vom Server (Net.Inv); jede Aktion ist eine Anfrage an den Server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)

local InventoryController = {}

local C = Theme.Color
local player = Players.LocalPlayer

local MAX_ITEMS = 40 -- wie Server (Systems/Inventory)
local COLUMNS, CELL, GAP = 6, 76, 8
local PAD = 28

-- Icon je Ausrüstungsplatz (Assets.Icon)
local SLOT_ICON: { [string]: string } = {
	helm = "slot_helm",
	ruestung = "slot_brust",
	waffe = "slot_stab",
	amulett = "slot_amulett",
	ring = "slot_ring",
}
local STAT_ICON: { [string]: string } = {
	damage = "schwert",
	life = "leben",
	crit = "ziel",
	speed = "skill_dash",
}
local STAT_ORDER = { "damage", "life", "crit", "speed" }
local RARITY_RANK: { [string]: number } = { normal = 1, magic = 2, rare = 3, epic = 4 }

local gui: ScreenGui
local equipPanel: Frame
local gridFrame: ScrollingFrame
local tabRow: Frame
local detail: Frame
local countLabel: TextLabel
local ilvlLabel: TextLabel
local statLabels: { [string]: TextLabel } = {}
local viewport: ViewportFrame

local items: { Items.Item } = {}
local equipped: { [string]: Items.Item } = {}
local selected: Items.Item? = nil
local selectedEquipped = false
local filter: string? = nil -- nil = alle Plätze
local sortByLevel = false

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

local function statTotals(list: { [any]: Items.Item }): { [string]: number }
	local t: { [string]: number } = {}
	for _, item in list do
		for _, a in item.affixes do
			t[a.stat] = (t[a.stat] or 0) + a.value
		end
	end
	return t
end

local function fmt(v: number): string
	local s = if v == math.floor(v) then tostring(v) else string.format("%.1f", v)
	return (s:gsub("%.", ","))
end

local function title(parent: GuiObject, text: string)
	local t = Kit.label(string.upper(text), 26, C.Text, Theme.Font.Title)
	t.Position = UDim2.fromOffset(PAD, 22)
	t.Parent = parent
end

-- ------------------------------------------------------------------ Ausrüstung (links)
local function refreshViewport()
	for _, child in viewport:GetChildren() do
		child:Destroy()
	end
	local character = player.Character
	if not character then
		return
	end
	local was = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = was
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180 - 20), 0))
	clone.Parent = world
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1, -11), Vector3.new(0, 0.3, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function renderEquip()
	for _, child in equipPanel:GetChildren() do
		if child.Name == "Slot" then
			child:Destroy()
		end
	end
	local left = { "helm", "ruestung", "waffe" }
	local right = { "amulett", "ring" }
	local function place(slot: string, x: number, i: number)
		local item = equipped[slot]
		local b = Kit.itemSlot(84, SLOT_ICON[slot], {
			rarity = if item then item.rarity else nil,
			selected = item ~= nil and selected ~= nil and selected.id == item.id,
			dim = item == nil,
		})
		b.Position = UDim2.fromOffset(x, 80 + (i - 1) * 100)
		if item then
			b.Activated:Connect(function()
				selected = item
				selectedEquipped = true
				InventoryController.render()
			end)
		end
		b.Parent = equipPanel
	end
	for i, slot in left do
		place(slot, PAD, i)
	end
	for i, slot in right do
		place(slot, 440 - PAD - 84, i)
	end

	local totals = statTotals(equipped)
	for stat, label in statLabels do
		local info = Items.Stats[stat]
		label.Text = "+" .. fmt(totals[stat] or 0) .. (if info then info.unit else "")
	end
	local sum, n = 0, 0
	for _, item in equipped do
		sum += item.ilvl
		n += 1
	end
	ilvlLabel.Text = if n > 0 then tostring(math.floor(sum / n + 0.5)) else "–"
end

local function buildEquip(parent: Frame)
	equipPanel = Kit.panel(Vector2.new(440, 760))
	equipPanel.Parent = parent
	title(equipPanel, "Ausrüstung")

	local lvl = Instance.new("Frame")
	lvl.BackgroundTransparency = 1
	lvl.AnchorPoint = Vector2.new(1, 0)
	lvl.Position = UDim2.new(1, -PAD, 0, 26)
	lvl.AutomaticSize = Enum.AutomaticSize.X
	lvl.Size = UDim2.fromOffset(0, 26)
	Kit.list(lvl, Enum.FillDirection.Horizontal, 6)
	local ic = Kit.icon("itemstufe", 24)
	ic.LayoutOrder = 1
	ic.Parent = lvl
	ilvlLabel = Kit.label("–", 20, C.Gold)
	ilvlLabel.LayoutOrder = 2
	ilvlLabel.Parent = lvl
	lvl.Parent = equipPanel

	viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(PAD + 96, 76)
	viewport.Size = UDim2.fromOffset(440 - 2 * (PAD + 96), 380)
	viewport.Ambient = Color3.fromRGB(170, 175, 200)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.Parent = equipPanel
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, 76 + 360)
	glow.Size = UDim2.fromOffset(170, 26)
	glow.BackgroundColor3 = C.Cyan
	glow.BackgroundTransparency = 0.75
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	Kit.corner(glow, 13)
	Kit.stroke(glow, C.Cyan, 2)
	glow.Parent = equipPanel

	-- Werte 2×2
	for i, stat in STAT_ORDER do
		local tile = Instance.new("Frame")
		tile.Size = UDim2.fromOffset(184, 56)
		tile.Position = UDim2.fromOffset(PAD + ((i - 1) % 2) * 200, 500 + ((i - 1) // 2) * 68)
		tile.BackgroundColor3 = C.Bg2
		tile.BorderSizePixel = 0
		if not Kit.skin(tile, "stat_tile", 56, 0.5) then
			Kit.corner(tile, Theme.Radius.M)
			Kit.stroke(tile, C.Line)
		end
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 12)
		p.Parent = tile
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.VerticalAlignment = Enum.VerticalAlignment.Center
		l.Padding = UDim.new(0, 10)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = tile
		local sic = Kit.icon(STAT_ICON[stat], 30)
		sic.LayoutOrder = 1
		sic.Parent = tile
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.AutomaticSize = Enum.AutomaticSize.XY
		col.LayoutOrder = 2
		local cl = Instance.new("UIListLayout")
		cl.SortOrder = Enum.SortOrder.LayoutOrder
		cl.Parent = col
		local v = Kit.label("+0", 20, C.Text)
		v.LayoutOrder = 1
		v.Parent = col
		local info = Items.Stats[stat]
		local n = Kit.label(if info then info.label else stat, 13, C.Muted, Theme.Font.Body)
		n.LayoutOrder = 2
		n.Parent = col
		col.Parent = tile
		statLabels[stat] = v
		tile.Parent = equipPanel
	end
end

-- ------------------------------------------------------------------ Raster (Mitte)
local function sorted(): { Items.Item }
	local list: { Items.Item } = {}
	for _, item in items do
		if not filter or item.slot == filter then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		if sortByLevel and a.ilvl ~= b.ilvl then
			return a.ilvl > b.ilvl
		end
		local ra, rb = RARITY_RANK[a.rarity] or 0, RARITY_RANK[b.rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		return a.ilvl > b.ilvl
	end)
	return list
end

local function renderTabs()
	clear(tabRow)
	local function tab(slot: string?, order: number)
		local icon = if slot then SLOT_ICON[slot] else "beutel"
		local b = Kit.iconButton(icon, slot or "Alle", 60, slot == filter, "tab")
		b.LayoutOrder = order
		b.Activated:Connect(function()
			filter = slot
			InventoryController.render()
		end)
		b.Parent = tabRow
	end
	tab(nil, 0)
	for i, slot in Items.Slots do
		tab(slot, i)
	end
end

local function renderGrid()
	clear(gridFrame)
	local list = sorted()
	for i, item in list do
		local b = Kit.itemSlot(CELL, SLOT_ICON[item.slot], {
			rarity = item.rarity,
			selected = selected ~= nil and not selectedEquipped and selected.id == item.id,
		})
		b.LayoutOrder = i
		b.Activated:Connect(function()
			selected = item
			selectedEquipped = false
			InventoryController.render()
		end)
		b.Parent = gridFrame
	end
	local rows = math.ceil(#list / COLUMNS)
	gridFrame.CanvasSize = UDim2.fromOffset(0, rows * (CELL + GAP))
	countLabel.Text = string.format("%d / %d", #items, MAX_ITEMS)
end

local function buildGrid(parent: Frame)
	local panel = Kit.panel(Vector2.new(560, 760))
	panel.Parent = parent
	title(panel, "Inventar")

	local count = Instance.new("Frame")
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -PAD, 0, 24)
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromOffset(0, 30)
	Kit.list(count, Enum.FillDirection.Horizontal, 8)
	local ic = Kit.icon("beutel", 28)
	ic.LayoutOrder = 1
	ic.Parent = count
	countLabel = Kit.label("0 / 40", 20, C.Text)
	countLabel.LayoutOrder = 2
	countLabel.Parent = count
	count.Parent = panel

	tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(PAD, 76)
	tabRow.Size = UDim2.fromOffset(560 - 2 * PAD, 60)
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 8)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = tabRow
	tabRow.Parent = panel

	local sort = Kit.button("Sortieren: Seltenheit", C.Cyan, Vector2.new(260, 44), "sortieren")
	Kit.buttonLabel(sort).TextSize = 16
	sort.Position = UDim2.fromOffset(PAD, 150)
	sort.Activated:Connect(function()
		sortByLevel = not sortByLevel
		Kit.buttonLabel(sort).Text = if sortByLevel
			then "Sortieren: Stufe"
			else "Sortieren: Seltenheit"
		InventoryController.render()
	end)
	sort.Parent = panel

	gridFrame = Instance.new("ScrollingFrame")
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.Position = UDim2.fromOffset(PAD, 212)
	gridFrame.Size = UDim2.fromOffset(560 - 2 * PAD + 12, 760 - 212 - PAD)
	gridFrame.ScrollBarThickness = 6
	gridFrame.ScrollBarImageColor3 = C.Line2
	gridFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gridFrame
	gridFrame.Parent = panel
end

-- ------------------------------------------------------------------ Details (rechts)
local function chip(text: string, good: boolean, order: number): Frame
	local color = if good then C.Good else C.Danger
	local f = Instance.new("Frame")
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 32)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.85
	f.BorderSizePixel = 0
	f.LayoutOrder = order
	if not Kit.skin(f, if good then "chip_green" else "chip_red", 32, 0.5) then
		Kit.corner(f, 16)
		Kit.stroke(f, color)
	end
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 12)
	p.PaddingRight = UDim.new(0, 12)
	p.Parent = f
	local t = Kit.label(text, 15, color)
	t.Size = UDim2.fromScale(0, 1)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Parent = f
	return f
end

local function renderDetail()
	clear(detail)
	local item = selected
	if not item then
		local hint = Kit.label("Wähle einen Gegenstand", 18, C.Muted, Theme.Font.Body)
		hint.AnchorPoint = Vector2.new(0.5, 0.5)
		hint.Position = UDim2.fromScale(0.5, 0.45)
		hint.Parent = detail
		return
	end
	local color = Theme.Rarity[item.rarity] or Theme.Rarity.normal

	local big = Kit.itemSlot(110, SLOT_ICON[item.slot], { rarity = item.rarity })
	big.Active = false
	big.Position = UDim2.fromOffset(PAD, PAD)
	big.Parent = detail

	local name = Kit.label(item.name, 24, color, Theme.Font.Title)
	name.Position = UDim2.fromOffset(PAD + 126, PAD + 4)
	name.AutomaticSize = Enum.AutomaticSize.Y
	name.Size = UDim2.fromOffset(420 - 2 * PAD - 126, 0)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = detail
	local sub = Kit.label(
		string.format(
			"%s · %s · Stufe %d",
			Items.RarityName[item.rarity] or item.rarity,
			Items.SlotName[item.slot] or item.slot,
			item.ilvl
		),
		15,
		C.Muted,
		Theme.Font.Body
	)
	sub.Position = UDim2.fromOffset(PAD + 126, PAD + 74)
	sub.Parent = detail

	-- Vergleich mit dem angelegten Teil am selben Platz
	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.fromOffset(PAD, PAD + 128)
	chips.Size = UDim2.fromOffset(420 - 2 * PAD, 32)
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.Padding = UDim.new(0, 8)
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = chips
	chips.Parent = detail
	local current = equipped[item.slot]
	if not selectedEquipped then
		local mine = statTotals({ item })
		local theirs = if current then statTotals({ current }) else {}
		for i, stat in STAT_ORDER do
			local d = (mine[stat] or 0) - (theirs[stat] or 0)
			if math.abs(d) >= 0.05 then
				local info = Items.Stats[stat]
				local text = fmt(math.abs(d))
					.. (if info then info.unit .. " " .. info.label else "")
				chip(if d > 0 then "+" .. text else "−" .. text, d > 0, i).Parent = chips
			end
		end
	end

	-- Affixe mit Balken (Wurfqualität)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(PAD, PAD + 180)
	list.Size = UDim2.fromOffset(420 - 2 * PAD, 300)
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 14)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	list.Parent = detail
	for i, a in item.affixes do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = i
		local t = Kit.label(Items.affixText(a), 18, if a.implicit then C.Gold else C.Text)
		t.Parent = row
		local back, fill = Kit.bar(Vector2.new(420 - 2 * PAD, 4), C.Gold)
		back.Position = UDim2.new(0, 0, 1, -4)
		fill.Size = UDim2.fromScale(Items.affixQuality(a, item.ilvl), 1)
		back.Parent = row
		row.Parent = list
	end
	if #item.affixes == 0 then
		Kit.label("Keine Werte", 16, C.Muted, Theme.Font.Body).Parent = list
	end

	-- Aktionen unten
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(0, 1)
	actions.Position = UDim2.new(0, PAD, 1, -PAD)
	actions.Size = UDim2.fromOffset(420 - 2 * PAD, 130)
	local al = Instance.new("UIListLayout")
	al.Padding = UDim.new(0, 12)
	al.SortOrder = Enum.SortOrder.LayoutOrder
	al.Parent = actions
	actions.Parent = detail
	local w = 420 - 2 * PAD
	if selectedEquipped then
		local b = Kit.button("Ablegen", C.Cyan, Vector2.new(w, 60), "neu_wuerfeln")
		Kit.buttonLabel(b).TextSize = 22
		b.Activated:Connect(function()
			Net.Unequip:FireServer(item.slot)
			selected = nil
		end)
		b.Parent = actions
	else
		local b = Kit.button("Ausrüsten", C.Gold, Vector2.new(w, 60), "verbessern")
		Kit.buttonLabel(b).TextSize = 22
		b.LayoutOrder = 1
		b.Activated:Connect(function()
			Net.Equip:FireServer(item.id)
			selected = nil
		end)
		b.Parent = actions
		local s = Kit.button(
			"Verkaufen · " .. tostring(Items.sellValue(item)) .. " Gold",
			C.Danger,
			Vector2.new(w, 50),
			"verwerten"
		)
		s.LayoutOrder = 2
		s.Activated:Connect(function()
			Net.Sell:FireServer(item.id)
			selected = nil
		end)
		s.Parent = actions
	end
end

local function buildDetail(parent: Frame)
	detail = Kit.panel(Vector2.new(420, 760))
	detail.Parent = parent
end

-- ------------------------------------------------------------------ Ablauf
function InventoryController.render()
	-- Auswahl verschwunden (verkauft/angelegt)? Dann Details leeren
	if selected then
		local still = false
		for _, it in items do
			still = still or it.id == selected.id
		end
		for _, it in equipped do
			still = still or it.id == selected.id
		end
		if not still then
			selected = nil
		end
	end
	renderTabs()
	renderGrid()
	renderEquip()
	renderDetail()
end

function InventoryController.toggle()
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		refreshViewport()
	end
end

function InventoryController.init()
	local root: Frame
	gui, root = Kit.scaledGui("LootRushInventory", 5)
	gui.Enabled = false

	local window = Instance.new("Frame")
	window.BackgroundTransparency = 1
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.new(0.5, 40, 0.5, 20)
	window.Size = UDim2.fromOffset(440 + 560 + 420 + 2 * 16, 760)
	local wl = Instance.new("UIListLayout")
	wl.FillDirection = Enum.FillDirection.Horizontal
	wl.Padding = UDim.new(0, 16)
	wl.SortOrder = Enum.SortOrder.LayoutOrder
	wl.Parent = window
	window.Parent = root

	buildEquip(window)
	equipPanel.LayoutOrder = 1
	buildGrid(window)
	buildDetail(window)
	detail.LayoutOrder = 3
	for _, child in window:GetChildren() do
		if child:IsA("Frame") and child.LayoutOrder == 0 then
			child.LayoutOrder = 2
		end
	end

	local close = Kit.iconButton("schliessen", "Schließen", 48, false, "close")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -28, 0, 24)
	close.Activated:Connect(InventoryController.toggle)
	close.Parent = root

	InventoryController.render()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function InventoryController.start()
	Net.Inv.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then
			return
		end
		items = data.items or {}
		equipped = data.equipped or {}
		InventoryController.render()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.I then
			InventoryController.toggle()
		end
	end)
end

return InventoryController
