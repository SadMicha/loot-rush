--!strict
-- Inventory window (key I or hub button), flat code look (Theme.Flat, UI/Flat, UI/Spring).
--   header: title, bag count, currencies, close
--   left:   equipment around the 3D figure; below it the comparison equipped vs. selected item
--   right:  category tabs + search, item grid with rarity glow, footer with sort/filter and salvage mode
-- Only shows the snapshot from the server (Net.Inv); every action is a request to the server.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Forge = require(ReplicatedStorage.Shared.Forge)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Spring = require(script.Parent.Parent.UI.Spring)
local Window = require(script.Parent.Parent.UI.Window)
local AnimController = require(script.Parent.AnimController)
local ProgressController = require(script.Parent.ProgressController)
local QuestController = require(script.Parent.QuestController)

local InventoryController = {}

local C = Theme.Color
local F = Theme.Flat
local player = Players.LocalPlayer

local MAX_ITEMS = Items.BAG_MAX
local SALVAGE_GAP = 0.15 -- seconds between salvage requests (server allows 8 per second)
local SALVAGE_STALE = 3 -- seconds after sending: an item the server kept shows up again
local CONFIRM_TIME = 3 -- seconds a "tap again" confirmation stays armed

-- Layout (design pixels). The window is fitted to the screen width and grows in height on taller
-- screens (tablets) down to the menu dock: the figure gets taller and the bag cells bigger.
local WIN_W, WIN_H = 1460, 650 -- WIN_H = smallest height (phones)
local WIN_H_MAX = 1000
local WINDOW_TOP = 84
local HEAD_H = 48
local BODY_Y = HEAD_H + 12
local LEFT_W = 600
local RIGHT_X = LEFT_W + 16
local RIGHT_W = WIN_W - RIGHT_X
local DOLL_H = 334
local CMP_H = WIN_H - (BODY_Y + DOLL_H + 10)
local PAD = 14
local DOLL_CELL, DOLL_STEP = 60, 64
local GAP = 8
local cols, cellSize = 9, 80 -- bag grid; bigger cells / fewer columns when the window grows taller
local CELL_MAX = 120
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
local RARITY_RANK: { [string]: number } = { normal = 1, magic = 2, rare = 3, epic = 4, unique = 5 }
local RARITY_CYCLE = { "normal", "magic", "rare", "epic", "unique" }
local SORTS = { "rarity", "upgrades", "level", "newest" }
local SORT_NAME: { [string]: string } =
	{ rarity = "Rarity", upgrades = "Upgrades", level = "Item Level", newest = "Newest" }

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
local gridLayout: UIGridLayout
local bagCard: Frame
local stageLight: Frame
local countLabel: TextLabel
local capLabel: TextLabel
local ipLabel: TextLabel
local footNormal: Frame
local footSalvage: Frame
local salvageLabel: TextLabel
local quickNormal: TextLabel
local quickMagic: TextLabel
local autoButton: TextButton
local autoLabel: TextLabel
local AUTO_CYCLE = { "", "normal", "magic", "rare" } -- auto-salvage on pickup (never uniques)
local sortLabel: TextLabel
local filterLabel: TextLabel
local upgradeChip: Frame
local upgradeLabel: TextLabel
local tabs: Flat.Tabs
local searchFrame: Frame
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
local marked: { [string]: boolean } = {} -- salvage mode: epic/unique armed by a first tap
local pending: { [string]: number } = {} -- salvaged locally, waiting for the server (send time)
local salvageQueue: { string } = {}
local salvagedCount, salvagedGold = 0, 0 -- tally of the current salvage session
local quickArmed: string? = nil -- "normal"/"magic" while a quick salvage waits for its second tap
local popId: string? = nil -- cell that gets a selection pop on the next render
local seenIds: { [string]: boolean }? = nil -- item ids known so far (nil until the first snapshot)
local freshIds: { [string]: boolean } = {} -- new loot that gets a reveal when its cell is shown
local salvaging = false
local salvageItems: (list: { Items.Item }) -> ()

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
	-- Clones carry no playing animations: strike the class holding stance like in game
	-- (Anim.STANCE via AnimController); only a rig without Motor6D joints raises the weapon arm
	-- with Roblox's tool-hold animation (Systems/Weapons)
	local held = clone:FindFirstChild("HeldWeapon")
	local weapon = held and Weapons.ById[tostring(held:GetAttribute("Weapon") or "")]
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local posed = weapon ~= nil and AnimController.posePreview(clone, weapon.id, 0)
	if weapon and weapon.ready and not posed and humanoid and animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R6
			then Weapons.HOLD_ANIM.R6
			else Weapons.HOLD_ANIM.R15
		pcall(function()
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0)
		end)
	end
	-- Idle: gentle swaying and breathing while the window is open
	local base = clone:GetPivot()
	local t0 = os.clock()
	idleConn = RunService.Heartbeat:Connect(function()
		if not clone.Parent or not gui.Enabled then
			return
		end
		local t = os.clock() - t0
		if posed and weapon then
			AnimController.posePreview(clone, weapon.id, t)
		end
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
local layoutRender = false -- true while a resize rebuilds the grid: no loot reveals then
local function popIfSelected(cell: GuiButton, item: Items.Item)
	if freshIds[item.id] and gui.Enabled and not layoutRender then
		freshIds[item.id] = nil
		task.defer(Flat.reveal, cell)
	end
	if popId == item.id then
		local motion = cell:FindFirstChild("Motion")
		if motion and motion:IsA("UIScale") then
			Spring.impulse(motion, "Scale", 3, "Bouncy")
		end
	end
end

-- ------------------------------------------------------------------ Equipment (left top)
local dollTop = 12 -- y of the first equipment row (centered when the card grows)
local dollStep = DOLL_STEP -- row pitch of the equipment slots (grows with touch-sized slots)
-- Phones: the window is scaled so far down that text and slots grow to their minimum sizes. The
-- left column then shows either the figure or (while an item is picked) the comparison, each with
-- the full column height, instead of both stacked.
local compact = false
local COMPACT_UNIT = 0.62 -- screen pixels per window design pixel below which the layout is compact
local cmpH = CMP_H -- current height of the comparison card
local lastUnit = 0 -- screen pixels per window design pixel at the last refit

-- Text height and line pitch (window design pixels) of small text at the current scale: small
-- text is raised to Kit.MIN_TEXT_PX on screen, so rows must open up when the window shrinks
local function rhythm(): (number, number)
	local unit = if lastUnit > 0 then lastUnit else 1
	local t = math.max(Kit.fontSize(11), math.ceil(Kit.MIN_TEXT_PX / unit))
	return t, t + 4
end

-- Height of a button row (window design pixels): touch buttons grow to Kit.MIN_TOUCH_PX on screen
local function buttonH(): number
	local unit = if lastUnit > 0 then lastUnit else 1
	return if UserInputService.TouchEnabled
		then math.max(40, math.ceil(Kit.MIN_TOUCH_PX / unit))
		else 40
end
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
		b.Position = UDim2.fromOffset(x, dollTop + (row - 1) * dollStep)
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

	-- Stage: soft light behind the figure (no floor ring)
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
	stageLight = light

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
	local t, line = rhythm()
	local top = line + 4 -- below the caption
	local cell = Flat.cell(52, slotArt(item.slot), { rarity = item.rarity })
	cell.Active = false
	cell.Position = UDim2.fromOffset(0, top + 2)
	cell.Parent = parent
	local textW = COL_W - 64
	local name = Flat.text(item.name, 14, color, Theme.Font.Title)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.fromOffset(textW, math.max(20, t + 2))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(64, top)
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
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.Size = UDim2.fromOffset(textW, t)
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Position = UDim2.fromOffset(64, top + math.max(22, t + 4))
	sub.Parent = parent
	local ip =
		Flat.text("Item Power " .. Format.int(Items.itemPower(item)), 11, C.Text, Theme.Font.Body)
	ip.AutomaticSize = Enum.AutomaticSize.None
	ip.Size = UDim2.fromOffset(textW, t)
	ip.TextTruncate = Enum.TextTruncate.AtEnd
	ip.Position = UDim2.fromOffset(64, top + math.max(22, t + 4) + line)
	ip.Parent = parent
end

-- y of the first stat row below a caption + item header (or caption + one hint line)
local function statsTop(): number
	local t, line = rhythm()
	return line + 4 + math.max(56, math.max(22, t + 4) + line + t) + 8
end

-- Stat rows with bars; `other` = values to compare against (deltas shown when given)
local function statRows(
	parent: Frame,
	mine: { [string]: number },
	other: { [string]: number }?,
	accent: Color3
)
	local t, line = rhythm()
	local step = math.max(22, line)
	-- Compact (phones): no bars, the value stands right (left of the delta) so the enlarged label
	-- keeps its room; wide windows keep the bar layout
	local deltaW = if other then math.max(54, t * 3) else 0
	local valueX = if compact then COL_W - deltaW - 4 else 170
	for i, stat in STAT_ORDER do
		local y = statsTop() + (i - 1) * step
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
		value.Position = UDim2.fromOffset(valueX, y)
		value.Parent = parent
		if compact then
			if other then
				local d = v - (other[stat] or 0)
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
			continue
		end
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
	local t = Flat.text(string.upper(text), 13, color or C.Gold, Theme.Font.Title)
	t.Position = UDim2.fromOffset(0, 2)
	t.Parent = parent
end

local function renderCompare()
	clear(cmpCard)
	local left = Flat.frame(UDim2.fromOffset(COL_W, cmpH - 2 * PAD), UDim2.fromOffset(PAD, PAD))
	left.Name = "Equipped"
	left.Parent = cmpCard
	local right =
		Flat.frame(UDim2.fromOffset(COL_W, cmpH - 2 * PAD), UDim2.fromOffset(2 * PAD + COL_W, PAD))
	right.Name = "Selected"
	right.Parent = cmpCard
	local split = Instance.new("Frame")
	split.BackgroundColor3 = F.Edge
	split.BorderSizePixel = 0
	split.Position = UDim2.fromOffset(PAD + COL_W + PAD / 2, PAD)
	split.Size = UDim2.fromOffset(1, cmpH - 2 * PAD)
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
			local w = if compact then COL_W - 118 else COL_W
			local b = Flat.button("Unequip", "secondary", Vector2.new(w, buttonH()))
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
		local _, line = rhythm()
		hint.AutomaticSize = Enum.AutomaticSize.None
		hint.Size = UDim2.fromOffset(COL_W, 2 * line)
		hint.TextWrapped = true
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.Position = UDim2.fromOffset(0, line + 8)
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

		local actions = Flat.frame(UDim2.fromOffset(COL_W, buttonH()), UDim2.fromScale(0, 1))
		actions.AnchorPoint = Vector2.new(0, 1)
		local al = Kit.list(actions, Enum.FillDirection.Horizontal, 8)
		al.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local equip = Flat.button("Equip", "primary", Vector2.new(COL_W - 118, buttonH()))
		equip.LayoutOrder = 1
		equip.Activated:Connect(function()
			Net.Equip:FireServer(bagItem.id)
			selected = nil
		end)
		equip.Parent = actions
		local sell = Flat.button("Salvage", "danger", Vector2.new(110, buttonH()))
		sell.LayoutOrder = 2
		sell.Activated:Connect(function()
			selected = nil
			salvageItems({ bagItem })
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

	-- Compact (phones): the comparison stands in for the figure; Back brings the figure back
	if compact and item then
		local back = Flat.button("Back", "secondary", Vector2.new(110, buttonH()))
		back.Name = "Back"
		back.AnchorPoint = Vector2.new(1, 1)
		back.Position = UDim2.fromScale(1, 1)
		back.Activated:Connect(function()
			selected = nil
			InventoryController.render()
		end)
		back.Parent = left
	end
end

-- ------------------------------------------------------------------ Grid (right)
-- Upgrade marker per bag item (Items.upgradeMarks, same rule as the "UPGRADE" drop label)
local marks: { [string]: Items.UpgradeMark } = {}
local upgradeTotal = 0

local function refreshMarks()
	marks, upgradeTotal = Items.upgradeMarks(items, equipped)
end

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
	-- "Upgrades": upgrades first, the biggest gain on top (empty slots count as the biggest)
	local gains: { [string]: number } = {}
	if sortMode == "upgrades" then
		for _, item in list do
			gains[item.id] = if marks[item.id] == "up"
				then Items.upgradeGain(item, equipped[item.slot])
				else -math.huge
		end
	end
	table.sort(list, function(a, b)
		if sortMode == "upgrades" and gains[a.id] ~= gains[b.id] then
			return gains[a.id] > gains[b.id]
		end
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

-- Grid cells are kept per item id and only rebuilt when their look changes, so a click, a salvage
-- or a new server snapshot never resets the whole grid (scroll position and reveals stay).
type CellEntry = { cell: TextButton, key: string }
local itemCells: { [string]: CellEntry } = {}
local emptyPool: { TextButton } = {}
local gridShowsMaterials = false

local function resetGrid()
	clear(gridFrame)
	table.clear(itemCells)
	table.clear(emptyPool)
end

local function emptyCell(): TextButton
	local e = Flat.cell(cellSize, nil, nil)
	e.Name = "Empty"
	e.Active = false
	e.Parent = gridFrame
	return e
end

local function renderMaterials()
	local have = ProgressController.materials()
	for i, key in MATERIALS do
		local n = math.floor((have :: any)[key] or 0)
		local b = Flat.cell(cellSize, Forge.MaterialIcon[key], {
			rarity = if key == "dust" then "epic" elseif key == "candy" then "rare" else "magic",
			count = n,
		})
		b.Active = false
		b.LayoutOrder = i
		b.Parent = gridFrame
	end
	for i = #MATERIALS + 1, cols * 5 do
		emptyCell().LayoutOrder = i
	end
end

local function findItem(id: string): Items.Item?
	for _, it in items do
		if it.id == id then
			return it
		end
	end
	return nil
end

-- Send queued salvage requests one at a time (the server throttles to 8 per second)
local function pumpSalvage()
	if salvaging then
		return
	end
	salvaging = true
	task.spawn(function()
		while #salvageQueue > 0 do
			local id = table.remove(salvageQueue, 1) :: string
			pending[id] = os.clock()
			Net.Sell:FireServer(id)
			task.wait(SALVAGE_GAP)
		end
		salvaging = false
	end)
end

-- Salvage right away: the cells vanish at once, the server confirms with its next snapshot
local function salvageNow(list: { Items.Item })
	if #list == 0 then
		return
	end
	local gone: { [string]: boolean } = {}
	local clock = os.clock()
	for _, item in list do
		local sent = pending[item.id]
		if not sent or (sent ~= math.huge and clock - sent >= SALVAGE_STALE) then
			pending[item.id] = math.huge -- queued, not sent yet
			table.insert(salvageQueue, item.id)
			salvagedCount += 1
			salvagedGold += Items.sellValue(item)
		end
		gone[item.id] = true
		marked[item.id] = nil
	end
	local rest: { Items.Item } = {}
	for _, it in items do
		if not gone[it.id] then
			table.insert(rest, it)
		end
	end
	items = rest
	pumpSalvage()
	InventoryController.render()
end

local function onItemTap(id: string)
	local item = findItem(id)
	if not item then
		return
	end
	if not salvageMode then
		selectItem(item, false)
		return
	end
	-- Epic and unique items need a second tap, everything else goes on the first
	if (RARITY_RANK[item.rarity] or 0) >= RARITY_RANK.epic and not marked[id] then
		marked[id] = true
		InventoryController.render()
		task.delay(CONFIRM_TIME, function()
			if marked[id] then
				marked[id] = nil
				InventoryController.render()
			end
		end)
		return
	end
	salvageNow({ item })
end

local function renderItems(): number
	if gridShowsMaterials then
		resetGrid()
		gridShowsMaterials = false
	end
	local list = visibleItems()
	local keep: { [string]: boolean } = {}
	for i, item in list do
		local isSel = selected ~= nil
			and not selectedEquipped
			and selected.id == item.id
			and not salvageMode
		local isMarked = salvageMode and marked[item.id] == true
		local mark: Items.UpgradeMark? = marks[item.id]
		local key = item.rarity
			.. (if isSel then "|sel" else "")
			.. (if isMarked then "|mark" else "")
			.. (if mark then "|" .. mark else "")
		local entry: CellEntry? = itemCells[item.id]
		if entry and entry.key ~= key then
			entry.cell:Destroy()
			entry = nil
		end
		if not entry then
			local b = Flat.cell(cellSize, slotArt(item.slot), {
				rarity = item.rarity,
				selected = isSel,
				marked = isMarked,
				upgrade = mark,
			})
			b.Name = "Item"
			local id = item.id
			b.Activated:Connect(function()
				onItemTap(id)
			end)
			b.Parent = gridFrame
			entry = { cell = b, key = key }
			itemCells[item.id] = entry
		end
		local e = entry :: CellEntry
		e.cell.LayoutOrder = i
		keep[item.id] = true
		popIfSelected(e.cell, item)
	end
	for id, entry in itemCells do
		if not keep[id] then
			entry.cell:Destroy()
			itemCells[id] = nil
		end
	end
	-- Empty places up to full rows (at least the bag size in "All")
	local total = math.max(#list, if category == "all" then MAX_ITEMS else 0, cols * 5)
	total = math.ceil(total / cols) * cols
	local need = total - #list
	while #emptyPool < need do
		table.insert(emptyPool, emptyCell())
	end
	while #emptyPool > need do
		(table.remove(emptyPool) :: TextButton):Destroy()
	end
	for k, e in emptyPool do
		e.LayoutOrder = #list + k
	end
	return total
end

local function quickCount(rarity: string): number
	local limit = RARITY_RANK[rarity] or 0
	local n = 0
	for _, item in items do
		if (RARITY_RANK[item.rarity] or 0) <= limit then
			n += 1
		end
	end
	return n
end

local function renderGrid()
	countLabel.Text = string.format("%d / %d", #items, MAX_ITEMS)
	capLabel.Text = string.format("%d / %d", #items, MAX_ITEMS)
	refreshMarks()
	upgradeChip.Visible = upgradeTotal > 0
	upgradeLabel.Text =
		string.format("%d %s", upgradeTotal, if upgradeTotal == 1 then "Upgrade" else "Upgrades")
	local shown = 0
	if category == "materials" then
		resetGrid()
		gridShowsMaterials = true
		renderMaterials()
		shown = cols * 5
	else
		shown = renderItems()
	end
	local rows = math.ceil(shown / cols)
	gridFrame.CanvasSize = UDim2.fromOffset(0, rows * (cellSize + GAP) - GAP + 2 * GRID_PAD)

	-- Footer state
	footNormal.Visible = not salvageMode
	footSalvage.Visible = salvageMode
	salvageLabel.Text = if salvagedCount > 0
		then string.format("Salvaged %d - +%s Gold", salvagedCount, Format.big(salvagedGold))
		else "Tap items to salvage"
	salvageLabel.TextColor3 = if salvagedCount > 0 then C.Gold else F.Faint
	quickNormal.Text = if quickArmed == "normal"
		then string.format("Confirm %d?", quickCount("normal"))
		else "All Normal"
	quickMagic.Text = if quickArmed == "magic"
		then string.format("Confirm %d?", quickCount("magic"))
		else "All ≤ Magic"
	local auto = (player:GetAttribute("AutoSalvage") or "") :: string
	autoLabel.Text = if not QuestController.isOpen("auto_salvage")
		then "Auto: Locked"
		elseif auto == "" then "Auto: Off"
		else "Auto: ≤ " .. (Items.RarityName[auto] or auto)
	Flat.setEnabled(autoButton, QuestController.isOpen("auto_salvage"))
	sortLabel.Text = "Sort: " .. SORT_NAME[sortMode]
	filterLabel.Text = if rarityFilter
		then Items.RarityName[rarityFilter] or rarityFilter
		else "All Rarities"
end

-- Quick salvage of every bag item of a rarity and below (worn gear is never in the bag).
-- First tap arms it and shows the count, the second tap within CONFIRM_TIME salvages.
local function quickSalvage(rarity: string)
	if quickArmed ~= rarity then
		if quickCount(rarity) == 0 then
			return
		end
		quickArmed = rarity
		InventoryController.render()
		task.delay(CONFIRM_TIME, function()
			if quickArmed == rarity then
				quickArmed = nil
				InventoryController.render()
			end
		end)
		return
	end
	quickArmed = nil
	local limit = RARITY_RANK[rarity] or 0
	local list: { Items.Item } = {}
	for _, item in items do
		if (RARITY_RANK[item.rarity] or 0) <= limit then
			table.insert(list, item)
		end
	end
	salvageNow(list)
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
	bagCard = card
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
	searchFrame = search
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
	gridLayout = layout
	layout.CellSize = UDim2.fromOffset(cellSize, cellSize)
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
	local markNormal
	markNormal, quickNormal = footButton("All Normal", 110, nil, "ghost")
	quickNormal.TextSize = Kit.fontSize(12)
	markNormal.LayoutOrder = 1
	markNormal.Activated:Connect(function()
		quickSalvage("normal")
	end)
	markNormal.Parent = footSalvage
	local markMagic
	markMagic, quickMagic = footButton("All ≤ Magic", 110, nil, "ghost")
	quickMagic.TextSize = Kit.fontSize(12)
	markMagic.LayoutOrder = 2
	markMagic.Activated:Connect(function()
		quickSalvage("magic")
	end)
	markMagic.Parent = footSalvage
	-- Auto-salvage on pickup (unlocked at depth 10): cycles Off → Normal → Magic → Rare
	autoButton, autoLabel = footButton("Auto: Off", 118, nil, "ghost")
	autoLabel.TextSize = Kit.fontSize(12)
	autoButton.Name = "AutoSalvage"
	autoButton.LayoutOrder = 3
	autoButton.Activated:Connect(function()
		if not QuestController.isOpen("auto_salvage") then
			QuestController.toast("Locked - " .. (QuestController.lockHint("auto_salvage") or ""))
			return
		end
		local now = (player:GetAttribute("AutoSalvage") or "") :: string
		local i = table.find(AUTO_CYCLE, now) or 1
		Net.AutoSalvage:FireServer(AUTO_CYCLE[i % #AUTO_CYCLE + 1])
	end)
	autoButton.Parent = footSalvage
	-- Tally of this salvage session (epic/unique cells ask for a second tap)
	salvageLabel = Flat.text("Tap items to salvage", 12, F.Faint, Theme.Font.Body)
	salvageLabel.LayoutOrder = 4
	salvageLabel.Parent = footSalvage
	footSalvage.Parent = foot

	salvageToggle = Flat.toggle("Salvage", "salvage", C.Danger, function(on: boolean)
		salvageMode = on
		marked = {}
		quickArmed = nil
		salvagedCount, salvagedGold = 0, 0
		if on then
			selected = nil
		end
		InventoryController.render()
	end)
	-- centered on the footer: a touch-sized toggle grows up and down, not past the screen bottom
	salvageToggle.frame.AnchorPoint = Vector2.new(1, 0.5)
	salvageToggle.frame.Position = UDim2.new(1, 0, 0.5, 0)
	salvageToggle.frame.Parent = foot
end

-- ------------------------------------------------------------------ Header
local titleRow: Frame

local stage: Frame
local fit: UIScale
local guiRoot: Frame
local closeButton: GuiButton
local CLOSE_SIZE = 48 -- same as Window (top right of the screen, outside the scaled stage)

-- Window height in design pixels: the equipment card takes the extra height (taller figure, slots
-- centered), the bag grid picks the biggest cells that still show the whole bag without scrolling.
local shownH = WIN_H
local shownCompact = false
local shownUnit = 0
local function relayout(h: number)
	h = math.floor(h)
	local isCompact = lastUnit > 0 and lastUnit < COMPACT_UNIT
	if h == shownH and isCompact == shownCompact and math.abs(lastUnit - shownUnit) < 0.005 then
		return
	end
	shownH = h
	shownUnit = lastUnit
	shownCompact = isCompact
	compact = isCompact
	local extra = h - WIN_H
	stage.Size = UDim2.fromOffset(WIN_W, h)
	-- Compact: figure and comparison each take the whole left column (one shows at a time)
	local dollH = if compact then h - BODY_Y else DOLL_H + extra
	dollCard.Size = UDim2.fromOffset(LEFT_W, dollH)
	viewport.Size = UDim2.fromOffset(LEFT_W - 180, dollH - 16)
	stageLight.Position = UDim2.new(0.5, 0, 0, math.floor(dollH * 0.45))
	stageLight.Size = UDim2.fromOffset(300 + extra // 2, 300 + extra // 2)
	-- Slot rows: at least a touch-sized slot apart, the column centered in the card
	local unit = if lastUnit > 0 then lastUnit else 1
	local slotH = math.max(
		DOLL_CELL,
		if UserInputService.TouchEnabled then math.ceil(Kit.MIN_TOUCH_PX / unit) else 0
	)
	dollStep = math.max(DOLL_STEP, slotH + 4)
	local column = (#DOLL_LEFT - 1) * dollStep + slotH
	dollTop = math.max(12, math.floor((dollH - column) / 2))
	if compact then
		cmpH = dollH
		cmpCard.Position = UDim2.fromOffset(0, BODY_Y)
	else
		cmpH = CMP_H
		cmpCard.Position = UDim2.fromOffset(0, BODY_Y + dollH + 10)
	end
	cmpCard.Size = UDim2.fromOffset(LEFT_W, cmpH)
	-- Search field takes what the tabs leave (their text grows on phones); hidden below a usable width
	local room = RIGHT_W - 2 * PAD - tabs.width() - 10
	searchFrame.Visible = room >= 120
	searchFrame.Size = UDim2.fromOffset(math.clamp(room, 120, 190), TAB_H)
	bagCard.Size = UDim2.fromOffset(RIGHT_W, h - BODY_Y)
	local gridH = h - BODY_Y - (PAD + TAB_H + 6) - FOOT_H - PAD - 6
	gridFrame.Size = UDim2.fromOffset(gridFrame.Size.X.Offset, gridH)
	-- Fewest columns (= biggest cells) whose rows for a full bag still fit the grid height
	local inner = gridFrame.Size.X.Offset - 2 * GRID_PAD - 8 -- 8: scroll bar inset + rounding
	local bestCols, bestCell = 9, math.min(80, (inner - 8 * GAP) // 9)
	for c = 6, 9 do
		local size = math.min(CELL_MAX, (inner - (c - 1) * GAP) // c)
		local rows = math.ceil(MAX_ITEMS / c)
		if rows * (size + GAP) - GAP + 2 * GRID_PAD <= gridH and size > 80 then
			bestCols, bestCell = c, size
			break
		end
	end
	if bestCols ~= cols or bestCell ~= cellSize then
		cols, cellSize = bestCols, bestCell
		gridLayout.CellSize = UDim2.fromOffset(cellSize, cellSize)
		resetGrid() -- cells are rebuilt at the new size
	end
	layoutRender = true
	InventoryController.render()
	layoutRender = false
end

-- Fit the window into the screen: full width, and as tall as the room above the menu dock allows
-- (phones: the smallest height, scaled down). Keeps the title clear of the Roblox buttons.
local function arrange()
	local rootScale = guiRoot:FindFirstChildOfClass("UIScale")
	local s = if rootScale then rootScale.Scale else 1
	local camera = workspace.CurrentCamera
	if s <= 0 or not camera or camera.ViewportSize.X <= 0 then
		return
	end
	-- The root covers the gui's area: the whole screen, or the part between the side safe edges on
	-- notched phones (Roblox letterboxes it); everything below is relative to that area
	local guiX = Kit.guiLeft(gui)
	local screen = Kit.guiArea(gui)
	local view = screen / s -- design pixels
	local barRight, barH = Window.topbar()
	barRight -= guiX
	-- Close button like in every Window: right edge, vertically centered on the Roblox bar;
	-- the window starts below it
	local mid = math.max(40 + CLOSE_SIZE / 2 - 16, barH / s / 2)
	closeButton.Position = UDim2.new(1, -28, 0, mid)
	local closeH = math.max(CLOSE_SIZE, closeButton.Size.Y.Offset) -- grows on touch screens
	local stageTop = math.max(WINDOW_TOP, mid + closeH / 2 + 8)
	local reserveBottom, reserveLeft = Window.reserve()
	reserveLeft = math.max(0, reserveLeft - guiX)
	local leftFree = reserveLeft / s
	stage.Position = UDim2.new(0.5, leftFree / 2, 0, stageTop)

	local roomH = view.Y - stageTop - 12 - reserveBottom / s
	local k = math.min((view.X - 32 - leftFree) / WIN_W, F.MaxFit)
	local h = WIN_H
	if roomH / k >= WIN_H then
		h = math.min(roomH / k, WIN_H_MAX)
	else
		k = math.min(k, roomH / WIN_H)
	end
	k = math.max(k, 0.5)
	local unit = s * k -- screen pixels per window design pixel
	-- Scale and touch / text minimums first, then the new height (its re-render reads sizes)
	if math.abs(fit.Scale - k) > 0.001 or math.abs(unit - lastUnit) > 0.0001 then
		fit.Scale = k
		lastUnit = unit
		Kit.refit(guiRoot)
	end
	relayout(h)
	local indent = 0
	-- Computed, not read back: the layout of the new scale only lands next frame
	local top = stageTop * s
	local left = (screen.X + reserveLeft) / 2 - WIN_W * unit / 2
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
	Flat.corner(count, F.Radius.M)
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

	-- Arrow icon + "3 Upgrades": bag items that beat the worn piece of their slot (hidden at 0)
	upgradeChip = Instance.new("Frame")
	upgradeChip.Name = "Upgrades"
	upgradeChip.LayoutOrder = 3
	upgradeChip.Visible = false
	upgradeChip.BackgroundColor3 = F.Surface1
	upgradeChip.BackgroundTransparency = 0.1
	upgradeChip.BorderSizePixel = 0
	upgradeChip.AutomaticSize = Enum.AutomaticSize.X
	upgradeChip.Size = UDim2.fromOffset(0, 28)
	Flat.corner(upgradeChip, F.Radius.M)
	Flat.stroke(upgradeChip, C.Good, F.Stroke, 0.35)
	local up = Instance.new("UIPadding")
	up.PaddingLeft = UDim.new(0, 12)
	up.PaddingRight = UDim.new(0, 12)
	up.Parent = upgradeChip
	local ul = Kit.list(upgradeChip, Enum.FillDirection.Horizontal, 6)
	ul.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local arrow = Kit.icon("upgrade", 20)
	arrow.LayoutOrder = 1
	arrow.Parent = upgradeChip
	upgradeLabel = Flat.text("0 Upgrades", 12, C.Good)
	upgradeLabel.LayoutOrder = 2
	upgradeLabel.Parent = upgradeChip
	upgradeChip.Parent = titleRow

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
	-- Compact (phones): the comparison takes the figure's place while an item is picked
	dollCard.Visible = not (compact and selected ~= nil)
	cmpCard.Visible = not compact or selected ~= nil
	popId = nil
end

-- For other windows (Forge): current snapshot, change signal, icon per slot
local changed = Instance.new("BindableEvent")
InventoryController.changed = changed.Event

function InventoryController.snapshot(): ({ Items.Item }, { [string]: Items.Item })
	return items, equipped
end

-- "Upgrade waits" dot on the Inventory button (HUD): a bag item beats the worn piece of its slot
-- and the player has not opened the Inventory since it arrived. Opening the window clears it.
local upgradeSeen: { [string]: boolean } = {}
local upgradeEvent = Instance.new("BindableEvent")
InventoryController.upgradeChanged = upgradeEvent.Event

function InventoryController.upgradeWaiting(): boolean
	for _, it in items do
		if not upgradeSeen[it.id] and Items.SlotName[it.slot] then
			if Items.isUpgrade(it, equipped[it.slot]) then
				return true
			end
		end
	end
	return false
end

local function seeUpgrades()
	for _, it in items do
		upgradeSeen[it.id] = true
	end
end

function InventoryController.slotIcon(slot: string): string
	return slotArt(slot)
end

function InventoryController.toggle()
	gui.Enabled = not gui.Enabled
	if gui.Enabled then
		Window.closeCurrent() -- only one fullscreen window at a time
		Window.blur(true)
		Flat.sound("ui_open")
		Flat.pop(window)
		arrange()
		refreshViewport()
		if next(freshIds) ~= nil then
			InventoryController.render() -- loot that came in while closed gets its reveal now
		end
		seeUpgrades()
		upgradeEvent:Fire()
	else
		Flat.sound("ui_close")
		if not Window.anyOpen() then
			Window.blur(false)
		end
		salvageMode = false
		marked = {}
		quickArmed = nil
		salvageToggle.set(false)
		InventoryController.render()
	end
end

function InventoryController.init()
	salvageItems = salvageNow -- the compare panel (built above) salvages through the same queue
	local root: Frame
	gui, root = Kit.scaledGui("LootRushInventory", 5, true)
	gui.Enabled = false
	Window.exclusive(function()
		if gui.Enabled then
			InventoryController.toggle()
		end
	end, function()
		return gui.Enabled
	end, "Inventory")

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
	cmpCard.Position = UDim2.fromOffset(0, BODY_Y + DOLL_H + 10)
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
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(arrange)
	Window.onReserve(arrange)
	arrange()

	InventoryController.render()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function InventoryController.start()
	Net.Inv.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then
			return
		end
		local fresh: { Items.Item } = data.items or {}
		equipped = data.equipped or {}
		-- Items salvaged locally stay hidden until the server drops them (or forgets the request)
		local inBag: { [string]: boolean } = {}
		local clock = os.clock()
		items = {}
		for _, it in fresh do
			if typeof(it) == "table" and typeof(it.id) == "string" then
				inBag[it.id] = true
				local sent = pending[it.id]
				if not (sent and clock - sent < SALVAGE_STALE) then
					table.insert(items, it)
				end
			end
		end
		for id in pending do
			if not inBag[id] then
				pending[id] = nil
			end
		end
		-- New loot since the last snapshot gets a reveal animation (not the first load)
		local known = seenIds
		local now: { [string]: boolean } = {}
		for _, it in fresh do
			if typeof(it) == "table" and typeof(it.id) == "string" then
				now[it.id] = true
				if known and not known[it.id] then
					freshIds[it.id] = true
				end
			end
		end
		for id in equipped do
			local it = equipped[id]
			if typeof(it) == "table" and typeof(it.id) == "string" then
				now[it.id] = true
			end
		end
		for id in freshIds do
			if not now[id] then
				freshIds[id] = nil
			end
		end
		seenIds = now
		for id in upgradeSeen do
			if not now[id] then
				upgradeSeen[id] = nil
			end
		end
		if gui.Enabled then
			seeUpgrades() -- arrived while looking at the bag
		end
		InventoryController.render()
		changed:Fire()
		upgradeEvent:Fire()
	end)
	player:GetAttributeChangedSignal("AutoSalvage"):Connect(function()
		InventoryController.render()
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
