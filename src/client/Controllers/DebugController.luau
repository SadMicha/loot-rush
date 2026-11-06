--!strict
-- Measurement overlay for playtests (F3 or the "Dbg" button bottom left, so it also works on phones):
-- FPS, ping, memory, instances (client) as well as server frame, send load, enemy count and the last Rift report.
-- Server values are provided by Systems/Metrics as workspace attributes. Can be disabled via Config.DEBUG_OVERLAY.
-- Test commands (gold, level, materials, ...) only appear if the server sets "DebugTools"
-- (Studio or whitelisted UserId, see Systems/Debug); validation happens there, not here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Kit = require(script.Parent.Parent.UI.Kit)
local AnimController = require(script.Parent.AnimController)
local Window = require(script.Parent.Parent.UI.Window)

local DebugController = {}

local player = Players.LocalPlayer
local REFRESH = 0.5 -- seconds between text updates

local panel: Frame
local dumpView: Frame -- on-screen copy of the last "Dump Joints" (phones have no Output)
local dumpText: TextLabel
local text: TextLabel
local tools: Frame

-- Button -> command to Systems/Debug (confirm = the first tap only arms the button)
local COMMANDS: { { label: string, command: string, value: number?, confirm: boolean? } } = {
	{ label = "+10k Gold", command = "gold", value = 10000 },
	{ label = "Level 10", command = "level", value = 10 },
	{ label = "Level 50", command = "level", value = 50 },
	{ label = "+100 Materials", command = "materials", value = 100 },
	{ label = "+500 Soulstars", command = "soulstars", value = 500 },
	{ label = "+5 Skill Levels", command = "skills", value = 5 },
	{ label = "+10 Items", command = "items", value = 10 },
	{ label = "Unlock Areas", command = "atlas" },
	{ label = "Kill All Enemies", command = "slay" },
	{ label = "Pet Egg", command = "pet" },
	{ label = "Next World Tier", command = "tier" },
	{ label = "Spell Stones", command = "stones" },
	{ label = "Fill Rush", command = "rush" },
	{ label = "Next Day (Daily)", command = "day" },
	{ label = "Season: Next Challenge", command = "season" },
	{ label = "Build: +1,000 Shards", command = "buildshards" },
	{ label = "Build: Finish Stage", command = "buildstage" },
	{ label = "All Cosmetics", command = "cosmetics" },
	{ label = "Dump Joints", command = "joints", value = nil }, -- client only: Output
	{ label = "Next Stance", command = "stance" }, -- weapon + stance preview, then back to own
	-- wipes the whole account (all heroes, stash, quests, hints) and kicks: replay the start
	{ label = "Reset Account", command = "reset", confirm = true },
}
local CONFIRM_TIME = 4 -- seconds an armed confirm button waits for the second tap
local LOCAL_COMMANDS: { [string]: () -> () } = {
	joints = function()
		dumpText.Text = AnimController.dump()
		dumpView.Visible = true
	end,
}

-- Overlay only in Studio or for whitelisted developers (Systems/Debug sets "DebugTools")
local function allowed(): boolean
	return RunService:IsStudio() or player:GetAttribute("DebugTools") == true
end

local function toggle()
	panel.Visible = allowed() and not panel.Visible
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
		"Client  %d FPS - Ping %d ms - %d MB - %s Instances\nServer  Frame avg %s / max %s ms - %s kbps - %s Enemies\nLast run: %s",
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

-- Dbg button above the HUD's level/XP chip (bottom left of the safe area), panel above the button
local DBG_BOTTOM = 48
local dbgButton: GuiButton? = nil

function DebugController.init()
	if not Config.DEBUG_OVERLAY then
		return
	end
	local gui, root = Kit.scaledGui("LootRushDebug", 10, false, nil, true)

	-- Fixed sizes instead of AutomaticSize: the panel grows upward from the Dbg button and stays on screen
	local W, PAD, TEXT_H, GAP, COLS, CELL_W = 560, 10, 54, 8, 3, 174
	panel = Kit.panel(Vector2.new(W, 0), Theme.Color.Line2)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 28, 1, -(DBG_BOTTOM + 44))
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
	tools.Name = "Commands"
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
		if entry.command == "stance" then
			-- the button names the previewed weapon (Systems/Debug "stance")
			local label = Kit.buttonLabel(b)
			player:GetAttributeChangedSignal("StanceWeapon"):Connect(function()
				local id = player:GetAttribute("StanceWeapon")
				local w = if typeof(id) == "string" then Weapons.ById[id] else nil
				label.Text = if w then "Stance: " .. w.name else entry.label
			end)
		end
		local armed = 0 -- os.clock() of the first tap on a confirm button (0 = not armed)
		b.Activated:Connect(function()
			if entry.confirm then
				local label = Kit.buttonLabel(b)
				if armed == 0 or os.clock() - armed > CONFIRM_TIME then
					armed = os.clock()
					label.Text = "Sure? Tap again"
					local stamp = armed
					task.delay(CONFIRM_TIME, function()
						if armed == stamp then
							armed = 0
							label.Text = entry.label
						end
					end)
					return
				end
				armed = 0
				label.Text = entry.label
			end
			local run = LOCAL_COMMANDS[entry.command]
			if run then
				run()
			else
				Net.Debug:FireServer(entry.command, entry.value)
			end
		end)
		b.Parent = tools
	end
	tools.Parent = panel

	-- The grid determines the button size (Kit.touchTarget does not apply here): on touch >= 33 px after HUD scaling
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
	Kit.onViewport(relayout)

	local button = Kit.button("Dbg", Theme.Color.Bg3, Vector2.new(48, 30))
	dbgButton = button
	button.Name = "Dbg"
	Kit.buttonLabel(button).TextColor3 = Theme.Color.Muted
	Kit.buttonLabel(button).TextSize = Kit.fontSize(13)
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 28, 1, -DBG_BOTTOM)
	button.Activated:Connect(toggle)
	button.Visible = allowed()
	button.Parent = root

	-- Dump view: scrollable text in the middle of the screen, tap "Close" to hide it
	dumpView = Kit.panel(Vector2.new(620, 400), Theme.Color.Line2)
	dumpView.Name = "JointDump"
	dumpView.AnchorPoint = Vector2.new(0.5, 0.5)
	dumpView.Position = UDim2.fromScale(0.5, 0.5)
	dumpView.Visible = false
	dumpView.ZIndex = 20
	dumpView.Parent = root
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(PAD, PAD)
	scroll.Size = UDim2.new(1, -2 * PAD, 1, -2 * PAD - 44)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ZIndex = 21
	scroll.Parent = dumpView
	dumpText = Kit.label("", 11, Theme.Color.Text, Theme.Font.Body)
	dumpText.AutomaticSize = Enum.AutomaticSize.Y
	dumpText.Size = UDim2.new(1, -8, 0, 0)
	dumpText.TextWrapped = true
	dumpText.TextXAlignment = Enum.TextXAlignment.Left
	dumpText.TextYAlignment = Enum.TextYAlignment.Top
	dumpText.ZIndex = 22
	dumpText.Parent = scroll
	local close = Kit.button("Close", Theme.Color.Bg3, Vector2.new(120, 36))
	close.Name = "CloseDump"
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -PAD, 1, -PAD)
	close.ZIndex = 22
	close.Activated:Connect(function()
		dumpView.Visible = false
	end)
	close.Parent = dumpView

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
		-- Hidden while a fullscreen window is open: the phone menu dock stands where it sits
		local shown = allowed() and Window.openName() == nil
		if dbgButton and dbgButton.Visible ~= shown then
			dbgButton.Visible = shown
		end
		if elapsed >= REFRESH then
			if panel.Visible then
				render(math.floor(frames / elapsed + 0.5))
			end
			frames, elapsed = 0, 0
		end
	end)
end

return DebugController
