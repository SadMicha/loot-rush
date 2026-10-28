--!strict
-- Fähigkeiten-Fenster nach Mockup „Fähigkeiten“ (Taste K oder Menü-Button):
--   links Skillleiste Q/E/R/F und Skill-Liste, Mitte Skill-Blüte, rechts Details.
-- Werte kommen aus Shared.Skills. Skill-Stufen und Blüten-Punkte gibt es noch nicht –
-- der Baum ist eine Vorschau (alle Knoten 0/5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills = require(ReplicatedStorage.Shared.Skills)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)

local AbilitiesController = {}

local C = Theme.Color
local KEYS = { "Q", "E", "R", "F" }
local PAD = 28
local LEFT_W, SIDE_W, TOP = 440, 420, 100
local TREE_W, TREE_H = 620, 700
-- Icons der Knoten je Ast
local BRANCH_ICON: { [string]: string } =
	{ trunk = "verbessern", left = "kristall", right = "timer" }

local win: Window.Window
local listPanel: Frame
local tree: Frame
local detail: Frame
local hint: TextLabel

local selected = 1 -- Index in Skills.bar

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

local function fmt(v: number): string
	local s = if v == math.floor(v) then tostring(v) else string.format("%.1f", v)
	return (s:gsub("%.", ","))
end

-- ------------------------------------------------------------------ Links: Leiste und Liste
local function renderList()
	clear(listPanel)

	local bar = Window.frame(UDim2.fromOffset(LEFT_W - 2 * PAD, 110), UDim2.fromOffset(PAD, PAD))
	Kit.list(bar, Enum.FillDirection.Horizontal, 16, Enum.VerticalAlignment.Top)
	for i, skill in Skills.bar do
		local s = Kit.itemSlot(80, skill.icon, {
			rarity = if i == selected then "rare" else "normal",
			selected = i == selected,
		})
		s.LayoutOrder = i
		s.Activated:Connect(function()
			selected = i
			AbilitiesController.render()
		end)
		local k = Kit.label(KEYS[i], 16, if i == selected then C.GoldHi else C.Muted)
		k.AnchorPoint = Vector2.new(0.5, 0)
		k.Position = UDim2.new(0.5, 0, 1, 4)
		k.ZIndex = 4
		k.Parent = s
		s.Parent = bar
	end
	bar.Parent = listPanel

	local divider = Kit.divider(LEFT_W - 2 * PAD)
	divider.Position = UDim2.fromOffset(PAD, PAD + 124)
	divider.Parent = listPanel

	local list =
		Window.frame(UDim2.fromOffset(LEFT_W - 2 * PAD, 560), UDim2.fromOffset(PAD, PAD + 148))
	Kit.list(list, Enum.FillDirection.Vertical, 10, Enum.VerticalAlignment.Top)
	for i, skill in Skills.bar do
		local row = Instance.new("ImageButton")
		row.Name = skill.id
		row.AutoButtonColor = false
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(LEFT_W - 2 * PAD, 84)
		row.LayoutOrder = i
		Kit.skin(row, if i == selected then "btn_sort" else "stat_tile", 84, 0.5)
		if i == selected then
			Kit.stroke(row, C.Gold, 2)
			Kit.corner(row, Theme.Radius.M)
		end
		local ic = Kit.itemSlot(64, skill.icon, { rarity = "normal" })
		ic.Active = false
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 10, 0.5, 0)
		ic.ZIndex = 2
		ic.Parent = row
		local name = Kit.label(skill.name, 19, if i == selected then C.GoldHi else C.Text)
		name.Position = UDim2.fromOffset(88, 14)
		name.ZIndex = 2
		name.Parent = row
		local sub = Kit.label(
			string.format("%d Schaden · %s s", skill.damage, fmt(skill.cooldown)),
			14,
			C.Muted,
			Theme.Font.Body
		)
		sub.Position = UDim2.fromOffset(88, 46)
		sub.ZIndex = 2
		sub.Parent = row
		local key = Kit.label(KEYS[i], 18, C.Muted)
		key.AnchorPoint = Vector2.new(1, 0.5)
		key.Position = UDim2.new(1, -18, 0.5, 0)
		key.ZIndex = 2
		key.Parent = row
		row.Activated:Connect(function()
			selected = i
			AbilitiesController.render()
		end)
		row.Parent = list
	end
	list.Parent = listPanel
end

-- ------------------------------------------------------------------ Mitte: Skill-Blüte
local function renderTree()
	clear(tree)
	local skill = Skills.bar[selected]
	local bloom = Skills.Blooms[skill.id]

	local cx = TREE_W / 2
	local root = Vector2.new(cx, 560)
	local trunk = { Vector2.new(cx, 430), Vector2.new(cx, 315), Vector2.new(cx, 200) }
	local left = { Vector2.new(cx - 120, 500), Vector2.new(cx - 240, 470) }
	local right = { Vector2.new(cx + 120, 500), Vector2.new(cx + 240, 470) }
	local lineColor = C.Gold

	-- Verbindungen zuerst, damit die Knoten darüber liegen
	Window.line(tree, root, trunk[1], lineColor, 3)
	Window.line(tree, trunk[1], trunk[2], lineColor, 3)
	Window.line(tree, trunk[2], trunk[3], lineColor, 3)
	Window.line(tree, root, left[1], lineColor, 3)
	Window.line(tree, left[1], left[2], lineColor, 3)
	Window.line(tree, root, right[1], lineColor, 3)
	Window.line(tree, right[1], right[2], lineColor, 3)

	local rootNode = Window.node(skill.icon, 120, root, {
		art = "node_ring_active",
		rarity = "rare",
	})
	rootNode.Parent = tree
	Window.caption(tree, skill.name, root + Vector2.new(0, 66), 18, C.GoldHi)

	if not bloom then
		hint.Text = "Für diesen Skill gibt es noch keine Blüte."
		return
	end

	local function branch(
		spec: { name: string, nodes: { Skills.BloomNode } },
		points: { Vector2 },
		key: string
	)
		for i, n in spec.nodes do
			local p = points[i]
			if not p then
				break
			end
			local b = Window.node(BRANCH_ICON[key], 84, p, {
				art = "node_ring_locked",
				rarity = nil,
				dim = true,
			})
			b.Activated:Connect(function()
				hint.Text = n.name .. ": " .. n.text
			end)
			b.Parent = tree
			Window.caption(
				tree,
				"0/" .. tostring(Skills.BloomMax),
				p + Vector2.new(0, 46),
				15,
				C.Muted
			)
			Window.caption(tree, n.name, p + Vector2.new(0, 70), 14, C.Text)
		end
	end
	branch(bloom.trunk, trunk, "trunk")
	branch(bloom.left, left, "left")
	branch(bloom.right, right, "right")

	-- Ast-Namen
	local trunkName = Window.heading(bloom.trunk.name, 22, C.Cyan)
	trunkName.AnchorPoint = Vector2.new(0.5, 0)
	trunkName.Position = UDim2.fromOffset(cx, 96)
	trunkName.Parent = tree
	local leftName = Window.heading(bloom.left.name, 20, C.Gold)
	leftName.AnchorPoint = Vector2.new(0.5, 0)
	leftName.Position = UDim2.fromOffset(left[2].X + 20, 360)
	leftName.Parent = tree
	local rightName = Window.heading(bloom.right.name, 20, C.Gold)
	rightName.AnchorPoint = Vector2.new(0.5, 0)
	rightName.Position = UDim2.fromOffset(right[2].X - 20, 360)
	rightName.Parent = tree

	hint.Text = "Tippe einen Knoten an. Blüten-Punkte gibt es, sobald Skills Stufen haben."
end

-- ------------------------------------------------------------------ Rechts: Details
local function statTile(iconName: string, value: string, label: string, order: number): Frame
	local f = Window.frame(UDim2.fromOffset(112, 96))
	f.LayoutOrder = order
	Kit.skin(f, "stat_tile", 96, 0.4)
	local ic = Kit.icon(iconName, 28)
	ic.AnchorPoint = Vector2.new(0.5, 0)
	ic.Position = UDim2.new(0.5, 0, 0, 10)
	ic.ZIndex = 2
	ic.Parent = f
	local v = Kit.label(value, 18, C.Text)
	v.AnchorPoint = Vector2.new(0.5, 0)
	v.Position = UDim2.new(0.5, 0, 0, 40)
	v.ZIndex = 2
	v.Parent = f
	local l = Kit.label(label, 12, C.Muted, Theme.Font.Body)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 68)
	l.ZIndex = 2
	l.Parent = f
	return f
end

local function renderDetail()
	clear(detail)
	local skill = Skills.bar[selected]
	local w = SIDE_W - 2 * PAD

	local big = Kit.itemSlot(110, skill.icon, { rarity = "rare" })
	big.Active = false
	big.Position = UDim2.fromOffset(PAD, PAD)
	big.Parent = detail
	local name = Window.heading(skill.name, 22, C.Cyan)
	name.Position = UDim2.fromOffset(PAD + 128, PAD + 18)
	name.Parent = detail
	local key = Kit.label("Taste " .. KEYS[selected], 16, C.Muted, Theme.Font.Body)
	key.Position = UDim2.fromOffset(PAD + 128, PAD + 62)
	key.Parent = detail

	local desc = Kit.label(skill.desc, 16, C.Text, Theme.Font.Body)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.Size = UDim2.fromOffset(w, 0)
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Position = UDim2.fromOffset(PAD, PAD + 132)
	desc.Parent = detail

	local tiles = Window.frame(UDim2.fromOffset(w, 96), UDim2.fromOffset(PAD, PAD + 210))
	Kit.list(tiles, Enum.FillDirection.Horizontal, 10)
	statTile("schwert", tostring(skill.damage), "Schaden", 1).Parent = tiles
	statTile("timer", fmt(skill.cooldown) .. " s", "Abklingzeit", 2).Parent = tiles
	local reach = if skill.range > 0 then skill.range else skill.radius
	statTile("ziel", fmt(reach), if skill.range > 0 then "Reichweite" else "Radius", 3).Parent =
		tiles
	tiles.Parent = detail

	local divider = Kit.divider(w)
	divider.Position = UDim2.fromOffset(PAD, PAD + 326)
	divider.Parent = detail

	local pts = Kit.label("0 / " .. tostring(Skills.BloomMax), 22, C.GoldHi)
	pts.Position = UDim2.fromOffset(PAD + 40, PAD + 350)
	pts.Parent = detail
	local ptsIcon = Kit.icon("sternennetz", 30)
	ptsIcon.Position = UDim2.fromOffset(PAD, PAD + 350)
	ptsIcon.Parent = detail
	local info = Kit.label(
		"Jede Skill-Stufe gibt einen Blüten-Punkt. Pro Ast entsteht eine eigene Spielweise.",
		15,
		C.Muted,
		Theme.Font.Body
	)
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Size = UDim2.fromOffset(w, 0)
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.Position = UDim2.fromOffset(PAD, PAD + 392)
	info.Parent = detail

	-- Alle vier Skills liegen fest auf der Leiste; Tauschen kommt mit weiteren Skills
	local b = Kit.button("Ausgerüstet", C.Gold, Vector2.new(w, 60), "verbessern")
	Kit.buttonLabel(b).TextSize = Kit.fontSize(22)
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(0, PAD, 1, -PAD)
	Kit.setEnabled(b, false)
	b.Parent = detail
end

-- ------------------------------------------------------------------ Ablauf
function AbilitiesController.render()
	renderList()
	renderTree()
	renderDetail()
end

function AbilitiesController.toggle()
	win.toggle()
end

function AbilitiesController.init()
	win = Window.new({
		name = "Abilities",
		title = "Fähigkeiten",
		icon = "skills",
		key = Enum.KeyCode.K,
		background = "bg_skills",
	})

	listPanel = Kit.panel(Vector2.new(LEFT_W, 770))
	listPanel.Position = UDim2.fromOffset(40, TOP)
	listPanel.Parent = win.root

	local center =
		Window.frame(UDim2.fromOffset(TREE_W, 770), UDim2.fromOffset(40 + LEFT_W + 20, TOP))
	center.Parent = win.root
	local treeTitle = Window.heading("Skill-Blüte", 26, C.Text)
	treeTitle.AnchorPoint = Vector2.new(0.5, 0)
	treeTitle.Position = UDim2.new(0.5, 0, 0, 0)
	treeTitle.Parent = center
	tree = Window.frame(UDim2.fromOffset(TREE_W, TREE_H), UDim2.fromOffset(0, 0))
	tree.Parent = center
	hint = Kit.label("", 16, C.Muted, Theme.Font.Body)
	hint.AutomaticSize = Enum.AutomaticSize.Y
	hint.Size = UDim2.fromOffset(TREE_W - 40, 0)
	hint.TextWrapped = true
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, 0)
	hint.Parent = center

	detail = Kit.panel(Vector2.new(SIDE_W, 770))
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -40, 0, TOP)
	detail.Parent = win.root

	AbilitiesController.render()
end

return AbilitiesController
