--!strict
-- Sternennetz-Fenster nach Mockup „Sternennetz“ (Taste N oder Menü-Button):
--   links das Netz mit Sternen und Verbindungen, rechts Punkte, Stern-Details und Aktionen.
-- Vorschau ohne Server-System: Punkte = Spieler-Level, Zuweisungen leben nur im Client und wirken
-- noch nicht. Sobald es ein System gibt, ersetzt ein Net-Schnappschuss `allocated`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarNet = require(ReplicatedStorage.Shared.StarNet)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)

local StarNetController = {}

local C = Theme.Color
local player = Players.LocalPlayer
local PAD = 28
local SIDE_W, TOP = 420, 90
local SIZE: { [string]: number } = { core = 100, small = 46, big = 78 }
local BRANCH_COLOR: { [string]: Color3 } = {
	kraft = Theme.Rarity.unique,
	geschick = Theme.Rarity.magic,
	weisheit = Theme.Rarity.epic,
}

local win: Window.Window
local net: Frame
local side: Frame

local allocated: { [string]: boolean } = { herz = true }
local selected = "eisenhaut"

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

local function spent(): number
	local n = 0
	for id in allocated do
		n += StarNet.Cost[StarNet.ById[id].kind]
	end
	return n
end

local function points(): number
	local level = (player:GetAttribute("Level") or 1) :: number
	return level - spent()
end

local function canAllocate(s: StarNet.Star): boolean
	return not allocated[s.id]
		and s.from ~= nil
		and allocated[s.from] == true
		and points() >= StarNet.Cost[s.kind]
end

-- Entfernen nur am Ende eines Astes, damit nichts in der Luft hängt
local function canRemove(s: StarNet.Star): boolean
	if not allocated[s.id] or s.kind == "core" then
		return false
	end
	for _, other in StarNet.Stars do
		if other.from == s.id and allocated[other.id] then
			return false
		end
	end
	return true
end

-- ------------------------------------------------------------------ Netz
local function artName(s: StarNet.Star): string
	if s.kind == "core" then
		return "star_core"
	end
	return "star_" .. s.kind .. (if allocated[s.id] then "_active" else "")
end

local function renderNet()
	clear(net)
	for _, s in StarNet.Stars do
		if s.from then
			local parent = StarNet.ById[s.from]
			local color = BRANCH_COLOR[s.branch or "kraft"]
			local l = Window.line(net, parent.pos, s.pos, color, if allocated[s.id] then 4 else 2)
			l.BackgroundTransparency = if allocated[s.id] then 0 else 0.55
		end
	end
	for _, s in StarNet.Stars do
		local on = allocated[s.id] == true
		local size = SIZE[s.kind]
		local b = Window.node(s.icon, size, s.pos, {
			art = artName(s),
			rarity = if s.kind == "core"
				then "rare"
				elseif on then StarNet.BranchRarity[s.branch or "kraft"]
				else nil,
			dim = not on,
			selected = s.id == selected,
			tint = if on and s.branch then BRANCH_COLOR[s.branch] else nil,
		})
		b.Activated:Connect(function()
			selected = s.id
			StarNetController.render()
		end)
		b.Parent = net
		if s.kind == "big" then
			Window.caption(
				net,
				s.name,
				s.pos + Vector2.new(0, size / 2 + 4),
				16,
				if s.id == selected then C.GoldHi else C.Text
			)
		end
	end
end

-- ------------------------------------------------------------------ Rechts
local function renderSide()
	clear(side)
	local w = SIDE_W - 2 * PAD
	local s = StarNet.ById[selected]

	-- Punkte und Fortschritt
	local head = Window.frame(UDim2.fromOffset(w, 60), UDim2.fromOffset(PAD, PAD))
	local ic = Kit.icon("sternennetz", 44)
	ic.Parent = head
	local p = Kit.label(tostring(points()), 30, C.GoldHi)
	p.Position = UDim2.fromOffset(56, 4)
	p.Parent = head
	local count = 0
	for _ in allocated do
		count += 1
	end
	local prog = Kit.label(
		string.format("%d / %d", count - 1, #StarNet.Stars - 1),
		15,
		C.Muted,
		Theme.Font.Body
	)
	prog.AnchorPoint = Vector2.new(1, 0)
	prog.Position = UDim2.new(1, 0, 0, 2)
	prog.Parent = head
	local back, fill = Kit.bar(Vector2.new(w - 140, 12), C.Gold)
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.new(1, 0, 0, 34)
	fill.Size = UDim2.fromScale((count - 1) / math.max(1, #StarNet.Stars - 1), 1)
	back.Parent = head
	head.Parent = side

	local divider = Kit.divider(w)
	divider.Position = UDim2.fromOffset(PAD, PAD + 76)
	divider.Parent = side

	-- Stern-Karte
	local kindText = if s.kind == "core"
		then "Herz"
		elseif s.kind == "big" then "Großer Stern"
		else "Stern"
	local branchText = if s.branch then " · " .. StarNet.BranchName[s.branch] else ""
	local kind = Kit.label(kindText .. branchText, 16, BRANCH_COLOR[s.branch or ""] or C.Gold)
	kind.Position = UDim2.fromOffset(PAD, PAD + 100)
	kind.Parent = side
	local state = if allocated[s.id]
		then "Zugewiesen"
		elseif canAllocate(s) then "Verfügbar"
		else "Gesperrt"
	local st = Kit.label(state, 14, if allocated[s.id] then C.Gold else C.Muted)
	st.AnchorPoint = Vector2.new(1, 0)
	st.Position = UDim2.new(1, -PAD, 0, PAD + 102)
	st.Parent = side

	local big = Kit.itemSlot(104, s.icon, {
		rarity = if s.branch then StarNet.BranchRarity[s.branch] else "rare",
	})
	big.Active = false
	big.Position = UDim2.fromOffset(PAD, PAD + 140)
	big.Parent = side
	local name = Window.heading(s.name, 22, C.Text)
	name.Position = UDim2.fromOffset(PAD + 120, PAD + 140)
	name.Parent = side
	local stats =
		Window.frame(UDim2.fromOffset(w - 120, 80), UDim2.fromOffset(PAD + 120, PAD + 184))
	local sl = Kit.list(stats, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Top)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	for i, line in s.stats do
		local t = Kit.label(line, 16, C.Text, Theme.Font.Body)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.Size = UDim2.fromOffset(w - 120, 0)
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.LayoutOrder = i
		t.Parent = stats
	end
	stats.Parent = side

	local y = PAD + 270
	if s.flavor then
		local italic = Font.fromName("Nunito", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
		local f = Kit.label(s.flavor, 15, C.Muted, italic)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.Size = UDim2.fromOffset(w, 0)
		f.TextWrapped = true
		f.TextXAlignment = Enum.TextXAlignment.Left
		f.Position = UDim2.fromOffset(PAD, y)
		f.Parent = side
		y += 70
	end

	-- Kosten
	local cost = StarNet.Cost[s.kind]
	if cost > 0 then
		local c = Kit.label(
			string.format("Kosten: %d Punkt%s", cost, if cost == 1 then "" else "e"),
			16,
			C.Text
		)
		c.Position = UDim2.fromOffset(PAD, y)
		c.Parent = side
	end

	local note = Kit.label(
		"Vorschau: Sterne wirken noch nicht und werden nicht gespeichert.",
		14,
		C.Muted,
		Theme.Font.Body
	)
	note.AutomaticSize = Enum.AutomaticSize.Y
	note.Size = UDim2.fromOffset(w, 0)
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, PAD, 1, -PAD - 140)
	note.Parent = side

	-- Aktionen
	local remove = allocated[s.id] == true
	local main = Kit.button(
		if remove then "Entfernen" else "Zuweisen",
		C.Gold,
		Vector2.new(w, 60),
		if remove then "neu_wuerfeln" else "verbessern"
	)
	Kit.buttonLabel(main).TextSize = Kit.fontSize(22)
	main.AnchorPoint = Vector2.new(0, 1)
	main.Position = UDim2.new(0, PAD, 1, -PAD - 62)
	Kit.setEnabled(main, if remove then canRemove(s) else canAllocate(s))
	main.Activated:Connect(function()
		if not main.Active then
			return
		end
		if remove then
			allocated[s.id] = nil
		else
			allocated[s.id] = true
		end
		StarNetController.render()
	end)
	main.Parent = side

	local reset = Kit.button("Zurücksetzen", C.Danger, Vector2.new(w, 50), "neu_wuerfeln")
	reset.AnchorPoint = Vector2.new(0, 1)
	reset.Position = UDim2.new(0, PAD, 1, -PAD)
	reset.Activated:Connect(function()
		allocated = { herz = true }
		StarNetController.render()
	end)
	reset.Parent = side
end

-- ------------------------------------------------------------------ Ablauf
function StarNetController.render()
	renderNet()
	renderSide()
end

function StarNetController.toggle()
	win.toggle()
end

function StarNetController.init()
	win = Window.new({
		name = "StarNet",
		title = "Sternennetz",
		icon = "sternennetz",
		key = Enum.KeyCode.N,
		background = "bg_starnet",
	})

	net = Window.frame(UDim2.fromOffset(StarNet.Size.X, StarNet.Size.Y), UDim2.fromOffset(40, TOP))
	net.Parent = win.root

	side = Kit.panel(Vector2.new(SIDE_W, 790))
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.new(1, -40, 0, TOP)
	side.Parent = win.root

	win.onOpen(StarNetController.render)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		if win.isOpen() then
			StarNetController.render()
		end
	end)
	StarNetController.render()
end

return StarNetController
