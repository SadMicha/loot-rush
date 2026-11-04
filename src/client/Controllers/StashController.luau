--!strict
-- Stash window (hub station "Stash", Systems/Stash, Shared/Stash): account-wide storage shared
-- by every hero. Left: the stash with its tabs, right: the hero's bag. One tap moves an item to
-- the other side (the server checks and answers with both snapshots); "Store All" empties the bag
-- into the open tab. Hover (PC) or the last tap (touch) shows the item's details at the bottom.
-- The window closes by itself when the hero walks away from the stash.
-- Items above this hero's level (Items.requiredLevel) can be stored and taken, but show a lock:
-- the server refuses to equip them until the hero reaches that level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Stash)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local InventoryController = require(script.Parent.InventoryController)
local QuestController = require(script.Parent.QuestController)

local StashController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local F = Theme.Flat

-- Layout (design pixels inside Window.BODY = 1520 × 790)
local GAP_X = 16
local PANEL_W = (Window.BODY.X - GAP_X) / 2
local PANEL_H = Window.BODY.Y
local HEAD_Y = 20
local TAB_Y = 64
local TAB_H = 44
local GRID_Y = 124 -- stash grid (below the tabs)
local BAG_Y = 72 -- bag grid (no tabs on that side; "Store All" sits in the title row)
-- Phones in landscape fit the 790 px tall body at a scale of ~0.36: cells of 92 stay ≥ 32 px
-- touch targets, so 7 columns × 6 rows (Config.STASH_TAB_SLOTS = 42) is the most that fits.
local COLS = 7
local CELL = 92
local GAP = 5
local GRID_W = COLS * CELL + (COLS - 1) * GAP
local PAD = math.floor((PANEL_W - GRID_W) / 2)
local BAG_ROWS = math.ceil(Items.BAG_MAX / COLS)
local INFO_Y = BAG_Y + BAG_ROWS * (CELL + GAP) + 8
local RESEND = 1.5 -- seconds a tapped item ignores more taps (waiting for the server)
local CLOSE_CHECK = 0.5 -- seconds between "still at the stash?" checks while open

local win: Window.Window
local tabs: Flat.Tabs
local stashGrid: Frame
local bagGrid: Frame
local stashCount: TextLabel
local bagCount: TextLabel
local status: TextLabel
local infoName: TextLabel
local infoMeta: TextLabel
local infoAffixes: TextLabel
local storeAll: TextButton

local stashTabs: { { Items.Item } } = {}
local loaded = false
local tab = 1
local sent: { [string]: number } = {} -- item id → time of the last move request

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function grid(parent: Frame, rows: number, pos: Vector2): Frame
	local f = Flat.frame(UDim2.fromOffset(GRID_W, rows * CELL + (rows - 1) * GAP))
	f.Position = UDim2.fromOffset(pos.X, pos.Y)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirectionMaxCells = COLS
	layout.Parent = f
	f.Parent = parent
	return f
end

local function rarityName(rarity: string): string
	return string.upper(string.sub(rarity, 1, 1)) .. string.sub(rarity, 2)
end

local function heroLevel(): number
	return (player:GetAttribute("Level") or 1) :: number
end

-- Hero level the item still needs (Items.requiredLevel), nil when this hero can wear it
local function lockOf(item: Items.Item): number?
	return if Items.canWear(item, heroLevel()) then nil else Items.requiredLevel(item)
end

local function showInfo(item: Items.Item?, note: string?)
	if not item then
		infoName.Text = ""
		infoMeta.Text = note or "Tap an item to move it. Hover to see its stats."
		infoMeta.TextColor3 = C.Muted
		infoAffixes.Text = ""
		return
	end
	infoName.Text = item.name
	infoName.TextColor3 = Theme.Rarity[item.rarity] or Theme.Rarity.normal
	local slot = Items.SlotName[item.slot] or item.slot
	local meta = `{rarityName(item.rarity)} {slot} - Item Level {Format.int(item.ilvl)}`
	local need = lockOf(item)
	if need then
		meta ..= ` - Requires Level {Format.int(need)}`
	end
	infoMeta.Text = if note then `{meta} - {note}` else meta
	infoMeta.TextColor3 = if need then C.Danger else C.Muted
	local lines = {}
	for _, a in item.affixes do
		table.insert(lines, Items.affixText(a))
	end
	infoAffixes.Text = table.concat(lines, "   ")
end

local function canSend(id: string): boolean
	local last = sent[id]
	if last and os.clock() - last < RESEND then
		return false
	end
	sent[id] = os.clock()
	return true
end

local function itemCell(item: Items.Item, mark: Items.UpgradeMark?, toStash: boolean): TextButton
	local b = Flat.cell(CELL, InventoryController.slotIcon(item.slot), {
		rarity = item.rarity,
		upgrade = mark,
		locked = lockOf(item),
	})
	b.Name = if toStash then "BagItem" else "StashItem"
	b.MouseEnter:Connect(function()
		showInfo(item)
	end)
	b.Activated:Connect(function()
		if not canSend(item.id) then
			return
		end
		if toStash then
			Net.Stash:FireServer("put", item.id, tab)
			showInfo(item, `Stored in Tab {tab}`)
		else
			Net.Stash:FireServer("take", item.id)
			showInfo(item, "Moved to your bag")
		end
	end)
	return b
end

local function fill(parent: Frame, list: { Items.Item }, slots: number, toStash: boolean)
	clear(parent)
	local _, equipped = InventoryController.snapshot()
	local marks = Items.upgradeMarks(list, equipped, heroLevel())
	for i, item in list do
		local b = itemCell(item, marks[item.id], toStash)
		b.LayoutOrder = i
		b.Parent = parent
	end
	for i = #list + 1, slots do
		local e = Flat.cell(CELL, nil, nil)
		e.Name = "Empty"
		e.LayoutOrder = i
		e.Parent = parent
	end
end

local function render()
	if not win or not win.isOpen() then
		return
	end
	local bag = InventoryController.snapshot()
	local list = stashTabs[tab] or {}
	fill(stashGrid, list, Rules.TAB_SLOTS, false)
	fill(bagGrid, bag, Items.BAG_MAX, true)
	stashCount.Text = `{Format.int(#list)} / {Format.int(Rules.TAB_SLOTS)}`
	stashCount.TextColor3 = if #list >= Rules.TAB_SLOTS then C.Danger else C.Muted
	bagCount.Text = `{Format.int(#bag)} / {Format.int(Items.BAG_MAX)}`
	bagCount.TextColor3 = if #bag >= Items.BAG_MAX then C.Danger else C.Muted
	status.Text = if loaded then "" else "Opening the stash…"
	Flat.setEnabled(storeAll, loaded and #bag > 0 and #list < Rules.TAB_SLOTS)
end

local function heading(parent: Frame, text: string, right: number?): TextLabel
	local t = Window.gilded(text, 26)
	t.Position = UDim2.fromOffset(PAD, HEAD_Y)
	t.Parent = parent
	local count = Flat.text("", 18, C.Muted, Theme.Font.UI, Enum.TextXAlignment.Right)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -PAD - (right or 0), 0, HEAD_Y + 6)
	count.Parent = parent
	return count
end

local function build()
	local left = Kit.panel(Vector2.new(PANEL_W, PANEL_H))
	left.Name = "StashPanel"
	left.Parent = win.body
	Shape.brackets(left)
	stashCount = heading(left, "Stash")
	stashCount.Name = "Count"

	local defs = {}
	for i = 1, Rules.TABS do
		table.insert(defs, { id = tostring(i), text = `Tab {i}` })
	end
	tabs = Flat.tabs(defs, TAB_H, function(id: string)
		tab = tonumber(id) or 1
		render()
	end)
	tabs.frame.Position = UDim2.fromOffset(PAD, TAB_Y)
	tabs.frame.Parent = left
	local rowsStash = math.ceil(Rules.TAB_SLOTS / COLS)
	stashGrid = grid(left, rowsStash, Vector2.new(PAD, GRID_Y))
	stashGrid.Name = "StashGrid"
	local shared = Flat.text(
		"Shared by all your heroes",
		16,
		C.Muted,
		Theme.Font.Body,
		Enum.TextXAlignment.Left
	)
	shared.Position = UDim2.fromOffset(PAD, GRID_Y + rowsStash * (CELL + GAP) + 8)
	shared.Parent = left

	local right = Kit.panel(Vector2.new(PANEL_W, PANEL_H))
	right.Name = "BagPanel"
	right.Position = UDim2.fromOffset(PANEL_W + GAP_X, 0)
	right.Parent = win.body
	Shape.brackets(right)
	local storeW = 190
	bagCount = heading(right, "Bag", storeW + 16)
	bagCount.Name = "Count"
	local b = Flat.button("Store All", "secondary", Vector2.new(storeW, TAB_H), "chest")
	b.Name = "StoreAll"
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -PAD, 0, HEAD_Y - 6)
	b.Activated:Connect(function()
		if b:GetAttribute("Enabled") == false then
			return
		end
		Net.Stash:FireServer("all", tab)
	end)
	b.Parent = right
	storeAll = b
	bagGrid = grid(right, BAG_ROWS, Vector2.new(PAD, BAG_Y))
	bagGrid.Name = "BagGrid"

	local info = Flat.card(UDim2.fromOffset(PANEL_W - 2 * PAD, PANEL_H - INFO_Y - 14), F.Surface2)
	info.Name = "Info"
	info.Position = UDim2.fromOffset(PAD, INFO_Y)
	info.Parent = right
	infoName = Flat.text("", 22, C.Text, Theme.Font.UI)
	infoName.Name = "Name"
	infoName.Position = UDim2.fromOffset(18, 10)
	infoName.Parent = info
	infoMeta = Flat.text("", 16, C.Muted, Theme.Font.Body)
	infoMeta.Name = "Meta"
	infoMeta.Position = UDim2.fromOffset(18, 40)
	infoMeta.Parent = info
	infoAffixes = Flat.text("", 16, C.Text, Theme.Font.Body)
	infoAffixes.Name = "Affixes"
	infoAffixes.Position = UDim2.fromOffset(18, 66)
	infoAffixes.AutomaticSize = Enum.AutomaticSize.Y
	infoAffixes.Size = UDim2.fromOffset(PANEL_W - 2 * PAD - 36, 0)
	infoAffixes.TextWrapped = true
	infoAffixes.Parent = info

	status = Flat.text("", 20, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.new(0.5, 0, 0, GRID_Y + 120)
	status.ZIndex = 5
	status.Parent = left

	tabs.select("1")
	showInfo(nil)
end

-- Station part of the stash (nil while it is streamed out: then the window stays open)
local function stationPart(): BasePart?
	local hub = workspace:FindFirstChild("Lumenhaven")
	local part = hub and hub:FindFirstChild("Station_Stash", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function tooFar(): boolean
	local part = stationPart()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not part or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude > Config.STASH_RANGE
end

function StashController.isOpen(): boolean
	return win ~= nil and win.isOpen()
end

function StashController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function StashController.toggle()
	win.toggle()
end

function StashController.init()
	win = Window.new({ name = "Stash", title = "Stash", icon = "chest" })
	build()
	win.onOpen(function()
		loaded = false
		sent = {}
		showInfo(nil)
		render()
		Net.Stash:FireServer("open")
	end)
	Net.StashData.OnClientEvent:Connect(function(snap: any)
		if typeof(snap) ~= "table" or typeof(snap.tabs) ~= "table" then
			return
		end
		if typeof(snap.text) == "string" and snap.text ~= "" then
			QuestController.toast(snap.text, C.Danger)
		end
		if snap.text == Rules.Text.far then
			win.close()
			return
		end
		stashTabs = snap.tabs
		loaded = true
		sent = {}
		render()
	end)
	Net.Inv.OnClientEvent:Connect(function()
		-- InventoryController takes the snapshot first (it connected earlier); draw after it
		task.defer(render)
	end)
end

function StashController.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if not win.isOpen() then
			return
		end
		acc += dt
		if acc < CLOSE_CHECK then
			return
		end
		acc = 0
		if tooFar() then
			win.close()
		end
	end)
end

return StashController
