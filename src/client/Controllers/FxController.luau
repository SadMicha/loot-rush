--!strict
-- Combat effects: damage numbers, projectiles, rings, lightning chains, death burst, level-up
-- and health bars above enemies. Everything arrives as a Net.Fx event from the server (see Types.luau).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)

local FxController = {}

local C = Theme.Color
local container: Folder
local rng = Random.new()

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

local function popText(pos: Vector3, text: string, color: Color3, size: number, pop: number?)
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
	if pop then
		-- Short overshoot: starts small, pops to `pop` and settles at 1
		local scale = Instance.new("UIScale")
		scale.Scale = 0.5
		scale.Parent = label
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
		popText(pos, "Dodged!", C.Cyan, 22)
	elseif d.text then
		popText(pos, d.text, (d.color :: Color3?) or C.Gold, 22)
	elseif d.hurt then
		popText(pos, "-" .. tostring(d.amount), C.Danger, 28)
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

function handlers.death(d)
	local pos = d.pos :: Vector3
	local color = d.color :: Color3
	for _ = 1, 8 do
		local cube = part(
			Vector3.one * rng:NextNumber(0.6, 1.1),
			CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			color
		)
		local out = Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(1, 5), rng:NextNumber(-5, 5))
		TweenService
			:Create(cube, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(pos + out),
				Size = Vector3.one * 0.1,
				Transparency = 1,
			})
			:Play()
		Debris:AddItem(cube, 0.55)
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
-- The server creates one BillboardGui per drop under workspace.Loot. Here (client only) gold labels are
-- only shown when near and overlapping labels are stacked upwards.
local LABEL_BASE_Y = 2 -- studs, same as the server's StudsOffset
local LABEL_STEP_PX = 20 -- vertical pitch of stacked labels on screen
local LABEL_WIDTH_PX = 150 -- labels closer than this horizontally count as overlapping
local GOLD_LABEL_DISTANCE = 45 -- gold labels vanish beyond this distance (studs)
local ITEM_LABEL_DISTANCE = 90

local function spreadLootLabels()
	local loot = workspace:FindFirstChild("Loot")
	local camera = workspace.CurrentCamera
	if not loot or not camera then
		return
	end
	local labels: { { gui: BillboardGui, x: number, y: number, depth: number } } = {}
	for _, gui in loot:GetDescendants() do
		local adornee = gui.Parent
		if gui:IsA("BillboardGui") and adornee and adornee:IsA("BasePart") then
			local text = gui:FindFirstChildOfClass("TextLabel")
			local isGold = text ~= nil and string.sub(text.Text, -5) == " Gold"
			gui.MaxDistance = if isGold then GOLD_LABEL_DISTANCE else ITEM_LABEL_DISTANCE
			local screen, onScreen = camera:WorldToViewportPoint(adornee.Position)
			if onScreen then
				table.insert(labels, { gui = gui, x = screen.X, y = screen.Y, depth = screen.Z })
			end
		end
	end
	-- Front to back (nearest first) so the nearest label keeps the lowest slot
	table.sort(labels, function(a, b)
		return a.depth < b.depth
	end)
	local studsPerPx = 2
		* math.tan(math.rad(camera.FieldOfView) / 2)
		/ math.max(camera.ViewportSize.Y, 1)
	local placed: { { x: number, y: number } } = {}
	for _, l in labels do
		local level = 0
		local y = l.y
		while true do
			local hit = false
			for _, p in placed do
				if math.abs(p.x - l.x) < LABEL_WIDTH_PX and math.abs(p.y - y) < LABEL_STEP_PX then
					hit = true
					break
				end
			end
			if not hit or level >= 6 then
				break
			end
			level += 1
			y = l.y - level * LABEL_STEP_PX
		end
		table.insert(placed, { x = l.x, y = y })
		l.gui.StudsOffset =
			Vector3.new(0, LABEL_BASE_Y + level * LABEL_STEP_PX * studsPerPx * l.depth, 0)
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
