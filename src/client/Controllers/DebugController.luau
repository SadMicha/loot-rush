--!strict
-- Mess-Overlay für Playtests (F3 oder „Dbg“-Knopf unten links, damit es auch auf dem Handy geht):
-- FPS, Ping, Speicher, Instanzen (Client) sowie Server-Frame, Sendelast, Gegnerzahl und der letzte Rift-Bericht.
-- Server-Werte liefert Systems/Metrics als workspace-Attribute. Abschaltbar über Config.DEBUG_OVERLAY.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)

local DebugController = {}

local player = Players.LocalPlayer
local REFRESH = 0.5 -- Sekunden zwischen Textaktualisierungen

local panel: Frame
local text: TextLabel

local function toggle()
	panel.Visible = not panel.Visible
end

local function serverNumber(name: string): string
	local value = workspace:GetAttribute(name)
	return if typeof(value) == "number" then tostring(value) else "–"
end

local function render(fps: number)
	local instances = "–"
	local ok, count = pcall(function()
		return (Stats :: any).InstanceCount
	end)
	if ok and typeof(count) == "number" then
		instances = tostring(count)
	end
	local report = workspace:GetAttribute("LastReport")
	text.Text = string.format(
		"Client  %d FPS · Ping %d ms · %d MB · %s Instanzen\nServer  Frame Ø %s / max %s ms · %s kbps · %s Gegner\nLetzter Lauf: %s",
		fps,
		math.floor(player:GetNetworkPing() * 1000 + 0.5),
		math.floor(Stats:GetTotalMemoryUsageMb() + 0.5),
		instances,
		serverNumber("ServerFrameMs"),
		serverNumber("ServerFrameMaxMs"),
		serverNumber("ServerSendKbps"),
		serverNumber("ServerEnemies"),
		if typeof(report) == "string" then report else "–"
	)
end

function DebugController.init()
	if not Config.DEBUG_OVERLAY then
		return
	end
	local gui, root = Kit.scaledGui("LootRushDebug", 10)

	panel = Kit.panel(Vector2.new(520, 0), Theme.Color.Line2)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 28, 1, -72)
	panel.Visible = false
	Kit.padding(panel, 10)
	panel.Parent = root

	text = Kit.label("", 13, Theme.Color.Muted, Theme.Font.Body)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.Size = UDim2.fromOffset(500, 0)
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = panel

	local button = Kit.button("Dbg", Theme.Color.Bg3, Vector2.new(48, 30))
	Kit.buttonLabel(button).TextColor3 = Theme.Color.Muted
	Kit.buttonLabel(button).TextSize = 13
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 28, 1, -28)
	button.Activated:Connect(toggle)
	button.Parent = root

	gui.Parent = player:WaitForChild("PlayerGui")
end

function DebugController.start()
	if not Config.DEBUG_OVERLAY then
		return
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.F3 then
			toggle()
		end
	end)

	local frames, elapsed = 0, 0
	RunService.RenderStepped:Connect(function(dt: number)
		frames += 1
		elapsed += dt
		if elapsed >= REFRESH then
			if panel.Visible then
				render(math.floor(frames / elapsed + 0.5))
			end
			frames, elapsed = 0, 0
		end
	end)
end

return DebugController
