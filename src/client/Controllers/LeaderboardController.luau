--!strict
-- Leaderboards (Shared/Leaderboard, Systems/Leaderboard):
--  • Window: tabs for the overall ladder and each World Tier, class tabs below, the top list and
--    the player's own best pinned at the bottom. Opens from the trophy on the HUD and the board
--    in the hub.
--  • Hub board: the top 10 of the overall ladder drawn on the part "LeaderboardScreen"
--    (Systems/Hub), refreshed every Leaderboard.CACHE seconds.
-- Pages come from the server (Net.BoardData); the client only names the board it wants.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Leaderboard)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)

local LeaderboardController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local F = Theme.Flat

local PAD = 28
local TAB_H = 48
local ROW_H = 52
local LIST_TOP = 2 * TAB_H + 40
local MINE_H = 64
local HUB_ROWS = Rules.HUB_TOP
local HUB_SIZE = Vector2.new(550, 400) -- SurfaceGui canvas (studs × 50)

local win: Window.Window
local pages: { [string]: Rules.Page } = {}
local tier = 0 -- 0 = overall ladder
local class = ""
local autoClass = "" -- class picked from the hero (not by a click): follows the hero until a click
local list: ScrollingFrame
local mineRow: Frame
local status: TextLabel
local classTabs: Flat.Tabs
local classFrame: Frame
local hubRows: Frame? = nil
local hubStatus: TextLabel? = nil

local function boardId(): string
	if tier == 0 then
		return Rules.OVERALL
	end
	return Rules.boardId(tier, class)
end

local function tierName(id: number): string
	local t = WorldTiers.List[id]
	return if t then t.name else "–"
end

local function result(e: Rules.Entry, overall: boolean): string
	local depth = `Depth {Format.int(e.depth)}`
	if overall then
		return `{tierName(e.tier)} · {depth}`
	end
	return depth
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- One list row: rank, name, result, time
local function row(e: Rules.Entry, width: number, overall: boolean, mine: boolean): Frame
	local f = Flat.card(UDim2.fromOffset(width, ROW_H), if mine then F.Surface2 else nil)
	f.Name = "Row_" .. e.rank
	f.LayoutOrder = e.rank
	local top3 = e.rank >= 1 and e.rank <= 3
	local rank = Flat.text(
		if e.rank > 0 then `#{Format.int(e.rank)}` else `{Rules.TOP}+`,
		18,
		if top3 then C.GoldHi else C.Muted,
		Theme.Font.UI
	)
	rank.AnchorPoint = Vector2.new(0, 0.5)
	rank.Position = UDim2.new(0, 20, 0.5, 0)
	rank.Parent = f
	if e.rank == 1 then
		local crown = Kit.icon("crown", 28)
		crown.AnchorPoint = Vector2.new(0, 0.5)
		crown.Position = UDim2.new(0, 84, 0.5, 0)
		crown.Parent = f
	end
	local name = Flat.text(e.name, 18, if mine then C.GoldHi else C.Text, Theme.Font.UI)
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, 124, 0.5, 0)
	name.Parent = f
	local res = Flat.text(result(e, overall), 18, C.Text, Theme.Font.UI, Enum.TextXAlignment.Right)
	res.AnchorPoint = Vector2.new(1, 0.5)
	res.Position = UDim2.new(1, -170, 0.5, 0)
	res.Parent = f
	local time =
		Flat.text(Rules.time(e.seconds), 16, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Right)
	time.AnchorPoint = Vector2.new(1, 0.5)
	time.Position = UDim2.new(1, -24, 0.5, 0)
	time.Parent = f
	return f
end

local function render()
	local id = boardId()
	local page = pages[id]
	local width = Window.BODY.X - 2 * PAD - 16
	local overall = tier == 0
	clear(list)
	clear(mineRow)
	if not page then
		status.Text = "Loading…"
		return
	end
	if #page.entries == 0 then
		status.Text = if page.updated == 0
			then "Leaderboards are not reachable right now."
			else "No entries yet. Clear a depth to be the first!"
	else
		status.Text = ""
	end
	for _, e in page.entries do
		row(e, width, overall, e.userId == player.UserId).Parent = list
	end
	local mine = page.mine
	if mine then
		local r = row(mine, width, overall, true)
		r.Parent = mineRow
	else
		local t = Flat.text(
			"Clear a depth on this ladder to get your own entry.",
			16,
			C.Muted,
			Theme.Font.Body,
			Enum.TextXAlignment.Center
		)
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.5)
		t.Parent = mineRow
	end
end

local function request(id: string)
	Net.Board:FireServer(id)
end

local function show()
	render()
	request(boardId())
end

-- Opening: the class tab follows the hero (setup may pick the class after init) until a click
local function opened()
	local hero = Kit.playerClass()
	if class == autoClass and Classes.ById[hero] and hero ~= class then
		class, autoClass = hero, hero
		classTabs.select(hero)
	end
	show()
end

local function build()
	local body = Window.BODY
	local panel = Kit.panel(body)
	panel.Name = "Board"
	panel.Parent = win.body
	Shape.brackets(panel)

	local tierDefs = { { id = "overall", text = "Overall" } }
	for _, t in WorldTiers.List do
		table.insert(tierDefs, { id = "t" .. t.id, text = t.name })
	end
	local tierTabs = Flat.tabs(tierDefs, TAB_H, function(id: string)
		tier = if id == "overall" then 0 else tonumber(string.sub(id, 2)) or 0
		classFrame.Visible = tier ~= 0
		show()
	end)
	tierTabs.frame.Position = UDim2.fromOffset(PAD, 16)
	tierTabs.frame.Parent = panel

	local classDefs = {}
	for _, c in Classes.List do
		table.insert(classDefs, { id = c.id, text = c.name })
	end
	classFrame =
		Flat.frame(UDim2.fromOffset(body.X - 2 * PAD, TAB_H), UDim2.fromOffset(PAD, 16 + TAB_H + 8))
	classFrame.Name = "Classes"
	classTabs = Flat.tabs(classDefs, TAB_H, function(id: string)
		class = id
		show()
	end)
	classTabs.frame.Parent = classFrame
	classFrame.Visible = false
	classFrame.Parent = panel

	local listH = body.Y - LIST_TOP - MINE_H - 2 * PAD
	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(PAD, LIST_TOP)
	list.Size = UDim2.fromOffset(body.X - 2 * PAD, listH)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = C.Gold
	list.ScrollBarImageTransparency = 0.2
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local ll = Kit.list(list, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Top)
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.Parent = panel

	status = Flat.text("", 18, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, LIST_TOP + 40)
	status.Parent = panel

	mineRow = Flat.frame(
		UDim2.fromOffset(body.X - 2 * PAD, MINE_H),
		UDim2.fromOffset(PAD, body.Y - PAD - MINE_H)
	)
	mineRow.Name = "Mine"
	mineRow.Parent = panel
	local rule = Flat.rule(body.X - 2 * PAD, F.Edge)
	rule.Position = UDim2.fromOffset(PAD, body.Y - PAD - MINE_H - 6)
	rule.Parent = panel

	tierTabs.select("overall")
	class = Kit.playerClass()
	if not Classes.ById[class] then
		class = Classes.DEFAULT
	end
	autoClass = class
	classTabs.select(class)
end

-- ------------------------------------------------------------------ Board in the hub
local function renderHub()
	local rows, st = hubRows, hubStatus
	if not rows or not st or not rows:IsDescendantOf(workspace) then
		return -- no board, or its part streamed out (rebuilt when it streams back in)
	end
	clear(rows)
	local page = pages[Rules.OVERALL]
	if not page or #page.entries == 0 then
		st.Text = if page and page.updated == 0 then "Offline" else "Be the first to clear a depth!"
		return
	end
	st.Text = ""
	for i = 1, math.min(HUB_ROWS, #page.entries) do
		local e = page.entries[i]
		local f = Flat.frame(UDim2.new(1, 0, 0, 28))
		f.LayoutOrder = i
		local left =
			Flat.text(`#{e.rank}  {e.name}`, 20, if i <= 3 then C.GoldHi else C.Text, Theme.Font.UI)
		left.Parent = f
		local right =
			Flat.text(result(e, true), 20, C.Text, Theme.Font.UI, Enum.TextXAlignment.Right)
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.fromScale(1, 0)
		right.Parent = f
		f.Parent = rows
	end
end

local function buildHubBoard(screen: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LootRushHubBoard"
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = HUB_SIZE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = F.Surface0
	back.BorderSizePixel = 0
	back.Parent = gui
	local title = Window.gilded("LEADERBOARD", 30)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 14)
	title.Parent = back
	local sub = Flat.text(
		"Highest World Tier and depth",
		16,
		C.Muted,
		Theme.Font.Body,
		Enum.TextXAlignment.Center
	)
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0, 54)
	sub.Parent = back
	local rows = Flat.frame(UDim2.new(1, -48, 1, -100), UDim2.fromOffset(24, 88))
	rows.Name = "Rows"
	Kit.list(rows, Enum.FillDirection.Vertical, 2, Enum.VerticalAlignment.Top)
	rows.Parent = back
	local st = Flat.text("", 20, C.Muted, Theme.Font.Body, Enum.TextXAlignment.Center)
	st.AnchorPoint = Vector2.new(0.5, 0.5)
	st.Position = UDim2.fromScale(0.5, 0.55)
	st.Parent = back
	hubRows, hubStatus = rows, st
	gui.Parent = screen -- client-side only: every player draws their own copy
	renderHub()
end

-- The screen part can stream out and back in (StreamingEnabled): a new part gets a new board
local function bindScreen(screen: Instance)
	if screen.Name ~= "LeaderboardScreen" or not screen:IsA("BasePart") then
		return
	end
	if hubRows and hubRows:IsDescendantOf(screen) then
		return -- already bound (the stream-in signal and the first lookup can both see it)
	end
	buildHubBoard(screen)
end

local function watchHub()
	workspace.DescendantAdded:Connect(bindScreen)
	local hub = workspace:WaitForChild("Lumenhaven", 60)
	local screen = hub and hub:FindFirstChild("LeaderboardScreen", true)
	if screen then
		bindScreen(screen)
	end
	while true do
		request(Rules.OVERALL)
		task.wait(Rules.CACHE)
	end
end

function LeaderboardController.toggle()
	win.toggle()
end

function LeaderboardController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function LeaderboardController.isOpen(): boolean
	return win.isOpen()
end

function LeaderboardController.init()
	win = Window.new({ name = "Leaderboard", title = "Leaderboard", icon = "trophy" })
	build()
	win.onOpen(opened)
	Net.BoardData.OnClientEvent:Connect(function(page: any)
		if
			typeof(page) ~= "table"
			or typeof(page.id) ~= "string"
			or typeof(page.entries) ~= "table"
		then
			return
		end
		pages[page.id] = page :: Rules.Page
		if page.id == Rules.OVERALL then
			renderHub()
		end
		if win.isOpen() and page.id == boardId() then
			render()
		end
	end)
end

function LeaderboardController.start()
	task.spawn(watchHub)
end

return LeaderboardController
