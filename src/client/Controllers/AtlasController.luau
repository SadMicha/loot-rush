--!strict
-- Atlas-Fenster nach Mockup „Atlas“ (Taste M oder Menü-Button):
--   links die Karte mit Gebieten und Pfaden, rechts Steckbrief des gewählten Gebiets und „Reisen“.
-- Reisen startet das Rift des Gebiets (Net.Rift „enter“, Gebiet). Ob ein Gebiet offen ist, folgt aus
-- den Bestleistungen, die der Server als Attribute AtlasBest_<Gebiet> setzt (Regel in Shared/Atlas).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local RiftController = require(script.Parent.RiftController)

local AtlasController = {}

local C = Theme.Color
local PAD = 28
local SIDE_W, TOP = 440, 90
local LABEL = Vector2.new(230, 98) -- Seitenverhältnis wie plaque_region
local DOT_GAP = 18

local win: Window.Window
local map: Frame
local side: Frame

local selected = Atlas.Start

local function best(id: string): number
	return (Players.LocalPlayer:GetAttribute(Atlas.attr(id)) or 0) :: number
end

local function isOpen(r: Atlas.Region): boolean
	return Atlas.isOpen(r.id, best)
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
	t.TextXAlignment = Enum.TextXAlignment.Left
	return t
end

-- ------------------------------------------------------------------ Karte
local function path(a: Atlas.Region, b: Atlas.Region)
	local d = b.pos - a.pos
	local n = math.floor(d.Magnitude / DOT_GAP)
	local lit = isOpen(a) and isOpen(b)
	for i = 1, n - 1 do
		local p = a.pos + d * (i / n)
		local dot = Instance.new("Frame")
		dot.Name = "Pfad"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(p.X, p.Y)
		dot.Size = UDim2.fromOffset(6, 6)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = if lit then C.GoldHi else C.Text
		dot.BackgroundTransparency = if lit then 0 else 0.5
		dot.ZIndex = 0
		Kit.corner(dot, 3)
		dot.Parent = map
	end
end

local function renderMap()
	clear(map)
	for _, r in Atlas.Regions do
		for _, id in r.next do
			local to = Atlas.ById[id]
			if to then
				path(r, to)
			end
		end
	end
	for _, r in Atlas.Regions do
		local on = r.id == selected
		local island = Window.art("island_" .. r.id, Vector2.new(260, 220))
		if island then
			island.AnchorPoint = Vector2.new(0.5, 1)
			island.Position = UDim2.fromOffset(r.pos.X, r.pos.Y - 10)
			island.ZIndex = 1
			island.Parent = map
		end

		-- Namensschild
		local plate = Instance.new("ImageButton")
		plate.Name = r.id
		plate.AutoButtonColor = false
		plate.AnchorPoint = Vector2.new(0.5, 1)
		plate.Position = UDim2.fromOffset(r.pos.X, r.pos.Y)
		plate.Size = UDim2.fromOffset(LABEL.X, LABEL.Y)
		plate.ZIndex = 2
		local art = Window.art("plaque_region", LABEL)
		if art then
			plate.BackgroundTransparency = 1
			art.ScaleType = Enum.ScaleType.Stretch
			art.Size = UDim2.fromScale(1, 1)
			art.ImageColor3 = if on then C.GoldHi else r.color
			art.Parent = plate
		else
			plate.BackgroundColor3 = C.Bg1
			plate.BackgroundTransparency = 0.1
			Kit.corner(plate, LABEL.Y // 2)
			Kit.stroke(plate, if on then C.GoldHi else r.color, if on then 3 else 2)
		end
		local name = Kit.label(r.name, 18, if on then C.GoldHi else C.Text)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 20)
		name.ZIndex = 3
		name.Parent = plate
		local lv = Kit.label("Stufe " .. r.levels, 14, C.Muted, Theme.Font.Body)
		lv.AnchorPoint = Vector2.new(0.5, 1)
		lv.Position = UDim2.new(0.5, 0, 1, -22)
		lv.ZIndex = 3
		lv.Parent = plate
		plate.Activated:Connect(function()
			selected = r.id
			AtlasController.render()
		end)
		plate.Parent = map

		-- Raute oder Schloss unter dem Schild
		local mark: GuiObject
		if isOpen(r) then
			local diamond = Instance.new("Frame")
			diamond.Size = UDim2.fromOffset(22, 22)
			diamond.Rotation = 45
			diamond.BackgroundColor3 = C.Bg1
			diamond.BorderSizePixel = 0
			Kit.stroke(diamond, if on then C.GoldHi else r.color, 3)
			mark = diamond
		else
			mark = Kit.icon("schloss", 34)
		end
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromOffset(r.pos.X, r.pos.Y + 22)
		mark.ZIndex = 3
		mark.Parent = map
	end
end

-- ------------------------------------------------------------------ Steckbrief
local function infoTile(iconName: string, text: string, width: number, order: number): Frame
	local f = Window.frame(UDim2.fromOffset(width, 56))
	f.LayoutOrder = order
	Kit.skin(f, "stat_tile", 56, 0.4)
	local ic = Kit.icon(iconName, 30)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 12, 0.5, 0)
	ic.ZIndex = 2
	ic.Parent = f
	local t = Kit.label(text, 16, C.Text)
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.new(0, 50, 0.5, 0)
	t.ZIndex = 2
	t.Parent = f
	return f
end

local function row(y: number, w: number): Frame
	local f = Window.frame(UDim2.fromOffset(w, 56), UDim2.fromOffset(PAD, y))
	local l = Kit.list(f, Enum.FillDirection.Horizontal, 10)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Left
	f.Parent = side
	return f
end

local function renderSide()
	clear(side)
	local r = Atlas.ById[selected]
	local w = SIDE_W - 2 * PAD

	-- Vorschaubild
	local picture = Window.art("region_" .. r.id, Vector2.new(w, 200))
	if picture then
		picture.ScaleType = Enum.ScaleType.Crop
		picture.Position = UDim2.fromOffset(PAD, PAD)
		picture.Parent = side
	else
		local ph = Window.frame(UDim2.fromOffset(w, 200), UDim2.fromOffset(PAD, PAD))
		ph.BackgroundTransparency = 0.8
		ph.BackgroundColor3 = r.color
		Kit.corner(ph, Theme.Radius.M)
		local ic = Kit.icon(r.bossIcon, 110)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = ph
		ph.Parent = side
	end

	local name = Window.heading(r.name, 26, C.GoldHi)
	name.Position = UDim2.fromOffset(PAD, PAD + 214)
	name.Parent = side

	local half = (w - 10) / 2
	local top = row(PAD + 262, w)
	local record = best(r.id)
	local depthText = if record > 0
		then string.format("Rekord: Tiefe %d", record)
		else string.format("Ab Tiefe %d", r.depth)
	infoTile("portal", depthText, half, 1).Parent = top
	infoTile(r.bossIcon, r.boss, half, 2).Parent = top
	local mods = row(PAD + 328, w)
	for i, m in r.mods do
		infoTile(m.icon, m.text, half, i).Parent = mods
	end

	local desc = wrapLabel(r.desc, 15, C.Muted, w)
	desc.Position = UDim2.fromOffset(PAD, PAD + 398)
	desc.Parent = side

	local rewardHead = Window.heading("Mögliche Belohnungen", 16, C.Text)
	rewardHead.Position = UDim2.fromOffset(PAD, PAD + 490)
	rewardHead.Parent = side
	local rewards = row(PAD + 524, w)
	rewards.Size = UDim2.fromOffset(w, 76)
	for i, rw in r.rewards do
		local s = Kit.itemSlot(72, rw.icon, { rarity = rw.rarity })
		s.Active = false
		s.LayoutOrder = i
		s.Parent = rewards
	end

	local inRift = RiftController.active()
	local open = isOpen(r)
	local text = if not open
		then string.format("Erst Tiefe %d schaffen", r.depth - 1)
		elseif inRift then "Schon im Rift"
		else "Reisen"
	local go = Kit.button(text, C.Gold, Vector2.new(w, 64), if open then "portal" else "schloss")
	Kit.buttonLabel(go).TextSize = Kit.fontSize(24)
	go.AnchorPoint = Vector2.new(0, 1)
	go.Position = UDim2.new(0, PAD, 1, -PAD)
	Kit.setEnabled(go, open and not inRift)
	go.Activated:Connect(function()
		if not go.Active then
			return
		end
		Net.Rift:FireServer("enter", r.id)
		win.close()
	end)
	go.Parent = side
end

-- ------------------------------------------------------------------ Ablauf
function AtlasController.render()
	renderMap()
	renderSide()
end

function AtlasController.toggle()
	win.toggle()
end

function AtlasController.init()
	win = Window.new({
		name = "Atlas",
		title = "Atlas",
		icon = "atlas",
		key = Enum.KeyCode.M,
		background = "bg_atlas",
	})

	map = Window.frame(UDim2.fromOffset(Atlas.Size.X, Atlas.Size.Y), UDim2.fromOffset(40, TOP))
	map.Parent = win.root

	side = Kit.panel(Vector2.new(SIDE_W, 790))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.new(1, -40, 0, TOP)
	side.Parent = win.root

	win.onOpen(AtlasController.render)
	AtlasController.render()
end

return AtlasController
