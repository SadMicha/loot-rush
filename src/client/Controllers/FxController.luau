--!strict
-- Kampf-Effekte: Schadenszahlen, Projektile, Ringe, Blitzketten, Todes-Burst, Level-Up
-- und Lebensbalken über Gegnern. Alles kommt als Net.Fx-Ereignis vom Server (siehe Types.luau).

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

local function popText(pos: Vector3, text: string, color: Color3, size: number)
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

	TweenService:Create(
		anchor,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) }
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
		popText(pos, "Ausgewichen!", C.Cyan, 22)
	elseif d.text then
		popText(pos, d.text, (d.color :: Color3?) or C.Gold, 22)
	elseif d.heal then
		popText(pos, "+" .. tostring(d.amount), C.Good, 26)
	elseif d.hurt then
		popText(pos, "-" .. tostring(d.amount), C.Danger, 28)
	elseif d.crit then
		popText(pos, tostring(d.amount) .. "!", C.Gold, 36)
	else
		popText(pos, tostring(d.amount), C.Text, 24)
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

-- ------------------------------------------------------------------ Lebensbalken über Gegnern
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
	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(attachBar)
	for _, model in CollectionService:GetTagged("Enemy") do
		attachBar(model)
	end
end

return FxController
