--!strict
-- Shop-Fenster (Taste P oder das + an den Kapseln oben): links Reiter und Bestand, rechts die Angebote
-- des Reiters als Karten mit Kauf-Knopf. Regeln und Katalog liegen in Shared.Shop; gekauft wird auf dem
-- Server (Systems/Shop) über Net.Buy, die Rückmeldung kommt über Net.ShopResult.
-- Robux-Angebote öffnen den Roblox-Kaufdialog, sobald in Shared.Shop.Products echte IDs stehen.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Shop = require(ReplicatedStorage.Shared.Shop)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)

local ShopController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local PAD = 28
local LEFT_W = 380
local GAP = 24
local TAB_H = 64
local CARD_GAP = 20
local CARD_H = 520
local ART = 150 -- Bild/Slot oben in der Karte

local win: Window.Window
local left: Frame
local right: Frame

local tab = Shop.Tabs[1].id
local lastResult: { ok: boolean, text: string }? = nil

-- Bestand aus Player-Attributen (Server setzt sie: Inventory, Progress, Shop)
local ATTR: { [string]: string } = {
	gold = "Gold",
	soulstars = "Soulstars",
	potions = "Potions",
	candy = "Candy",
	shards = "Shards",
	dust = "Dust",
}
local WALLET_ORDER = { "gold", "soulstars", "potions", "shards", "candy", "dust" }

local function wallet(): Shop.Wallet
	local w: Shop.Wallet = {}
	for kind, attr in ATTR do
		local v = player:GetAttribute(attr)
		w[kind :: Shop.Kind] = if typeof(v) == "number" then v else 0
	end
	return w
end

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
	t.TextXAlignment = Enum.TextXAlignment.Center
	return t
end

-- ------------------------------------------------------------------ Links: Reiter und Bestand
local function renderLeft(have: Shop.Wallet)
	clear(left)
	local w = LEFT_W - 2 * PAD
	for i, t in Shop.Tabs do
		local active = t.id == tab
		local b =
			Kit.button(t.name, if active then C.Gold else C.Mana, Vector2.new(w, TAB_H), t.icon)
		b.Name = "Tab_" .. t.id
		b.Position = UDim2.fromOffset(PAD, PAD + (i - 1) * (TAB_H + 12))
		b.Activated:Connect(function()
			tab = t.id
			lastResult = nil
			ShopController.render()
		end)
		b.Parent = left
	end

	local top = PAD + #Shop.Tabs * (TAB_H + 12) + 12
	local divider = Kit.divider(w)
	divider.Position = UDim2.fromOffset(PAD, top)
	divider.Parent = left
	local head = Window.heading("Dein Bestand", 18, C.Muted)
	head.Position = UDim2.fromOffset(PAD, top + 24)
	head.Parent = left

	local rows = Window.frame(UDim2.fromOffset(w, 0), UDim2.fromOffset(PAD, top + 64))
	rows.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(rows, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
	for i, kind in WALLET_ORDER do
		local row = Window.frame(UDim2.fromOffset(w, 36))
		row.LayoutOrder = i
		local ic = Kit.icon(Shop.KindIcon[kind], 32)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.fromScale(0, 0.5)
		ic.Parent = row
		local name = Kit.label(Shop.KindName[kind], 16, C.Muted, Theme.Font.Body)
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.new(0, 44, 0.5, 0)
		name.Parent = row
		local n = have[kind :: Shop.Kind] or 0
		local max = Shop.Max[kind]
		local amount =
			Kit.label(if max then string.format("%d / %d", n, max) else Format.int(n), 17, C.Text)
		amount.AnchorPoint = Vector2.new(1, 0.5)
		amount.Position = UDim2.fromScale(1, 0.5)
		amount.Parent = row
		row.Parent = rows
	end
	rows.Parent = left
end

-- ------------------------------------------------------------------ Rechts: Angebote
-- Beste Tiefe über alle Gebiete (Server-Attribut), bestimmt die Goldpreise
local function bestDepth(): number
	local v = player:GetAttribute("BestDepth")
	return if typeof(v) == "number" then v else 1
end

local function priceButton(offer: Shop.Offer, have: Shop.Wallet, w: number): (ImageButton, string?)
	local size = Vector2.new(w, 64)
	local best = bestDepth()
	local price = Shop.price(offer, best)
	if price then
		local ok, why = Shop.check(offer, have, best)
		local b = Kit.button(Format.int(price.amount), C.Gold, size, Shop.KindIcon[price.kind])
		Kit.setEnabled(b, ok)
		b.Activated:Connect(function()
			if b.Active then
				Net.Buy:FireServer(offer.id)
			end
		end)
		return b, why
	end
	local product = Shop.productOf(offer)
	local planned = if offer.product then Shop.Products[offer.product] else nil
	local b = Kit.button(
		if planned then string.format("%d Robux", planned.robux) else "–",
		C.Gold,
		size
	)
	Kit.setEnabled(b, product ~= nil)
	b.Activated:Connect(function()
		if b.Active and product then
			MarketplaceService:PromptProductPurchase(player, product.id)
		end
	end)
	return b, if product then nil else "Bald verfügbar"
end

local function card(offer: Shop.Offer, have: Shop.Wallet, w: number): Frame
	local f = Window.frame(UDim2.fromOffset(w, CARD_H))
	f.Name = "Angebot_" .. offer.id
	Kit.skin(f, "stat_tile", 96, 0.4)
	local inner = w - 2 * PAD

	local pic: GuiObject? = Window.art(offer.art or "", Vector2.new(ART, ART))
	if not pic then
		local slot = Kit.itemSlot(ART, offer.icon, { rarity = offer.rarity })
		slot.Active = false
		pic = slot
	end
	local p = pic :: GuiObject
	p.AnchorPoint = Vector2.new(0.5, 0)
	p.Position = UDim2.new(0.5, 0, 0, PAD)
	p.ZIndex = 2
	p.Parent = f

	local info = Window.frame(UDim2.fromOffset(inner, 0), UDim2.fromOffset(PAD, PAD + ART + 16))
	info.AutomaticSize = Enum.AutomaticSize.Y
	local il = Kit.list(info, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
	il.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local name = Window.heading(offer.name, 22, Theme.Rarity[offer.rarity] or C.Text)
	name.LayoutOrder = 1
	name.ZIndex = 2
	name.Parent = info
	local gain = Kit.label(
		string.format(
			"+%s %s",
			Format.int(Shop.amount(offer, bestDepth())),
			Shop.KindName[offer.give]
		),
		18,
		C.Gold
	)
	gain.LayoutOrder = 2
	gain.ZIndex = 2
	gain.Parent = info
	local text = wrapLabel(offer.text, 15, C.Muted, inner)
	text.LayoutOrder = 3
	text.ZIndex = 2
	text.Parent = info
	info.Parent = f

	local buy, why = priceButton(offer, have, inner)
	buy.Name = "Kaufen"
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -PAD)
	buy.ZIndex = 2
	buy.Parent = f
	if why then
		-- im Textfluss unter der Beschreibung, damit große Handy-Schrift nichts überdeckt
		local reason =
			Kit.label(why, 14, if offer.price then C.Danger else C.Muted, Theme.Font.Body)
		reason.LayoutOrder = 4
		reason.ZIndex = 2
		reason.Parent = info
	end
	return f
end

local function renderRight(have: Shop.Wallet)
	clear(right)
	local rightW = Window.BODY.X - LEFT_W - GAP
	local tabInfo = Shop.Tabs[1]
	for _, t in Shop.Tabs do
		if t.id == tab then
			tabInfo = t
		end
	end
	local head = Window.heading(tabInfo.name, 26, C.GoldHi)
	head.Position = UDim2.fromOffset(PAD, PAD)
	head.Parent = right

	local offers = Shop.inTab(tab)
	local perRow = 3
	local cardW = math.floor((rightW - 2 * PAD - (perRow - 1) * CARD_GAP) / perRow)
	local grid =
		Window.frame(UDim2.fromOffset(rightW - 2 * PAD, CARD_H), UDim2.fromOffset(PAD, PAD + 56))
	local gl = Kit.list(grid, Enum.FillDirection.Horizontal, CARD_GAP, Enum.VerticalAlignment.Top)
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for i, offer in offers do
		local c = card(offer, have, cardW)
		c.LayoutOrder = i
		c.Parent = grid
	end
	grid.Parent = right

	local note = if lastResult
		then lastResult.text
		elseif tab == "seelensterne" then "Robux-Käufe sind noch nicht freigeschaltet."
		else "Gold gibt es im Rift, Seelensterne kommen bald."
	local foot = Kit.label(
		note,
		16,
		if lastResult and not lastResult.ok then C.Danger elseif lastResult then C.Good else C.Muted,
		Theme.Font.Body
	)
	foot.Name = "Hinweis"
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.new(0, PAD, 1, -PAD)
	foot.Parent = right
end

-- ------------------------------------------------------------------ Ablauf
function ShopController.render()
	local have = wallet()
	renderLeft(have)
	renderRight(have)
end

function ShopController.toggle()
	win.toggle()
end

-- Shop auf einem Reiter öffnen (das + an den Kapseln)
function ShopController.open(tabId: string?)
	if tabId then
		tab = tabId
	end
	lastResult = nil
	if win.isOpen() then
		ShopController.render()
	else
		win.toggle()
	end
end

function ShopController.init()
	win = Window.new({
		name = "Shop",
		title = "Shop",
		icon = "beutel",
		key = Enum.KeyCode.P,
		background = "bg_shop",
	})

	local body = Window.BODY
	left = Kit.panel(Vector2.new(LEFT_W, body.Y))
	left.Parent = win.body

	right = Kit.panel(Vector2.new(body.X - LEFT_W - GAP, body.Y))
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Parent = win.body

	win.onOpen(ShopController.render)
	local function refresh()
		if win.isOpen() then
			ShopController.render()
		end
	end
	for _, attr in ATTR do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	player:GetAttributeChangedSignal("BestDepth"):Connect(refresh) -- Goldpreise
	Net.ShopResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" or typeof(data.text) ~= "string" then
			return
		end
		lastResult = { ok = data.ok == true, text = data.text }
		refresh()
	end)
end

return ShopController
