--!strict
-- Hero switch cover (audit #14, docs/CRITERIA-AUDIT.md): switching heroes saves and teleports into
-- a fresh server (Systems/Characters). The server sets "SwitchingTo" = hero name first; this covers
-- the screen with "Switching to Fynn…" and hands the cover to the teleport (SetTeleportGui), so
-- the player sees one loading screen from the tap until the new server's own one
-- (ReplicatedFirst/LootRushLoading, which reads the name from the teleport data).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local SwitchController = {}

local player = Players.LocalPlayer
local C = Theme.Color

local gui: ScreenGui? = nil

local function label(
	parent: Instance,
	text: string,
	size: number,
	color: Color3,
	font: Font,
	y: number
)
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.new(0.5, 0, 0.5, y)
	t.Size = UDim2.new(1, -32, 0, size + 8)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color
	t.FontFace = font
	t.Parent = parent
	return t
end

-- Same look as the loading screen: game name and a pulsing status line
local function cover(name: string): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = "LootRushSwitch"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 1000
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = C.Bg0
	back.BorderSizePixel = 0
	back.Parent = g
	label(back, "LOOT RUSH", 64, C.GoldHi, Theme.Font.Title, -24)
	local status = label(back, "Switching to " .. name .. "…", 20, C.Muted, Theme.Font.UI, 40)
	status.Name = "Status"
	TweenService:Create(
		status,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextTransparency = 0.6 }
	):Play()
	return g
end

local function refresh()
	local name = player:GetAttribute("SwitchingTo")
	if typeof(name) ~= "string" or name == "" then
		if gui then
			gui:Destroy()
			gui = nil
		end
		return
	end
	if gui then
		return
	end
	local g = cover(name)
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	pcall(function()
		TeleportService:SetTeleportGui(g:Clone())
	end)
end

function SwitchController.start()
	player:GetAttributeChangedSignal("SwitchingTo"):Connect(refresh)
	refresh()
end

return SwitchController
