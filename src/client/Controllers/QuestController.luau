--!strict
-- Onboarding on the client: holds the latest quest snapshot (Net.Quest), answers whether a hub
-- window is unlocked and shows short toasts at the top ("Quest complete", "New: Forge").
-- The HUD quest panel and the hub bar locks read from here (HudController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Quests)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)

local QuestController = {}

export type State = {
	step: number,
	total: number,
	text: string?,
	gold: number?,
	count: number,
	target: number,
	unlocks: { [string]: boolean },
}

local player = Players.LocalPlayer
local C = Theme.Color

local state: State = {
	step = 1,
	total = #Rules.Chain,
	text = nil,
	gold = nil,
	count = 0,
	target = 0,
	unlocks = {},
}
local received = false

local changed = Instance.new("BindableEvent")
QuestController.changed = changed.Event

local toastRoot: Frame
local queue: { { text: string, color: Color3 } } = {}
local showing = false

function QuestController.state(): State
	return state
end

-- Unlocked? Before the first snapshot, everything without a rule is open and locked windows
-- fall back to level/depth (no flicker for players with progress).
function QuestController.isOpen(id: string): boolean
	local rule = Rules.Unlocks[id]
	if not rule or state.unlocks[id] then
		return true
	end
	local level = (player:GetAttribute("Level") or 1) :: number
	local depth = (player:GetAttribute("BestDepth") or 0) :: number
	return (rule.level ~= nil and level >= rule.level)
		or (rule.depth ~= nil and depth >= rule.depth)
end

-- "Reach level 5" for a locked window, nil when open
function QuestController.lockHint(id: string): string?
	if QuestController.isOpen(id) then
		return nil
	end
	local rule = Rules.Unlocks[id]
	return if rule then rule.caption else nil
end

local TOAST_W, TOAST_MAX_W, TOAST_Y = 420, 760, 70

local function showNext()
	if showing or #queue == 0 or not toastRoot then
		return
	end
	showing = true
	local entry = table.remove(queue, 1) :: { text: string, color: Color3 }
	-- Width follows the text (two lines past MAX_W), so long lore lines stay inside the card
	local textW = #entry.text * Kit.fontSize(16) * 0.55
	local w = math.clamp(math.ceil(textW) + 48, TOAST_W, TOAST_MAX_W)
	local lines = if textW + 48 > TOAST_MAX_W then 2 else 1
	local h = 46 + (lines - 1) * 24
	local panel = Kit.panel(Vector2.new(w, h), entry.color)
	panel.Name = "Toast"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, -h - 14)
	local label = Kit.label(entry.text, 16, entry.color)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, -32, 1, -8)
	label.TextWrapped = true
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Parent = panel
	panel.Parent = toastRoot
	-- Below the top-center column (capsules, boss bar, Rift card) instead of on top of it
	local scale = toastRoot:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	local gui = toastRoot:FindFirstAncestorWhichIsA("LayerCollector")
	local top = if gui then gui.AbsolutePosition.Y else 0
	local y = math.max(TOAST_Y, (Kit.topCenterBottom() - top) / s + 8)
	local inInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(panel, inInfo, { Position = UDim2.new(0.5, 0, 0, y) }):Play()
	task.delay(2.4, function()
		local out = TweenService:Create(
			panel,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -h - 14) }
		)
		out:Play()
		task.wait(0.3)
		panel:Destroy()
		showing = false
		showNext()
	end)
end

function QuestController.toast(text: string, color: Color3?)
	if #queue >= 6 then
		return -- never pile up
	end
	table.insert(queue, { text = text, color = color or C.Text })
	showNext()
end

local function onQuest(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local unlocks = {}
	if typeof(payload.unlocks) == "table" then
		for _, id in payload.unlocks do
			if typeof(id) == "string" then
				unlocks[id] = true
			end
		end
	end
	local function num(v: any, default: number): number
		return if typeof(v) == "number" and v == v then v else default
	end
	state = {
		step = num(payload.step, 1),
		total = num(payload.total, #Rules.Chain),
		text = if typeof(payload.text) == "string" then payload.text else nil,
		gold = if typeof(payload.gold) == "number" then payload.gold else nil,
		count = num(payload.count, 0),
		target = num(payload.target, 0),
		unlocks = unlocks,
	}
	-- Toasts only for events after the first snapshot (not on join)
	if received then
		if typeof(payload.done) == "table" then
			for _, text in payload.done do
				if typeof(text) == "string" then
					QuestController.toast("Quest complete: " .. text, C.Gold)
				end
			end
		end
		if typeof(payload.unlocked) == "table" then
			for _, id in payload.unlocked do
				local name = if typeof(id) == "string" then Rules.Names[id] else nil
				if name then
					QuestController.toast("New: " .. name, C.Cyan)
				end
			end
		end
	end
	received = true
	changed:Fire()
end

-- Progress of the active quest; level/depth goals read the live attributes
function QuestController.count(): number
	local q = Rules.Chain[state.step]
	if q and q.goal == "level" then
		return math.min((player:GetAttribute("Level") or 1) :: number, q.target)
	elseif q and q.goal == "depth" then
		return math.min((player:GetAttribute("BestDepth") or 0) :: number, q.target)
	end
	return state.count
end

-- Has the first snapshot arrived?
function QuestController.ready(): boolean
	return received
end

-- Short line for the quest panel: "Defeat 10 enemies", "4 / 10", "+30 Gold"
function QuestController.lines(): (string, string, string)
	if not received then
		return "", "", "" -- no snapshot yet: an empty panel, not "all done"
	end
	if not state.text then
		local depth = (player:GetAttribute("BestDepth") or 0) :: number
		return "Push deeper!", string.format("Best depth %d", depth), ""
	end
	local reward = if state.gold then "+" .. Format.big(state.gold) .. " Gold" else ""
	-- Extra rewards (Forge materials, spell stones) on their own line under the objective
	local q = Rules.Chain[state.step]
	local extra = if q then Rules.extraText(q) else ""
	local text = if extra ~= "" then state.text .. "\nReward: " .. extra else state.text
	return text, string.format("%d / %d", QuestController.count(), state.target), reward
end

function QuestController.init()
	local gui, root = Kit.scaledGui("LootRushToast", 20, false, nil, true)
	gui.Parent = player:WaitForChild("PlayerGui")
	toastRoot = root
	Window.setGate(function(id: string): boolean
		local hint = QuestController.lockHint(id)
		if hint then
			QuestController.toast("Locked - " .. hint, C.Muted)
		end
		return hint ~= nil
	end)
end

function QuestController.start()
	Net.Quest.OnClientEvent:Connect(onQuest)
	-- level/depth change the progress of state goals and the fallback unlocks
	player:GetAttributeChangedSignal("Level"):Connect(function()
		changed:Fire()
	end)
	player:GetAttributeChangedSignal("BestDepth"):Connect(function()
		changed:Fire()
	end)
end

return QuestController
