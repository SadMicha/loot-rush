--!strict
-- Atlas window after the "Atlas" mockup (key M or menu button):
--   the map with areas and paths on the left, profile of the selected area and "Travel" on the right.
-- Traveling starts the area's Rift (Net.Rift "enter", area). Whether an area is open follows from
-- the personal bests that the server sets as attributes AtlasBest_<area> (rule in Shared/Atlas).
-- A run resumes at the first depth not cleared yet on the chosen World Tier (AtlasStart_<area>);
-- the depth picker can start lower ("enter", area, depth; the server clamps it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local QuestController = require(script.Parent.QuestController)
local RiftController = require(script.Parent.RiftController)

local AtlasController = {}

local C = Theme.Color
local PAD = 28
local ACTION_H = 84 -- bottom row (tier arrows + Travel): touch size on phones without growing
local ARROW_W = 84
local STEP_H = 52 -- depth picker row (resume depth)
local SIDE_W = 440
local LABEL = Vector2.new(230, 98) -- aspect ratio like plaque_region
local DOT_GAP = 18
local MARK_Y = 22 -- diamond/lock sits this far below the plate

local win: Window.Window
local map: Frame
local side: Frame

local selected = Atlas.Start
local picked: { [string]: number } = {} -- start depth chosen this session (nil = deepest)
local pickedMax: { [string]: number } = {} -- deepest start when it was picked

-- Deepest start depth of a region on the selected tier (server attribute)
local function maxStart(r: Atlas.Region): number
	local v = Players.LocalPlayer:GetAttribute(Atlas.startAttr(r.id))
	return if typeof(v) == "number" then math.max(r.depth, v) else r.depth
end

-- Start depth the next run of this region uses: the pick, or the deepest when the deepest moved
local function startOf(r: Atlas.Region): number
	local max = maxStart(r)
	if picked[r.id] and pickedMax[r.id] ~= max then
		picked[r.id] = nil -- cleared deeper or switched tier: resume at the new frontier
	end
	return math.clamp(picked[r.id] or max, r.depth, max)
end

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

-- ------------------------------------------------------------------ Map
-- Is the point on a name plate or a marker? No path dots there.
local function covered(p: Vector2): boolean
	for _, r in Atlas.Regions do
		local dx, dy = math.abs(p.X - r.pos.X), r.pos.Y - p.Y
		if dx < LABEL.X / 2 + 8 and dy > -8 and dy < LABEL.Y + 8 then
			return true
		end
		if (p - (r.pos + Vector2.new(0, MARK_Y))).Magnitude < 26 then
			return true
		end
	end
	return false
end

-- Dotted path from marker to marker
local function path(a: Atlas.Region, b: Atlas.Region)
	local from = a.pos + Vector2.new(0, MARK_Y)
	local d = b.pos - a.pos
	local n = math.floor(d.Magnitude / DOT_GAP)
	local lit = isOpen(a) and isOpen(b)
	for i = 1, n - 1 do
		local p = from + d * (i / n)
		if covered(p) then
			continue
		end
		local dot = Instance.new("Frame")
		dot.Name = "Path"
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

		-- Name plate
		local plate = Instance.new("ImageButton")
		plate.Name = r.id
		plate.AutoButtonColor = false
		plate.AnchorPoint = Vector2.new(0.5, 1)
		plate.Position = UDim2.fromOffset(r.pos.X, r.pos.Y)
		plate.Size = UDim2.fromOffset(LABEL.X, LABEL.Y)
		plate.ZIndex = 2
		-- Fallback plate built in code until the image has loaded
		plate.BackgroundColor3 = C.Bg1
		plate.BackgroundTransparency = 0.1
		Kit.corner(plate, Theme.Flat.Radius.M)
		Kit.stroke(plate, if on then C.GoldHi else r.color, if on then 2.5 else 1.5)
		Shape.topLine(plate)
		Shape.brackets(plate, if on then C.GoldHi else r.color, 12, 0)
		local art = Window.art("plaque_region", LABEL)
		if art then
			art.ScaleType = Enum.ScaleType.Stretch
			art.Size = UDim2.fromScale(1, 1)
			art.ImageColor3 = if on then C.GoldHi else r.color
			art.Parent = plate
			Window.whenLoaded(art, function()
				plate.BackgroundTransparency = 1
				local stroke = plate:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Enabled = false
				end
			end)
		end
		local name =
			Kit.label(string.upper(r.name), 17, if on then C.GoldHi else C.Text, Theme.Font.Title)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 20)
		name.ZIndex = 3
		name.Parent = plate
		local lv = Kit.label("Level " .. r.levels, 14, C.Muted, Theme.Font.Body)
		lv.AnchorPoint = Vector2.new(0.5, 1)
		lv.Position = UDim2.new(0.5, 0, 1, -22)
		lv.ZIndex = 3
		lv.Parent = plate
		plate.Activated:Connect(function()
			selected = r.id
			AtlasController.render()
		end)
		plate.Parent = map

		-- Diamond or lock below the plate
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
			mark = Kit.icon("lock", 34)
		end
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromOffset(r.pos.X, r.pos.Y + MARK_Y)
		mark.ZIndex = 3
		mark.Parent = map
	end
end

-- ------------------------------------------------------------------ Profile
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
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, -60, 1, -8) -- stay inside the capsule, two lines if necessary
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
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

	-- Preview image; the fallback (area color + boss) always sits underneath in case the image fails to load
	local ph = Window.frame(UDim2.fromOffset(w, 200), UDim2.fromOffset(PAD, PAD))
	ph.Name = "Preview"
	ph.BackgroundTransparency = 0.8
	ph.BackgroundColor3 = r.color
	Kit.corner(ph, Theme.Radius.M)
	local ic = Kit.icon(r.bossIcon, 110)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.Parent = ph
	local picture = Window.art("region_" .. r.id, Vector2.new(w, 200))
	if picture then
		picture.ScaleType = Enum.ScaleType.Crop
		picture.Size = UDim2.fromScale(1, 1)
		picture.ZIndex = 2
		picture.Parent = ph
	end
	ph.Parent = side

	local name = Window.heading(r.name, 26, C.GoldHi)
	name.Position = UDim2.fromOffset(PAD, PAD + 214)
	name.Parent = side

	local half = (w - 10) / 2
	local top = row(PAD + 262, w)
	local record = best(r.id)
	local depthText = if record > 0
		then string.format("Best: Depth %d", record)
		else string.format("From Depth %d", r.depth)
	infoTile("portal", depthText, half, 1).Parent = top
	infoTile(r.bossIcon, r.boss, half, 2).Parent = top
	local mods = row(PAD + 328, w)
	for i, m in r.mods do
		infoTile(m.icon, m.text, half, i).Parent = mods
	end

	local desc = wrapLabel(r.desc, 15, C.Muted, w)
	desc.Position = UDim2.fromOffset(PAD, PAD + 398)
	desc.Parent = side

	local rewardHead = Window.heading("Possible Rewards", 16, C.Text)
	rewardHead.Position = UDim2.fromOffset(PAD, PAD + 464)
	rewardHead.Parent = side
	local rewards = row(PAD + 492, w)
	rewards.Size = UDim2.fromOffset(w, 48)
	for i, rw in r.rewards do
		local s = Kit.itemSlot(48, rw.icon, { rarity = rw.rarity })
		s.Active = false
		s.LayoutOrder = i
		s.Parent = rewards
	end

	-- World Tier picker (Shared/WorldTiers): only between runs, only unlocked tiers
	local player = Players.LocalPlayer
	local tier = WorldTiers.get(player:GetAttribute("WorldTier"))
	local unlocked = WorldTiers.get(player:GetAttribute("WorldTierUnlocked")).id
	-- One bottom row: [<] [Travel] [>], all ACTION_H tall (already touch size on phones, so
	-- nothing grows into a neighbour); the tier name sits on its own line above the row.
	local bottom = Window.frame(UDim2.fromOffset(w, ACTION_H))
	bottom.Name = "WorldTier"
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, PAD, 1, -PAD)
	local function arrow(text: string, step: number)
		local target = tier.id + step
		local b = Kit.button(text, C.Gold, Vector2.new(ARROW_W, ACTION_H))
		b.Name = if step < 0 then "TierDown" else "TierUp"
		b.AnchorPoint = Vector2.new(if step < 0 then 0 else 1, 0.5)
		b.Position = UDim2.new(if step < 0 then 0 else 1, 0, 0.5, 0)
		Kit.setEnabled(b, target >= 1 and target <= unlocked and not RiftController.active())
		b.Activated:Connect(function()
			if b.Active then
				Net.Rift:FireServer("tier", target)
			end
		end)
		b.Parent = bottom
	end
	arrow("<", -1)
	arrow(">", 1)
	local tierText =
		Kit.label("World Tier: " .. tier.name, 18, if tier.id > 1 then C.GoldHi else C.Text)
	tierText.AutomaticSize = Enum.AutomaticSize.Y
	tierText.Size = UDim2.fromOffset(w, 0)
	tierText.TextXAlignment = Enum.TextXAlignment.Center
	tierText.TextTruncate = Enum.TextTruncate.AtEnd
	tierText.AnchorPoint = Vector2.new(0.5, 1)
	tierText.Position = UDim2.new(0, PAD + w / 2, 1, -PAD - ACTION_H - 8)
	tierText.Parent = side

	local inRift = RiftController.active()
	local open = isOpen(r)

	-- Start depth picker: [-] Start: Depth N [+], from the region start up to the resume depth
	local max = maxStart(r)
	local start = startOf(r)
	if open then
		local depthRow = Window.frame(UDim2.fromOffset(w, STEP_H))
		depthRow.Name = "StartDepth"
		depthRow.AnchorPoint = Vector2.new(0, 1)
		depthRow.Position = UDim2.new(0, PAD, 1, -PAD - ACTION_H - 46)
		local function step(text: string, delta: number)
			local target = start + delta
			local b = Kit.button(text, C.Gold, Vector2.new(STEP_H, STEP_H))
			b.Name = if delta < 0 then "DepthDown" else "DepthUp"
			b.AnchorPoint = Vector2.new(if delta < 0 then 0 else 1, 0.5)
			b.Position = UDim2.new(if delta < 0 then 0 else 1, 0, 0.5, 0)
			Kit.setEnabled(b, target >= r.depth and target <= max and not inRift)
			b.Activated:Connect(function()
				if b.Active then
					picked[r.id] = target
					pickedMax[r.id] = max
					renderSide()
				end
			end)
			b.Parent = depthRow
		end
		step("-", -1)
		step("+", 1)
		local startText = Kit.label(
			string.format("Start: Depth %d", start),
			20,
			if start == max then C.Text else C.Muted
		)
		startText.Name = "StartText"
		startText.Size = UDim2.new(1, -2 * (STEP_H + 8), 1, 0)
		startText.AutomaticSize = Enum.AutomaticSize.None
		startText.TextXAlignment = Enum.TextXAlignment.Center
		startText.TextTruncate = Enum.TextTruncate.AtEnd
		startText.AnchorPoint = Vector2.new(0.5, 0.5)
		startText.Position = UDim2.fromScale(0.5, 0.5)
		startText.Parent = depthRow
		depthRow.Parent = side
	end
	local text = if not open
		then string.format("Clear Depth %d first", r.depth - 1)
		elseif inRift then "Already in Rift"
		else "Travel"
	local go = Kit.button(
		text,
		C.Gold,
		Vector2.new(w - 2 * (ARROW_W + 10), ACTION_H),
		if open then "portal" else "lock"
	)
	Kit.buttonLabel(go).TextSize = Kit.fontSize(24)
	go.AnchorPoint = Vector2.new(0.5, 0.5)
	go.Position = UDim2.fromScale(0.5, 0.5)
	Kit.setEnabled(go, open and not inRift)
	go.Activated:Connect(function()
		if not go.Active then
			return
		end
		Net.Rift:FireServer("enter", r.id, startOf(r))
		win.close()
	end)
	go.Parent = bottom
	bottom.Parent = side
end

-- ------------------------------------------------------------------ Flow
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

	map = Window.frame(UDim2.fromOffset(Atlas.Size.X, Atlas.Size.Y))
	map.Parent = win.body

	side = Kit.panel(Vector2.new(SIDE_W, Window.BODY.Y))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Parent = win.body

	win.onOpen(AtlasController.render)
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("WorldTier"):Connect(function()
		if win.isOpen() then
			AtlasController.render()
		end
	end)
	local known = player:GetAttribute("WorldTierUnlocked")
	player:GetAttributeChangedSignal("WorldTierUnlocked"):Connect(function()
		local now = player:GetAttribute("WorldTierUnlocked")
		if typeof(known) == "number" and typeof(now) == "number" and now > known then
			QuestController.toast(
				"World Tier " .. WorldTiers.get(now).name .. " unlocked",
				C.GoldHi
			)
		end
		known = now
		if win.isOpen() then
			AtlasController.render()
		end
	end)
	AtlasController.render()
end

return AtlasController
