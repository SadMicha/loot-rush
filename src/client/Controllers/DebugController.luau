--!strict
-- Mess-Overlay für Playtests (F3 oder „Dbg“-Knopf unten links, damit es auch auf dem Handy geht):
-- FPS, Ping, Speicher, Instanzen (Client) sowie Server-Frame, Sendelast, Gegnerzahl und der letzte Rift-Bericht.
-- Server-Werte liefert Systems/Metrics als workspace-Attribute. Abschaltbar über Config.DEBUG_OVERLAY.
-- Test-Befehle (Gold, Level, Material, …) erscheinen nur, wenn der Server „DebugTools“ setzt
-- (Studio oder freigeschaltete UserId, siehe Systems/Debug); geprüft wird dort, nicht hier.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)

local DebugController = {}

local player = Players.LocalPlayer
local REFRESH = 0.5 -- Sekunden zwischen Textaktualisierungen

local panel: Frame
local text: TextLabel
local tools: Frame

-- Knopf → Befehl an Systems/Debug
local COMMANDS: { { label: string, command: string, value: number? } } = {
	{ label = "+10k Gold", command = "gold", value = 10000 },
	{ label = "Level 10", command = "level", value = 10 },
	{ label = "Level 50", command = "level", value = 50 },
	{ label = "+100 Material", command = "materials", value = 100 },
	{ label = "+500 Seelensterne", command = "soulstars", value = 500 },
	{ label = "+10 Tränke", command = "potions", value = 10 },
	{ label = "+5 Skill-Stufen", command = "skills", value = 5 },
	{ label = "+10 Items", command = "items", value = 10 },
	{ label = "Gebiete frei", command = "atlas" },
}

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

	-- Feste Größen statt AutomaticSize: das Panel wächst vom Dbg-Knopf nach oben und bleibt im Bild
	local W, PAD, TEXT_H, GAP, COLS, CELL_W = 560, 10, 54, 8, 3, 174
	panel = Kit.panel(Vector2.new(W, 0), Theme.Color.Line2)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 28, 1, -72)
	panel.Visible = false
	Kit.padding(panel, PAD)
	panel.Parent = root

	text = Kit.label("", 13, Theme.Color.Muted, Theme.Font.Body)
	text.AutomaticSize = Enum.AutomaticSize.None
	text.Size = UDim2.fromOffset(W - 2 * PAD, TEXT_H)
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Parent = panel

	tools = Instance.new("Frame")
	tools.Name = "Befehle"
	tools.BackgroundTransparency = 1
	tools.Position = UDim2.fromOffset(0, TEXT_H + GAP)
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tools
	for i, entry in COMMANDS do
		local b = Kit.button(entry.label, Theme.Color.Bg3, Vector2.new(CELL_W, 36))
		b.Name = entry.command
		b.LayoutOrder = i
		Kit.buttonLabel(b).TextSize = Kit.fontSize(13)
		b.Activated:Connect(function()
			Net.Debug:FireServer(entry.command, entry.value)
		end)
		b.Parent = tools
	end
	tools.Parent = panel

	-- Raster bestimmt die Knopfgröße (Kit.touchTarget greift hier nicht): auf Touch ≥ 33 px nach HUD-Skalierung
	local function relayout()
		local cellH = if UserInputService.TouchEnabled then 60 else 36
		local rows = math.ceil(#COMMANDS / COLS)
		local toolsH = rows * cellH + (rows - 1) * GAP
		grid.CellSize = UDim2.fromOffset(CELL_W, cellH)
		tools.Size = UDim2.fromOffset(W - 2 * PAD, toolsH)
		tools.Visible = player:GetAttribute("DebugTools") == true
		local h = TEXT_H + (if tools.Visible then GAP + toolsH else 0)
		panel.Size = UDim2.fromOffset(W, h + 2 * PAD)
	end
	relayout()
	player:GetAttributeChangedSignal("DebugTools"):Connect(relayout)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end

	local button = Kit.button("Dbg", Theme.Color.Bg3, Vector2.new(48, 30))
	button.Name = "Dbg"
	Kit.buttonLabel(button).TextColor3 = Theme.Color.Muted
	Kit.buttonLabel(button).TextSize = Kit.fontSize(13)
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
