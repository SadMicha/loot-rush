--!strict
-- Abilities window after the "Abilities" mockup (key K or menu button):
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
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local ClassController = require(script.Parent.ClassController)
local ProgressController = require(script.Parent.ProgressController)

local AbilitiesController = {}

local C = Theme.Color
local KEYS = { "Q", "E", "R", "F" }
local PAD = 28
local LEFT_W, SIDE_W = 440, 420
local TREE_W, TREE_H = 620, 700
-- Node icons per branch
local BRANCH_ICON: { [string]: string } = { trunk = "upgrade", left = "crystal", right = "timer" }

local win: Window.Window
local listPanel: Frame
local tree: Frame
local detail: Frame
local hint: TextLabel

local player = Players.LocalPlayer
local ROW_H = 82 -- 8 rows must stay touchable on phones (Phone.spec)
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

	local head = Window.heading("Skills · 4 on the bar", 20, C.Text)
	head.Position = UDim2.fromOffset(PAD, PAD - 6)
	head.Parent = listPanel
	-- Class change: hub only (the server refuses it inside a rift)
	local change = Kit.button("Class", C.Gold, Vector2.new(110, 40), "crown")
	change.Name = "ChangeClass"
	change.AnchorPoint = Vector2.new(1, 0)
	change.Position = UDim2.new(1, -PAD, 0, PAD - 10)
	Kit.setEnabled(change, (player:GetAttribute("RiftPhase") or "") == "")
	change.Activated:Connect(function()
		if change.Active then
			win.close()
			ClassController.open()
		end
	end)
	change.Parent = listPanel

	local list = Window.frame(
		UDim2.fromOffset(LEFT_W - 2 * PAD, Window.BODY.Y - PAD - 44),
		UDim2.fromOffset(PAD, PAD + 44)
	)
	Kit.list(list, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Top)
	local level = playerLevel()
	for i, skill in kit().list do
		local on = skill.id == selected
		local locked = level < (skill.unlock or 1)
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
		name.Parent = row
		local eff = effectiveOf(skill)
		local sub = Kit.label(
			if locked
				then string.format("Unlocks at level %d", skill.unlock or 1)
				else string.format(
					"Level %d · %s Damage · %s s",
					progressOf(skill).level,
					fmt(math.floor(eff.damage + 0.5)),
					fmt(eff.cooldown)
				),
			14,
			C.Muted,
			Theme.Font.Body
		)
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.Size = UDim2.fromOffset(LEFT_W - 2 * PAD - 84 - 70, 20)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Position = UDim2.fromOffset(84, 46)
		sub.ZIndex = 2
		sub.Parent = row
		-- Right side: bar key if equipped
		local tagText = if locked then "" elseif slot then KEYS[slot] else ""
		local key = Kit.label(tagText, 15, if slot then C.GoldHi else C.Cyan)
		key.AnchorPoint = Vector2.new(1, 0.5)
		key.Position = UDim2.new(1, -14, 0.5, 0)
		key.ZIndex = 2
		key.Parent = row
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

	local cx = TREE_W / 2
	local root = Vector2.new(cx, 600)
	local trunk = { Vector2.new(cx, 470), Vector2.new(cx, 345), Vector2.new(cx, 220) }
	local left = { Vector2.new(cx - 120, 540), Vector2.new(cx - 240, 500) }
	local right = { Vector2.new(cx + 120, 540), Vector2.new(cx + 240, 500) }
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
	Window.caption(tree, skill.name, root + Vector2.new(0, 66), 18, C.GoldHi)

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
			local title = Window.caption(
				tree,
				n.name,
				p + (if side then Vector2.new(52, 0) else Vector2.new(0, 70)),
				14,
				C.Text
			)
			if side then
				ptsLabel.AnchorPoint = Vector2.zero
				title.AnchorPoint = Vector2.zero
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

	local node = if selectedNode then Skills.bloomNode(skill.id, selectedNode) else nil
	if node and selectedNode then
		local _, why = Progression.canBloom(sp, skill.id, selectedNode)
		local maxed = (sp.bloom[selectedNode] or 0) >= Skills.BloomMax -- no reason text needed when fully upgraded
		hint.Text = string.format(
			"%s: %s%s",
			node.name,
			node.text,
			if why and not maxed then " · " .. why else ""
		)
	else
		hint.Text = "Tap a node. Each skill level grants a bloom point."
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

local function renderDetail()
	clear(detail)
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
			then string.format("Key %s · Level %d", KEYS[slot], sp.level)
			else string.format("Not on the bar · Level %d", sp.level),
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
	xp.Position = UDim2.fromOffset(PAD, PAD + 514)
	xp.Parent = detail
	local ptsIcon = Kit.icon("star_net", 30)
	ptsIcon.Position = UDim2.fromOffset(PAD, PAD + 350)
	ptsIcon.Parent = detail
	local info = Kit.label(
		"Skills level up when they defeat enemies. Each level: +5% damage and a bloom point.",
		15,
		C.Muted,
		Theme.Font.Body
	)
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Size = UDim2.fromOffset(w, 0)
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.Position = UDim2.fromOffset(PAD, PAD + 404)
	info.Parent = detail

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
	local okEquip, why = Progression.canEquip(skill.id, playerLevel(), Kit.playerClass())
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
		local b = Kit.button(KEYS[i], if here then C.Gold else C.Cyan, Vector2.new(bw, 60))
		b.Name = "Slot" .. i
		b.LayoutOrder = i
		Kit.buttonLabel(b).TextSize = Kit.fontSize(22)
		Kit.setEnabled(b, not here)
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
		title = "Abilities",
		icon = "skills",
		key = Enum.KeyCode.K,
		background = "bg_skills",
	})

	local body = Window.BODY
	listPanel = Kit.panel(Vector2.new(LEFT_W, body.Y))
	listPanel.Parent = win.body

	-- Tree centered between the two panels
	local center = Window.frame(UDim2.fromOffset(TREE_W, body.Y))
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
