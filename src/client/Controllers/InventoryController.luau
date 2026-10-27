--!strict
-- Inventar-Fenster (Taste I oder Menü-Button): Ausrüstung links, Raster in der Mitte, Details rechts.
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

local gui: ScreenGui
local grid: Frame
local equipCol: Frame
local detail: Frame
local items: { Items.Item } = {}
local equipped: { [string]: Items.Item } = {}
local selected: Items.Item? = nil
local selectedEquipped = false

local COLUMNS, CELL, GAP = 8, 58, 6

local function rarityColor(item: Items.Item): Color3
	return Theme.Rarity[item.rarity] or Theme.Rarity.normal
end

local function itemButton(item: Items.Item?, size: number, caption: string): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = C.Bg2
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = ""
	Kit.corner(b, Theme.Radius.S)
	Kit.stroke(b, if item then rarityColor(item) else C.Line, if item then 2 else 1)
	local t = Kit.label(caption, 11, if item then rarityColor(item) else C.Muted, Theme.Font.Body)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, -6, 1, -6)
	t.TextWrapped = true
	t.Parent = b
	return b
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

local function line(text: string, color: Color3, order: number, size: number?): TextLabel
	local l = Kit.label(text, size or 15, color, Theme.Font.Body)
	l.LayoutOrder = order
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, 0)
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = detail
	return l
end

local function actionButton(text: string, color: Color3, order: number, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 40)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Text = text
	b.TextSize = 16
	b.TextColor3 = C.Bg0
	b.FontFace = Theme.Font.UI
	b.BorderSizePixel = 0
	Kit.corner(b, Theme.Radius.M)
	b.Activated:Connect(onClick)
	b.Parent = detail
end

local function renderDetail()
	clear(detail)
	local item = selected
	if not item then
		line("Wähle einen Gegenstand", C.Muted, 1)
		return
	end
	line(item.name, rarityColor(item), 1, 18)
	line(
		string.format("%s · Stufe %d", Items.SlotName[item.slot] or item.slot, item.ilvl),
		C.Muted,
		2,
		13
	)
	for i, a in item.affixes do
		line(Items.affixText(a), if a.implicit then C.Gold else C.Text, 10 + i)
	end
	if selectedEquipped then
		actionButton("Ablegen", C.Cyan, 100, function()
			Net.Unequip:FireServer(item.slot)
			selected = nil
		end)
	else
		actionButton("Ausrüsten", C.Cyan, 100, function()
			Net.Equip:FireServer(item.id)
			selected = nil
		end)
		actionButton(
			"Verkaufen (" .. tostring(Items.sellValue(item)) .. ")",
			C.Gold,
			101,
			function()
				Net.Sell:FireServer(item.id)
				selected = nil
			end
		)
	end
end

local function select(item: Items.Item, isEquipped: boolean)
	selected = item
	selectedEquipped = isEquipped
	renderDetail()
end

local function render()
	clear(grid)
	for i, item in items do
		local b = itemButton(item, CELL, item.name)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			select(item, false)
		end)
		b.Parent = grid
	end

	clear(equipCol)
	for i, slot in Items.Slots do
		local item = equipped[slot]
		local b = itemButton(item, 72, if item then item.name else Items.SlotName[slot])
		b.LayoutOrder = i
		if item then
			b.Activated:Connect(function()
				select(item, true)
			end)
		end
		b.Parent = equipCol
	end

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
	renderDetail()
end

function InventoryController.toggle()
	gui.Enabled = not gui.Enabled
end

function InventoryController.init()
	local root: Frame
	gui, root = Kit.scaledGui("LootRushInventory", 5)
	gui.Enabled = false

	local panel = Kit.panel(Vector2.new(900, 560))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Parent = root

	local title = Kit.label("Inventar", 24, C.Text, Theme.Font.Title)
	title.Position = UDim2.fromOffset(24, 18)
	title.Parent = panel
	local close = Kit.iconButton("schliessen", "Schließen", 36, false)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 14)
	close.Activated:Connect(InventoryController.toggle)
	close.Parent = panel

	equipCol = Instance.new("Frame")
	equipCol.BackgroundTransparency = 1
	equipCol.Position = UDim2.fromOffset(24, 70)
	equipCol.Size = UDim2.fromOffset(72, 5 * 72 + 4 * 10)
	Kit.list(equipCol, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	equipCol.Parent = panel

	grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(120, 70)
	grid.Size = UDim2.fromOffset(COLUMNS * (CELL + GAP), 5 * (CELL + GAP))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = panel

	detail = Instance.new("Frame")
	detail.BackgroundColor3 = C.Bg2
	detail.BorderSizePixel = 0
	detail.Position = UDim2.fromOffset(630, 70)
	detail.Size = UDim2.fromOffset(250, 460)
	Kit.corner(detail, Theme.Radius.M)
	Kit.stroke(detail, C.Line)
	Kit.padding(detail, 14)
	local dl = Instance.new("UIListLayout")
	dl.Padding = UDim.new(0, 8)
	dl.SortOrder = Enum.SortOrder.LayoutOrder
	dl.Parent = detail
	detail.Parent = panel

	renderDetail()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function InventoryController.start()
	Net.Inv.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then
			return
		end
		items = data.items or {}
		equipped = data.equipped or {}
		render()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.I then
			InventoryController.toggle()
		end
	end)
end

return InventoryController
