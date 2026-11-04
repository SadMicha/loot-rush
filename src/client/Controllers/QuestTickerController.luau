--!strict
-- Quest progress in combat (audit #12, docs/CRITERIA-AUDIT.md): the quest panel only flies in at
-- rest, so in a Rift the player could not see "Defeat 10 enemies 4/10". A one-line ticker hangs
-- under the Rift run card (RiftController "RunInfo", top left) and therefore shows exactly while
-- the run card does. It reads QuestController (Net.Quest snapshot) and flashes when the count moves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rules = require(ReplicatedStorage.Shared.Quests)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local QuestController = require(script.Parent.QuestController)

local QuestTickerController = {}

local player = Players.LocalPlayer
local C = Theme.Color

local GAP = 6 -- px below the run card
local H = 24
local FLASH = 0.5 -- seconds of the gold flash when the count moves

local ticker: Frame?
local label: TextLabel?
local lastKey = ""

-- Text of the ticker for the active quest ("" = nothing to show)
function QuestTickerController.text(): string
	local state = QuestController.state()
	local q = Rules.Chain[state.step]
	if not QuestController.ready() or not state.text or not q or q.goal == "rift" then
		return "" -- "Enter a Rift" is done by being here
	end
	return string.format("%s  %d/%d", state.text, QuestController.count(), state.target)
end

local function refresh()
	local t, l = ticker, label
	if not t or not l then
		return
	end
	local text = QuestTickerController.text()
	t.Visible = text ~= ""
	if text == l.Text then
		return
	end
	local state = QuestController.state()
	local key = string.format("%d|%d", state.step, QuestController.count())
	local moved = lastKey ~= "" and key ~= lastKey
	lastKey = key
	l.Text = text
	if moved then
		l.TextColor3 = C.GoldHi
		TweenService:Create(l, TweenInfo.new(FLASH), { TextColor3 = C.Text }):Play()
	end
end

local function build(card: GuiObject)
	local f = Flat.card(UDim2.new(1, 0, 0, H))
	f.Name = "QuestTicker"
	f.BackgroundTransparency = 0.35
	f.Position = UDim2.new(0, 0, 1, GAP)
	f.Visible = false
	local ic = Kit.icon("quest", 14, C.Gold)
	ic.AnchorPoint = Vector2.new(0, 0.5)
	ic.Position = UDim2.new(0, 8, 0.5, 0)
	ic.ZIndex = 2
	ic.Parent = f
	local t = Flat.text("", 11, C.Text, Theme.Font.Body)
	t.Name = "Text"
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, -34, 1, 0)
	t.Position = UDim2.fromOffset(28, 0)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.ZIndex = 2
	t.Parent = f
	f.Parent = card
	ticker, label = f, t
	refresh()
end

function QuestTickerController.start()
	QuestController.changed:Connect(refresh)
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("LootRushRift", 30)
	local root = gui and gui:WaitForChild("Root", 10)
	local card = root and root:WaitForChild("RunInfo", 10)
	if card and card:IsA("GuiObject") then
		build(card)
	end
end

return QuestTickerController
