--!strict
-- Level-up moment (audit #11, docs/CRITERIA-AUDIT.md): the world effect (ring + "LEVEL N!") lives
-- in FxController; this adds a short card for the own player that says what the level gave:
-- life and damage, the Star Web point, and "New skill: X" when a skill unlocks at this level
-- (Progression.unlockLevel: new heroes' starting skills at Skills.StartUnlock, skills 5-8 at
-- 8/12/16/20), with the key or "tap" to use it. Several levels at once (a big boss kill) show as
-- one card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Balance = require(ReplicatedStorage.Shared.Balance)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local ProgressController = require(script.Parent.ProgressController)

local LevelUpController = {}

local player = Players.LocalPlayer
local C = Theme.Color

local CARD_W = 300
local SHOW_TIME = 3.2 -- seconds on screen (a new skill stays a bit longer)
local SKILL_EXTRA = 1.5
-- Star Web points (1 per level from level 2, Shared/Progression) are only mentioned once the
-- Star Web window is open by level (Quests.Unlocks)
local STAR_LEVEL = Quests.Unlocks.star_net.level or 1

local card: Frame
local title: TextLabel
local stats: TextLabel
local skillRow: Frame
local skillIcon: Frame
local skillText: TextLabel
local known = 0 -- last level seen (the server sends one event for a multi-level jump)
local shownFrom = 0 -- level before the jump the open card counts from
local stamp = 0

local KEYS = { "Q", "E", "R", "F" }

-- Skills that unlock at a level in (from, to] for the own hero
local function unlockedBetween(from: number, to: number): { Skills.Skill }
	return Progression.unlockedBetween(ProgressController.data(), Kit.playerClass(), from, to)
end

-- "New skill: X" plus how to use it when it already sits on the bar (pure, used by the spec)
function LevelUpController.skillLine(skill: Skills.Skill, bar: { string }, touch: boolean): string
	local slot = table.find(bar, skill.id)
	if not slot then
		return "New skill: " .. skill.name .. " · equip it in Skills"
	end
	return "New skill: "
		.. skill.name
		.. (if touch then " · tap its new button" else " · press " .. (KEYS[slot] or "?"))
end

-- Pure text of the card (also used by the spec): stats line for a jump from → to
function LevelUpController.statsLine(from: number, to: number): string
	local gained = math.max(0, to - from)
	local life = Balance.life(to) - Balance.life(from)
	local dmg = gained * Config.DAMAGE_PER_LEVEL * 100
	local stars = if to >= STAR_LEVEL then math.max(0, to - 1) - math.max(0, from - 1) else 0
	local parts = {
		string.format("+%d Life", life),
		string.format(
			"+%s%% Damage",
			if dmg % 1 == 0 then tostring(dmg) else string.format("%.1f", dmg)
		),
	}
	if stars > 0 then
		table.insert(
			parts,
			string.format("+%d Star Web point%s", stars, if stars == 1 then "" else "s")
		)
	end
	return table.concat(parts, " - ")
end

local function show(level: number)
	if not card.Visible then
		shownFrom = math.clamp(known, 1, level - 1)
	end
	known = level
	local from = shownFrom
	title.Text = if level - from > 1
		then string.format("LEVEL %d  (+%d)", level, level - from)
		else string.format("LEVEL %d", level)
	stats.Text = LevelUpController.statsLine(from, level)
	local new = unlockedBetween(from, level)
	skillRow.Visible = #new > 0
	if #new > 0 then
		local s = new[#new]
		skillText.Text = LevelUpController.skillLine(
			s,
			ProgressController.data().bar,
			UserInputService.TouchEnabled
		)
		for _, child in skillIcon:GetChildren() do
			child:Destroy()
		end
		local ic = Kit.icon(Kit.skillIcon(s.id, s.icon), 30)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = skillIcon
	end
	if not card.Visible then
		Flat.pop(card)
	end
	card.Visible = true
	stamp += 1
	local mine = stamp
	task.delay(SHOW_TIME + (if #new > 0 then SKILL_EXTRA else 0), function()
		if stamp == mine then
			card.Visible = false
		end
	end)
end

local function build(root: Frame)
	card = Flat.card(UDim2.fromOffset(CARD_W, 0), nil, C.GoldHi)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Name = "LevelUp"
	-- Upper third: above the hero, below the run card and the cleared card spot
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0.2, 0)
	card.Visible = false
	Shape.brackets(card, C.GoldHi, 8, 0)

	local body = Flat.frame(UDim2.fromScale(1, 0))
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Name = "Body"
	body.ZIndex = 2
	Kit.padding(body, 10)
	local list = Kit.list(body, Enum.FillDirection.Vertical, 4)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	body.Parent = card

	title = Flat.text("", 24, C.GoldHi, Theme.Font.Title, Enum.TextXAlignment.Center)
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Parent = body
	stats = Flat.text("", 12, C.Text, Theme.Font.Body, Enum.TextXAlignment.Center)
	stats.Name = "Stats"
	stats.LayoutOrder = 2
	stats.Parent = body

	skillRow = Flat.frame(UDim2.fromOffset(CARD_W - 20, 36))
	skillRow.Name = "NewSkill"
	skillRow.LayoutOrder = 3
	skillRow.Visible = false
	local rl = Kit.list(skillRow, Enum.FillDirection.Horizontal, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	skillIcon = Flat.frame(UDim2.fromOffset(36, 36))
	skillIcon.LayoutOrder = 1
	skillIcon.Parent = skillRow
	-- Fixed width, grows down: the line also says how to use the skill and may wrap
	skillRow.AutomaticSize = Enum.AutomaticSize.Y
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	skillText = Flat.text("", 15, C.Gold, Theme.Font.UI)
	skillText.AutomaticSize = Enum.AutomaticSize.Y
	skillText.Size = UDim2.fromOffset(CARD_W - 20 - 36 - 8, 0)
	skillText.TextWrapped = true
	skillText.LayoutOrder = 2
	skillText.Parent = skillRow
	skillRow.Parent = body
	card.Parent = root
end

function LevelUpController.init()
	local gui, root = Kit.scaledGui("LootRushLevelUp", 4, false, Kit.hudDesign, true)
	build(root)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function LevelUpController.start()
	local function readLevel()
		local v = player:GetAttribute("Level")
		if typeof(v) == "number" and v > known then
			known = v
		end
	end
	Net.Fx.OnClientEvent:Connect(function(kind: any, d: any)
		if kind ~= "levelup" or typeof(d) ~= "table" or d.who ~= player.UserId then
			return
		end
		local level = tonumber(d.level)
		if level and level == level and level >= 2 then
			show(math.floor(level))
		end
	end)
	-- Joining (or a test command) sets the level without an event: count from there.
	-- The event fires after the attribute, so `known` must lag one step: read it deferred.
	readLevel()
	player:GetAttributeChangedSignal("Level"):Connect(function()
		task.delay(0.5, readLevel)
	end)
end

return LevelUpController
