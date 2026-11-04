--!strict
-- Pet window (hub bar "Pets" button or the Pet Stable station): two tabs.
--   EGGS: both eggs as cards with price, the drop odds per rarity (always visible, required for paid
--     random items) and a Hatch button. Gold prices grow with the best depth, like in the shop.
--   COMPANIONS: owned pets as slots tinted by rarity, details with bonus text and Equip / Unequip.
-- Rules live in Shared/Pets; hatching and equipping happen on the server (Systems/Pets) via Net.Pet,
-- state arrives through PetController (Net.Pets), feedback through Net.PetResult.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Pets = require(ReplicatedStorage.Shared.Pets)
local Shop = require(ReplicatedStorage.Shared.Shop)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local HubController = require(script.Parent.HubController)
local QuestController = require(script.Parent.QuestController)
local PetController = require(script.Parent.PetController)

local PetWindowController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local PAD = 28
local TAB_W, TAB_H = 300, 64
local TOP = PAD + TAB_H + 20 -- content starts below the tab row
local FOOT = 52 -- feedback line at the bottom
local CARD_GAP = 24
local CARD_PAD = 24
local ART = 112
local ODD_H = 40
local CELL_W, CELL_H, SLOT = 136, 156, 112
local DETAIL_W = 580

local RARITY_NAME: { [string]: string } = {
	normal = "Normal",
	magic = "Magic",
	rare = "Rare",
	epic = "Epic",
	legend = "Legendary",
}
local STAT_NAME: { [string]: string } = {
	damage = "Damage",
	life = "Life",
	gold = "Gold",
	xp = "XP",
	items = "Item Chance",
}
local WALLET_ATTR: { [string]: string } = { gold = "Gold", soulstars = "Soulstars" }

local win: Window.Window
local panel: Frame

local tab = "eggs" -- "eggs" | "pets"
local selectedPet: string? = nil
local lastResult: { ok: boolean, text: string, rarity: string? }? = nil

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

local function wrapLabel(text: string, size: number, color: Color3, width: number): TextLabel
	local t = Kit.label(text, size, color, Theme.Font.Body)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromOffset(width, 0)
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	return t
end

local function number(v: number): string
	return if v % 1 == 0 then string.format("%d", v) else string.format("%.1f", v)
end

-- ------------------------------------------------------------------ State helpers
local function walletOf(kind: string): number
	local v = player:GetAttribute(WALLET_ATTR[kind] or "")
	return if typeof(v) == "number" then v else 0
end

local function bestDepth(): number
	local v = player:GetAttribute("BestDepth")
	return if typeof(v) == "number" then v else 1
end

local function owned(): { [string]: number }
	local o = PetController.state.owned
	return if typeof(o) == "table" then o else {}
end

local function slotCount(): number
	local s = PetController.state.slots
	return if typeof(s) == "number" then s else Pets.BASE_SLOTS
end

-- Equipped pets that exist on this server and fit the slots (unknown ids never show)
local function equippedList(): { string }
	local out: { string } = {}
	local list = PetController.state.equipped
	if typeof(list) == "table" then
		for _, id in list do
			if typeof(id) == "string" and Pets.ById[id] and #out < slotCount() then
				table.insert(out, id)
			end
		end
	end
	return out
end

-- Highest rarity an egg can drop (tints its slot)
local function topRarity(egg: Pets.Egg): string
	local best = "normal"
	for _, odd in Pets.odds(egg) do
		best = odd.rarity
	end
	return best
end

-- ------------------------------------------------------------------ Shared pieces
local function renderTabs()
	for i, t in { { "eggs", "Eggs" }, { "pets", "Companions" } } do
		local active = t[1] == tab
		local b =
			Kit.button(t[2], if active then C.Gold else C.Mana, Vector2.new(TAB_W, TAB_H), nil)
		b.Name = "Tab_" .. t[1]
		b.Position = UDim2.fromOffset(PAD + (i - 1) * (TAB_W + 12), PAD)
		b.Activated:Connect(function()
			tab = t[1]
			lastResult = nil
			PetWindowController.render()
		end)
		b.Parent = panel
	end

	-- Slot counter on the right
	local used = #equippedList()
	local counter = Kit.label(
		string.format("Companions equipped  %d/%d", used, slotCount()),
		20,
		if used >= slotCount() then C.Gold else C.Text
	)
	counter.Name = "SlotCounter"
	counter.AnchorPoint = Vector2.new(1, 0.5)
	counter.Position = UDim2.new(1, -PAD, 0, PAD + TAB_H / 2)
	counter.Parent = panel
end

local function renderFooter()
	local text = if lastResult then lastResult.text else nil
	if not text then
		text = if tab == "eggs"
			then "Hatching a duplicate raises its level, at max level it gives Crystal Shards."
			else "Equipped companions follow you and grant their bonus."
	end
	local color = C.Muted
	if lastResult then
		color = if not lastResult.ok
			then C.Danger
			else (lastResult.rarity and Theme.Rarity[lastResult.rarity]) or C.Good
	end
	local foot = Kit.label(text :: string, 18, color, Theme.Font.Body)
	foot.Name = "Hint"
	foot.AutomaticSize = Enum.AutomaticSize.None
	foot.Size = UDim2.new(1, -2 * PAD, 0, 30)
	foot.TextXAlignment = Enum.TextXAlignment.Left
	foot.TextTruncate = Enum.TextTruncate.AtEnd
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.new(0, PAD, 1, -PAD + 4)
	foot.Parent = panel
end

-- ------------------------------------------------------------------ Eggs
local function oddsRow(odd: Pets.Odd, w: number): Frame
	local row = Window.frame(UDim2.fromOffset(w, ODD_H))
	local col = Theme.Rarity[odd.rarity] or C.Text
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.BackgroundColor3 = col
	dot.BorderSizePixel = 0
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 4, 0.5, 0)
	dot.Size = UDim2.fromOffset(16, 16)
	Kit.corner(dot, 8)
	dot.Parent = row
	local name = Kit.label(RARITY_NAME[odd.rarity] or odd.rarity, 20, col)
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, 34, 0.5, 0)
	name.Parent = row
	local pct = Kit.label(string.format("%.1f%%", odd.percent), 22, C.Text)
	pct.Name = "Percent"
	pct.AnchorPoint = Vector2.new(1, 0.5)
	pct.Position = UDim2.new(1, 0, 0.5, 0)
	pct.Parent = row
	local back, fill = Kit.bar(Vector2.new(w - 330, 14), col)
	fill.Size = UDim2.fromScale(math.clamp(odd.percent / 100, 0.02, 1), 1)
	back.AnchorPoint = Vector2.new(0, 0.5)
	back.Position = UDim2.new(0, 190, 0.5, 0)
	back.Parent = row
	return row
end

local function eggCard(egg: Pets.Egg, w: number, h: number): Frame
	local f = Window.frame(UDim2.fromOffset(w, h))
	f.Name = "Egg_" .. egg.id
	Kit.skin(f, "stat_tile", 96, 0.4)
	local inner = w - 2 * CARD_PAD

	local art = Kit.itemSlot(ART, Pets.eggIconOf(egg), { rarity = topRarity(egg) })
	art.Active = false
	art.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD)
	art.ZIndex = 2
	art.Parent = f

	local textX = CARD_PAD + ART + 16
	local textW = w - textX - CARD_PAD
	local name = Window.heading(egg.name, 24, C.GoldHi)
	name.Position = UDim2.fromOffset(textX, CARD_PAD)
	name.ZIndex = 2
	name.Parent = f
	local desc = wrapLabel(egg.text, 16, C.Muted, textW)
	desc.Position = UDim2.fromOffset(textX, CARD_PAD + 34)
	desc.ZIndex = 2
	desc.Parent = f

	-- Price (live: gold grows with the best depth)
	-- nil until the first pet state arrived (no "FREE" flash for players who own pets)
	local ownedNow: number? = nil
	if typeof(PetController.state.owned) == "table" then
		ownedNow = 0
		for _ in owned() do
			ownedNow = (ownedNow :: number) + 1
		end
	end
	local price = Pets.eggPrice(egg, bestDepth(), ownedNow)
	local affordable = walletOf(egg.price.kind) >= price
	local priceRow = Window.frame(UDim2.fromOffset(textW, 32))
	priceRow.Name = "Price"
	priceRow.Position = UDim2.fromOffset(textX, CARD_PAD + ART - 32)
	priceRow.ZIndex = 2
	Kit.list(priceRow, Enum.FillDirection.Horizontal, 8).HorizontalAlignment =
		Enum.HorizontalAlignment.Left
	local ic = Kit.icon(Shop.KindIcon[egg.price.kind] or "gold", 30)
	ic.LayoutOrder = 1
	ic.Parent = priceRow
	local amount = Kit.label(
		if price == 0 then "FREE" else Format.int(price),
		24,
		if affordable then C.Gold else C.Danger
	)
	amount.LayoutOrder = 2
	amount.Parent = priceRow
	if price == 0 then
		local first = Kit.label("· your first pet", 14, C.Muted, Theme.Font.Body)
		first.LayoutOrder = 3
		first.Parent = priceRow
	elseif egg.price.kind == "gold" then
		local grows = Kit.label("· grows with depth", 14, C.Muted, Theme.Font.Body)
		grows.LayoutOrder = 3
		grows.Parent = priceRow
	end
	priceRow.Parent = f

	local divider = Kit.divider(inner)
	divider.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD + ART + 14)
	divider.Parent = f

	-- Odds list: always visible before purchase
	local oddsHead = Window.heading("Drop chances", 16, C.Muted)
	oddsHead.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD + ART + 30)
	oddsHead.Parent = f
	local rows =
		Window.frame(UDim2.fromOffset(inner, 0), UDim2.fromOffset(CARD_PAD, CARD_PAD + ART + 62))
	rows.Name = "Odds"
	rows.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(rows, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Top)
	for i, odd in Pets.odds(egg) do
		local row = oddsRow(odd, inner)
		row.LayoutOrder = i
		row.Parent = rows
	end
	rows.Parent = f

	-- Can't pay: the disabled button itself says why (no extra line squeezed above it)
	local hatch = Kit.button(
		if affordable
			then "Hatch"
			else "Not enough " .. (Shop.KindName[egg.price.kind] or egg.price.kind),
		C.Gold,
		Vector2.new(inner, 64),
		nil
	)
	hatch.Name = "Hatch_" .. egg.id
	hatch.AnchorPoint = Vector2.new(0.5, 1)
	hatch.Position = UDim2.new(0.5, 0, 1, -CARD_PAD)
	hatch.ZIndex = 2
	Kit.setEnabled(hatch, affordable)
	hatch.Activated:Connect(function()
		if hatch.Active then
			Net.Pet:FireServer("hatch", egg.id)
		end
	end)
	hatch.Parent = f
	return f
end

local function renderEggs()
	local cardW = math.floor((Window.BODY.X - 2 * PAD - CARD_GAP) / 2)
	local cardH = Window.BODY.Y - TOP - FOOT - PAD
	for i, egg in Pets.Eggs do
		local card = eggCard(egg, cardW, cardH)
		card.Position = UDim2.fromOffset(PAD + (i - 1) * (cardW + CARD_GAP), TOP)
		card.Parent = panel
	end
end

-- ------------------------------------------------------------------ Companions
local function bonusLines(id: string, level: number): { string }
	local lines: { string } = {}
	local pet = Pets.ById[id]
	if not pet then
		return lines
	end
	local stats = {}
	for stat in pet.bonus do
		table.insert(stats, stat)
	end
	table.sort(stats)
	for _, stat in stats do
		local v = (Pets.bonusOf(id, level)[stat]) :: number
		if stat == "magnet" then
			table.insert(lines, string.format("+%s studs pickup radius", number(v)))
		else
			table.insert(lines, string.format("+%s%% %s", number(v), STAT_NAME[stat] or stat))
		end
	end
	return lines
end

local function levelPips(level: number): Frame
	local row = Window.frame(UDim2.fromOffset(Pets.MAX_LEVEL * 30, 22))
	Kit.list(row, Enum.FillDirection.Horizontal, 6).HorizontalAlignment =
		Enum.HorizontalAlignment.Left
	for i = 1, Pets.MAX_LEVEL do
		local pip = Instance.new("Frame")
		pip.LayoutOrder = i
		pip.Size = UDim2.fromOffset(24, 14)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = if i <= level then C.Gold else C.Bg3
		Kit.corner(pip, 7)
		pip.Parent = row
	end
	return row
end

local function renderDetail(x: number, w: number, h: number, ownedMap: { [string]: number })
	local f = Window.frame(UDim2.fromOffset(w, h), UDim2.fromOffset(x, TOP))
	f.Name = "Detail"
	Kit.skin(f, "stat_tile", 96, 0.4)
	local id = selectedPet
	local pet = if id then Pets.ById[id] else nil
	if not id or not pet then
		local empty = wrapLabel("Select a companion.", 18, C.Muted, w - 2 * CARD_PAD)
		empty.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD)
		empty.Parent = f
		f.Parent = panel
		return
	end
	local level = ownedMap[id] or 1
	local col = Theme.Rarity[pet.rarity] or C.Text
	local inner = w - 2 * CARD_PAD

	local big = Kit.itemSlot(ART, Pets.iconOf(pet), { rarity = pet.rarity })
	big.Active = false
	big.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD)
	big.ZIndex = 2
	big.Parent = f

	local info = Window.frame(
		UDim2.fromOffset(inner - ART - 16, 0),
		UDim2.fromOffset(CARD_PAD + ART + 16, CARD_PAD)
	)
	info.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(info, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Top).HorizontalAlignment =
		Enum.HorizontalAlignment.Left
	local name = Window.heading(pet.name, 24, col)
	name.LayoutOrder = 1
	name.Parent = info
	local sub = Kit.label(
		string.format(
			"%s · Level %d/%d",
			RARITY_NAME[pet.rarity] or pet.rarity,
			level,
			Pets.MAX_LEVEL
		),
		17,
		C.Muted,
		Theme.Font.Body
	)
	sub.LayoutOrder = 2
	sub.Parent = info
	local pips = levelPips(level)
	pips.LayoutOrder = 3
	pips.Parent = info
	info.Parent = f

	-- Everything below stacked, so long texts push the rest down
	local body =
		Window.frame(UDim2.fromOffset(inner, 0), UDim2.fromOffset(CARD_PAD, CARD_PAD + ART + 16))
	body.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(body, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top).HorizontalAlignment =
		Enum.HorizontalAlignment.Left
	local text = wrapLabel(pet.text, 17, C.Text, inner)
	text.LayoutOrder = 1
	text.Parent = body
	for i, line in bonusLines(id, level) do
		local l = Kit.label(line, 22, C.Gold)
		l.Name = "Bonus"
		l.LayoutOrder = 1 + i
		l.Parent = body
	end
	local note = if level >= Pets.MAX_LEVEL
		then string.format("Max level. A duplicate gives %d Crystal Shards.", Pets.DUPE_SHARDS)
		else string.format("Next level: %s", table.concat(bonusLines(id, level + 1), ", "))
	local n = wrapLabel(note, 15, C.Muted, inner)
	n.LayoutOrder = 10
	n.Parent = body
	body.Parent = f

	local equipped = table.find(equippedList(), id) ~= nil
	local btn = Kit.button(
		if equipped then "Unequip" else "Equip",
		if equipped then C.Mana else C.Gold,
		Vector2.new(inner, 64),
		nil
	)
	btn.Name = "EquipToggle"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -CARD_PAD)
	btn.ZIndex = 2
	btn.Activated:Connect(function()
		lastResult = nil
		Net.Pet:FireServer(if equipped then "unequip" else "equip", id)
	end)
	btn.Parent = f
	if not equipped and #equippedList() >= slotCount() then
		local first = equippedList()[1]
		local replaced = if first and Pets.ById[first] then Pets.ById[first].name else "oldest"
		local hint = Kit.label(
			string.format("Slots full: replaces %s", replaced),
			14,
			C.Muted,
			Theme.Font.Body
		)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -CARD_PAD - 70)
		hint.Parent = f
	elseif slotCount() < Pets.MAX_SLOTS then
		local hint =
			Kit.label("A second slot comes with the Pet Slot pass.", 14, C.Muted, Theme.Font.Body)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -CARD_PAD - 70)
		hint.Parent = f
	end
	f.Parent = panel
end

local function petCell(pet: Pets.Pet, level: number, equipped: boolean, selected: boolean): Frame
	local cell = Window.frame(UDim2.fromOffset(CELL_W, CELL_H))
	cell.Name = "Pet_" .. pet.id
	local slot = Kit.itemSlot(SLOT, Pets.iconOf(pet), { rarity = pet.rarity, selected = selected })
	slot.Name = "PetSlot"
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.new(0.5, 0, 0, 6)
	slot.Activated:Connect(function()
		selectedPet = pet.id
		lastResult = nil
		PetWindowController.render()
	end)
	slot.Parent = cell
	if equipped then
		local mark = Instance.new("Frame")
		mark.Name = "EquippedMark"
		mark.BackgroundColor3 = C.Gold
		mark.BorderSizePixel = 0
		mark.AnchorPoint = Vector2.new(0.5, 0)
		mark.Position = UDim2.new(0.5, 0, 0, 0)
		mark.Size = UDim2.fromOffset(72, 22)
		mark.ZIndex = 5
		Kit.corner(mark, 11)
		local t = Kit.label("Active", 14, C.Bg0)
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.5)
		t.ZIndex = 6
		t.Parent = mark
		mark.Parent = cell
	end
	local name = Kit.label(pet.name, 16, Theme.Rarity[pet.rarity] or C.Text, Theme.Font.Body)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.fromOffset(CELL_W, 20)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(0, SLOT + 12)
	name.Parent = cell
	local lv = Kit.label(
		if level >= Pets.MAX_LEVEL then "Lv 5 MAX" else string.format("Lv %d", level),
		14,
		if level >= Pets.MAX_LEVEL then C.Gold else C.Muted,
		Theme.Font.Body
	)
	lv.AutomaticSize = Enum.AutomaticSize.None
	lv.Size = UDim2.fromOffset(CELL_W, 18)
	lv.TextXAlignment = Enum.TextXAlignment.Center
	lv.Position = UDim2.fromOffset(0, SLOT + 34)
	lv.Parent = cell
	return cell
end

local function renderPets()
	local ownedMap = owned()
	local list: { Pets.Pet } = {}
	for _, pet in Pets.List do
		if ownedMap[pet.id] then
			table.insert(list, pet)
		end
	end
	local h = Window.BODY.Y - TOP - FOOT - PAD

	if #list == 0 then
		local empty = wrapLabel(
			"No companions yet. Hatch an egg to find your first one.",
			20,
			C.Muted,
			Window.BODY.X - 2 * PAD
		)
		empty.Position = UDim2.fromOffset(PAD, TOP)
		empty.Parent = panel
		local go = Kit.button("Go to Eggs", C.Gold, Vector2.new(300, TAB_H), nil)
		go.Position = UDim2.fromOffset(PAD, TOP + 56)
		go.Activated:Connect(function()
			tab = "eggs"
			lastResult = nil
			PetWindowController.render()
		end)
		go.Parent = panel
		return
	end

	-- keep a valid selection: previous one, else first equipped, else first owned
	if not selectedPet or not ownedMap[selectedPet] or not Pets.ById[selectedPet] then
		selectedPet = equippedList()[1] or list[1].id
	end

	local gridW = Window.BODY.X - 2 * PAD - DETAIL_W - CARD_GAP
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(PAD, TOP)
	grid.Size = UDim2.fromOffset(gridW, h)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = C.Gold
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
	layout.CellPadding = UDim2.fromOffset(12, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local equipped = equippedList()
	for i, pet in list do
		local cell = petCell(
			pet,
			ownedMap[pet.id] or 1,
			table.find(equipped, pet.id) ~= nil,
			pet.id == selectedPet
		)
		cell.LayoutOrder = i
		cell.Parent = grid
	end
	grid.Parent = panel

	renderDetail(PAD + gridW + CARD_GAP, DETAIL_W, h, ownedMap)
end

-- ------------------------------------------------------------------ Flow
function PetWindowController.render()
	clear(panel)
	renderTabs()
	if tab == "eggs" then
		renderEggs()
	else
		renderPets()
	end
	renderFooter()
end

function PetWindowController.toggle()
	win.toggle()
end

function PetWindowController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function PetWindowController.init()
	win = Window.new({
		name = "Pets",
		title = "Pet Stable",
		icon = "companion",
	})
	panel = Kit.panel(Window.BODY)
	panel.Parent = win.body

	win.onOpen(PetWindowController.render)
	local function refresh()
		if win.isOpen() then
			PetWindowController.render()
		end
	end
	PetController.Changed.Event:Connect(refresh)
	for _, attr in WALLET_ATTR do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	player:GetAttributeChangedSignal("BestDepth"):Connect(refresh) -- live egg price

	Net.PetResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" or typeof(data.text) ~= "string" then
			return
		end
		local pet = if typeof(data.pet) == "string" then Pets.ById[data.pet] else nil
		local wasHatch = data.kind == "hatch"
		lastResult = {
			ok = data.ok == true,
			text = data.text,
			rarity = if data.ok == true and wasHatch and pet then pet.rarity else nil,
		}
		if data.ok == true and wasHatch and pet then
			selectedPet = pet.id -- the new/leveled pet is the one shown in Companions
		end
		refresh()
	end)

	HubController.Requested.Event:Connect(function(name: string)
		if name == "Pets" then
			local hint = QuestController.lockHint("pets")
			if hint then
				QuestController.toast("Locked · " .. hint)
			else
				PetWindowController.open()
			end
		end
	end)
end

return PetWindowController
