--!strict
-- Loading screen (docs/ROADMAP.md O2): replaces the Roblox default as soon as the theme has
-- replicated. Shows the title with a soft glow, a real progress bar (N / M assets, gold shine),
-- a rotating gameplay tip and a quiet drifting-studs backdrop, then fades out once the client
-- finished preloading, the character exists and the hero setup state is known
-- (Client/Controllers/PreloadController publishes PreloadDone / PreloadTotal / PreloadPhase and
-- finally ClientReady), or after Theme.Loading.MaxWait seconds, whichever comes first.
-- Lives in ReplicatedFirst, so it only requires Shared (Theme, Settings) and uses plain Instances.
-- Low effects quality (phones on "auto" count as medium) drops sparkles, pulses and tip fades.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared", 30)
local ui = shared and shared:WaitForChild("UI", 30)
local themeModule = ui and ui:WaitForChild("Theme", 30)
if not (themeModule and themeModule:IsA("ModuleScript")) then
	return -- keep the Roblox default screen
end
local Theme = require(themeModule) :: any
local C = Theme.Color
local L = Theme.Loading

-- Motion level: "low" = static, "medium" = fewer sparkles, "high" = everything
local level = "high"
pcall(function()
	local settingsModule = shared and shared:FindFirstChild("Settings")
	if settingsModule and settingsModule:IsA("ModuleScript") then
		local Settings = require(settingsModule) :: any
		local roblox: number? = nil
		pcall(function()
			roblox = (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
		end)
		level = Settings.effectLevel("auto", UserInputService.TouchEnabled, roblox)
	end
end)
local animated = level ~= "low"

local gui = Instance.new("ScreenGui")
gui.Name = "LootRushLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000

-- One CanvasGroup so the final fade is a single tween
local root = Instance.new("CanvasGroup")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = C.Bg0
root.BorderSizePixel = 0
root.Parent = gui
local backGradient = Instance.new("UIGradient")
backGradient.Rotation = 90
backGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C.Bg1),
	ColorSequenceKeypoint.new(0.55, C.Bg0),
	ColorSequenceKeypoint.new(1, C.Bg0),
})
backGradient.Parent = root

local function frame(parent: Instance, color: Color3, transparency: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function round(f: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
end

local function text(
	parent: Instance,
	value: string,
	size: number,
	color: Color3,
	font: Font,
	position: UDim2,
	height: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = UDim2.fromScale(0.9, height)
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextScaled = true
	label.TextColor3 = color
	label.FontFace = font
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = size
	cap.MinTextSize = 8
	cap.Parent = label
	label.Parent = parent
	return label
end

-- Backdrop: drifting studs (plain frames, one tween each)
local rng = Random.new()
local sparkles = if level == "high"
	then L.SparkleCount
	elseif level == "medium" then L.SparkleCount // 2
	else 0
local sparkleLayer = Instance.new("Frame")
sparkleLayer.Size = UDim2.fromScale(1, 1)
sparkleLayer.BackgroundTransparency = 1
sparkleLayer.Parent = root
for i = 1, sparkles do
	local s = frame(sparkleLayer, if i % 3 == 0 then C.Cyan else C.Gold, rng:NextNumber(0.45, 0.8))
	s.Size = UDim2.fromOffset(L.SparkleSize, L.SparkleSize)
	s.Position = UDim2.fromScale(rng:NextNumber(0.03, 0.97), 1.05)
	s.Rotation = rng:NextInteger(0, 45)
	local duration = rng:NextNumber(7, 13)
	TweenService:Create(
		s,
		TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.Out,
			-1,
			false,
			rng:NextNumber(0, duration)
		),
		{ Position = UDim2.fromScale(s.Position.X.Scale, -0.05) }
	):Play()
end

-- Soft glow behind the title: three stacked discs (square against the screen height)
local glow = Instance.new("Frame")
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromScale(0.5, 0.36)
glow.Size = UDim2.fromScale(1, 1)
glow.SizeConstraint = Enum.SizeConstraint.RelativeYY
glow.BackgroundTransparency = 1
glow.Parent = root
local glowScale = Instance.new("UIScale")
glowScale.Parent = glow
for index, ring in { 0.34, 0.56, 0.8 } do
	local disc = frame(glow, C.Gold, 0.95 - index * 0.012)
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(ring, ring)
	round(disc)
end

local title =
	text(root, L.Title, L.TitleSize, C.GoldHi, Theme.Font.Title, UDim2.fromScale(0.5, 0.36), 0.2)
local titleGradient = Instance.new("UIGradient")
titleGradient.Rotation = 90
titleGradient.Color = ColorSequence.new(C.GoldHi, C.GoldLo)
titleGradient.Parent = title
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = C.Bg0
titleStroke.Thickness = 2
titleStroke.Transparency = 0.2
titleStroke.Parent = title

-- After a hero switch the old server sends the hero name as teleport data (Systems/Characters);
-- display only, so anything odd falls back to the plain line
local TeleportService = game:GetService("TeleportService")
local hero: string? = nil
pcall(function()
	local data = TeleportService:GetLocalPlayerTeleportData()
	if typeof(data) == "table" and typeof(data.hero) == "string" and #data.hero <= 32 then
		hero = data.hero
	end
end)
local heroLine = if hero and hero ~= "" then hero else nil

-- Progress bar
local barWidth = Instance.new("Frame") -- centering holder: scale width, but never narrower than BarMinWidth
barWidth.AnchorPoint = Vector2.new(0.5, 0.5)
barWidth.Position = UDim2.fromScale(0.5, 0.6)
barWidth.Size = UDim2.new(L.BarWidth, 0, 0, L.BarHeight)
barWidth.BackgroundTransparency = 1
barWidth.Parent = root
local barMin = Instance.new("UISizeConstraint")
barMin.MinSize = Vector2.new(L.BarMinWidth, L.BarHeight)
barMin.Parent = barWidth

local track = frame(barWidth, C.Bg2, 0)
track.Size = UDim2.fromScale(1, 1)
track.ClipsDescendants = true
round(track)
local trackStroke = Instance.new("UIStroke")
trackStroke.Color = C.Line2
trackStroke.Thickness = 1
trackStroke.Parent = track

local fill = frame(track, C.Gold, 0)
fill.Size = UDim2.fromScale(0, 1)
round(fill)
local fillGradient = Instance.new("UIGradient")
fillGradient.Rotation = 90
fillGradient.Color = ColorSequence.new(C.GoldHi, C.GoldLo)
fillGradient.Parent = fill
fill.ClipsDescendants = true

local shine = frame(fill, Color3.new(1, 1, 1), 0)
shine.AnchorPoint = Vector2.new(0, 0)
shine.Size = UDim2.fromScale(0.35, 1)
shine.Position = UDim2.fromScale(-0.5, 0)
local shineGradient = Instance.new("UIGradient")
shineGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
shineGradient.Parent = shine
if animated then
	TweenService:Create(
		shine,
		TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.5),
		{ Position = UDim2.fromScale(1.15, 0) }
	):Play()
	TweenService:Create(
		glowScale,
		TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.08 }
	):Play()
end

local percent = text(
	root,
	"0%",
	L.StatusSize + 4,
	C.Text,
	Theme.Font.Number,
	UDim2.fromScale(0.5, 0.6 + 0.07),
	0.06
)
local status = text(
	root,
	if heroLine then "Loading " .. heroLine .. "…" else "Loading…",
	L.StatusSize,
	C.Muted,
	Theme.Font.UI,
	UDim2.fromScale(0.5, 0.6 + 0.125),
	0.05
)
local tip = text(root, "", L.TipSize, C.Cyan, Theme.Font.Body, UDim2.fromScale(0.5, 0.9), 0.07)
tip.TextTransparency = 1

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Rotating tips
local tips: { string } = L.Tips
local alive = true
if #tips > 0 then
	task.spawn(function()
		local index = rng:NextInteger(1, #tips)
		while alive do
			tip.Text = tips[index]
			if animated then
				TweenService:Create(tip, TweenInfo.new(L.TipFade), { TextTransparency = 0.1 })
					:Play()
			else
				tip.TextTransparency = 0.1
			end
			task.wait(L.TipInterval)
			if not alive then
				break
			end
			if animated then
				TweenService:Create(tip, TweenInfo.new(L.TipFade), { TextTransparency = 1 }):Play()
				task.wait(L.TipFade)
			end
			index = index % #tips + 1
		end
	end)
end

-- Real progress: assets count 0..0.96, then the world wait up to 1 (ClientReady)
local function target(): number
	local total = player:GetAttribute("PreloadTotal")
	local done = player:GetAttribute("PreloadDone")
	local phase = player:GetAttribute("PreloadPhase")
	if player:GetAttribute("ClientReady") == true or phase == "ready" then
		return 1
	end
	local assets = 0
	if typeof(total) == "number" and typeof(done) == "number" and total > 0 then
		assets = math.clamp(done / total, 0, 1)
	end
	return if phase == "world" then 0.97 else assets * 0.96
end

local shown = 0
local connection = RunService.Heartbeat:Connect(function(dt: number)
	shown += (target() - shown) * math.min(1, dt * L.BarEase)
	fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	percent.Text = tostring(math.floor(math.clamp(shown, 0, 1) * 100 + 0.5)) .. "%"
	local total = player:GetAttribute("PreloadTotal")
	local done = player:GetAttribute("PreloadDone")
	local phase = player:GetAttribute("PreloadPhase")
	if phase == "world" then
		status.Text = "Entering the world…"
	elseif typeof(total) == "number" and typeof(done) == "number" and total > 0 then
		status.Text = `Loading assets  {done} / {total}`
	end
end)

local started = os.clock()
while player:GetAttribute("ClientReady") ~= true and os.clock() - started < L.MaxWait do
	task.wait(0.1)
end

-- Let the bar visibly arrive at 100% before the fade
local arrive = os.clock()
while shown < 0.985 and os.clock() - arrive < 0.8 do
	task.wait(0.05)
end
connection:Disconnect()
alive = false
fill.Size = UDim2.fromScale(1, 1)
percent.Text = "100%"
TweenService:Create(root, TweenInfo.new(L.Fade, Enum.EasingStyle.Sine), { GroupTransparency = 1 })
	:Play()
task.wait(L.Fade)
gui:Destroy()
