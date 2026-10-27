--!strict
-- Rift-Anzeige: Banner (Tiefe · Welle · Gegner), Boss-Leiste und die Wahl nach dem Boss.
-- Der Zustand kommt vom Server als Player-Attribute (siehe Types.luau); hier wird nur angezeigt
-- und per Net.Rift „enter“, „deeper“ oder „leave“ angefragt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)

local RiftController = {}

local player = Players.LocalPlayer
local C = Theme.Color

local banner: Frame
local bannerText: TextLabel
local bossBox: Frame
local bossFill: Frame
local bossName: TextLabel
local choice: Frame
local deeperButton: ImageButton

local function phase(): string
	return (player:GetAttribute("RiftPhase") or "") :: string
end

-- „Im Rift“ = Lauf läuft oder wartet auf die Wahl (nicht bei „failed“)
function RiftController.active(): boolean
	local p = phase()
	return p == "wave" or p == "boss" or p == "clear"
end

function RiftController.toggle()
	Net.Rift:FireServer(if RiftController.active() then "leave" else "enter")
end

local function refresh()
	local p = phase()
	local depth = (player:GetAttribute("RiftDepth") or 1) :: number
	banner.Visible = p ~= ""
	bossBox.Visible = p == "boss"
	choice.Visible = p == "clear"
	bannerText.TextColor3 = if p == "failed" then C.Danger else C.Text
	if p == "wave" then
		local wave = (player:GetAttribute("RiftWave") or 1) :: number
		local waves = (player:GetAttribute("RiftWaves") or 1) :: number
		local left = (player:GetAttribute("RiftLeft") or 0) :: number
		bannerText.Text =
			string.format("Tiefe %d · Welle %d/%d · Gegner %d", depth, wave, waves, left)
	elseif p == "boss" then
		bannerText.Text = string.format("Tiefe %d · Boss", depth)
	elseif p == "clear" then
		bannerText.Text = string.format("Tiefe %d geschafft", depth)
		Kit.buttonLabel(deeperButton).Text = string.format("Tiefer (Tiefe %d)", depth + 1)
	elseif p == "failed" then
		bannerText.Text = "Rift gescheitert"
	end
end

local function refreshBoss()
	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy:GetAttribute("Boss") == true then
			local max = math.max((enemy:GetAttribute("MaxHealth") or 1) :: number, 1)
			local ratio = math.clamp(((enemy:GetAttribute("Health") or 0) :: number) / max, 0, 1)
			bossFill.Size = UDim2.fromScale(ratio, 1)
			bossName.Text = enemy.Name
			return
		end
	end
end

function RiftController.init()
	local gui, root = Kit.scaledGui("LootRushRift", 3)

	banner = Kit.panel(Vector2.new(400, 44), C.Gold)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 84)
	banner.Visible = false
	banner.Parent = root
	bannerText = Kit.label("", 17)
	bannerText.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerText.Position = UDim2.fromScale(0.5, 0.5)
	bannerText.Parent = banner

	bossBox = Instance.new("Frame")
	bossBox.BackgroundTransparency = 1
	bossBox.Size = UDim2.fromOffset(520, 44)
	bossBox.AnchorPoint = Vector2.new(0.5, 0)
	bossBox.Position = UDim2.new(0.5, 0, 0, 140)
	bossBox.Visible = false
	bossBox.Parent = root
	bossName = Kit.label("", 15, C.Muted)
	bossName.AnchorPoint = Vector2.new(0.5, 0)
	bossName.Position = UDim2.fromScale(0.5, 0)
	bossName.Parent = bossBox
	local back, fill = Kit.bar(Vector2.new(520, 14), C.Danger)
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.fromScale(0.5, 1)
	back.Parent = bossBox
	bossFill = fill

	choice = Kit.panel(Vector2.new(400, 84), C.Gold)
	choice.AnchorPoint = Vector2.new(0.5, 0)
	choice.Position = UDim2.new(0.5, 0, 0, 140)
	choice.Visible = false
	choice.Parent = root
	Kit.list(choice, Enum.FillDirection.Horizontal, 12)
	deeperButton = Kit.button("Tiefer", C.Gold, Vector2.new(180, 48))
	deeperButton.LayoutOrder = 1
	deeperButton.Activated:Connect(function()
		Net.Rift:FireServer("deeper")
	end)
	deeperButton.Parent = choice
	local home = Kit.button("Zurück ins Dorf", C.Cyan, Vector2.new(180, 48))
	home.LayoutOrder = 2
	home.Activated:Connect(function()
		Net.Rift:FireServer("leave")
	end)
	home.Parent = choice

	gui.Parent = player:WaitForChild("PlayerGui")
end

function RiftController.start()
	for _, attr in { "RiftPhase", "RiftDepth", "RiftWave", "RiftWaves", "RiftLeft" } do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	refresh()
	while true do
		if bossBox.Visible then
			refreshBoss()
		end
		task.wait(0.15)
	end
end

return RiftController
