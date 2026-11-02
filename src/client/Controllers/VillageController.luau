--!strict
-- Village window (key V, hub bar or the Village Ledger at the well): one card per building with
-- level, production and the upgrade price. Rules: Shared/Village; upgrades happen on the server
-- (Systems/Village) via Net.Village, the state arrives via Net.VillageState. After a join with
-- offline production a toast says what the Village made while the player was away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Village)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local HubController = require(script.Parent.HubController)
local QuestController = require(script.Parent.QuestController)

local VillageController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local PAD = 28
local GAP = 20
local CARD_H = 560
local ART = 120

local RESOURCE_NAME: { [string]: string } =
	{ gold = "Gold", shards = "Shards", candy = "Rune Candy" }

local win: Window.Window
local panel: Frame
local levels: { [string]: number } = {}

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

-- Per hour reads better than per second for slow buildings
local function rateText(b: Rules.Building, level: number): string
	local out = Rules.output(b, level)
	if not b.resource then
		return string.format("+%s%% Soulstars", Format.big(out))
	end
	local perHour = out * 3600
	local name = RESOURCE_NAME[b.resource] or b.resource
	if perHour < 10 then
		return string.format("%.1f %s / h", perHour, name)
	end
	return string.format("%s %s / h", Format.big(perHour), name)
end

local function wrap(text: string, size: number, color: Color3, w: number): TextLabel
	local t = Kit.label(text, size, color, Theme.Font.Body)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromOffset(w, 0)
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Center
	return t
end

local function card(b: Rules.Building, w: number, gold: number): Frame
	local level = levels[b.id] or 0
	local f = Window.frame(UDim2.fromOffset(w, CARD_H))
	f.Name = "Building_" .. b.id
	Kit.skin(f, "stat_tile", 96, 0.4)
	local inner = w - 2 * PAD

	local slot = Kit.itemSlot(ART, b.icon, { rarity = if level > 0 then "rare" else "normal" })
	slot.Active = false
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.new(0.5, 0, 0, PAD)
	slot.ZIndex = 2
	slot.Parent = f

	local info = Window.frame(UDim2.fromOffset(inner, 0), UDim2.fromOffset(PAD, PAD + ART + 16))
	info.AutomaticSize = Enum.AutomaticSize.Y
	local il = Kit.list(info, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
	il.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local name = Window.heading(b.name, 22, C.Text)
	name.LayoutOrder = 1
	name.Parent = info
	local lvl = Kit.label(if level > 0 then "Level " .. level else "Not built", 16, C.Muted)
	lvl.LayoutOrder = 2
	lvl.Parent = info
	local now = Kit.label(if level > 0 then rateText(b, level) else "–", 18, C.Gold)
	now.Name = "Rate"
	now.LayoutOrder = 3
	now.Parent = info
	local nextText = wrap("Next: " .. rateText(b, level + 1), 14, C.Muted, inner)
	nextText.LayoutOrder = 4
	nextText.Parent = info
	local text = wrap(b.text, 15, C.Muted, inner)
	text.LayoutOrder = 5
	text.Parent = info
	info.Parent = f

	local cost = Rules.cost(b, level)
	local button = Kit.button(
		if cost then Format.int(cost) else "Max",
		C.Gold,
		Vector2.new(inner, 64),
		if cost then "gold" else nil
	)
	button.Name = "Upgrade"
	Kit.setEnabled(button, cost ~= nil and gold >= cost)
	button.Activated:Connect(function()
		if button.Active then
			Net.Village:FireServer("upgrade", b.id)
		end
	end)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -PAD)
	button.ZIndex = 2
	button.Parent = f
	return f
end

function VillageController.render()
	clear(panel)
	local gold = (player:GetAttribute("Gold") or 0) :: number
	local head = Window.heading("Village", 26, C.GoldHi)
	head.Position = UDim2.fromOffset(PAD, PAD)
	head.Parent = panel
	local sub = Kit.label(
		"Buildings work while you play and at half speed while you are away (up to 8 h).",
		16,
		C.Muted,
		Theme.Font.Body
	)
	sub.Position = UDim2.fromOffset(PAD, PAD + 40)
	sub.Parent = panel

	local count = #Rules.Buildings
	local width = Window.BODY.X - 2 * PAD
	local cardW = math.floor((width - (count - 1) * GAP) / count)
	local grid = Window.frame(UDim2.fromOffset(width, CARD_H), UDim2.fromOffset(PAD, PAD + 90))
	Kit.list(grid, Enum.FillDirection.Horizontal, GAP, Enum.VerticalAlignment.Top)
	for i, b in Rules.Buildings do
		local c = card(b, cardW, gold)
		c.LayoutOrder = i
		c.Parent = grid
	end
	grid.Parent = panel
end

function VillageController.toggle()
	if not win.isOpen() then
		local hint = QuestController.lockHint("village")
		if hint then
			QuestController.toast("Locked · " .. hint, C.Muted)
			return
		end
	end
	win.toggle()
end

local function onState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local fresh: { [string]: number } = {}
	if typeof(payload.levels) == "table" then
		for id, lvl in payload.levels do
			if typeof(id) == "string" and Rules.ById[id] and typeof(lvl) == "number" then
				fresh[id] = lvl
			end
		end
	end
	levels = fresh
	local off = payload.offline
	if typeof(off) == "table" and typeof(off.pay) == "table" then
		local parts = {}
		for _, key in { "gold", "shards", "candy" } do
			local n = off.pay[key]
			if typeof(n) == "number" and n > 0 then
				table.insert(parts, "+" .. Format.big(n) .. " " .. (RESOURCE_NAME[key] or key))
			end
		end
		if #parts > 0 then
			QuestController.toast("While you were away: " .. table.concat(parts, " · "), C.Gold)
		end
	end
	if win.isOpen() then
		VillageController.render()
	end
end

function VillageController.init()
	win = Window.new({
		name = "Village",
		title = "Village",
		icon = "hub",
		key = Enum.KeyCode.V,
		unlock = "village",
	})
	panel = Kit.panel(Window.BODY)
	panel.Parent = win.body
	win.onOpen(VillageController.render)
	player:GetAttributeChangedSignal("Gold"):Connect(function()
		if win.isOpen() then
			VillageController.render()
		end
	end)
	Net.VillageState.OnClientEvent:Connect(onState)
	HubController.Requested.Event:Connect(function(name: string)
		if name == "Village" and not win.isOpen() then
			VillageController.toggle()
		end
	end)
end

return VillageController
