--!strict
-- Skills window after the "Abilities" mockup (key K or menu button):
--   left: skill bar Q/E/R/F and all 8 skills, center: skill bloom, right: details with the
--   slot buttons (equip a skill to Q/E/R/F).
-- Values come from Shared.Skills, combined with level, bloom and stars (Progression.effectiveSkill).
-- Levels and bloom points are kept by the server (Systems/Progress); the window only sends requests
-- (Net.Bloom, Net.Loadout).

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skills = require(ReplicatedStorage.Shared.Skills)
local SpellStones = require(ReplicatedStorage.Shared.SpellStones)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local ProgressController = require(script.Parent.ProgressController)

local AbilitiesController = {}

local C = Theme.Color
local KEYS = { "Q", "E", "R", "F" }
local PAD = 28
local LEFT_W, SIDE_W = 440, 420
local TREE_W, TREE_H = 620, 700
-- Node icons per branch
local BRANCH_ICON: { [string]: string } = { trunk = "upgrade", left = "crystal", right = "timer" }

-- Small viewports (phones, shorter side under Theme.TabletMinSide): the content area is scaled down
-- a lot, so texts and touch targets grow to their minimum screen size (Kit.MIN_TEXT_PX/MIN_TOUCH_PX)
-- relative to the layout. The compact layout therefore has fewer labels and flows downward.
local COMPACT_SIDE_W, COMPACT_TREE_W = 520, 520
local small = false
local sideW, treeW = SIDE_W, TREE_W

local win: Window.Window
local listPanel: Frame
local center: Frame
local tree: Frame
local detail: Frame
local hint: TextLabel

local player = Players.LocalPlayer
local LIST_TOP = 44 -- skill list below the header
local PICK_W, PICK_ROW = 560, 66 -- stone picker card and its rows
-- 8 rows (+ 2 px gaps) fill the list height so they stay touchable on notched phones with the
-- menu dock (Phone.spec, Matrix.spec): 8 × 88 + 7 × 2 = 718 = BODY.Y - PAD - LIST_TOP
local ROW_H = 88
local ROW_GAP = 2
local selected = Skills.DefaultBar[1] -- skill id (kept inside the current class, see kit())
local selectedNode: string? = nil -- bloom node, e.g. "trunk2"

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Skin" then
			child:Destroy()
		end
	end
end

local function progressOf(skill: Skills.Skill): Progression.SkillProgress
	return Progression.skill(ProgressController.data(), skill.id)
end

local function effectiveOf(skill: Skills.Skill): Skills.Skill
	return Progression.effectiveSkill(skill, ProgressController.data())
end

local function fmt(v: number): string
	return if v == math.floor(v) then tostring(v) else string.format("%.1f", v)
end

-- Skills of the player's class; moves the selection into the class if it is outside
local function kit(): Skills.ClassKit
	local k = Skills.forClass(Kit.playerClass())
	local s = Skills.ById[selected]
	if not s or s.class ~= Kit.playerClass() then
		selected = k.bar[1]
		selectedNode = nil
	end
	return k
end

local function playerLevel(): number
	return (player:GetAttribute("Level") or 1) :: number
end

-- Bar slot of a skill (nil = not equipped)
local function slotOf(id: string): number?
	for i, other in ProgressController.data().bar do
		if other == id then
			return i
		end
	end
	return nil
end

-- ------------------------------------------------------------------ Left: bar and list
local function renderList()
	clear(listPanel)

	local head = Window.heading("Skills - 4 on the bar", 20, C.Text)
	head.Position = UDim2.fromOffset(PAD, PAD - 6)
	head.Parent = listPanel

	local list = Window.frame(
		UDim2.fromOffset(LEFT_W - 2 * PAD, Window.BODY.Y - PAD - LIST_TOP),
		UDim2.fromOffset(PAD, PAD + LIST_TOP)
	)
	Kit.list(list, Enum.FillDirection.Vertical, ROW_GAP, Enum.VerticalAlignment.Top)
	local level = playerLevel()
	for i, skill in kit().list do
		local on = skill.id == selected
		local need = Progression.unlockLevel(skill, ProgressController.data())
		local locked = level < need
		local slot = slotOf(skill.id)
		local row = Instance.new("ImageButton")
		row.Name = skill.id
		row.AutoButtonColor = false
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(LEFT_W - 2 * PAD, ROW_H)
		row.LayoutOrder = i
		if on then
			Kit.corner(row, Theme.Radius.M)
			Kit.stroke(row, C.Gold, 2)
		end
		Kit.skin(row, if on then "btn_sort" else "stat_tile", ROW_H, 0.5)
		local ic = Kit.itemSlot(60, Kit.skillIcon(skill.id, skill.icon), { rarity = "normal" })
		ic.Active = false
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 8, 0.5, 0)
		ic.ZIndex = 2
		ic.Parent = row
		local name =
			Kit.label(skill.name, 17, if on then C.GoldHi elseif locked then C.Muted else C.Text)
		name.Position = UDim2.fromOffset(84, 14)
		name.ZIndex = 2
		if small then
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Size = UDim2.fromOffset(LEFT_W - 2 * PAD - 84 - 54, 32)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
		end
		name.Parent = row
		local eff = effectiveOf(skill)
		local sub = Kit.label(
			if locked
				then string.format("Unlocks at level %d", need)
				elseif small then string.format(
					"Lv %d - %s dmg",
					progressOf(skill).level,
					fmt(math.floor(eff.damage + 0.5))
				)
				else string.format(
					"Lv %d - %s dmg - %s s",
					progressOf(skill).level,
					fmt(math.floor(eff.damage + 0.5)),
					fmt(eff.cooldown)
				),
			14,
			C.Muted,
			Theme.Font.Body
		)
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.Size = UDim2.fromOffset(LEFT_W - 2 * PAD - 84 - 54, 20)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Position = UDim2.fromOffset(84, 46)
		sub.ZIndex = 2
		sub.Parent = row
		-- Right side: key badge if equipped
		if slot and not locked then
			local badge = Instance.new("Frame")
			badge.Name = "Key"
			badge.BackgroundColor3 = Theme.Flat.Surface0
			badge.BackgroundTransparency = 0.2
			badge.AnchorPoint = Vector2.new(1, 0.5)
			badge.Position = UDim2.new(1, -12, 0.5, 0)
			badge.Size = UDim2.fromOffset(34, 34)
			badge.ZIndex = 2
			Kit.corner(badge, Theme.Radius.M)
			Kit.stroke(badge, C.Gold, 1)
			local key = Kit.label(KEYS[slot], 16, C.GoldHi)
			key.AnchorPoint = Vector2.new(0.5, 0.5)
			key.Position = UDim2.fromScale(0.5, 0.5)
			key.ZIndex = 3
			key.Parent = badge
			badge.Parent = row
		end
		if locked then
			local lock = Kit.icon("lock", 22, C.Muted)
			lock.AnchorPoint = Vector2.new(1, 0.5)
			lock.Position = UDim2.new(1, -14, 0.5, 0)
			lock.ZIndex = 2
			lock.Parent = row
		end
		row.Activated:Connect(function()
			selected = skill.id
			selectedNode = nil
			AbilitiesController.render()
		end)
		row.Parent = list
	end
	list.Parent = listPanel
end

-- ------------------------------------------------------------------ Center: skill bloom
local function renderTree()
	clear(tree)
	local skill = Skills.ById[selected]
	local bloom = Skills.Blooms[skill.id]

	local cx = treeW / 2
	local root = Vector2.new(cx, 600)
	local trunk = { Vector2.new(cx, 470), Vector2.new(cx, 345), Vector2.new(cx, 220) }
	local reach1, reach2 = if small then 110 else 120, if small then 195 else 240
	local left = { Vector2.new(cx - reach1, 540), Vector2.new(cx - reach2, 500) }
	local right = { Vector2.new(cx + reach1, 540), Vector2.new(cx + reach2, 500) }
	local lineColor = C.Gold

	-- Connections first so the nodes sit on top
	Window.line(tree, root, trunk[1], lineColor, 3)
	Window.line(tree, trunk[1], trunk[2], lineColor, 3)
	Window.line(tree, trunk[2], trunk[3], lineColor, 3)
	Window.line(tree, root, left[1], lineColor, 3)
	Window.line(tree, left[1], left[2], lineColor, 3)
	Window.line(tree, root, right[1], lineColor, 3)
	Window.line(tree, right[1], right[2], lineColor, 3)

	local rootNode = Window.node(Kit.skillIcon(skill.id, skill.icon), 120, root, {
		art = "node_ring_active",
		rarity = "rare",
	})
	rootNode.Parent = tree
	Window.caption(tree, skill.name, root + Vector2.new(0, 66), if small then 14 else 18, C.GoldHi)

	if not bloom then
		hint.Text = "This skill has no bloom yet."
		return
	end

	local sp = progressOf(skill)
	local function branch(spec: Skills.BloomBranch, points: { Vector2 }, key: string)
		for i, n in spec.nodes do
			local p = points[i]
			if not p then
				break
			end
			local nodeKey = key .. tostring(i)
			local pts = sp.bloom[nodeKey] or 0
			local open = Progression.canBloom(sp, skill.id, nodeKey)
			local b = Window.node(BRANCH_ICON[key], 84, p, {
				art = if pts > 0 then "node_ring_active" else "node_ring_locked",
				rarity = if pts > 0 then "rare" elseif open then "normal" else nil,
				dim = pts == 0 and not open,
				selected = selectedNode == nodeKey,
			})
			b.Activated:Connect(function()
				selectedNode = nodeKey
				AbilitiesController.render()
			end)
			b.Parent = tree
			-- On the trunk the texts sit to the right so the connecting line stays clear
			local side = key == "trunk"
			local ptsLabel = Window.caption(
				tree,
				if n.effect then string.format("%d/%d", pts, Skills.BloomMax) else "soon",
				p + (if side then Vector2.new(52, -24) else Vector2.new(0, 46)),
				15,
				if pts > 0 then C.GoldHi else C.Muted
			)
			if side then
				ptsLabel.AnchorPoint = Vector2.zero
			end
			-- Compact: no node titles (they would run into each other); the selected node's
			-- name and text are shown in the hint below the bloom
			if not small then
				local title = Window.caption(
					tree,
					n.name,
					p + (if side then Vector2.new(52, 0) else Vector2.new(0, 70)),
					14,
					C.Text
				)
				if side then
					title.AnchorPoint = Vector2.zero
				end
			end
		end
	end
	branch(bloom.trunk, trunk, "trunk")
	branch(bloom.left, left, "left")
	branch(bloom.right, right, "right")

	-- Branch names
	local trunkName = Window.heading(bloom.trunk.name, 22, C.Cyan)
	trunkName.AnchorPoint = Vector2.new(0.5, 0)
	trunkName.Position = UDim2.fromOffset(cx, 130)
	trunkName.Parent = tree
	local leftName = Window.heading(bloom.left.name, 20, C.Gold)
	leftName.AnchorPoint = Vector2.new(0.5, 0)
	leftName.Position = UDim2.fromOffset(left[2].X + 20, 400)
	leftName.Parent = tree
	local rightName = Window.heading(bloom.right.name, 20, C.Gold)
	rightName.AnchorPoint = Vector2.new(0.5, 0)
	rightName.Position = UDim2.fromOffset(right[2].X - 20, 400)
	rightName.Parent = tree
	if small then
		-- Wrapped into a column of their own on each side so the long names stay inside the tree
		local colW = 230
		for _, label in { trunkName, leftName, rightName } do
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.TextWrapped = true
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.Size = UDim2.fromOffset(if label == trunkName then treeW - 40 else colW, 0)
		end
		leftName.Position = UDim2.fromOffset(colW / 2, 392)
		rightName.Position = UDim2.fromOffset(treeW - colW / 2, 392)
	end

	local node = if selectedNode then Skills.bloomNode(skill.id, selectedNode) else nil
	if node and selectedNode then
		local _, why = Progression.canBloom(sp, skill.id, selectedNode)
		local maxed = (sp.bloom[selectedNode] or 0) >= Skills.BloomMax -- no reason text needed when fully upgraded
		hint.Text = string.format(
			"%s: %s%s",
			node.name,
			node.text,
			if why and not maxed then " - " .. why else ""
		)
	else
		hint.Text = if small
			then skill.desc
			else "Tap a node. Each skill level grants a bloom point."
	end
end

-- ------------------------------------------------------------------ Right: details
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

-- ------------------------------------------------------------------ Stone picker
-- Small menu over the bloom tree: tap a socket, pick one of the fitting stones you own (with a
-- spare copy), or take the socketed one out. Gone with the next render or a tap outside.
local picker: Frame? = nil

local function closePicker()
	if picker then
		picker:Destroy()
		picker = nil
	end
end

local function openPicker(skill: Skills.Skill, socket: number, current: string?)
	closePicker()
	local data = ProgressController.data()
	local body = Window.BODY
	local layer = Window.frame(UDim2.fromOffset(body.X, body.Y))
	layer.Name = "StonePicker"
	layer.ZIndex = 20
	-- Tap outside closes
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 20
	shade.Activated:Connect(closePicker)
	shade.Parent = layer

	local options: { SpellStones.Stone } = {}
	for _, st in SpellStones.List do
		local owned = ((data.stones or {})[st.id] or 0) :: number
		local spare = owned - Progression.stonesUsed(data, st.id)
		if SpellStones.fits(st.id, skill.kind) and spare > 0 and st.id ~= current then
			table.insert(options, st)
		end
	end
	local rows = #options + (if current then 1 else 0)
	local w = PICK_W - 2 * PAD
	local h = PAD + 56 + math.max(1, rows) * (PICK_ROW + 8) + 28 + PAD
	local card = Kit.panel(Vector2.new(PICK_W, h), C.Gold)
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = 21
	card.Active = true -- taps on the card do not reach the shade
	local title = Window.heading(string.format("Socket %d - %s", socket, skill.name), 20, C.Text)
	title.Position = UDim2.fromOffset(PAD, PAD - 4)
	title.ZIndex = 22
	title.Parent = card
	local tip = Kit.label("Tap outside to close", 13, C.Muted, Theme.Font.Body)
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.new(0.5, 0, 1, -PAD + 6)
	tip.ZIndex = 22
	tip.Parent = card

	local list =
		Window.frame(UDim2.fromOffset(w, h - 2 * PAD - 84), UDim2.fromOffset(PAD, PAD + 52))
	Kit.list(list, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
	local function pick(stoneId: string)
		local args: { any } = { socket, stoneId }
		Net.Loadout:FireServer("socket", skill.id, args)
		closePicker()
	end
	local function row(
		order: number,
		name: string,
		text: string,
		color: Color3,
		icon: string?,
		onPick: () -> ()
	)
		local r = Instance.new("ImageButton")
		r.Name = "Option" .. order
		r.AutoButtonColor = false
		r.BackgroundTransparency = 1
		r.Size = UDim2.fromOffset(w, PICK_ROW)
		r.LayoutOrder = order
		r.ZIndex = 22
		Kit.skin(r, "stat_tile", PICK_ROW, 0.5)
		Kit.touchTarget(r)
		if icon then
			local ic = Kit.icon(icon, 48)
			ic.Name = "Stone"
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.new(0, 30, 0.5, 0)
			ic.ZIndex = 23
			ic.Parent = r
		else
			local gem = Instance.new("Frame")
			gem.Name = "Gem"
			gem.BackgroundColor3 = color
			gem.BorderSizePixel = 0
			gem.Rotation = 45
			gem.AnchorPoint = Vector2.new(0.5, 0.5)
			gem.Position = UDim2.new(0, 30, 0.5, 0)
			gem.Size = UDim2.fromOffset(22, 22)
			gem.ZIndex = 23
			Kit.corner(gem, Theme.Radius.S)
			gem.Parent = r
		end
		local n = Kit.label(name, 18, color)
		n.AutomaticSize = Enum.AutomaticSize.None
		n.Size = UDim2.fromOffset(w - 76, 24)
		n.TextXAlignment = Enum.TextXAlignment.Left
		n.TextTruncate = Enum.TextTruncate.AtEnd
		n.Position = UDim2.fromOffset(60, 10)
		n.ZIndex = 23
		n.Parent = r
		local t = Kit.label(text, 14, C.Muted, Theme.Font.Body)
		t.AutomaticSize = Enum.AutomaticSize.None
		t.Size = UDim2.fromOffset(w - 76, 20)
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Position = UDim2.fromOffset(60, 38)
		t.ZIndex = 23
		t.Parent = r
		r.Activated:Connect(onPick)
		r.Parent = list
	end
	for i, st in options do
		local spare = ((data.stones or {})[st.id] or 0) - Progression.stonesUsed(data, st.id)
		row(i, string.format("%s  ×%d", st.name, spare), st.text, st.color, st.icon, function()
			pick(st.id)
		end)
	end
	if current then
		row(#options + 1, "Remove stone", "Back into your stones", C.Danger, nil, function()
			pick("")
		end)
	end
	if rows == 0 then
		local none = Kit.label(
			"No fitting stones yet. Bosses and elites drop them.",
			16,
			C.Muted,
			Theme.Font.Body
		)
		none.AutomaticSize = Enum.AutomaticSize.Y
		none.Size = UDim2.fromOffset(w, 0)
		none.TextWrapped = true
		none.TextXAlignment = Enum.TextXAlignment.Left
		none.ZIndex = 22
		none.Parent = list
	end
	list.Parent = card
	card.Parent = layer
	layer.Parent = win.body
	picker = layer
end

-- Compact detail panel: one top-down flow instead of fixed y positions, so growing texts and
-- touch targets push the next block down instead of running into it. No description (it is shown
-- below the bloom), icon-only stat tiles, reset only when there is something to reset.
local function renderDetailCompact()
	local skill = Skills.ById[selected]
	local eff = effectiveOf(skill)
	local sp = progressOf(skill)
	local w = sideW - 2 * PAD
	local slot = slotOf(skill.id)
	local data = ProgressController.data()

	local flow = Window.frame(UDim2.fromOffset(w, 0), UDim2.fromOffset(PAD, PAD))
	flow.Name = "Flow"
	flow.AutomaticSize = Enum.AutomaticSize.Y
	local flowList = Kit.list(flow, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
	flowList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local order = 0
	local function add(child: GuiObject)
		order += 1
		child.LayoutOrder = order
		child.Parent = flow
	end
	local function rowFrame(height: number): Frame
		local f = Window.frame(UDim2.fromOffset(w, height))
		if height == 0 then
			f.AutomaticSize = Enum.AutomaticSize.Y
		end
		return f
	end

	-- Header: icon, name, key and level
	local head = rowFrame(96)
	local big = Kit.itemSlot(96, Kit.skillIcon(skill.id, skill.icon), { rarity = "rare" })
	big.Active = false
	big.Parent = head
	local name = Window.heading(skill.name, 20, C.Cyan)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.fromOffset(w - 110, 36)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(110, 8)
	name.Parent = head
	local key = Kit.label(
		if slot
			then string.format("Key %s - Level %d", KEYS[slot], sp.level)
			else string.format("Off bar - Level %d", sp.level),
		16,
		C.Muted,
		Theme.Font.Body
	)
	key.AutomaticSize = Enum.AutomaticSize.None
	key.Size = UDim2.fromOffset(w - 110, 36)
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextTruncate = Enum.TextTruncate.AtEnd
	key.Position = UDim2.fromOffset(110, 52)
	key.Parent = head
	add(head)

	-- Stat tiles: icon over value, no caption text
	local tiles = rowFrame(84)
	Kit.list(tiles, Enum.FillDirection.Horizontal, 8)
	local tileW = math.floor((w - 16) / 3)
	local reach = if skill.range > 0 then skill.range else eff.radius
	local stats = {
		{ "sword", fmt(math.floor(eff.damage + 0.5)) },
		{ "timer", fmt(eff.cooldown) .. " s" },
		{ "target", fmt(reach) },
	}
	for i, stat in stats do
		local f = Window.frame(UDim2.fromOffset(tileW, 84))
		f.LayoutOrder = i
		Kit.skin(f, "stat_tile", 84, 0.4)
		local ic = Kit.icon(stat[1], 28)
		ic.AnchorPoint = Vector2.new(0.5, 0)
		ic.Position = UDim2.new(0.5, 0, 0, 6)
		ic.ZIndex = 2
		ic.Parent = f
		local v = Kit.label(stat[2], 18, C.Text)
		v.AnchorPoint = Vector2.new(0.5, 0)
		v.Position = UDim2.new(0.5, 0, 0, 40)
		v.ZIndex = 2
		v.Parent = f
		f.Parent = tiles
	end
	add(tiles)

	-- Bloom points and skill XP
	local free = Progression.bloomPoints(sp)
	local pointsRow = rowFrame(40)
	local ptsIcon = Kit.icon("star_net", 30)
	ptsIcon.Position = UDim2.fromOffset(0, 5)
	ptsIcon.Parent = pointsRow
	local pts = Kit.label(
		string.format("%d Bloom Point%s", free, if free == 1 then "" else "s"),
		22,
		if free > 0 then C.GoldHi else C.Muted
	)
	pts.Position = UDim2.fromOffset(40, 2)
	pts.Parent = pointsRow
	add(pointsRow)

	local maxed = sp.level >= Skills.MaxLevel
	local need = Progression.skillXpFor(sp.level)
	local xpRow = rowFrame(52)
	local back, fill = Kit.bar(Vector2.new(w, 8), C.Cyan)
	fill.Size = UDim2.fromScale(if maxed then 1 else math.clamp(sp.xp / need, 0, 1), 1)
	back.Parent = xpRow
	local xp = Kit.label(
		if maxed then "Max level" else string.format("%d / %d XP", sp.xp, need),
		14,
		C.Muted,
		Theme.Font.Body
	)
	xp.AutomaticSize = Enum.AutomaticSize.None
	xp.Size = UDim2.fromOffset(w, 36)
	xp.TextXAlignment = Enum.TextXAlignment.Left
	xp.Position = UDim2.fromOffset(0, 14)
	xp.Parent = xpRow
	add(xpRow)

	-- Spell stone sockets
	local socketed: { string } = (data.sockets or {})[skill.id] or {}
	local sockets = rowFrame(0)
	Kit.list(sockets, Enum.FillDirection.Horizontal, 8)
	local sw = math.floor((w - 2 * 8) / SpellStones.SOCKETS)
	for i = 1, SpellStones.SOCKETS do
		local id = socketed[i]
		local stone = if id then SpellStones.ById[id] else nil
		local b = Kit.button(
			if stone then stone.name else "Empty",
			if stone then stone.color else C.Muted,
			Vector2.new(sw, 40),
			if stone then stone.icon else nil
		)
		b.Name = "Socket" .. i
		b.LayoutOrder = i
		Kit.setEnabled(b, i <= #socketed + 1)
		b.Activated:Connect(function()
			if b.Active then
				openPicker(skill, i, id)
			end
		end)
		b.Parent = sockets
	end
	add(sockets)

	-- Reset bloom (free), only when something is spent
	if Progression.bloomSpent(sp) > 0 then
		local reset = Kit.button("Reset Bloom", C.Danger, Vector2.new(w, 50), "reroll")
		reset.Activated:Connect(function()
			if reset.Active then
				Net.Bloom:FireServer("reset", skill.id)
			end
		end)
		add(reset)
	end

	-- Selected node: spend a point. Otherwise: keys to put the skill on Q/E/R/F.
	local nodeKey = selectedNode
	if nodeKey then
		local b = Kit.button("Spend Point", C.Gold, Vector2.new(w, 60), "upgrade")
		Kit.setEnabled(b, (Progression.canBloom(sp, skill.id, nodeKey)))
		b.Activated:Connect(function()
			if b.Active then
				Net.Bloom:FireServer("spend", skill.id, nodeKey)
			end
		end)
		Kit.buttonLabel(b).TextSize = Kit.fontSize(22)
		add(b)
	else
		local okEquip, why = Progression.canEquip(skill.id, playerLevel(), Kit.playerClass(), data)
		if not okEquip then
			local b = Kit.button(why or "Locked", C.Muted, Vector2.new(w, 60), "lock")
			Kit.setEnabled(b, false)
			add(b)
		else
			local caption = Kit.label(
				if slot then "Move to another key" else "Put on key",
				14,
				C.Muted,
				Theme.Font.Body
			)
			add(caption)
			-- Wraps onto a second line when the grown touch targets no longer fit side by side
			local gap = 8
			local bw = math.floor((w - gap * (Skills.SLOTS - 1)) / Skills.SLOTS)
			local keys = rowFrame(0)
			keys.Name = "Slots"
			Kit.list(keys, Enum.FillDirection.Horizontal, gap).Wraps = true
			for i = 1, Skills.SLOTS do
				local here = slot == i
				local held = Progression.barSkill(data, i)
				local shut = held ~= nil and not Progression.isUnlocked(held, playerLevel(), data)
				local b = Kit.button(KEYS[i], if here then C.Gold else C.Cyan, Vector2.new(bw, 60))
				b.Name = "Slot" .. i
				b.LayoutOrder = i
				Kit.buttonLabel(b).TextSize = Kit.fontSize(22)
				Kit.setEnabled(b, not here and not shut)
				b.Activated:Connect(function()
					if b.Active then
						Net.Loadout:FireServer("equip", i, skill.id)
					end
				end)
				b.Parent = keys
			end
			add(keys)
		end
	end
	flow.Parent = detail
end

local function renderDetail()
	clear(detail)
	if small then
		renderDetailCompact()
		return
	end
	local skill = Skills.ById[selected]
	local eff = effectiveOf(skill)
	local sp = progressOf(skill)
	local w = SIDE_W - 2 * PAD

	local big = Kit.itemSlot(110, Kit.skillIcon(skill.id, skill.icon), { rarity = "rare" })
	big.Active = false
	big.Position = UDim2.fromOffset(PAD, PAD)
	big.Parent = detail
	local name = Window.heading(skill.name, 22, C.Cyan)
	name.Position = UDim2.fromOffset(PAD + 128, PAD + 18)
	name.Parent = detail
	local slot = slotOf(skill.id)
	local key = Kit.label(
		if slot
			then string.format("Key %s - Level %d", KEYS[slot], sp.level)
			else string.format("Not on the bar - Level %d", sp.level),
		16,
		C.Muted,
		Theme.Font.Body
	)
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
	statTile("sword", fmt(math.floor(eff.damage + 0.5)), "Damage", 1).Parent = tiles
	statTile("timer", fmt(eff.cooldown) .. " s", "Cooldown", 2).Parent = tiles
	local reach = if skill.range > 0 then skill.range else eff.radius
	statTile("target", fmt(reach), if skill.range > 0 then "Range" else "Radius", 3).Parent = tiles
	tiles.Parent = detail

	local divider = Kit.divider(w)
	divider.Position = UDim2.fromOffset(PAD, PAD + 326)
	divider.Parent = detail

	local free = Progression.bloomPoints(sp)
	local pts = Kit.label(
		string.format("%d Bloom Point%s", free, if free == 1 then "" else "s"),
		22,
		if free > 0 then C.GoldHi else C.Muted
	)
	pts.Position = UDim2.fromOffset(PAD + 40, PAD + 350)
	pts.Parent = detail
	-- XP to the next skill level
	local maxed = sp.level >= Skills.MaxLevel
	local need = Progression.skillXpFor(sp.level)
	local back, fill = Kit.bar(Vector2.new(w, 8), C.Cyan)
	back.Position = UDim2.fromOffset(PAD, PAD + 500)
	fill.Size = UDim2.fromScale(if maxed then 1 else math.clamp(sp.xp / need, 0, 1), 1)
	back.Parent = detail
	local xp = Kit.label(
		if maxed then "Max level" else string.format("%d / %d Skill-XP", sp.xp, need),
		14,
		C.Muted,
		Theme.Font.Body
	)
	xp.AutomaticSize = Enum.AutomaticSize.None
	xp.Size = UDim2.fromOffset(w, 20)
	xp.TextXAlignment = Enum.TextXAlignment.Left
	xp.Position = UDim2.fromOffset(PAD, PAD + 514)
	xp.Parent = detail
	local ptsIcon = Kit.icon("star_net", 30)
	ptsIcon.Position = UDim2.fromOffset(PAD, PAD + 350)
	ptsIcon.Parent = detail

	-- Reset bloom (free)
	local reset = Kit.button("Reset Bloom", C.Danger, Vector2.new(w, 50), "reroll")
	reset.AnchorPoint = Vector2.new(0, 1)
	reset.Position = UDim2.new(0, PAD, 1, -PAD - 90)
	Kit.setEnabled(reset, Progression.bloomSpent(sp) > 0)
	reset.Activated:Connect(function()
		if reset.Active then
			Net.Bloom:FireServer("reset", skill.id)
		end
	end)
	reset.Parent = detail

	-- Spell stone sockets (Shared/SpellStones): tap opens the stone picker.
	-- (Skills level up by defeating enemies: +5% damage and a bloom point per level.)
	local data = ProgressController.data()
	local socketed: { string } = (data.sockets or {})[skill.id] or {}
	local sw = (w - 2 * 8) / SpellStones.SOCKETS
	for i = 1, SpellStones.SOCKETS do
		local id = socketed[i]
		local stone = if id then SpellStones.ById[id] else nil
		local b = Kit.button(
			if stone then stone.name else "Empty",
			if stone then stone.color else C.Muted,
			Vector2.new(sw, 40),
			if stone then stone.icon else nil
		)
		b.Name = "Socket" .. i
		b.Position = UDim2.fromOffset(PAD + (i - 1) * (sw + 8), PAD + 410) -- above the XP bar
		local usable = i <= #socketed + 1
		Kit.setEnabled(b, usable)
		b.Activated:Connect(function()
			if b.Active then
				openPicker(skill, i, id)
			end
		end)
		b.Parent = detail
	end

	-- Selected node: spend a point. Otherwise: slot buttons to put the skill on Q/E/R/F.
	local nodeKey = selectedNode
	if nodeKey then
		local b = Kit.button("Spend Point", C.Gold, Vector2.new(w, 60), "upgrade")
		Kit.setEnabled(b, (Progression.canBloom(sp, skill.id, nodeKey)))
		b.Activated:Connect(function()
			if b.Active then
				Net.Bloom:FireServer("spend", skill.id, nodeKey)
			end
		end)
		Kit.buttonLabel(b).TextSize = Kit.fontSize(22)
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.new(0, PAD, 1, -PAD)
		b.Parent = detail
		return
	end
	local okEquip, why =
		Progression.canEquip(skill.id, playerLevel(), Kit.playerClass(), ProgressController.data())
	if not okEquip then
		local b = Kit.button(why or "Locked", C.Muted, Vector2.new(w, 60), "lock")
		Kit.setEnabled(b, false)
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.new(0, PAD, 1, -PAD)
		b.Parent = detail
		return
	end
	local gap = 10
	local bw = math.floor((w - gap * (Skills.SLOTS - 1)) / Skills.SLOTS)
	local row = Window.frame(UDim2.fromOffset(w, 60))
	row.Name = "Slots"
	Kit.list(row, Enum.FillDirection.Horizontal, gap)
	for i = 1, Skills.SLOTS do
		local here = slot == i
		-- a key whose skill is still locked (new heroes) cannot be swapped onto
		local held = Progression.barSkill(data, i)
		local shut = held ~= nil and not Progression.isUnlocked(held, playerLevel(), data)
		local b = Kit.button(KEYS[i], if here then C.Gold else C.Cyan, Vector2.new(bw, 60))
		b.Name = "Slot" .. i
		b.LayoutOrder = i
		Kit.buttonLabel(b).TextSize = Kit.fontSize(22)
		Kit.setEnabled(b, not here and not shut)
		b.Activated:Connect(function()
			if b.Active then
				Net.Loadout:FireServer("equip", i, skill.id)
			end
		end)
		b.Parent = row
	end
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0, PAD, 1, -PAD)
	row.Parent = detail
	local label = Kit.label(
		if slot then "Move to another key" else "Put on key",
		14,
		C.Muted,
		Theme.Font.Body
	)
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, PAD, 1, -PAD - 64)
	label.Parent = detail
end

-- ------------------------------------------------------------------ Flow
-- Sizes the tree and detail panels for the current viewport (compact on phones)
local function applyLayout()
	local camera = workspace.CurrentCamera
	small = camera ~= nil
		and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < Theme.TabletMinSide
	sideW = if small then COMPACT_SIDE_W else SIDE_W
	treeW = if small then COMPACT_TREE_W else TREE_W
	local body = Window.BODY
	center.Size = UDim2.fromOffset(treeW, body.Y)
	center.Position = UDim2.fromOffset(LEFT_W + (body.X - LEFT_W - sideW) / 2, 0)
	tree.Size = UDim2.fromOffset(treeW, TREE_H)
	hint.Size = UDim2.fromOffset(treeW - 40, 0)
	detail.Size = UDim2.fromOffset(sideW, body.Y)
end

function AbilitiesController.render()
	closePicker()
	applyLayout()
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
		title = "Skills",
		icon = "skills",
		key = Enum.KeyCode.K,
		background = "bg_skills",
	})

	local body = Window.BODY
	listPanel = Kit.panel(Vector2.new(LEFT_W, body.Y))
	listPanel.Parent = win.body

	-- Tree centered between the two panels
	center = Window.frame(UDim2.fromOffset(TREE_W, body.Y))
	center.AnchorPoint = Vector2.new(0.5, 0)
	center.Position = UDim2.fromOffset(LEFT_W + (body.X - LEFT_W - SIDE_W) / 2, 0)
	center.Parent = win.body
	local treeTitle = Window.heading("Skill Bloom", 26, C.Text)
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

	detail = Kit.panel(Vector2.new(SIDE_W, body.Y))
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.fromScale(1, 0)
	detail.Parent = win.body

	win.onOpen(AbilitiesController.render)
	local function refresh()
		if win.isOpen() then
			AbilitiesController.render()
		end
	end
	ProgressController.changed:Connect(refresh)
	player:GetAttributeChangedSignal("Level"):Connect(refresh)
	player:GetAttributeChangedSignal("Class"):Connect(refresh)
	AbilitiesController.render()
end

return AbilitiesController
