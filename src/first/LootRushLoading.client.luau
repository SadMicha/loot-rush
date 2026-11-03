--!strict
-- Loading screen (docs/ROADMAP-1.0.md O2): replaces the Roblox default as soon as the theme has
-- replicated, shows the game name and a pulsing status line, and fades out once the client
-- preloaded the HUD art (Client/Controllers/PreloadController sets the local player attribute
-- "ClientReady") or after MAX_WAIT seconds, whichever comes first. Purely client-side.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MAX_WAIT = 15 -- seconds: never keep a player behind the cover longer than this
local FADE = 0.45

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared", 30)
local ui = shared and shared:WaitForChild("UI", 30)
local themeModule = ui and ui:WaitForChild("Theme", 30)
if not (themeModule and themeModule:IsA("ModuleScript")) then
	return -- keep the Roblox default screen
end
local Theme = require(themeModule) :: any
local C = Theme.Color

local gui = Instance.new("ScreenGui")
gui.Name = "LootRushLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = C.Bg0
back.BorderSizePixel = 0
back.Parent = gui

local function text(value: string, size: number, color: Color3, font: Font, y: number): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, y)
	label.Size = UDim2.new(1, -32, 0, size + 8)
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextSize = size
	label.TextColor3 = color
	label.FontFace = font
	label.Parent = back
	return label
end

local title = text("LOOT RUSH", 64, C.GoldHi, Theme.Font.Title, -24)
local status = text("Loading…", 20, C.Muted, Theme.Font.UI, 40)

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local pulse = TweenService:Create(
	status,
	TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ TextTransparency = 0.6 }
)
pulse:Play()

local started = os.clock()
while player:GetAttribute("ClientReady") ~= true and os.clock() - started < MAX_WAIT do
	task.wait(0.1)
end

pulse:Cancel()
local info = TweenInfo.new(FADE)
TweenService:Create(back, info, { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, info, { TextTransparency = 1 }):Play()
TweenService:Create(status, info, { TextTransparency = 1 }):Play()
task.wait(FADE)
gui:Destroy()
