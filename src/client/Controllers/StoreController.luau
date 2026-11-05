--!strict
-- Shop window = the Robux shop (bar button "Shop", key P, the + on the gold and Soulstar capsules).
-- Tabs: Featured (hero banner + hot offers), Soulstars, Gold, Cosmetics (preview + wardrobe + packs),
-- Passes. The Cosmetics tab starts with a turning 3D preview of the own hero (UI/CosmeticPreview):
-- it shows the worn look, or a pack's cosmetics after "Try on" on its card.
-- Catalog and button states: Shared/Store; what a purchase gives and every Robux ID:
-- Shared/Monetization. The client only opens the Roblox purchase dialog; the server books the
-- purchase (Systems/Monetization) and answers via Net.ShopResult (robux = true) → celebration.
-- An ID that is still 0 shows a disabled "Coming soon" button.
-- The in-game trades (materials, gold for Soulstars) are the Market (MarketController).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local CosmeticRules = require(ReplicatedStorage.Shared.Cosmetics)
local Monetization = require(ReplicatedStorage.Shared.Monetization)
local Net = require(ReplicatedStorage.Shared.Net)
local Store = require(ReplicatedStorage.Shared.Store)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local CosmeticPreview = require(script.Parent.Parent.UI.CosmeticPreview)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Spring = require(script.Parent.Parent.UI.Spring)
local Window = require(script.Parent.Parent.UI.Window)
local MarketController = require(script.Parent.MarketController)

local StoreController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local F = Theme.Flat
local S = Theme.Store
local BODY = Window.BODY
local PAD = 24
local SCROLLBAR = 8
local PAGE_W = BODY.X - SCROLLBAR - 4
local GRID_TOP = 14
local GRID_LEFT = 10
local CARD_W = math.floor((PAGE_W - GRID_LEFT - 2 * S.Gap) / 3) -- 3 per row

local win: Window.Window
local tabs: Flat.Tabs
local page: ScrollingFrame
local starLabel: TextLabel
local goldLabel: TextLabel
local tab = "featured"
local promptAt = 0 -- debounce of the purchase dialog

-- Robux shop state from the server (Net.Store)
local ownedCosmetics: { [string]: boolean } = {}
local wear: { [string]: string } = { trail = "", aura = "" }
local bought: { [string]: boolean } = {}
-- Cosmetics preview: built once, moved into each new render of the Cosmetics tab
local preview: CosmeticPreview.Preview? = nil
local trying: { [string]: string }? = nil -- slot → id of a pack being tried on (nil = own look)

local owner: Store.Owner = {
	pass = function(key: string): boolean
		return player:GetAttribute(Monetization.passAttr(key)) == true
	end,
	cosmetic = function(id: string): boolean
		return ownedCosmetics[id] == true
	end,
	bought = function(key: string): boolean
		return bought[key] == true
	end,
}

-- ------------------------------------------------------------------ Animation clock
-- One Heartbeat while the window is open: floating art, turning light rays, pulsing badges.
type Bob = { obj: GuiObject, base: UDim2, phase: number }
local bobs: { Bob } = {}
local rays: { [GuiObject]: number } = {} -- ray wheel → speed factor
local pulses: { UIScale } = {}
local clock: RBXScriptConnection? = nil

local function tick()
	if not win.isOpen() then
		if clock then
			clock:Disconnect()
			clock = nil
		end
		return
	end
	local t = os.clock()
	for _, b in bobs do
		b.obj.Position = b.base + UDim2.fromOffset(0, math.sin(t * S.BobSpeed + b.phase) * S.Bob)
	end
	for wheel, speed in rays do
		if wheel.Parent then
			wheel.Rotation = (t * S.RaySpin * speed) % 360
		else
			rays[wheel] = nil
		end
	end
	for _, p in pulses do
		-- only grows (never below 1): the badge text is already at the phone minimum size
		p.Scale = 1 + (math.sin(t * 5) * 0.5 + 0.5) * S.BadgePulse
	end
end

local function runClock()
	if not clock then
		clock = RunService.Heartbeat:Connect(tick)
	end
end

local function bob(obj: GuiObject)
	table.insert(bobs, { obj = obj, base = obj.Position, phase = math.random() * 2 * math.pi })
end

-- ------------------------------------------------------------------ Small pieces
local function bestDepth(): number
	local v = player:GetAttribute("BestDepth")
	return if typeof(v) == "number" then v else 1
end

local function number(attr: string): number
	local v = player:GetAttribute(attr)
	return if typeof(v) == "number" then v else 0
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function wrapText(text: string, size: number, color: Color3, width: number): TextLabel
	local t = Flat.text(text, size, color, Theme.Font.Body, Enum.TextXAlignment.Center)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromOffset(width, 0)
	t.TextWrapped = true
	return t
end

-- Robux glyph (built-in texture) or "R$" when the image is not registered
local function robuxGlyph(size: number, color: Color3): GuiObject
	if Assets.Robux ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "Robux"
		img.BackgroundTransparency = 1
		img.Image = Assets.Robux
		img.ImageColor3 = color
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromOffset(size, size)
		return img
	end
	return Flat.text("R$", size * 0.6, color, Theme.Font.Number)
end

-- Ribbon in the top left corner ("BEST VALUE", "LIMITED" pulses)
local function badge(kind: string): Frame
	local color = S.Badge[kind] or C.Gold
	local f = Instance.new("Frame")
	f.Name = "Badge"
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 36)
	f.Rotation = -5
	f.ZIndex = 8
	Flat.corner(f, F.Radius.M)
	Flat.gradient(f, color:Lerp(Color3.new(1, 1, 1), 0.3), color)
	Flat.stroke(f, color:Lerp(Color3.new(1, 1, 1), 0.5), 1.5, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = f
	local t = Flat.text(
		string.upper(Store.BadgeText[kind] or kind),
		15,
		S.BadgeText,
		Theme.Font.UI,
		Enum.TextXAlignment.Center
	)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromScale(0, 1)
	t.ZIndex = 10 -- above the light sweep
	t.Parent = f
	Shape.shine(f, F.Radius.M, 0.4)
	if kind == "limited" then
		local s = Instance.new("UIScale")
		s.Name = "Pulse"
		s.Parent = f
		table.insert(pulses, s)
	end
	return f
end

-- Light rays turning behind featured art (a wheel of thin fading bars)
local function rayWheel(size: number, color: Color3, speed: number): Frame
	local wheel = Flat.frame(UDim2.fromOffset(size, size))
	wheel.Name = "Rays"
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	for i = 1, S.Rays do
		local bar = Instance.new("Frame")
		bar.Name = "Ray"
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0.55
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0, math.max(6, math.floor(size * 0.05)), 1, 0)
		bar.Rotation = (i - 1) * 180 / S.Rays
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.65, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = bar
		bar.Parent = wheel
	end
	rays[wheel] = speed
	return wheel
end

-- Art: soft glow disc in the rarity color, rays for top offers, the icon floats
local function art(iconName: string, rarity: string, size: number, withRays: boolean): Frame
	local color = Theme.Rarity[rarity] or C.Gold
	local zone = Flat.frame(UDim2.fromOffset(size * 1.4, size * 1.25))
	zone.Name = "Art"
	if withRays then
		rayWheel(size * 1.7, color:Lerp(C.GoldHi, 0.5), 1).Parent = zone
	end
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(size * 0.95, size * 0.95)
	disc.BackgroundColor3 = color
	disc.BackgroundTransparency = 0.8
	disc.BorderSizePixel = 0
	Flat.corner(disc, math.floor(size))
	Flat.glow(disc, color, 3, true, math.floor(size / 2))
	disc.Parent = zone
	local ic = Kit.icon(iconName, size)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = 3
	ic.Parent = zone
	bob(ic)
	return zone
end

-- ------------------------------------------------------------------ Buying
local function prompt(offer: Store.Offer)
	local id = Store.idOf(offer)
	if id <= 0 or os.clock() - promptAt < 1 then
		return
	end
	promptAt = os.clock()
	if offer.kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

-- Buy button by state: price with the Robux glyph, "Coming soon" (placeholder ID) or "Owned"
local function buyButton(offer: Store.Offer, size: Vector2): TextButton
	local state = Store.state(offer, owner)
	if state == "owned" then
		local b, label = Flat.button("Owned", "secondary", size)
		b.Name = "Buy"
		Flat.setEnabled(b, false)
		label.TextColor3 = S.Owned
		label:SetAttribute("BaseColor", S.Owned)
		return b
	end
	if state == "soon" then
		local b = Flat.button("Coming soon", "ghost", size)
		b.Name = "Buy"
		Flat.setEnabled(b, false)
		return b
	end
	local b, label = Flat.button(Flat.thousands(Store.robux(offer)), "primary", size)
	b.Name = "Buy"
	label.TextSize = Kit.fontSize(math.min(24, size.Y * 0.36))
	label.FontFace = Theme.Font.Number
	local row = b:FindFirstChild("Row")
	if row then
		local glyph = robuxGlyph(math.floor(size.Y * 0.42), F.Surface0)
		glyph.LayoutOrder = 1
		glyph.Parent = row
	end
	b.Activated:Connect(function()
		prompt(offer)
	end)
	return b
end

-- ------------------------------------------------------------------ Offer card
local function card(offer: Store.Offer, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.Name = "Offer_" .. offer.id
	f.Size = UDim2.fromOffset(w, h)
	Shape.cell(f, 66, { rarity = offer.rarity })
	local lift = Instance.new("UIScale")
	lift.Name = "Lift"
	lift.Parent = f
	f.MouseEnter:Connect(function()
		Spring.target(lift, { Scale = S.HoverLift }, "Bouncy")
	end)
	f.MouseLeave:Connect(function()
		Spring.target(lift, { Scale = 1 }, "Snappy")
	end)

	local inner = w - 2 * PAD
	local col = Flat.frame(UDim2.fromOffset(inner, 0), UDim2.fromOffset(PAD, 14))
	col.Name = "Info"
	col.AutomaticSize = Enum.AutomaticSize.Y
	col.ZIndex = 3
	local layout = Kit.list(col, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Top)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local glow = F.Glow[offer.rarity] or F.Glow.normal
	local zone = art(offer.icon, offer.rarity, S.ArtSize, glow.spin)
	zone.LayoutOrder = 1
	zone.Parent = col

	local name = Window.heading(offer.name, 22, Theme.Rarity[offer.rarity] or C.Text)
	name.LayoutOrder = 2
	name.Parent = col

	local amount, unit = Store.amount(offer, bestDepth())
	if amount then
		local row = Flat.frame(UDim2.fromOffset(inner, 0))
		row.Name = "Amount"
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = 3
		Kit.list(row, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Bottom)
		local big = Flat.text(amount :: string, 34, C.GoldHi, Theme.Font.Number)
		big.LayoutOrder = 1
		Flat.gradient(big, C.GoldHi, C.Gold)
		big.Parent = row
		local u = Flat.text(unit or "", 18, C.Muted, Theme.Font.UI)
		u.LayoutOrder = 2
		u.Parent = row
		row.Parent = col
	else
		local parts = {}
		for _, line in Store.contents(offer, bestDepth()) do
			table.insert(parts, line.text)
		end
		if #parts > 0 then
			local list = Flat.text(
				table.concat(parts, " + "),
				18,
				C.GoldHi,
				Theme.Font.UI,
				Enum.TextXAlignment.Center
			)
			list.LayoutOrder = 3
			list.Parent = col
		end
	end
	local text = wrapText(offer.text, 18, C.Muted, inner)
	text.LayoutOrder = 4
	text.Parent = col
	col.Parent = f

	local product = Store.product(offer)
	local packed: { string } = if product and product.cosmetics then product.cosmetics else {}
	if #packed > 0 then
		local try = Flat.button("Try on", "secondary", Vector2.new(124, 44), "wings")
		try.Name = "TryOn"
		try.AnchorPoint = Vector2.new(1, 0)
		try.Position = UDim2.new(1, -14, 0, 14)
		try.ZIndex = 6
		try.Activated:Connect(function()
			local set: { [string]: string } = { trail = "", aura = "" }
			for _, id in packed do
				local c = CosmeticRules.ById[id]
				if c then
					set[c.slot] = id
				end
			end
			-- the preview lives on the Cosmetics tab (Try on also sits on featured cards)
			tab = "cosmetics"
			tabs.select(tab)
			trying = set
			StoreController.render() -- to the top: the preview is the first thing on the tab
		end)
		try.Parent = f
	end
	if offer.bonus then
		local tag = Flat.text(offer.bonus, 18, C.Good, Theme.Font.UI, Enum.TextXAlignment.Right)
		tag.Name = "Bonus"
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -16, 0, 14)
		tag.ZIndex = 6
		tag.Parent = f
	end
	if offer.badge then
		local b = badge(offer.badge)
		b.Position = UDim2.fromOffset(-8, -12)
		b.Parent = f
	end

	local buy = buyButton(offer, Vector2.new(inner, S.ButtonH))
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -PAD)
	buy.ZIndex = 5
	buy.Parent = f
	return f
end

-- Grid of cards (3 per row)
local function grid(offers: { Store.Offer }, order: number): Frame
	local rows = math.max(1, math.ceil(#offers / 3))
	local height = GRID_TOP + rows * S.CardH + (rows - 1) * (S.Gap + 8)
	local g = Flat.frame(UDim2.fromOffset(PAGE_W, height))
	g.Name = "Grid"
	g.LayoutOrder = order
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, GRID_TOP) -- badges stick out above the cards
	pad.PaddingLeft = UDim.new(0, GRID_LEFT)
	pad.Parent = g
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, S.CardH)
	layout.CellPadding = UDim2.fromOffset(S.Gap, S.Gap + 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = g
	for i, offer in offers do
		local c = card(offer, CARD_W, S.CardH)
		c.LayoutOrder = i
		c.Parent = g
	end
	return g
end

local function sectionTitle(text: string, order: number): Frame
	local f = Flat.frame(UDim2.fromOffset(PAGE_W, 44))
	f.Name = "Section"
	f.LayoutOrder = order
	local t = Window.gilded(text, 24)
	t.Position = UDim2.fromOffset(10, 0)
	t.Parent = f
	local rule = Flat.accentRule(320)
	rule.Position = UDim2.fromOffset(10, 38)
	rule.Parent = f
	return f
end

-- ------------------------------------------------------------------ Hero banner (Featured)
local function heroOffer(): Store.Offer?
	for _, id in { Store.HERO, "pack_void" } do
		local offer = Store.ById[id]
		if offer and not Store.owned(offer, owner) then
			return offer
		end
	end
	return nil
end

local function hero(offer: Store.Offer, order: number): Frame
	local f = Instance.new("Frame")
	f.Name = "Hero"
	f.LayoutOrder = order
	f.Size = UDim2.fromOffset(PAGE_W - 10, S.HeroH)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.ClipsDescendants = false
	Flat.corner(f, F.Radius.L)
	Flat.gradient(f, S.HeroTop, S.HeroBottom)
	local color = Theme.Rarity[offer.rarity] or C.Gold
	local edge = Flat.stroke(f, C.Gold, 2, 0)
	Flat.spin(edge, C.Gold)
	Flat.glow(f, color, 3, true, F.Radius.L)
	Flat.brackets(f, C.GoldHi)
	Flat.shine(f, F.Radius.L, 0.7)

	-- Art on the left behind its own clip (the rays stay inside the banner)
	local clip = Flat.frame(UDim2.fromOffset(460, S.HeroH))
	clip.Name = "ArtClip"
	clip.ClipsDescendants = true
	local zone = art(offer.icon, offer.rarity, S.HeroArt, true)
	zone.AnchorPoint = Vector2.new(0.5, 0.5)
	zone.Position = UDim2.fromScale(0.5, 0.5)
	zone.Parent = clip
	clip.Parent = f

	local infoW = PAGE_W - 10 - 460 - 380
	local info = Flat.frame(UDim2.fromOffset(infoW, 0), UDim2.fromOffset(460, S.HeroH / 2))
	info.Name = "Info"
	info.AnchorPoint = Vector2.new(0, 0.5)
	info.AutomaticSize = Enum.AutomaticSize.Y
	local il = Kit.list(info, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	il.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local title = Window.gilded(offer.name, 44)
	title.LayoutOrder = 1
	title.Parent = info
	local text = Flat.text(offer.text, 18, C.Text, Theme.Font.Body)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.Size = UDim2.fromOffset(infoW, 0)
	text.TextWrapped = true
	text.LayoutOrder = 2
	text.Parent = info
	for i, line in Store.contents(offer, bestDepth()) do
		local row = Flat.frame(UDim2.fromOffset(infoW, 40))
		row.Name = "Gives"
		row.LayoutOrder = 2 + i
		Kit.list(row, Enum.FillDirection.Horizontal, 10, Enum.VerticalAlignment.Center).HorizontalAlignment =
			Enum.HorizontalAlignment.Left
		local ic = Kit.icon(line.icon, 36)
		ic.LayoutOrder = 1
		ic.Parent = row
		local t = Flat.text(line.text, 20, C.GoldHi, Theme.Font.UI)
		t.LayoutOrder = 2
		t.Parent = row
		row.Parent = info
	end
	info.Parent = f

	local buy = buyButton(offer, Vector2.new(320, 96))
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -40, 0.5, 10)
	buy.ZIndex = 5
	buy.Parent = f
	if offer.badge then
		local b = badge(offer.badge)
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, -40, 0, 40)
		b.Parent = f
	end
	return f
end

-- ------------------------------------------------------------------ Wardrobe (Cosmetics tab)
local COLUMN_W = PAGE_W - S.Preview.X - 40 -- slot rows right of the preview

local function shown(slot: string): string
	local t = trying
	if t then
		return t[slot] or ""
	end
	return wear[slot] or ""
end

-- Preview stage (left) with a caption of what it shows
local function stage(): Frame
	local p: CosmeticPreview.Preview = preview or CosmeticPreview.new(S.Preview)
	preview = p
	p.show(shown("aura"), shown("trail"))
	local names = {}
	for _, slot in CosmeticRules.Slots do
		local c = CosmeticRules.ById[shown(slot)]
		if c then
			table.insert(names, c.name)
		end
	end
	local caption = p.frame:FindFirstChild("Caption")
	if caption then
		caption:Destroy()
	end
	local text = if trying
		then "Trying on: " .. table.concat(names, " + ")
		elseif #names > 0 then table.concat(names, " + ")
		else "Nothing worn yet"
	local label = Flat.text(
		text,
		18,
		if trying then C.GoldHi else C.Text,
		Theme.Font.UI,
		Enum.TextXAlignment.Center
	)
	label.Name = "Caption"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -14)
	label.ZIndex = 4
	label.Parent = p.frame
	return p.frame
end

local function wardrobe(order: number): Frame
	local outer = Flat.frame(UDim2.fromOffset(PAGE_W, 0))
	outer.Name = "Look"
	outer.LayoutOrder = order
	outer.AutomaticSize = Enum.AutomaticSize.Y
	local ol = Kit.list(outer, Enum.FillDirection.Horizontal, 30, Enum.VerticalAlignment.Top)
	ol.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local pad0 = Instance.new("UIPadding")
	pad0.PaddingLeft = UDim.new(0, 10)
	pad0.Parent = outer
	local st = stage()
	st.LayoutOrder = 1
	st.Parent = outer

	local f = Flat.frame(UDim2.fromOffset(COLUMN_W, 0))
	f.Name = "Wardrobe"
	f.LayoutOrder = 2
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.Parent = outer
	local list = Kit.list(f, Enum.FillDirection.Vertical, 18, Enum.VerticalAlignment.Top)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	if trying then
		local back = Flat.button("Back to my look", "secondary", Vector2.new(260, 56), "close")
		back.Name = "BackToLook"
		back.LayoutOrder = 0
		back.Activated:Connect(function()
			trying = nil
			StoreController.render(true)
		end)
		back.Parent = f
	end
	local any = false
	for i, slot in CosmeticRules.Slots do
		local row = Flat.frame(UDim2.fromOffset(COLUMN_W, 150))
		row.Name = "Slot_" .. slot
		row.LayoutOrder = i
		local rl = Kit.list(row, Enum.FillDirection.Horizontal, 22, Enum.VerticalAlignment.Top)
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = row
		local label = Flat.text(string.upper(CosmeticRules.SlotName[slot]), 20, C.Muted)
		label.Size = UDim2.fromOffset(110, 96)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.LayoutOrder = 0
		label.Parent = row
		local entries: { { id: string, icon: string, rarity: string?, name: string } } =
			{ { id = "", icon = "close", rarity = nil, name = "None" } }
		for _, c in CosmeticRules.List do
			if c.slot == slot and ownedCosmetics[c.id] then
				any = true
				table.insert(
					entries,
					{ id = c.id, icon = c.icon, rarity = c.rarity, name = c.name }
				)
			end
		end
		for j, e in entries do
			local worn = (wear[slot] or "") == e.id
			local cell = Flat.cell(96, e.icon, {
				rarity = e.rarity,
				selected = worn,
				dim = e.id == "",
				caption = e.name,
			})
			cell.Name = "Wear_" .. (if e.id == "" then slot .. "_none" else e.id)
			cell.LayoutOrder = j
			cell.Activated:Connect(function()
				trying = nil -- wearing something shows the own look again
				if (wear[slot] or "") ~= e.id then
					wear[slot] = e.id
					Net.Wear:FireServer(slot, e.id)
				end
				StoreController.render(true)
			end)
			cell.Parent = row
		end
		row.Parent = f
	end
	if not any then
		local hint = wrapText(
			"Buy a pack to unlock trails and auras. Everyone in the server sees them. Tap Try on to see a pack on your hero.",
			18,
			C.Muted,
			COLUMN_W
		)
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.LayoutOrder = 10
		hint.Parent = f
	end
	return outer
end

-- ------------------------------------------------------------------ Pages
-- keepScroll: stay where the player is (wardrobe clicks, server updates); tab changes start at the top
function StoreController.render(keepScroll: boolean?)
	local scroll = page.CanvasPosition
	bobs = {}
	pulses = {}
	if preview then
		preview.frame.Parent = nil -- kept across renders (no new hero copy on every click)
	end
	clear(page)

	if tab == "featured" then
		local top = heroOffer()
		if top then
			hero(top, 1).Parent = page
		end
		sectionTitle("Hot right now", 2).Parent = page
		local offers = {}
		for _, offer in Store.inTab("featured") do
			if offer ~= top then
				table.insert(offers, offer)
			end
		end
		grid(offers, 3).Parent = page
	else
		if tab == "cosmetics" then
			sectionTitle(if trying then "Try on" else "Your look", 1).Parent = page
			wardrobe(2).Parent = page
			grid(Store.inTab(tab), 3).Parent = page
		else
			grid(Store.inTab(tab), 1).Parent = page
		end
	end
	if not Store.anyLive() then
		local note = Flat.text(
			"Robux offers open soon. Soulstars can already be traded in the Market.",
			18,
			C.Muted,
			Theme.Font.Body
		)
		note.Name = "Hint"
		note.LayoutOrder = 99
		note.Parent = page
	end
	if keepScroll then
		page.CanvasPosition = scroll
		task.defer(function() -- the canvas grows to its new size after layout
			page.CanvasPosition = scroll
		end)
	else
		page.CanvasPosition = Vector2.zero
	end
	Kit.refit(win.root)
	runClock()
end

-- ------------------------------------------------------------------ Celebration
local BURST_COLORS = { C.GoldHi, C.Gold, C.Cyan, Theme.Rarity.epic, Theme.Rarity.legend, C.Text }

local function celebrate(offerId: string?, text: string)
	local offer = if offerId then Store.ById[offerId] else nil
	local root = win.root
	local old = root:FindFirstChild("Celebrate")
	if old then
		old:Destroy()
	end
	local layer = Instance.new("TextButton")
	layer.Name = "Celebrate"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.BackgroundColor3 = Color3.new(0, 0, 0)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 50
	layer.Parent = root
	TweenService:Create(layer, Theme.Tween.Fast, { BackgroundTransparency = 0.35 }):Play()

	local center = Flat.frame(UDim2.fromOffset(700, 620))
	center.Name = "Center"
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.ZIndex = 51
	center.Parent = layer
	local color = if offer then Theme.Rarity[offer.rarity] or C.Gold else C.Gold
	local wheel = rayWheel(640, color:Lerp(C.GoldHi, 0.4), 3)
	wheel.Position = UDim2.new(0.5, 0, 0.5, -90)
	wheel.Parent = center
	local icon = Kit.icon(if offer then offer.icon else "soulstar", 220)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, -90)
	icon.ZIndex = 53
	local pop = Instance.new("UIScale")
	pop.Scale = 0.2
	pop.Parent = icon
	icon.Parent = center
	Spring.target(pop, { Scale = 1 }, "Bouncy")

	local col = Flat.frame(UDim2.fromOffset(700, 0), UDim2.new(0, 0, 0.5, 60))
	col.AutomaticSize = Enum.AutomaticSize.Y
	local cl = Kit.list(col, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local title = Window.gilded("Purchase complete!", 48)
	title.LayoutOrder = 1
	title.ZIndex = 54
	title.Parent = col
	local gives = wrapText(text, 24, C.Text, 680)
	gives.LayoutOrder = 2
	gives.ZIndex = 54
	gives.Parent = col
	local tap = Flat.text("Tap to continue", 18, C.Muted, Theme.Font.Body)
	tap.LayoutOrder = 3
	tap.ZIndex = 54
	tap.Parent = col
	col.Parent = center
	local tscale = Instance.new("UIScale")
	tscale.Scale = 0.6
	tscale.Parent = col
	Spring.target(tscale, { Scale = 1 }, "Bouncy")

	-- Stud confetti flying out of the center
	for _ = 1, S.Burst do
		local stud = Instance.new("Frame")
		stud.Name = "Stud"
		stud.BorderSizePixel = 0
		stud.AnchorPoint = Vector2.new(0.5, 0.5)
		stud.Position = UDim2.new(0.5, 0, 0.5, -90)
		local edge = math.random(10, 20)
		stud.Size = UDim2.fromOffset(edge, edge)
		stud.BackgroundColor3 = BURST_COLORS[math.random(1, #BURST_COLORS)]
		stud.ZIndex = 52
		Flat.corner(stud, 3)
		stud.Parent = center
		local angle = math.random() * 2 * math.pi
		local dist = math.random(220, 480)
		local fly = TweenService:Create(
			stud,
			TweenInfo.new(1 + math.random() * 0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(
					0.5,
					math.cos(angle) * dist,
					0.5,
					-90 + math.sin(angle) * dist + 80
				),
				Rotation = math.random(-360, 360),
				BackgroundTransparency = 1,
			}
		)
		fly:Play()
	end
	Shape.sound("ui_reward")
	runClock()

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		local fade = TweenService:Create(layer, Theme.Tween.Fast, { BackgroundTransparency = 1 })
		fade.Completed:Connect(function()
			layer:Destroy()
		end)
		center:Destroy()
		fade:Play()
	end
	layer.Activated:Connect(close)
	task.delay(S.CelebrateTime, close)
end

-- ------------------------------------------------------------------ Flow
function StoreController.toggle()
	win.toggle()
end

-- Open the shop on a tab (the + on the capsules)
function StoreController.open(tabId: string?)
	if tabId then
		for _, t in Store.Tabs do
			if t.id == tabId then
				tab = tabId
			end
		end
	end
	tabs.select(tab)
	if win.isOpen() then
		StoreController.render()
	else
		win.toggle()
	end
end

local function buildTop()
	local top = Flat.frame(UDim2.fromOffset(BODY.X, S.TopH))
	top.Name = "Top"
	local defs = {}
	for _, t in Store.Tabs do
		table.insert(defs, { id = t.id, text = t.name })
	end
	tabs = Flat.tabs(defs, S.TopH - 4, function(id: string)
		tab = id
		trying = nil
		StoreController.render()
	end)
	tabs.frame.Parent = top

	local right = Flat.frame(UDim2.fromOffset(0, S.TopH))
	right.Name = "Wallet"
	right.AutomaticSize = Enum.AutomaticSize.X
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	local rl = Kit.list(right, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local stars, sl = Flat.currency("soulstar", Theme.Rarity.epic)
	stars.LayoutOrder = 1
	stars.Parent = right
	starLabel = sl
	local gold, gl = Flat.currency("gold", C.Gold)
	gold.LayoutOrder = 2
	gold.Parent = right
	goldLabel = gl
	local market = Flat.button("Market", "secondary", Vector2.new(170, S.TopH - 4), "pouch")
	market.Name = "Market"
	market.LayoutOrder = 3
	market.Activated:Connect(function()
		MarketController.open()
	end)
	market.Parent = right
	right.Parent = top
	top.Parent = win.body
end

local function updateWallet()
	Shape.tickTo(starLabel, number("Soulstars"), Format.currency)
	Shape.tickTo(goldLabel, number("Gold"), Format.currency)
end

function StoreController.init()
	win = Window.new({
		name = "Shop",
		title = "Shop",
		icon = "pouch",
		key = Enum.KeyCode.P,
	})
	buildTop()

	page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.fromOffset(0, S.TopH + 8)
	page.Size = UDim2.fromOffset(BODY.X, BODY.Y - S.TopH - 8)
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.ScrollBarThickness = SCROLLBAR
	page.ScrollBarImageColor3 = C.Gold
	page.ScrollBarImageTransparency = 0.4
	page.ElasticBehavior = Enum.ElasticBehavior.Always
	local layout = Kit.list(page, Enum.FillDirection.Vertical, 26, Enum.VerticalAlignment.Top)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 24)
	pad.Parent = page
	page.Parent = win.body
	tabs.select(tab)

	win.onOpen(function()
		updateWallet()
		trying = nil
		if preview then
			preview.refresh() -- new copy of the hero: gear or character may have changed
		end
		StoreController.render()
	end)
	local function refresh()
		if win.isOpen() then
			StoreController.render(true)
		end
	end
	for _, attr in { "Soulstars", "Gold" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if win.isOpen() then
				updateWallet()
			end
		end)
	end
	player:GetAttributeChangedSignal("BestDepth"):Connect(refresh) -- gold pack sizes
	for _, pass in Monetization.Passes do
		player:GetAttributeChangedSignal(Monetization.passAttr(pass.key)):Connect(refresh)
	end
	Net.Store.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then
			return
		end
		ownedCosmetics, bought = {}, {}
		for _, id in (if typeof(data.cosmetics) == "table" then data.cosmetics else {}) do
			if typeof(id) == "string" then
				ownedCosmetics[id] = true
			end
		end
		for _, key in (if typeof(data.bought) == "table" then data.bought else {}) do
			if typeof(key) == "string" then
				bought[key] = true
			end
		end
		if typeof(data.wear) == "table" then
			for _, slot in CosmeticRules.Slots do
				local id = data.wear[slot]
				wear[slot] = if typeof(id) == "string" then id else ""
			end
		end
		refresh()
	end)
	Net.ShopResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" or data.robux ~= true or typeof(data.text) ~= "string" then
			return
		end
		if win.isOpen() then
			celebrate(if typeof(data.offerId) == "string" then data.offerId else nil, data.text)
		end
	end)
	-- Back from the Market to the Robux shop
	MarketController.openStore = function()
		StoreController.open()
	end
end

return StoreController
