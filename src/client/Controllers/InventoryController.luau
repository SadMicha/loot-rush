--!strict
-- Inventory window (key I or hub button), flat code look (Theme.Flat, UI/Flat, UI/Spring).
--   header: title, bag count, currencies, close
--   left:   equipment around the 3D figure; below it the comparison equipped vs. selected item
--   right:  category tabs + search, item grid with rarity glow, footer with sort/filter and salvage mode
-- Only shows the snapshot from the server (Net.Inv); every action is a request to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Forge = require(ReplicatedStorage.Shared.Forge)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Spring = require(script.Parent.Parent.UI.Spring)
local Window = require(script.Parent.Parent.UI.Window)
local ProgressController = require(script.Parent.ProgressController)

local InventoryController = {}

local C = Theme.Color
local F = Theme.Flat
local player = Players.LocalPlayer

local MAX_ITEMS = 40 -- same as server (Systems/Inventory)
local SALVAGE_GAP = 0.15 -- seconds between batch salvage requests (server allows 8 per second)

-- Layout (design pixels). The window ends above the HUD hub bar on a phone (844x390).
local WIN_W, WIN_H = 1460, 650
local WINDOW_TOP = 84
local HEAD_H = 48
local BODY_Y = HEAD_H + 12
local LEFT_W = 600
local RIGHT_X = LEFT_W + 16
local RIGHT_W = WIN_W - RIGHT_X
local DOLL_H = 334
local CMP_Y = BODY_Y + DOLL_H + 10
local CMP_H = WIN_H - CMP_Y
local PAD = 14
local DOLL_CELL, DOLL_STEP = 60, 64
local COLS, CELL, GAP = 9, 80, 8
local GRID_PAD = 10 -- room for the glow of edge cells inside the scrolling frame
local TAB_H = 40
local FOOT_H = 48

-- Item categories of the tabs (slots per category); "materials" lists crafting materials instead
local CATEGORIES = {
	{ id = "all", text = "All" },
	{ id = "weapons", text = "Weapons" },
	{ id = "armor", text = "Armor" },
	{ id = "jewelry", text = "Jewelry" },
	{ id = "materials", text = "Materials" },
}
local CATEGORY_SLOTS: { [string]: { [string]: boolean } } = {
	weapons = { weapon = true, offhand = true },
	armor = { helmet = true, armor = true, gloves = true, belt = true, boots = true },
	jewelry = { amulet = true, ring = true },
}
local MATERIALS = { "shards", "candy", "dust" }

-- Icon per equipment slot (Assets.Icon), used while no class art exists
local SLOT_ICON: { [string]: string } = {
	helmet = "slot_helmet",
	armor = "slot_armor",
	gloves = "slot_gloves",
	belt = "slot_belt",
	boots = "slot_boots",
	weapon = "slot_staff",
	offhand = "slot_shield",
	amulet = "slot_amulet",
	ring = "slot_ring",
}
local DOLL_LEFT = { "helmet", "armor", "gloves", "belt", "boots" }
local DOLL_RIGHT = { "weapon", "offhand", "amulet", "ring" }

local STAT_ICON: { [string]: string } = {
	damage = "sword",
	life = "life",
	crit = "target",
	speed = "skill_dash",
}
local STAT_ORDER = { "damage", "life", "crit", "speed" }
local RARITY_RANK: { [string]: number } = { normal = 1, magic = 2, rare = 3, epic = 4 }
local RARITY_CYCLE = { "normal", "magic", "rare", "epic" }
local SORTS = { "rarity", "level", "newest" }
local SORT_NAME: { [string]: string } =
	{ rarity = "Rarity", level = "Item Level", newest = "Newest" }

-- Class art of the slot (Kit.equipIcon) or the atlas icon while that is not uploaded; unknown slots: pouch
local function slotArt(slot: string): string
	return Kit.equipIcon(slot, SLOT_ICON[slot] or "pouch")
end

-- ------------------------------------------------------------------ State
local gui: ScreenGui
local window: Frame
local dollCard: Frame
local cmpCard: Frame
local gridFrame: ScrollingFrame
local countLabel: TextLabel
local capLabel: TextLabel
local ipLabel: TextLabel
local footNormal: Frame
local footSalvage: Frame
local salvageButton: TextButton
local salvageLabel: TextLabel
local sortLabel: TextLabel
local filterLabel: TextLabel
local tabs: Flat.Tabs
local salvageToggle: Flat.Toggle
local viewport: ViewportFrame
local idleConn: RBXScriptConnection?

local items: { Items.Item } = {}
local equipped: { [string]: Items.Item } = {}
local selected: Items.Item? = nil
local selectedEquipped = false
local category = "all"
local sortMode = "rarity"
local rarityFilter: string? = nil
local searchText = "" -- lowercase
local salvageMode = false
local marked: { [string]: boolean } = {}
local popId: string? = nil -- cell that gets a selection pop on the next render
local salvaging = false

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Sheen" then
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
	return if v == math.floor(v) then tostring(v) else string.format("%.1f", v)
end

local function statText(stat: string, v: number): string
	local info = Items.Stats[stat]
	return fmt(v) .. (if info then info.unit else "")
end

local function rarityColor(rarity: string): Color3
	return Theme.Rarity[rarity] or Theme.Rarity.normal
end

local function markedCount(): number
	local n = 0
	for _ in marked do
		n += 1
	end
	return n
end

-- ------------------------------------------------------------------ 3D figure
local function refreshViewport()
	if idleConn then
		idleConn:Disconnect()
		idleConn = nil
	end
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
	clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(20), 0))
	clone.Parent = world
	-- Idle: gentle swaying and breathing while the window is open
	local base = clone:GetPivot()
	local t0 = os.clock()
	idleConn = RunService.Heartbeat:Connect(function()
		if not clone.Parent or not gui.Enabled then
			return
		end
		local t = os.clock() - t0
		clone:PivotTo(
			base
				* CFrame.new(0, math.sin(t * 1.6) * 0.04, 0)
				* CFrame.Angles(0, math.sin(t * 0.7) * 0.18, 0)
		)
	end)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.6, -15.5), Vector3.new(0, -0.1, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- ------------------------------------------------------------------ Selection
local function selectItem(item: Items.Item, isEquipped: boolean)
	if selected and selected.id == item.id and selectedEquipped == isEquipped then
		return
	end
	selected = item
	selectedEquipped = isEquipped
	popId = item.id
	InventoryController.render()
end

-- New render of a selected cell: small bounce so the choice is felt
local function popIfSelected(cell: GuiButton, item: Items.Item)
	if popId == item.id then
		local motion = cell:FindFirstChild("Motion")
		if motion and motion:IsA("UIScale") then
			Spring.impulse(motion, "Scale", 3, "Bouncy")
		end
	end
end

-- ------------------------------------------------------------------ Equipment (left top)
local function renderDoll()
	for _, child in dollCard:GetChildren() do
		if child.Name == "Slot" then
			child:Destroy()
		end
	end
	local function place(slot: string, x: number, row: number, side: "left" | "right")
		local item = equipped[slot]
		local isSel = item ~= nil and selected ~= nil and selected.id == item.id
		local b = Flat.cell(DOLL_CELL, slotArt(slot), {
			rarity = if item then item.rarity else nil,
			selected = isSel,
			dim = item == nil,
			caption = Items.SlotName[slot] or slot,
			captionSide = side,
		})
		b.Name = "Slot"
		b.Position = UDim2.fromOffset(x, 12 + (row - 1) * DOLL_STEP)
		b.ZIndex = 3
		if item then
			b.Activated:Connect(function()
				selectItem(item, true)
			end)
			popIfSelected(b, item)
		end
		b.Parent = dollCard
	end
	for i, slot in DOLL_LEFT do
		place(slot, PAD + 2, i, "right")
	end
	for i, slot in DOLL_RIGHT do
		place(slot, LEFT_W - PAD - 2 - DOLL_CELL, i, "left")
	end

	local sum = 0
	for _, item in equipped do
		sum += Items.itemPower(item)
	end
	ipLabel.Text = if next(equipped) then Format.int(sum) else "–"
end

local function buildDoll(parent: Frame)
	dollCard = Flat.card(UDim2.fromOffset(LEFT_W, DOLL_H))
	dollCard.Name = "Equipment"
	dollCard.Position = UDim2.fromOffset(0, BODY_Y)
	dollCard.ClipsDescendants = false
	dollCard.Parent = parent

	-- Stage: soft light behind the figure and an elliptic floor ring (shapes only)
	local light = Instance.new("Frame")
	light.Name = "StageLight"
	light.AnchorPoint = Vector2.new(0.5, 0.5)
	light.Position = UDim2.new(0.5, 0, 0, 150)
	light.Size = UDim2.fromOffset(300, 300)
	light.BackgroundColor3 = C.Gold
	light.BorderSizePixel = 0
	light.ZIndex = 1
	Flat.corner(light, 150)
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = light
	light.Parent = dollCard

	local floor = Instance.new("Frame")
	floor.Name = "StageRing"
	floor.AnchorPoint = Vector2.new(0.5, 0.5)
	floor.Position = UDim2.new(0.5, 0, 0, 296)
	floor.Size = UDim2.fromOffset(240, 34)
	floor.BackgroundColor3 = C.Gold
	floor.BackgroundTransparency = 0.9
	floor.BorderSizePixel = 0
	floor.ZIndex = 1
	Flat.corner(floor, 17)
	Flat.stroke(floor, C.Gold, 1.5, 0.45)
	floor.Parent = dollCard

	viewport = Instance.new("ViewportFrame")
	viewport.Name = "Figure"
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(90, 8)
	viewport.Size = UDim2.fromOffset(LEFT_W - 180, DOLL_H - 16)
	viewport.Ambient = Color3.fromRGB(170, 175, 200)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.ZIndex = 2
	viewport.Parent = dollCard

	-- Total item power of the worn gear, top center
	local ip = Flat.frame(UDim2.fromOffset(0, 26), UDim2.new(0.5, 0, 0, 12))
	ip.AnchorPoint = Vector2.new(0.5, 0)
	ip.AutomaticSize = Enum.AutomaticSize.X
	ip.ZIndex = 3
	Kit.list(ip, Enum.FillDirection.Horizontal, 6)
	local ic = Kit.icon("item_level", 22)
	ic.LayoutOrder = 1
	ic.Parent = ip
	local cap = Flat.text("POWER", 11, C.Muted)
	cap.LayoutOrder = 2
	cap.Parent = ip
	ipLabel = Flat.text("–", 16, C.GoldHi)
	ipLabel.LayoutOrder = 3
	ipLabel.Parent = ip
	ip.Parent = dollCard
end

-- ------------------------------------------------------------------ Comparison (left bottom)
local COL_W = (LEFT_W - 3 * PAD) // 2

-- Header of one comparison column: icon cell, name, rarity · slot, item power
local function itemHeader(parent: Frame, item: Items.Item)
	local color = rarityColor(item.rarity)
	local cell = Flat.cell(52, slotArt(item.slot), { rarity = item.rarity })
	cell.Active = false
	cell.Position = UDim2.fromOffset(0, 26)
	cell.Parent = parent
	local name = Flat.text(item.name, 14, color, Theme.Font.Title)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.fromOffset(COL_W - 64, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(64, 24)
	name.Parent = parent
	local sub = Flat.text(
		string.format(
			"%s %s",
			Items.RarityName[item.rarity] or item.rarity,
			Items.SlotName[item.slot] or item.slot
		),
		11,
		C.Muted,
		Theme.Font.Body
	)
	sub.Position = UDim2.fromOffset(64, 46)
	sub.Parent = parent
	local ip =
		Flat.text("Item Power " .. Format.int(Items.itemPower(item)), 11, C.Text, Theme.Font.Body)
	ip.Position = UDim2.fromOffset(64, 62)
	ip.Parent = parent
end

-- Stat rows with bars; `other` = values to compare against (deltas shown when given)
local function statRows(
	parent: Frame,
	mine: { [string]: number },
	other: { [string]: number }?,
	accent: Color3
)
	for i, stat in STAT_ORDER do
		local y = 88 + (i - 1) * 22
		local info = Items.Stats[stat]
		local ic = Kit.icon(STAT_ICON[stat], 16)
		ic.Position = UDim2.fromOffset(0, y + 1)
		ic.Parent = parent
		local label = Flat.text(if info then info.label else stat, 11, C.Muted, Theme.Font.Body)
		label.Position = UDim2.fromOffset(22, y + 1)
		label.Parent = parent
		local v = mine[stat] or 0
		local value =
			Flat.text(statText(stat, v), 12, C.Text, Theme.Font.UI, Enum.TextXAlignment.Right)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromOffset(170, y)
		value.Parent = parent
		local ref = if other then other[stat] or 0 else v
		local top = math.max(v, ref, 0.0001)
		local barColor = accent
		if other then
			barColor = if v > ref then C.Good elseif v < ref then C.Danger else accent
		end
		local track, set = Flat.bar(Vector2.new(if other then 46 else COL_W - 178, 6), barColor)
		track.Position = UDim2.fromOffset(178, y + 6)
		track.Parent = parent
		set(0)
		set(v / top, true)
		if other then
			local d = v - ref
			if math.abs(d) >= 0.05 then
				local delta = Flat.text(
					(if d > 0 then "+" else "−") .. statText(stat, math.abs(d)),
					12,
					if d > 0 then C.Good else C.Danger,
					Theme.Font.UI,
					Enum.TextXAlignment.Right
				)
				delta.Name = "Delta"
				delta.AnchorPoint = Vector2.new(1, 0)
				delta.Position = UDim2.fromOffset(COL_W, y)
				delta.Parent = parent
			end
		end
	end
end

local function caption(parent: Frame, text: string, color: Color3?)
	local t = Flat.text(string.upper(text), 11, color or C.Muted)
	t.Position = UDim2.fromOffset(0, 2)
	t.Parent = parent
end

local function renderCompare()
	clear(cmpCard)
	local left = Flat.frame(UDim2.fromOffset(COL_W, CMP_H - 2 * PAD), UDim2.fromOffset(PAD, PAD))
	left.Name = "Equipped"
	left.Parent = cmpCard
	local right =
		Flat.frame(UDim2.fromOffset(COL_W, CMP_H - 2 * PAD), UDim2.fromOffset(2 * PAD + COL_W, PAD))
	right.Name = "Selected"
	right.Parent = cmpCard
	local split = Instance.new("Frame")
	split.BackgroundColor3 = F.Edge
	split.BorderSizePixel = 0
	split.Position = UDim2.fromOffset(PAD + COL_W + PAD / 2, PAD)
	split.Size = UDim2.fromOffset(1, CMP_H - 2 * PAD)
	split.Parent = cmpCard

	local item = selected
	local bagItem = if item and not selectedEquipped then item else nil
	local worn = if item then equipped[item.slot] else nil

	-- Left column: the worn piece of the selected slot, or the character totals
	if worn then
		caption(left, "Equipped")
		itemHeader(left, worn)
		statRows(left, statTotals({ worn }), nil, C.Cyan)
		if selectedEquipped then
			local b = Flat.button("Unequip", "secondary", Vector2.new(COL_W, 40))
			b.AnchorPoint = Vector2.new(0, 1)
			b.Position = UDim2.fromScale(0, 1)
			b.Activated:Connect(function()
				Net.Unequip:FireServer(worn.slot)
				selected = nil
			end)
			b.Parent = left
		end
	else
		caption(left, if item then "Nothing equipped" else "Character")
		local hint = Flat.text(
			if item then "Empty slot: any piece is an upgrade" else "Total stats of your gear",
			12,
			F.Faint,
			Theme.Font.Body
		)
		hint.Position = UDim2.fromOffset(0, 40)
		hint.Parent = left
		statRows(left, statTotals(equipped), nil, C.Cyan)
	end

	-- Right column: the selected bag item against the worn one
	if bagItem then
		local color = rarityColor(bagItem.rarity)
		caption(right, "Selected", color)
		itemHeader(right, bagItem)
		local change = if worn
			then (Items.itemPower(bagItem) - Items.itemPower(worn)) / math.max(
				Items.itemPower(worn),
				1
			) * 100
			else nil
		local big = Flat.text(
			if change == nil then "NEW" else string.format("%+d%%", math.floor(change + 0.5)),
			22,
			if change == nil or change >= 0 then C.Good else C.Danger,
			Theme.Font.Title,
			Enum.TextXAlignment.Right
		)
		big.AnchorPoint = Vector2.new(1, 0)
		big.Position = UDim2.fromOffset(COL_W, -2)
		big.Parent = right
		statRows(right, statTotals({ bagItem }), if worn then statTotals({ worn }) else nil, color)

		local actions = Flat.frame(UDim2.fromOffset(COL_W, 40), UDim2.fromScale(0, 1))
		actions.AnchorPoint = Vector2.new(0, 1)
		local al = Kit.list(actions, Enum.FillDirection.Horizontal, 8)
		al.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local equip = Flat.button("Equip", "primary", Vector2.new(COL_W - 118, 40))
		equip.LayoutOrder = 1
		equip.Activated:Connect(function()
			Net.Equip:FireServer(bagItem.id)
			selected = nil
		end)
		equip.Parent = actions
		local sell = Flat.button("Salvage", "danger", Vector2.new(110, 40))
		sell.LayoutOrder = 2
		sell.Activated:Connect(function()
			Net.Sell:FireServer(bagItem.id)
			selected = nil
		end)
		sell.Parent = actions
		actions.Parent = right
	else
		caption(right, "Compare")
		local hint = Flat.text(
			if item then "Pick a bag item to compare" else "Pick an item",
			14,
			F.Faint,
			Theme.Font.Body
		)
		hint.AnchorPoint = Vector2.new(0.5, 0.5)
		hint.Position = UDim2.fromScale(0.5, 0.45)
		hint.Parent = right
	end
end

-- ------------------------------------------------------------------ Grid (right)
local function visibleItems(): { Items.Item }
	local slots = CATEGORY_SLOTS[category]
	local list: { Items.Item } = {}
	for _, item in items do
		if
			(not slots or slots[item.slot])
			and (not rarityFilter or item.rarity == rarityFilter)
			and (searchText == "" or string.find(string.lower(item.name), searchText, 1, true))
		then
			table.insert(list, item)
		end
	end
	if sortMode == "newest" then
		-- The server appends new loot: newest first = reverse bag order
		local rev: { Items.Item } = {}
		for i = #list, 1, -1 do
			table.insert(rev, list[i])
		end
		return rev
	end
	table.sort(list, function(a, b)
		if sortMode == "level" and a.ilvl ~= b.ilvl then
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

local function emptyCells(from: number, total: number)
	for i = from, total do
		local e = Flat.cell(CELL, nil, nil)
		e.Active = false
		e.LayoutOrder = i
		e.Parent = gridFrame
	end
end

local function renderMaterials()
	local have = ProgressController.materials()
	for i, key in MATERIALS do
		local n = math.floor((have :: any)[key] or 0)
		local b = Flat.cell(CELL, Forge.MaterialIcon[key], {
			rarity = if key == "dust" then "epic" elseif key == "candy" then "rare" else "magic",
			count = n,
		})
		b.Active = false
		b.LayoutOrder = i
		b.Parent = gridFrame
	end
	emptyCells(#MATERIALS + 1, COLS * 5)
end

local function renderGrid()
	clear(gridFrame)
	countLabel.Text = string.format("%d / %d", #items, MAX_ITEMS)
	capLabel.Text = string.format("%d / %d", #items, MAX_ITEMS)
	local shown = 0
	if category == "materials" then
		renderMaterials()
		shown = COLS * 5
	else
		local list = visibleItems()
		for i, item in list do
			local isSel = selected ~= nil and not selectedEquipped and selected.id == item.id
			local b = Flat.cell(CELL, slotArt(item.slot), {
				rarity = item.rarity,
				selected = isSel and not salvageMode,
				marked = salvageMode and marked[item.id] == true,
			})
			b.Name = "Item"
			b.LayoutOrder = i
			b.Activated:Connect(function()
				if salvageMode then
					if marked[item.id] then
						marked[item.id] = nil
					else
						marked[item.id] = true
					end
					InventoryController.render()
				else
					selectItem(item, false)
				end
			end)
			popIfSelected(b, item)
			b.Parent = gridFrame
		end
		-- Empty places up to full rows (at least the bag size in "All")
		local total = math.max(#list, if category == "all" then MAX_ITEMS else 0, COLS * 5)
		total = math.ceil(total / COLS) * COLS
		emptyCells(#list + 1, total)
		shown = total
	end
	local rows = math.ceil(shown / COLS)
	gridFrame.CanvasSize = UDim2.fromOffset(0, rows * (CELL + GAP) - GAP + 2 * GRID_PAD)

	-- Footer state
	footNormal.Visible = not salvageMode
	footSalvage.Visible = salvageMode
	local n = markedCount()
	local value, shards = 0, 0
	for _, item in items do
		if marked[item.id] then
			value += Items.sellValue(item)
			shards += (Items.Salvage[item.rarity] or Items.Salvage.normal).shards
		end
	end
	salvageLabel.Text = if n > 0
		then string.format("Salvage %d  ·  +%s Gold  +%d Shards", n, Format.big(value), shards)
		else "Mark items to salvage"
	Flat.setEnabled(salvageButton, n > 0 and not salvaging)
	sortLabel.Text = "Sort: " .. SORT_NAME[sortMode]
	filterLabel.Text = if rarityFilter
		then Items.RarityName[rarityFilter] or rarityFilter
		else "All Rarities"
end

-- Mark every bag item of a rarity (and below it) for salvage, worn gear is never in the bag
local function markUpTo(rarity: string)
	local limit = RARITY_RANK[rarity] or 0
	for _, item in items do
		if (RARITY_RANK[item.rarity] or 0) <= limit then
			marked[item.id] = true
		end
	end
	InventoryController.render()
end

-- Salvage all marked items, one request at a time (the server throttles to 8 per second)
local function salvageMarked()
	if salvaging then
		return
	end
	local ids: { string } = {}
	for _, item in items do
		if marked[item.id] then
			table.insert(ids, item.id)
		end
	end
	if #ids == 0 then
		return
	end
	salvaging = true
	marked = {}
	InventoryController.render()
	task.spawn(function()
		for _, id in ids do
			Net.Sell:FireServer(id)
			task.wait(SALVAGE_GAP)
		end
		salvaging = false
		InventoryController.render()
	end)
end

local function footButton(
	text: string,
	width: number,
	iconName: string?,
	kind: Flat.ButtonKind?
): (TextButton, TextLabel)
	return Flat.button(text, kind or "secondary", Vector2.new(width, FOOT_H - 4), iconName)
end

local function buildGrid(parent: Frame)
	local card = Flat.card(UDim2.fromOffset(RIGHT_W, WIN_H - BODY_Y))
	card.Name = "Bag"
	card.Position = UDim2.fromOffset(RIGHT_X, BODY_Y)
	card.Parent = parent

	tabs = Flat.tabs(CATEGORIES, TAB_H, function(id: string)
		category = id
		InventoryController.render()
	end)
	tabs.frame.Position = UDim2.fromOffset(PAD, PAD)
	tabs.frame.Parent = card

	-- Search field (flat)
	local search = Instance.new("Frame")
	search.Name = "Search"
	search.AnchorPoint = Vector2.new(1, 0)
	search.Position = UDim2.new(1, -PAD, 0, PAD)
	search.Size = UDim2.fromOffset(190, TAB_H)
	search.BackgroundColor3 = F.Surface0
	search.BackgroundTransparency = 0.2
	search.BorderSizePixel = 0
	Flat.corner(search, F.Radius.M)
	local searchEdge = Flat.stroke(search, F.Edge)
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(14, 0)
	box.Size = UDim2.new(1, -28, 1, 0)
	box.PlaceholderText = "Search items"
	box.PlaceholderColor3 = F.Faint
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextSize = Kit.fontSize(13)
	box.FontFace = Theme.Font.Body
	box.TextColor3 = C.Text
	box.Parent = search
	box.Focused:Connect(function()
		Spring.target(searchEdge, { Color = C.Gold }, "Soft")
	end)
	box.FocusLost:Connect(function()
		Spring.target(searchEdge, { Color = F.Edge }, "Soft")
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		searchText = string.lower(box.Text)
		InventoryController.render()
	end)
	search.Parent = card

	local gridY = PAD + TAB_H + 6
	local gridH = WIN_H - BODY_Y - gridY - FOOT_H - PAD - 6
	gridFrame = Instance.new("ScrollingFrame")
	gridFrame.Name = "Grid"
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.Position = UDim2.fromOffset(PAD - GRID_PAD + 4, gridY)
	gridFrame.Size = UDim2.fromOffset(RIGHT_W - 2 * PAD + 2 * GRID_PAD - 8, gridH)
	gridFrame.ScrollBarThickness = 4
	gridFrame.ScrollBarImageColor3 = F.EdgeHi
	gridFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	gridFrame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	local gp = Instance.new("UIPadding")
	gp.PaddingTop = UDim.new(0, GRID_PAD)
	gp.PaddingBottom = UDim.new(0, GRID_PAD)
	gp.PaddingLeft = UDim.new(0, GRID_PAD)
	gp.PaddingRight = UDim.new(0, GRID_PAD)
	gp.Parent = gridFrame
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gridFrame
	gridFrame.Parent = card

	-- Footer: capacity left, then sort/filter (normal) or quick marks + salvage (salvage mode),
	-- salvage switch on the right
	local foot = Flat.frame(UDim2.new(1, -2 * PAD, 0, FOOT_H), UDim2.new(0, PAD, 1, -PAD - FOOT_H))
	foot.Name = "Footer"
	foot.Parent = card
	local rule = Flat.rule(RIGHT_W - 2 * PAD)
	rule.Position = UDim2.fromOffset(0, -6)
	rule.Parent = foot

	local cap = Instance.new("Frame")
	cap.Name = "Capacity"
	cap.BackgroundColor3 = F.Surface0
	cap.BackgroundTransparency = 0.2
	cap.BorderSizePixel = 0
	cap.Size = UDim2.fromOffset(120, FOOT_H - 4)
	cap.Position = UDim2.fromOffset(0, 2)
	Flat.corner(cap, F.Radius.M)
	Flat.stroke(cap, F.Edge)
	Kit.list(cap, Enum.FillDirection.Horizontal, 8)
	local bag = Kit.icon("pouch", 24)
	bag.LayoutOrder = 1
	bag.Parent = cap
	capLabel = Flat.text("0 / 40", 14, C.Text)
	capLabel.LayoutOrder = 2
	capLabel.Parent = cap
	cap.Parent = foot

	footNormal = Flat.frame(UDim2.fromOffset(400, FOOT_H), UDim2.fromOffset(132, 0))
	footNormal.Name = "Normal"
	local nl = Kit.list(footNormal, Enum.FillDirection.Horizontal, 8)
	nl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local sort
	sort, sortLabel = footButton("Sort: Rarity", 190)
	sort.LayoutOrder = 1
	sort.Activated:Connect(function()
		local i = table.find(SORTS, sortMode) or 1
		sortMode = SORTS[i % #SORTS + 1]
		InventoryController.render()
	end)
	sort.Parent = footNormal
	local filterBtn
	filterBtn, filterLabel = footButton("All Rarities", 170)
	filterBtn.LayoutOrder = 2
	filterBtn.Activated:Connect(function()
		local i = if rarityFilter then table.find(RARITY_CYCLE, rarityFilter) or 0 else 0
		rarityFilter = RARITY_CYCLE[i + 1] -- past the last rarity: nil = all
		InventoryController.render()
	end)
	filterBtn.Parent = footNormal
	footNormal.Parent = foot

	footSalvage = Flat.frame(UDim2.fromOffset(470, FOOT_H), UDim2.fromOffset(132, 0))
	footSalvage.Name = "Salvage"
	footSalvage.Visible = false
	local sl = Kit.list(footSalvage, Enum.FillDirection.Horizontal, 8)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local markNormal = footButton("+ Normal", 100, nil, "ghost")
	markNormal.LayoutOrder = 1
	markNormal.Activated:Connect(function()
		markUpTo("normal")
	end)
	markNormal.Parent = footSalvage
	local markMagic = footButton("+ Magic", 100, nil, "ghost")
	markMagic.LayoutOrder = 2
	markMagic.Activated:Connect(function()
		markUpTo("magic")
	end)
	markMagic.Parent = footSalvage
	salvageButton, salvageLabel = footButton("Mark items to salvage", 250, nil, "danger")
	salvageLabel.TextSize = Kit.fontSize(12)
	salvageButton.LayoutOrder = 3
	salvageButton.Activated:Connect(function()
		if salvageButton:GetAttribute("Enabled") ~= false then
			salvageMarked()
		end
	end)
	salvageButton.Parent = footSalvage
	footSalvage.Parent = foot

	salvageToggle = Flat.toggle("Salvage", "salvage", C.Danger, function(on: boolean)
		salvageMode = on
		marked = {}
		if on then
			selected = nil
		end
		InventoryController.render()
	end)
	salvageToggle.frame.AnchorPoint = Vector2.new(1, 0)
	salvageToggle.frame.Position = UDim2.new(1, 0, 0, 2)
	salvageToggle.frame.Parent = foot
end

-- ------------------------------------------------------------------ Header
local titleRow: Frame

local stage: Frame
local fit: UIScale
local guiRoot: Frame
local closeButton: GuiButton
local CLOSE_SIZE = 48 -- same as Window (top right of the screen, outside the scaled stage)

-- Fit the window into the screen (phones: grows over the hub bar, the window is modal anyway) and keep
-- the title clear of the Roblox buttons at the top left
local function arrange()
	local rootScale = guiRoot:FindFirstChildOfClass("UIScale")
	local s = if rootScale then rootScale.Scale else 1
	local camera = workspace.CurrentCamera
	if s <= 0 or not camera or camera.ViewportSize.X <= 0 then
		return
	end
	local screen = camera.ViewportSize -- the root covers the whole screen (IgnoreGuiInset)
	local view = screen / s -- design pixels
	local barRight, barH = Window.topbar()
	-- Close button like in every Window: right edge, vertically centered on the Roblox bar;
	-- the window starts below it
	local mid = math.max(40 + CLOSE_SIZE / 2 - 16, barH / s / 2)
	closeButton.Position = UDim2.new(1, -28, 0, mid)
	local closeH = math.max(CLOSE_SIZE, closeButton.Size.Y.Offset) -- grows on touch screens
	local stageTop = math.max(WINDOW_TOP, mid + closeH / 2 + 8)
	stage.Position = UDim2.new(0.5, 0, 0, stageTop)

	local k = math.min((view.X - 40) / WIN_W, (view.Y - stageTop - 12) / WIN_H, F.MaxFit)
	k = math.max(k, 0.5)
	if math.abs(fit.Scale - k) > 0.001 then
		fit.Scale = k
		Kit.refit(guiRoot)
	end
	local unit = s * k -- screen pixels per window design pixel
	local indent = 0
	-- Computed, not read back: the layout of the new scale only lands next frame
	local top = stageTop * s
	local left = screen.X / 2 - WIN_W * unit / 2
	if top < barH and left < barRight + 12 then
		indent = (barRight + 12 - left) / unit
	end
	titleRow.Position = UDim2.fromOffset(math.max(0, indent), 0)
end

local function buildHeader(parent: Frame)
	local head = Flat.frame(UDim2.fromOffset(WIN_W, HEAD_H))
	head.Name = "Header"
	head.Parent = parent

	titleRow = Flat.frame(UDim2.fromOffset(0, HEAD_H))
	titleRow.AutomaticSize = Enum.AutomaticSize.X
	local tl = Kit.list(titleRow, Enum.FillDirection.Horizontal, 14)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	titleRow.Parent = head

	local titleBox = Flat.frame(UDim2.fromOffset(0, HEAD_H))
	titleBox.AutomaticSize = Enum.AutomaticSize.X
	titleBox.LayoutOrder = 1
	local title = Flat.text("INVENTORY", 26, C.GoldHi, Theme.Font.Title)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(0, 0.45)
	title.Parent = titleBox
	-- Gold underline that fades out to the right
	local line = Instance.new("Frame")
	line.Name = "Underline"
	line.BackgroundColor3 = C.Gold
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, 2)
	Flat.gradient(line, C.GoldHi, C.Gold, 0, 1, 0)
	line.Parent = titleBox
	titleBox.Parent = titleRow

	local count = Instance.new("Frame")
	count.Name = "Count"
	count.LayoutOrder = 2
	count.BackgroundColor3 = F.Surface1
	count.BackgroundTransparency = 0.1
	count.BorderSizePixel = 0
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromOffset(0, 28)
	Flat.corner(count, 14)
	Flat.stroke(count, F.Edge)
	local cp = Instance.new("UIPadding")
	cp.PaddingLeft = UDim.new(0, 12)
	cp.PaddingRight = UDim.new(0, 12)
	cp.Parent = count
	local cl = Kit.list(count, Enum.FillDirection.Horizontal, 6)
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local bagIcon = Kit.icon("pouch", 18)
	bagIcon.LayoutOrder = 1
	bagIcon.Parent = count
	countLabel = Flat.text("0 / 40", 12, C.Muted)
	countLabel.LayoutOrder = 2
	countLabel.Parent = count
	count.Parent = titleRow

	-- Currencies + close on the right
	local right = Flat.frame(UDim2.fromOffset(0, HEAD_H), UDim2.fromScale(1, 0))
	right.AnchorPoint = Vector2.new(1, 0)
	right.AutomaticSize = Enum.AutomaticSize.X
	local rl = Kit.list(right, Enum.FillDirection.Horizontal, 10)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local function currency(order: number, icon: string, color: Color3, attr: string)
		local pill, label = Flat.currency(icon, color)
		pill.LayoutOrder = order
		pill.Parent = right
		local function refresh()
			label.Text = Format.big((player:GetAttribute(attr) or 0) :: number)
		end
		refresh()
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	currency(1, "gold", C.GoldHi, "Gold")
	currency(2, "crystal", C.Cyan, "Shards")
	currency(3, "soulstar", Theme.Rarity.epic, "Soulstars")
	right.Parent = head
end

-- ------------------------------------------------------------------ Flow
function InventoryController.render()
	-- Selection or marks gone (sold/equipped)? Then drop them
	local present: { [string]: boolean } = {}
	for _, it in items do
		present[it.id] = true
	end
	for _, it in equipped do
		present[it.id] = true
	end
	if selected and not present[selected.id] then
		selected = nil
	end
	for id in marked do
		if not present[id] then
			marked[id] = nil
		end
	end
	renderGrid()
	renderDoll()
	renderCompare()
	popId = nil
end

-- For other windows (Forge): current snapshot, change signal, icon per slot
local changed = Instance.new("BindableEvent")
InventoryController.changed = changed.Event

function InventoryController.snapshot(): ({ Items.Item }, { [string]: Items.Item })
	return items, equipped
end

function InventoryController.slotIcon(slot: string): string
	return slotArt(slot)
end

function InventoryController.toggle()
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		Window.closeCurrent() -- only one fullscreen window at a time
		Flat.pop(window)
		arrange()
		refreshViewport()
	else
		salvageMode = false
		marked = {}
		salvageToggle.set(false)
		InventoryController.render()
	end
end

function InventoryController.init()
	local root: Frame
	gui, root = Kit.scaledGui("LootRushInventory", 5, true)
	gui.Enabled = false
	Window.exclusive(function()
		if gui.Enabled then
			InventoryController.toggle()
		end
	end, function()
		return gui.Enabled
	end)

	-- Dark scrim over the world; also blocks clicks to the HUD underneath
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.BackgroundColor3 = F.Surface0
	scrim.BackgroundTransparency = F.Scrim
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Active = true
	scrim.ZIndex = 0
	scrim.Parent = root

	guiRoot = root
	stage = Flat.frame(UDim2.fromOffset(WIN_W, WIN_H), UDim2.new(0.5, 0, 0, WINDOW_TOP))
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0)
	fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = stage
	stage.Parent = root
	window = Flat.frame(UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	window.AnchorPoint = Vector2.new(0.5, 0.5) -- the open pop scales around the center
	window.Name = "Window"
	window.Parent = stage

	closeButton = Flat.close(CLOSE_SIZE)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.ZIndex = 5
	closeButton.Activated:Connect(function()
		InventoryController.toggle()
	end)
	closeButton.Parent = root

	buildHeader(window)
	buildDoll(window)
	cmpCard = Flat.card(UDim2.fromOffset(LEFT_W, CMP_H))
	cmpCard.Name = "Compare"
	cmpCard.Position = UDim2.fromOffset(0, CMP_Y)
	cmpCard.Parent = window
	buildGrid(window)
	tabs.select(category)
	guiRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(arrange)
	local rootScale = root:FindFirstChildOfClass("UIScale")
	if rootScale then
		rootScale:GetPropertyChangedSignal("Scale"):Connect(arrange)
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(arrange)
	end
	arrange()

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
		changed:Fire()
	end)
	ProgressController.changed:Connect(function()
		if category == "materials" then
			InventoryController.render()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.I then
			InventoryController.toggle()
		end
	end)
end

return InventoryController
