--!strict
-- Combat effects: damage numbers, projectiles, rings, lightning chains, level-up
-- and health bars above enemies. Everything arrives as a Net.Fx event from the server (see Types.luau).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Prefs = require(script.Parent.Parent.Prefs)

local FxController = {}

local C = Theme.Color
local container: Folder

local function part(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Block
	p.Parent = container
	return p
end

-- `icon` (Kit.icon name) sits left of the text, e.g. the green arrow on "UPGRADE"
local function popText(
	pos: Vector3,
	text: string,
	color: Color3,
	size: number,
	pop: number?,
	icon: string?
)
	local anchor = part(Vector3.one * 0.1, CFrame.new(pos), color)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color
	label.FontFace = Theme.Font.UI
	label.TextStrokeColor3 = C.Bg0
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	local art: GuiObject? = nil
	if icon then
		-- Icon + text side by side, centered as one row
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 1)
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 4)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = row
		local ic = Kit.icon(icon, math.floor(size * 1.15))
		ic.LayoutOrder = 1
		ic.Parent = row
		art = ic
		label.LayoutOrder = 2
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.Parent = row
		row.Parent = gui
	end
	local scaled: GuiObject = if art then label.Parent :: GuiObject else label
	if pop then
		-- Short overshoot: starts small, pops to `pop` and settles at 1
		local scale = Instance.new("UIScale")
		scale.Scale = 0.5
		scale.Parent = scaled
		local up =
			TweenInfo.new(Theme.Damage.PopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local settle = TweenInfo.new(
			Theme.Damage.PopTime * 2,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		local grow = TweenService:Create(scale, up, { Scale = pop })
		grow.Completed:Connect(function()
			TweenService:Create(scale, settle, { Scale = 1 }):Play()
		end)
		grow:Play()
	end

	TweenService:Create(
		anchor,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(pos + Vector3.new(0, Theme.Damage.Rise, 0)) }
	):Play()
	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45)
	TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	if art then
		for _, img in art:GetDescendants() do
			if img:IsA("ImageLabel") then
				TweenService:Create(img, fade, { ImageTransparency = 1 }):Play()
			end
		end
	end
	Debris:AddItem(anchor, 0.9)
end

local function ring(pos: Vector3, radius: number, color: Color3, duration: number)
	local rot = CFrame.Angles(0, 0, math.rad(90))
	local p = part(Vector3.new(0.3, 2, 2), CFrame.new(pos) * rot, color, Enum.PartType.Cylinder)
	p.Transparency = 0.35
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService
		:Create(p, info, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 })
		:Play()
	Debris:AddItem(p, duration + 0.1)
end

local handlers: { [string]: (data: any) -> () } = {}

function handlers.dmg(d)
	local pos = d.pos :: Vector3
	if d.dodge then
		if d.counter then
			popText(pos, "Counter!", C.GoldHi, 28)
		else
			popText(pos, "Dodged!", C.Cyan, 22)
		end
	elseif d.text then
		popText(pos, d.text, (d.color :: Color3?) or C.Gold, 22)
		if d.upgrade == true then
			-- Loot pickup that beats the worn piece (Systems/Loot): big green tag above the name
			popText(pos + Vector3.new(0, 1.6, 0), "UPGRADE", C.Good, 30, 1.4, "upgrade")
		end
	elseif d.hurt then
		popText(pos, "-" .. tostring(d.amount), C.Danger, 28)
	elseif not Prefs.get("damageNumbers") then
		return -- "Damage numbers" off: dealt damage stays silent (dodges, texts, own hurt still show)
	elseif d.crit then
		local tiers = Theme.Damage.Tiers
		local tier = math.clamp(math.floor(tonumber(d.critTier) or 1), 1, #tiers)
		local style = tiers[tier]
		popText(
			pos,
			tostring(d.amount) .. style.suffix,
			style.color,
			style.size,
			if tier > 1 then style.pop else nil
		)
	else
		popText(pos, tostring(d.amount), C.Text, Theme.Damage.NormalSize)
	end
end

-- A boss is Broken (Systems/Enemies, Shared/Bosses): big gold text over it
handlers["break"] = function(d)
	if typeof(d.pos) == "Vector3" then
		popText(d.pos + Vector3.new(0, 6, 0), "BROKEN!", C.GoldHi, 40, 1.6)
	end
end

function handlers.proj(d)
	local color = d.color :: Color3
	local size = d.size :: number
	local p = part(Vector3.one * size, CFrame.new(d.from :: Vector3), color, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = p
	local time = math.max(d.time :: number, 0.03)
	TweenService:Create(
		p,
		TweenInfo.new(time, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(d.to :: Vector3) }
	):Play()
	Debris:AddItem(p, time + 0.05)
end

function handlers.nova(d)
	ring(d.pos :: Vector3, d.radius :: number, d.color :: Color3, 0.4)
end

function handlers.chain(d)
	local points = d.points :: { Vector3 }
	local color = d.color :: Color3
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dist = (b - a).Magnitude
		if dist > 0.1 then
			local seg = part(Vector3.new(0.4, 0.4, dist), CFrame.lookAt((a + b) / 2, b), color)
			TweenService:Create(
				seg,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1, Size = Vector3.new(0.1, 0.1, dist) }
			):Play()
			Debris:AddItem(seg, 0.4)
		end
	end
end

-- Kills: the enemy shatters into its own bricks (BrickController, FeelController)

-- ------------------------------------------------------------------ Boss loot burst
-- Systems/Loot sends the flight paths of a boss's drops; each one flies as a glowing orb on an arc
-- and ends 3 studs above its spot, where the real drop appears and bounces down (same frame-ish).
-- One Heartbeat loop moves all orbs and stops when none are left; trails only on medium/high.
type Orb = { p: Part, from: Vector3, to: Vector3, t0: number, dur: number, big: boolean }

local orbs: { Orb } = {}
local orbStep: RBXScriptConnection? = nil

local function stepOrbs()
	local now = os.clock()
	for i = #orbs, 1, -1 do
		local o = orbs[i]
		local u = math.clamp((now - o.t0) / o.dur, 0, 1)
		local flat = o.from:Lerp(o.to, u)
		local lift = Config.LOOT_BURST_ARC * 4 * u * (1 - u)
		o.p.CFrame = CFrame.new(flat + Vector3.new(0, lift, 0))
		if u >= 1 then
			if o.big then
				ring(Vector3.new(o.to.X, 0.3, o.to.Z), 4, o.p.Color, 0.35)
			end
			o.p:Destroy()
			table.remove(orbs, i)
		end
	end
	if #orbs == 0 and orbStep then
		orbStep:Disconnect()
		orbStep = nil
	end
end

local function launchOrb(from: Vector3, to: Vector3, color: Color3, big: boolean, dur: number)
	local p =
		part(Vector3.one * (if big then 1.3 else 0.8), CFrame.new(from), color, Enum.PartType.Ball)
	local level = Prefs.effectLevel()
	if level ~= "low" then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.35, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.35, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(color)
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Lifetime = if big then 0.35 else 0.2
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.Parent = p
	end
	if big and level == "high" then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 2
		light.Parent = p
	end
	table.insert(orbs, { p = p, from = from, to = to, t0 = os.clock(), dur = dur, big = big })
	if not orbStep then
		orbStep = RunService.Heartbeat:Connect(stepOrbs)
	end
	Debris:AddItem(p, dur + 1) -- safety net if the loop stopped early
end

function handlers.lootburst(d)
	local pos, arcs = d.pos, d.arcs
	if typeof(pos) ~= "Vector3" or typeof(arcs) ~= "table" then
		return
	end
	local flight = if typeof(d.flight) == "number" then math.clamp(d.flight, 0.1, 2) else 0.55
	local from = pos + Vector3.new(0, 1.5, 0)
	ring(Vector3.new(pos.X, 0.3, pos.Z), Config.LOOT_BURST_RADIUS_MAX, C.Gold, 0.6)
	for _, a in arcs do
		if typeof(a) == "table" and typeof(a.to) == "Vector3" then
			local color = if typeof(a.color) == "Color3" then a.color else C.Gold
			local delay = if typeof(a.delay) == "number" then math.clamp(a.delay, 0, 3) else 0
			task.delay(
				delay,
				launchOrb,
				from,
				a.to + Vector3.new(0, 3, 0),
				color,
				a.big == true,
				flight
			)
		end
	end
end

function handlers.levelup(d)
	local pos = d.pos :: Vector3
	popText(pos + Vector3.new(0, 3, 0), "LEVEL " .. tostring(d.level) .. "!", C.Gold, 40)
	ring(Vector3.new(pos.X, 0.3, pos.Z), 12, C.Gold, 0.6)
end

-- ------------------------------------------------------------------ Health bars above enemies
local function attachBar(model: Instance)
	if not model:IsA("Model") then
		return
	end
	task.spawn(function()
		local primary = model.PrimaryPart
		while not primary and model.Parent do
			task.wait(0.1)
			primary = model.PrimaryPart
		end
		if not primary then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(80, 12)
		gui.StudsOffset = Vector3.new(0, 4.2, 0)
		gui.LightInfluence = 0
		gui.Parent = primary
		local back, fill = Kit.bar(Vector2.new(80, 10), C.Danger)
		back.Position = UDim2.fromOffset(0, 1)
		back.Parent = gui
		local function refresh()
			local hp = (model:GetAttribute("Health") or 0) :: number
			local max = math.max((model:GetAttribute("MaxHealth") or 1) :: number, 1)
			fill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		end
		model:GetAttributeChangedSignal("Health"):Connect(refresh)
		refresh()
	end)
end

-- ------------------------------------------------------------------ Ground drop labels
-- The server creates one BillboardGui per drop under workspace.Loot (attribute "Rarity" on items,
-- "Gold" on coins). Here (client only) the labels are decluttered:
--   * best rarity first, then nearest; at most MAX_LABELS item labels at once
--   * gold and normal items only close by (gold is picked up from further away anyway)
--   * overlapping labels stack upwards a few steps; a label that finds no free place is hidden
--   * holding Left Alt (keyboard) shows every label
local LABEL_BASE_Y = 2 -- studs, same as the server's StudsOffset
local LABEL_STEP_PX = 20 -- vertical pitch of stacked labels on screen
local LABEL_WIDTH_PX = 150 -- labels closer than this horizontally count as overlapping
local LABEL_MAX_STACK = 3 -- stack steps before a label is hidden
local MAX_LABELS = 10
local GOLD_LABEL_DISTANCE = 24 -- studs
local NORMAL_LABEL_DISTANCE = 40
local ITEM_LABEL_DISTANCE = 90
local RARITY_RANK: { [string]: number } = { normal = 1, magic = 2, rare = 3, epic = 4, unique = 5 }

local function spreadLootLabels()
	local loot = workspace:FindFirstChild("Loot")
	local camera = workspace.CurrentCamera
	if not loot or not camera then
		return
	end
	local showAll = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
	local focus = camera.Focus.Position
	type Label = { gui: BillboardGui, x: number, y: number, depth: number, rank: number }
	local labels: { Label } = {}
	for _, gui in loot:GetDescendants() do
		local adornee = gui.Parent
		if gui:IsA("BillboardGui") and adornee and adornee:IsA("BasePart") then
			local rarity = gui:GetAttribute("Rarity")
			local rank = if typeof(rarity) == "string" then RARITY_RANK[rarity] or 1 else 0 -- 0 = gold
			local limit = if rank == 0
				then GOLD_LABEL_DISTANCE
				elseif rank == 1 then NORMAL_LABEL_DISTANCE
				else ITEM_LABEL_DISTANCE
			gui.MaxDistance = if showAll then ITEM_LABEL_DISTANCE else limit
			local near = (adornee.Position - focus).Magnitude <= gui.MaxDistance
			local screen, onScreen = camera:WorldToViewportPoint(adornee.Position)
			if onScreen and near then
				table.insert(
					labels,
					{ gui = gui, x = screen.X, y = screen.Y, depth = screen.Z, rank = rank }
				)
			else
				gui.Enabled = false
			end
		end
	end
	-- Best rarity first, then nearest: the important labels get the free places
	table.sort(labels, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.depth < b.depth
	end)
	local studsPerPx = 2
		* math.tan(math.rad(camera.FieldOfView) / 2)
		/ math.max(camera.ViewportSize.Y, 1)
	local placed: { { x: number, y: number } } = {}
	local shownItems = 0
	for _, l in labels do
		local level = 0
		local y = l.y
		local free = true
		while true do
			local hit = false
			for _, p in placed do
				if math.abs(p.x - l.x) < LABEL_WIDTH_PX and math.abs(p.y - y) < LABEL_STEP_PX then
					hit = true
					break
				end
			end
			if not hit then
				break
			end
			if level >= LABEL_MAX_STACK then
				free = showAll
				break
			end
			level += 1
			y = l.y - level * LABEL_STEP_PX
		end
		local full = l.rank > 0 and shownItems >= MAX_LABELS and not showAll
		l.gui.Enabled = free and not full
		if l.gui.Enabled then
			if l.rank > 0 then
				shownItems += 1
			end
			table.insert(placed, { x = l.x, y = y })
			l.gui.StudsOffset =
				Vector3.new(0, LABEL_BASE_Y + level * LABEL_STEP_PX * studsPerPx * l.depth, 0)
		end
	end
end

function FxController.init()
	container = Instance.new("Folder")
	container.Name = "Fx"
	container.Parent = workspace
end

function FxController.start()
	Net.Fx.OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler and typeof(data) == "table" then
			handler(data)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			spreadLootLabels()
		end
	end)
	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(attachBar)
	for _, model in CollectionService:GetTagged("Enemy") do
		attachBar(model)
	end
end

return FxController
