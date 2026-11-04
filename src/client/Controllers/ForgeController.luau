--!strict
-- Forge window (key B or menu button), one flow from left to right:
--   1. left: pick an item in a grid (tabs All / Worn / Bag, sort and rarity filter). Only items of
--      the current hero's class are listed. Cells show Forge charges left and a gold diamond on
--      worn gear; they fade when no action works on the item right now.
--   2. right: the item, four action tiles and its affixes (tap one when the action needs it)
--   3. bottom right: what happens (before -> after), the cost and one Forge button.
-- The window opens with the best candidate, action and affix already chosen (Shared/Forge
-- suggest*). Forging happens on the server (Systems/Forge): the window only sends
-- action + item + affix (Net.ForgeAct) and shows the feedback (Net.ForgeResult).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Forge = require(ReplicatedStorage.Shared.Forge)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local InventoryController = require(script.Parent.InventoryController)
local ProgressController = require(script.Parent.ProgressController)

local ForgeController = {}

local C = Theme.Color
local F = Theme.Flat

-- Layout in design pixels (Window.BODY = 1520 × 790)
local PAD = 24
local LEFT_W = 620
local GAP_X = 20
local TAB_H = 52
local FOOT_H = 56
local CELL, CELL_GAP, GRID_PAD = 100, 12, 10
local ACTION_H = 84
local AFFIX_H, AFFIX_GAP = 84, 8 -- 84 design px = touch size on the smallest phones
local BAR_H = 120
local HEAD = 100 -- item cell in the header

local win: Window.Window
local left: Frame
local right: Frame
local grid: ScrollingFrame
local tabs: Flat.Tabs
local sortLabel: TextLabel
local filterLabel: TextLabel
local countLabel: TextLabel
local detail: Frame -- right side content, rebuilt on every render

local view = "all" -- "all" | "worn" | "bag"
local SORTS = { "best", "rarity", "slot", "level" }
local SORT_NAME: { [string]: string } =
	{ best = "Best", rarity = "Rarity", slot = "Slot", level = "Level" }
local sortMode = "best"
local RARITY_CYCLE = { "normal", "magic", "rare", "epic" } -- uniques cannot be forged
local rarityFilter: string? = nil

local selectedItem: string? = nil -- item id
local selectedAction = "add"
local selectedAffix: number? = nil
local lastResult: { ok: boolean, text: string }? = nil

local function mats(): Forge.Materials
	return ProgressController.materials()
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Items of the current hero's class (every item is class-bound; items without a class fit all):
-- worn gear first, then the bag. `worn` = set of worn item ids.
local function forgeList(): ({ Items.Item }, { [string]: boolean })
	local bag, equipped = InventoryController.snapshot()
	local class = Kit.playerClass()
	local function fits(it: Items.Item): boolean
		local c = (it :: any).class
		return typeof(c) ~= "string" or string.lower(c) == class
	end
	local list: { Items.Item } = {}
	local worn: { [string]: boolean } = {}
	for _, slot in Items.Slots do
		local it = equipped[slot]
		if it and fits(it) then
			table.insert(list, it)
			worn[it.id] = true
		end
	end
	for _, it in bag do
		if fits(it) then
			table.insert(list, it)
		end
	end
	return list, worn
end

local function find(list: { Items.Item }, id: string?): Items.Item?
	for _, it in list do
		if it.id == id then
			return it
		end
	end
	return nil
end

-- Item, action and affix the way the suggestions would pick them
local function suggest(list: { Items.Item }, worn: { [string]: boolean })
	local it = Forge.suggestItem(list, worn, mats())
	selectedItem = if it then it.id else nil
	if it then
		selectedAction, selectedAffix = Forge.suggestAction(it, mats())
	else
		selectedAction, selectedAffix = Forge.Actions[1].id, nil
	end
end

local function pickItem(it: Items.Item)
	selectedItem = it.id
	selectedAction, selectedAffix = Forge.suggestAction(it, mats())
	lastResult = nil
end

local function pickAction(it: Items.Item, actionId: string)
	selectedAction = actionId
	local action = Forge.ById[actionId]
	if not action.needsAffix then
		selectedAffix = nil
	elseif not (selectedAffix and Forge.check(actionId, it, selectedAffix, mats())) then
		selectedAffix = Forge.suggestAffix(actionId, it, mats()) or selectedAffix
	end
	lastResult = nil
end

local function pickAffix(it: Items.Item, index: number)
	local a = it.affixes[index]
	if not a or a.implicit then
		return
	end
	selectedAffix = index
	if not Forge.ById[selectedAction].needsAffix then
		-- Tapping an affix while "Add Affix" is chosen: switch to the first action that works on it
		local switch = "tier"
		for _, action in Forge.Actions do
			if action.needsAffix and Forge.check(action.id, it, index, mats()) then
				switch = action.id
				break
			end
		end
		selectedAction = switch
	end
	lastResult = nil
end

-- Selection still fits the item (affixes change after forging or a new snapshot)
local function validate(it: Items.Item)
	local action = Forge.ById[selectedAction] or Forge.Actions[1]
	selectedAction = action.id
	if not action.needsAffix then
		selectedAffix = nil
		return
	end
	local a = if selectedAffix then it.affixes[selectedAffix] else nil
	if not a or a.implicit or a.sealed then
		selectedAffix = Forge.suggestAffix(action.id, it, mats())
	end
end

-- ------------------------------------------------------------------ Left: item grid
local function visible(list: { Items.Item }, worn: { [string]: boolean }): { Items.Item }
	local out: { Items.Item } = {}
	for _, it in list do
		local w = worn[it.id] == true
		if
			(view == "all" or (view == "worn") == w)
			and (not rarityFilter or it.rarity == rarityFilter)
		then
			table.insert(out, it)
		end
	end
	local order: { [string]: number } = {}
	local score: { [string]: number } = {}
	local slotOrder: { [string]: number } = {}
	for i, slot in Items.Slots do
		slotOrder[slot] = i
	end
	for i, it in list do
		order[it.id] = i
		score[it.id] = Forge.candidateScore(it, worn[it.id] == true, mats())
	end
	table.sort(out, function(a, b)
		if sortMode == "best" and score[a.id] ~= score[b.id] then
			return score[a.id] > score[b.id]
		elseif sortMode == "slot" and a.slot ~= b.slot then
			return (slotOrder[a.slot] or 99) < (slotOrder[b.slot] or 99)
		elseif sortMode == "level" and a.ilvl ~= b.ilvl then
			return a.ilvl > b.ilvl
		end
		local ra, rb = Items.rank(a.rarity), Items.rank(b.rarity)
		if ra ~= rb then
			return ra > rb
		end
		if a.ilvl ~= b.ilvl then
			return a.ilvl > b.ilvl
		end
		return (order[a.id] or 0) < (order[b.id] or 0)
	end)
	return out
end

-- Gold diamond top right of a cell: the hero wears this item
local function wornMark(cell: GuiObject)
	local d = Instance.new("Frame")
	d.Name = "Worn"
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.new(1, -14, 0, 14)
	d.Size = UDim2.fromOffset(13, 13)
	d.Rotation = 45
	d.BackgroundColor3 = C.GoldHi
	d.BorderSizePixel = 0
	d.ZIndex = 4
	Flat.stroke(d, F.Surface0, 1.5, 0)
	d.Parent = cell
end

-- Cells are kept per item id and only rebuilt when their look changes (selection and the green
-- arrow change in place), so a tap never restarts the glow or jumps the scroll position.
type CellEntry = { cell: TextButton, key: string }
local cells: { [string]: CellEntry } = {}

local function renderGrid(shown: { Items.Item }, worn: { [string]: boolean })
	local keep: { [string]: boolean } = {}
	local m = mats()
	for i, it in shown do
		keep[it.id] = true
		local w = worn[it.id] == true
		local charges = Items.chargesOf(it)
		local dim = not Forge.ready(it, m) -- faded: no action works on it right now
		local icon = InventoryController.slotIcon(it.slot)
		local key =
			table.concat({ it.rarity, icon, tostring(charges), tostring(dim), tostring(w) }, "|")
		local opts: Flat.CellOptions = {
			rarity = it.rarity,
			selected = it.id == selectedItem,
		}
		local entry: CellEntry? = cells[it.id]
		if entry and entry.key ~= key then
			entry.cell:Destroy()
			entry = nil
		end
		if not entry then
			local cellOpts = table.clone(opts)
			cellOpts.count = if it.rarity == "unique" then nil else charges
			cellOpts.dim = dim
			local cell = Flat.cell(CELL, icon, cellOpts)
			cell.Name = "Item_" .. it.id
			if w then
				wornMark(cell)
			end
			cell.Activated:Connect(function()
				local all = forgeList()
				local item = find(all, it.id)
				if item then
					pickItem(item)
					ForgeController.render()
				end
			end)
			cell.LayoutOrder = i
			cell.Parent = grid
			cells[it.id] = { cell = cell, key = key }
		else
			Flat.setCell(entry.cell, CELL, opts)
			entry.cell.LayoutOrder = i
		end
	end
	for id, entry in cells do
		if not keep[id] then
			entry.cell:Destroy()
			cells[id] = nil
		end
	end
	countLabel.Text = if #shown == 1 then "1 item" else string.format("%d items", #shown)
	sortLabel.Text = "Sort: " .. SORT_NAME[sortMode]
	filterLabel.Text = if rarityFilter
		then Items.RarityName[rarityFilter] or rarityFilter
		else "All Rarities"
end

-- ------------------------------------------------------------------ Right: item, action, affixes
local function textLine(
	parent: Instance,
	value: string,
	size: number,
	color: Color3,
	width: number,
	order: number,
	font: Font?
): TextLabel
	local t = Flat.text(value, size, color, font or Theme.Font.Body)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromOffset(width, 0)
	t.TextWrapped = true
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

local function renderHeader(it: Items.Item, w: number, worn: boolean)
	local cell = Flat.cell(HEAD, InventoryController.slotIcon(it.slot), { rarity = it.rarity })
	cell.Name = "Selected"
	cell.Active = false
	cell.Position = UDim2.fromOffset(0, 0)
	cell.Parent = detail

	-- Materials top right
	local matRow = Flat.frame(UDim2.fromOffset(0, 40))
	matRow.Name = "Materials"
	matRow.AutomaticSize = Enum.AutomaticSize.X
	matRow.AnchorPoint = Vector2.new(1, 0)
	matRow.Position = UDim2.new(1, 0, 0, 0)
	local ml = Kit.list(matRow, Enum.FillDirection.Horizontal, 8)
	ml.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local have = mats() :: any
	local MAT_COLOR: { [string]: Color3 } =
		{ candy = Theme.Rarity.epic, shards = C.Cyan, dust = C.Gold }
	for i, key in { "candy", "shards", "dust" } do
		local pill, label = Flat.currency(Forge.MaterialIcon[key], MAT_COLOR[key])
		pill.Name = "Mat_" .. key
		pill.LayoutOrder = i
		label.Text = Flat.thousands(have[key] or 0)
		pill.Parent = matRow
	end
	matRow.Parent = detail

	local colW = w - HEAD - 24 - 330
	local col = Flat.frame(UDim2.fromOffset(colW, HEAD), UDim2.fromOffset(HEAD + 24, 0))
	col.Name = "Info"
	local cl = Kit.list(col, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Center)
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local name = textLine(
		col,
		Window.caps(it.name),
		24,
		Theme.Rarity[it.rarity] or C.Text,
		colW,
		1,
		Theme.Font.Title
	)
	name.Name = "Name"
	local sub = string.format(
		"%s %s · Lv %d%s",
		Items.RarityName[it.rarity] or it.rarity,
		Items.SlotName[it.slot] or it.slot,
		it.ilvl,
		if worn then " · Worn" else ""
	)
	textLine(col, sub, 17, C.Muted, colW, 2)
	local charges = Items.chargesOf(it)
	local state = if it.rarity == "unique"
		then "Uniques cannot be forged"
		elseif charges <= 0 then "Fully forged: no charges left"
		else string.format("%d Forge charge%s left", charges, if charges == 1 then "" else "s")
	textLine(col, state, 17, if Forge.canForge(it) then C.Good else C.GoldHi, colW, 3)
	col.Parent = detail
end

-- Action tile: icon above the name; selected = gold edge and tint, faded when it cannot work now
local function actionTile(
	action: Forge.Action,
	size: Vector2,
	on: boolean,
	works: boolean
): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Action_" .. action.id
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Size = UDim2.fromOffset(size.X, size.Y)
	Kit.touchTarget(b)
	Flat.corner(b, F.Radius.M)
	if on then
		Flat.gradient(b, F.Surface3:Lerp(C.Gold, 0.22), F.Surface2:Lerp(C.Gold, 0.1))
		Flat.stroke(b, C.GoldHi, F.SelectStroke, 0)
	else
		Flat.gradient(b, F.Surface3, F.Surface2)
		Flat.stroke(b, F.Edge, F.Stroke, 0.2)
	end
	Shape.topLine(b)
	local col = Flat.frame(UDim2.fromScale(1, 1))
	Kit.list(col, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Center)
	local ic = Kit.icon(action.icon, 32)
	ic.LayoutOrder = 1
	if not works then
		Kit.setIconTransparency(ic, 0.55)
	end
	ic.Parent = col
	local t = Flat.text(
		action.name,
		16,
		if on then C.GoldHi elseif works then C.Text else C.Muted,
		Theme.Font.UI,
		Enum.TextXAlignment.Center
	)
	t.Name = "Label"
	t.LayoutOrder = 2
	t.Parent = col
	col.Parent = b
	Flat.motion(b)
	return b
end

local function renderActions(it: Items.Item, w: number, y: number)
	local row = Flat.frame(UDim2.fromOffset(w, ACTION_H), UDim2.fromOffset(0, y))
	row.Name = "Actions"
	Kit.list(row, Enum.FillDirection.Horizontal, 10)
	local n = #Forge.Actions
	local tileW = math.floor((w - 10 * (n - 1)) / n)
	local m = mats()
	for i, action in Forge.Actions do
		local works = if action.needsAffix
			then Forge.suggestAffix(action.id, it, m) ~= nil
			else (Forge.check(action.id, it, nil, m))
		local b =
			actionTile(action, Vector2.new(tileW, ACTION_H), action.id == selectedAction, works)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			pickAction(it, action.id)
			ForgeController.render()
		end)
		b.Parent = row
	end
	row.Parent = detail
end

local function affixTile(
	it: Items.Item,
	index: number,
	size: Vector2,
	needsAffix: boolean
): TextButton
	local a = it.affixes[index]
	local on = needsAffix and selectedAffix == index
	local works = not a.implicit
		and (not needsAffix or (Forge.check(selectedAction, it, index, mats())))
	local b = Instance.new("TextButton")
	b.Name = "Affix" .. index
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = if on then F.Surface3 else F.Surface2
	b.BackgroundTransparency = if a.implicit then 0.5 else 0.1
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.Active = not a.implicit
	Kit.touchTarget(b)
	Flat.corner(b, F.Radius.M)
	Flat.stroke(b, if on then C.GoldHi else F.Edge, if on then F.SelectStroke else F.Stroke, 0)
	local t = Flat.text(
		Items.affixText(a),
		19,
		if a.implicit then C.Gold elseif works or not needsAffix then C.Text else C.Muted,
		Theme.Font.Body
	)
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.new(0, 16, 0.5, 0)
	t.Parent = b
	-- Tier on the right, lock for sealed ones; base values cannot be forged
	if a.sealed then
		local lock = Kit.icon("lock", 28)
		lock.AnchorPoint = Vector2.new(1, 0.5)
		lock.Position = UDim2.new(1, -12, 0.5, 0)
		lock.Parent = b
	else
		local tag = Flat.text(
			if a.implicit then "Base" else "T" .. tostring(Items.tierOf(a)),
			16,
			if a.implicit then C.Muted else C.Cyan,
			Theme.Font.UI,
			Enum.TextXAlignment.Right
		)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -14, 0.5, 0)
		tag.Parent = b
	end
	if not a.implicit then
		b.Activated:Connect(function()
			pickAffix(it, index)
			ForgeController.render()
		end)
		Flat.motion(b, if on then F.SelectScale else 1)
	end
	return b
end

local function renderAffixes(it: Items.Item, w: number, y: number)
	local action = Forge.ById[selectedAction]
	local hint = Flat.text(
		if action.needsAffix then "Tap an affix" else "Affixes",
		16,
		C.Muted,
		Theme.Font.UI
	)
	hint.Name = "AffixHint"
	hint.Position = UDim2.fromOffset(0, y)
	hint.Parent = detail

	local box = Flat.frame(UDim2.fromOffset(w, 0), UDim2.fromOffset(0, y + 28))
	box.Name = "Affixes"
	box.AutomaticSize = Enum.AutomaticSize.Y
	local tileW = math.floor((w - AFFIX_GAP) / 2)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(tileW, AFFIX_H)
	layout.CellPadding = UDim2.fromOffset(AFFIX_GAP, AFFIX_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = box
	for i in it.affixes do
		local b = affixTile(it, i, Vector2.new(tileW, AFFIX_H), action.needsAffix)
		b.LayoutOrder = i
		b.Parent = box
	end
	-- Free affix slots: where "Add Affix" puts the new one (gold edge while it is chosen)
	local max = Forge.MaxAffixes[it.rarity] or 0
	local free = max - Forge.openCount(it)
	if free > 0 then
		local f = Instance.new("Frame")
		f.Name = "Free"
		f.BackgroundColor3 = F.Surface1
		f.BackgroundTransparency = 0.3
		f.BorderSizePixel = 0
		f.LayoutOrder = #it.affixes + 1
		Flat.corner(f, F.Radius.M)
		Flat.stroke(f, if selectedAction == "add" then C.Gold else F.Edge, F.Stroke, 0.2)
		local row = Flat.frame(UDim2.fromScale(1, 1))
		local rl = Kit.list(row, Enum.FillDirection.Horizontal, 10)
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.Parent = row
		local plus = Kit.icon("upgrade", 26)
		plus.LayoutOrder = 1
		plus.Parent = row
		local t = Flat.text(
			if free == 1 then "1 free slot" else string.format("%d free slots", free),
			17,
			C.Muted,
			Theme.Font.Body
		)
		t.LayoutOrder = 2
		t.Parent = row
		row.Parent = f
		f.Parent = box
	end
	box.Parent = detail
end

-- Bottom bar: before -> after, charges / reason / last result, and the one Forge button with its cost
local function renderConfirm(it: Items.Item, w: number, h: number)
	local bar = Flat.card(UDim2.fromOffset(w, BAR_H), F.Surface1)
	bar.Name = "Confirm"
	bar.Position = UDim2.fromOffset(0, h - BAR_H)
	bar.Parent = detail

	local action = Forge.ById[selectedAction]
	local m = mats()
	local ok, why = Forge.check(action.id, it, selectedAffix, m)
	local preview = Forge.preview(action.id, it, selectedAffix)
	local price = Forge.cost(action, it, selectedAffix)

	local btnW = 280
	local colW = w - btnW - 3 * 20
	local col = Flat.frame(UDim2.fromOffset(colW, BAR_H - 24), UDim2.fromOffset(20, 12))
	col.Name = "Preview"
	local cl = Kit.list(col, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Center)
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	if preview.before then
		textLine(col, preview.before, 17, C.Muted, colW, 1).Name = "Before"
	end
	textLine(col, "→ " .. preview.after, 21, C.GoldHi, colW, 2, Theme.Font.UI).Name = "After"
	local info, infoColor
	if lastResult then
		info, infoColor = lastResult.text, if lastResult.ok then C.Good else C.Danger
	elseif not ok then
		info, infoColor = why or "Not possible", C.Danger
	else
		info, infoColor = preview.charges, C.Muted
	end
	textLine(col, info, 16, infoColor, colW, 3).Name = "Info"
	col.Parent = bar

	local go, label = Flat.button(
		string.format("Forge · %s", Flat.thousands(price)),
		"primary",
		Vector2.new(btnW, 72),
		Forge.MaterialIcon[action.material]
	)
	go.Name = "ForgeButton"
	go.AnchorPoint = Vector2.new(1, 0.5)
	go.Position = UDim2.new(1, -20, 0.5, 0)
	label.TextSize = Kit.fontSize(18)
	Flat.setEnabled(go, ok)
	go.Activated:Connect(function()
		if go:GetAttribute("Enabled") == true then
			lastResult = nil
			Net.ForgeAct:FireServer(action.id, it.id, selectedAffix)
		end
	end)
	go.Parent = bar
end

local function renderDetail(it: Items.Item?, worn: { [string]: boolean }, filtered: boolean)
	clear(detail)
	local w, h = detail.Size.X.Offset, detail.Size.Y.Offset
	if not it then
		local empty = textLine(
			detail,
			if filtered
				then "No items match this filter."
				else "No items for this hero yet. Collect loot in a Rift and come back.",
			20,
			C.Muted,
			w,
			1
		)
		empty.Name = "Empty"
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Position = UDim2.fromOffset(0, h / 2 - 30)
		return
	end
	validate(it)
	renderHeader(it, w, worn[it.id] == true)
	local y = HEAD + 18
	renderActions(it, w, y)
	y += ACTION_H + 14
	renderAffixes(it, w, y)
	renderConfirm(it, w, h)
end

-- ------------------------------------------------------------------ Flow
function ForgeController.render()
	local list, worn = forgeList()
	-- The selection is always one of the shown cells: a tab or filter that hides it picks the
	-- best candidate among the shown ones instead
	local shown = visible(list, worn)
	if not find(shown, selectedItem) then
		suggest(shown, worn)
	end
	renderGrid(shown, worn)
	renderDetail(find(shown, selectedItem), worn, #list > 0)
end

function ForgeController.toggle()
	win.toggle()
end

local function footButton(caption: string, width: number, iconName: string): (TextButton, TextLabel)
	return Flat.button(caption, "secondary", Vector2.new(width, FOOT_H - 4), iconName)
end

local function buildLeft(body: Vector2)
	left = Kit.panel(Vector2.new(LEFT_W, body.Y))
	left.Name = "Pick"
	left.Parent = win.body

	tabs = Flat.tabs(
		{
			{ id = "all", text = "All" },
			{ id = "worn", text = "Worn" },
			{ id = "bag", text = "Bag" },
		},
		TAB_H,
		function(id: string)
			view = id
			ForgeController.render()
		end
	)
	tabs.frame.Position = UDim2.fromOffset(PAD, PAD)
	tabs.frame.Parent = left

	local gridY = PAD + TAB_H + 8
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(PAD - GRID_PAD, gridY)
	grid.Size = UDim2.fromOffset(LEFT_W - 2 * PAD + 2 * GRID_PAD, body.Y - gridY - FOOT_H - PAD - 8)
	grid.ScrollBarThickness = 4
	grid.ScrollBarImageColor3 = F.EdgeHi
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local gp = Instance.new("UIPadding")
	gp.PaddingTop = UDim.new(0, GRID_PAD)
	gp.PaddingBottom = UDim.new(0, GRID_PAD)
	gp.PaddingLeft = UDim.new(0, GRID_PAD)
	gp.PaddingRight = UDim.new(0, GRID_PAD)
	gp.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = left

	-- Footer: sort, rarity filter, item count
	local foot = Flat.frame(
		UDim2.fromOffset(LEFT_W - 2 * PAD, FOOT_H),
		UDim2.fromOffset(PAD, body.Y - PAD - FOOT_H)
	)
	foot.Name = "Footer"
	local fl = Kit.list(foot, Enum.FillDirection.Horizontal, 10)
	fl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local sort
	sort, sortLabel = footButton("Sort: Best", 200, "sort")
	sort.Name = "Sort"
	sort.LayoutOrder = 1
	sort.Activated:Connect(function()
		local i = table.find(SORTS, sortMode) or 1
		sortMode = SORTS[i % #SORTS + 1]
		ForgeController.render()
	end)
	sort.Parent = foot
	local filter
	filter, filterLabel = footButton("All Rarities", 200, "filter")
	filter.Name = "Filter"
	filter.LayoutOrder = 2
	filter.Activated:Connect(function()
		local i = if rarityFilter then table.find(RARITY_CYCLE, rarityFilter) or 0 else 0
		rarityFilter = RARITY_CYCLE[i + 1] -- past the last rarity: nil = all
		ForgeController.render()
	end)
	filter.Parent = foot
	countLabel = Flat.text("0 items", 15, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Right)
	countLabel.Name = "Count"
	countLabel.LayoutOrder = 3
	countLabel.Parent = foot
	foot.Parent = left
end

function ForgeController.init()
	win = Window.new({
		name = "Forge",
		title = "Forge",
		icon = "forge",
		key = Enum.KeyCode.B,
		unlock = "forge",
		background = "bg_forge",
	})

	local body = Window.BODY
	buildLeft(body)

	local rightW = body.X - LEFT_W - GAP_X
	right = Kit.panel(Vector2.new(rightW, body.Y))
	right.Name = "Work"
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Parent = win.body
	detail =
		Flat.frame(UDim2.fromOffset(rightW - 2 * 28, body.Y - 2 * 28), UDim2.fromOffset(28, 28))
	detail.Name = "Detail"
	detail.Parent = right

	win.onOpen(function()
		-- every visit starts on the best candidate (Shared/Forge suggestItem)
		selectedItem = nil
		lastResult = nil
		tabs.select(view)
		ForgeController.render()
	end)
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
		refresh()
	end)
	tabs.select(view)
	ForgeController.render()
end

return ForgeController
