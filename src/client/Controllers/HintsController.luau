--!strict
-- One-time tutorial hints (docs/CRITERIA-AUDIT.md §3 #2). Each hint is a callout (client/UI/Callout)
-- next to the HUD element it explains, with a pulsing ring around that element. A hint is queued
-- when its moment comes and shown at the next calm moment (no enemy or enemy telegraph close, no
-- window open, alive), one at a time. It stays until the player does the thing, taps the card or
-- Config.HINT_SHOW_TIME runs out, and only then counts as seen: a hint that never reached the screen
-- (or was only up for a blink) comes back later.
--   hintSkills   in a Rift, the first enemy within Config.HINT_SKILL_RANGE   → first skill button
--   newSkill     a starting skill just unlocked (new heroes, Skills.StartUnlock) → its new button
--                (not saved: comes once per unlock, closes when the skill is used)
--   hintDodge    the first enemy telegraph within Config.HINT_TELEGRAPH_RANGE → dash button
--   hintRush     Rush meter at Config.HINT_RUSH_AT (or the first Rush)       → Rush meter
--   hintBreak    the first boss                                              → boss Break bar
--   hintCounter  the first Counter, or the next boss after the Break hint    → dash button
--   hintEquip    quest "Equip an item" active, back at rest                  → Inventory button
-- "Seen" is a hidden account setting (Shared/Settings, saved through Client/Prefs); the Defaults
-- button in the settings window clears them. Nothing shows before the saved settings arrived.
-- Texts follow the input: touch buttons on phones, keys on PC.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Bosses = require(ReplicatedStorage.Shared.Bosses)
local Config = require(ReplicatedStorage.Shared.Config)
local Momentum = require(ReplicatedStorage.Shared.Momentum)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Rush = require(ReplicatedStorage.Shared.Rush)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Callout = require(script.Parent.Parent.UI.Callout)
local Kit = require(script.Parent.Parent.UI.Kit)
local Window = require(script.Parent.Parent.UI.Window)
local Prefs = require(script.Parent.Parent.Prefs)
local ProgressController = require(script.Parent.ProgressController)
local QuestController = require(script.Parent.QuestController)
local SkillController = require(script.Parent.SkillController)

local HintsController = {}

local TICK = 0.25

local player = Players.LocalPlayer

type Hint = {
	key: string,
	title: string,
	touch: string,
	keys: string,
	target: () -> GuiObject?,
	round: boolean, -- round button: round pulse ring
	valid: (() -> boolean)?, -- still makes sense (e.g. a boss lives); pending hints wait for it
	done: (() -> boolean)?, -- the player did it: close
	press: { Enum.KeyCode }?, -- PC keys that count as doing it
	text: (() -> (string, string))?, -- dynamic (touch, keys) texts instead of touch/keys
	pressNow: (() -> { Enum.KeyCode })?, -- dynamic keys instead of press
	transient: boolean?, -- not a saved one-time hint: queued by code each time its moment comes
}

local function inRift(): boolean
	return player:GetAttribute("RiftRegion") ~= nil
end

local function hudRoot(): Instance?
	local gui = player:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("LootRushHUD")
	return hud and hud:FindFirstChild("Root")
end

local function find(parent: Instance?, ...: string): GuiObject?
	local node = parent
	for _, name in { ... } do
		node = node and node:FindFirstChild(name, true)
	end
	return if node and node:IsA("GuiObject") then node else nil
end

local function boss(): Model?
	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy:IsA("Model") and enemy:GetAttribute("Boss") == true and enemy.Parent then
			return enemy
		end
	end
	return nil
end

local function questId(): string?
	local q = Quests.Chain[QuestController.state().step]
	return if q then q.id else nil
end

local function dashButton(): GuiObject?
	return find(hudRoot(), "Dash")
end

local SLOT_KEYS = { "Q", "E", "R", "F" }
local SLOT_CODES = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.F }

-- Bar slots whose skill the hero has learned (new heroes start with one, Skills.StartUnlock)
local function openSlots(): { number }
	local out = {}
	for slot = 1, #SLOT_KEYS do
		if SkillController.unlocked(slot) then
			table.insert(out, slot)
		end
	end
	return out
end

local function skillButton(slot: number?): GuiObject?
	return if slot then find(hudRoot(), "Skills", "Skill" .. slot) else nil
end

local newSlot: number? = nil -- slot of the skill the newSkill hint points at

local HINTS: { Hint } = {
	{
		key = "hintDodge",
		title = "DODGE",
		touch = "Red zones are enemy attacks. Tap Dash to roll out of them.",
		keys = "Red zones are enemy attacks. Press Space to dash out of them.",
		target = dashButton,
		round = true,
		valid = inRift,
		press = { Enum.KeyCode.Space },
	},
	{
		key = "hintSkills",
		title = "SKILLS",
		touch = "Your hero attacks on its own. Tap your skill buttons for big hits!",
		keys = "Your hero attacks on its own. Press Q, E, R or F for big hits!",
		-- A new hero has fewer skills: name only its keys and say that more are coming
		text = function()
			local open = openSlots()
			local keys = {}
			for _, slot in open do
				table.insert(keys, SLOT_KEYS[slot])
			end
			local list = if #keys > 1
				then table.concat(keys, ", ", 1, #keys - 1) .. " or " .. keys[#keys]
				else keys[1] or "Q"
			local more = if #open < #SLOT_KEYS then " More skills unlock as you level up." else ""
			return "Your hero attacks on its own. Tap your skill buttons for big hits!" .. more,
				"Your hero attacks on its own. Press " .. list .. " for big hits!" .. more
		end,
		target = function()
			return skillButton(openSlots()[1])
		end,
		round = true,
		valid = inRift,
		-- only the keys of learned skills count (a locked key does nothing)
		pressNow = function()
			local out = {}
			for _, slot in openSlots() do
				table.insert(out, SLOT_CODES[slot])
			end
			return out
		end,
	},
	{
		key = "newSkill",
		title = "NEW SKILL",
		touch = "",
		keys = "",
		text = function()
			local skill = if newSlot then SkillController.skill(newSlot) else nil
			local name = if skill then skill.name else "A new skill"
			return name .. " is ready. Tap its new button!",
				string.format("%s is ready. Press %s!", name, SLOT_KEYS[newSlot or 1] or "?")
		end,
		target = function()
			return skillButton(newSlot)
		end,
		round = true,
		valid = function()
			return inRift() and newSlot ~= nil and SkillController.unlocked(newSlot)
		end,
		done = function()
			return newSlot ~= nil and SkillController.remaining(newSlot) > 0
		end,
		transient = true,
	},
	{
		key = "hintRush",
		title = "STUD RUSH",
		touch = "Kills fill this meter. When it is full, you get faster and stronger for a few seconds.",
		keys = "Kills fill this meter. When it is full, you get faster and stronger for a few seconds.",
		target = function()
			return find(hudRoot(), "RushMeter")
		end,
		round = false,
	},
	{
		key = "hintBreak",
		title = "BREAK THE BOSS",
		touch = string.format(
			"Every hit drains this gold bar. Empty = BROKEN: the boss stands still and takes +%d%% damage.",
			Bosses.BREAK_DAMAGE * 100
		),
		keys = string.format(
			"Every hit drains this gold bar. Empty = BROKEN: the boss stands still and takes +%d%% damage.",
			Bosses.BREAK_DAMAGE * 100
		),
		target = function()
			local gui = player:FindFirstChild("PlayerGui")
			return find(gui and gui:FindFirstChild("LootRushRift"), "BossBar", "Poise")
		end,
		round = false,
		valid = function()
			return boss() ~= nil
		end,
	},
	{
		key = "hintCounter",
		title = "COUNTER",
		touch = string.format(
			"Dash into an attack right before it hits: Counter! Cooldowns -%d s and +%d%% damage.",
			Momentum.COUNTER_CDR,
			Momentum.FOCUS_DAMAGE
		),
		keys = string.format(
			"Dash (Space) into an attack right before it hits: Counter! Cooldowns -%d s and +%d%% damage.",
			Momentum.COUNTER_CDR,
			Momentum.FOCUS_DAMAGE
		),
		target = dashButton,
		round = true,
		valid = inRift,
	},
	{
		key = "hintEquip",
		title = "NEW GEAR",
		touch = "You picked up gear! Open your Inventory and tap an item to equip it.",
		keys = "You picked up gear! Open your Inventory and click an item to equip it.",
		target = function()
			return find(hudRoot(), "HubBar", "inventory")
		end,
		round = false,
		valid = function()
			return not inRift() and questId() == "equip"
		end,
		done = function()
			return Window.openName() == "Inventory"
		end,
	},
}

local byKey: { [string]: Hint } = {}
for _, h in HINTS do
	byKey[h.key] = h
end

local pending: { [string]: boolean } = {}
type Current = { hint: Hint, callout: Callout.Callout, shown: number, hidden: number, did: boolean }
local current: Current? = nil
local breakBoss: Model? = nil -- the boss the Break hint was shown on (Counter waits for the next)
local inputConn: RBXScriptConnection? = nil
local targetConn: RBXScriptConnection? = nil

local function unseen(key: string): boolean
	local h = byKey[key]
	if h and h.transient then
		return Prefs.loaded()
	end
	return Prefs.loaded() and Prefs.get(key) == false
end

-- Queues a hint for the next calm moment (true = queued now)
function HintsController.queue(key: string): boolean
	if not byKey[key] or not unseen(key) or pending[key] then
		return false
	end
	pending[key] = true
	return true
end

-- Old name (kept for callers): queue it
function HintsController.show(key: string): boolean
	return HintsController.queue(key)
end

function HintsController.current(): string?
	local c = current
	return if c then c.hint.key else nil
end

local function root(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function near(pos: Vector3, range: number): boolean
	local r = root()
	return r ~= nil and (pos - r.Position).Magnitude <= range
end

local function enemyNear(range: number): boolean
	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy:IsA("Model") and enemy.Parent and near(enemy:GetPivot().Position, range) then
			return true
		end
	end
	return false
end

local function telegraphNear(): boolean
	local folder = workspace:FindFirstChild("Enemies")
	if not folder then
		return false
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and near(child.Position, Config.HINT_TELEGRAPH_RANGE) then
			return true
		end
	end
	return false
end

-- A calm moment: alive, not downed, no window, nothing about to hit the player
function HintsController.calm(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or root() == nil then
		return false
	end
	if player:GetAttribute("SetupDone") ~= true or player:GetAttribute("RiftDowned") == true then
		return false
	end
	if Window.anyOpen() then
		return false
	end
	return not enemyNear(Config.HINT_CALM_RANGE) and not telegraphNear()
end

local function disconnect()
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
	if targetConn then
		targetConn:Disconnect()
		targetConn = nil
	end
end

-- Ends the shown hint. Seen = the player did it, tapped it, or it was up long enough to read.
local function finish(c: Current)
	disconnect()
	c.callout.close()
	current = nil
	if c.did or c.callout.tapped() or c.shown >= Config.HINT_MIN_SEEN then
		pending[c.hint.key] = nil
		if not c.hint.transient then
			Prefs.set(c.hint.key, true)
		end
		if c.hint.key == "hintBreak" then
			breakBoss = boss()
		end
	end
end

local function open(h: Hint, target: GuiObject)
	local touchText, keysText = h.touch, h.keys
	if h.text then
		touchText, keysText = h.text()
	end
	local text = if UserInputService.TouchEnabled then touchText else keysText
	local c: Current = {
		hint = h,
		callout = Callout.new(target, h.title, text, h.round),
		shown = 0,
		hidden = 0,
		did = false,
	}
	current = c
	-- Pressing the explained button (or its key) counts as doing it
	targetConn = target.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			c.did = true
		end
	end)
	local keys = if h.pressNow then h.pressNow() else h.press
	if keys then
		inputConn = UserInputService.InputBegan:Connect(
			function(input: InputObject, processed: boolean)
				if not processed and table.find(keys, input.KeyCode) then
					c.did = true
				end
			end
		)
	end
	c.callout.update()
end

-- Every frame while a hint is up: follow the target, close when done
local function step(dt: number)
	local c = current
	if not c then
		return
	end
	local h = c.hint
	local valid = h.valid
	if (valid and not valid()) or (h.done and h.done()) then
		if h.done and h.done() then
			c.did = true
		end
		finish(c)
		return
	end
	if c.did or c.callout.tapped() then
		finish(c)
		return
	end
	if c.callout.update() then
		c.shown += dt
		c.hidden = 0
		if c.shown >= Config.HINT_SHOW_TIME then
			finish(c)
		end
	else
		c.hidden += dt
		if c.hidden >= Config.HINT_HIDDEN_GIVE_UP then
			finish(c) -- target gone (window, flown out): back to the queue unless it was read
		end
	end
end

-- Next pending hint at a calm moment (list order = priority)
local function pick()
	if current or not Prefs.loaded() or not HintsController.calm() then
		return
	end
	for _, h in HINTS do
		if pending[h.key] then
			if not unseen(h.key) then
				pending[h.key] = nil
			elseif h.valid == nil or h.valid() then
				local target = h.target()
				if target and Callout.visible(target) then
					open(h, target)
					return
				end
			end
		end
	end
end

-- Learned skills on the bar at the last poll, by id (nil until the first snapshot and the level
-- are known, so a rejoin does not count its skills as new; ids, so a bar swap is not "new")
local knownOpen: { [string]: boolean }? = nil
local knownClass = ""

-- A starting skill just unlocked (level up): point at its new button
local function watchUnlocks()
	if
		not ProgressController.loaded()
		or typeof(player:GetAttribute("Level")) ~= "number"
		or typeof(player:GetAttribute("Class")) ~= "string"
	then
		return
	end
	if knownClass ~= Kit.playerClass() then
		knownClass = Kit.playerClass()
		knownOpen = nil -- class set (setup): start counting from here
	end
	local data = ProgressController.data()
	local level = player:GetAttribute("Level") :: number
	local now: { [string]: boolean } = {}
	for _, skill in Skills.forClass(Kit.playerClass()).list do
		if Progression.isUnlocked(skill, level, data) then
			now[skill.id] = true
		end
	end
	local before = knownOpen
	knownOpen = now
	if not before then
		return
	end
	for id in now do
		local slot = table.find(data.bar, id)
		if not before[id] and slot then
			newSlot = slot -- one at a time; a multi-level jump points at one of them
			HintsController.queue("newSkill")
		end
	end
end

-- Moments that queue a hint (polled)
local function triggers()
	if not Prefs.loaded() then
		return
	end
	watchUnlocks()
	if inRift() and unseen("hintSkills") and enemyNear(Config.HINT_SKILL_RANGE) then
		HintsController.queue("hintSkills")
	end
	local meter = player:GetAttribute("RushMeter")
	if
		unseen("hintRush")
		and typeof(meter) == "number"
		and meter >= Rush.METER * Config.HINT_RUSH_AT
	then
		HintsController.queue("hintRush")
	end
	local b = boss()
	if b then
		HintsController.queue("hintBreak")
		if Prefs.get("hintBreak") == true and b ~= breakBoss then
			HintsController.queue("hintCounter") -- one lesson per boss: Counter on the next one
		end
	end
	if questId() == "equip" and not inRift() then
		HintsController.queue("hintEquip")
	end
end

-- Enemy telegraphs are flat parts directly in workspace.Enemies (Systems/Enemies)
local function watchTelegraphs(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		if
			child:IsA("BasePart")
			and unseen("hintDodge")
			and near(child.Position, Config.HINT_TELEGRAPH_RANGE)
		then
			HintsController.queue("hintDodge")
		end
	end)
end

function HintsController.start()
	player:GetAttributeChangedSignal("Rushing"):Connect(function()
		if player:GetAttribute("Rushing") == true then
			HintsController.queue("hintRush")
		end
	end)
	Net.Fx.OnClientEvent:Connect(function(kind: any, data: any)
		if
			kind == "dmg"
			and typeof(data) == "table"
			and data.counter
			and data.who == player.UserId
		then
			HintsController.queue("hintCounter")
		end
	end)
	task.spawn(function()
		local folder = workspace:WaitForChild("Enemies", math.huge)
		if folder then
			watchTelegraphs(folder)
		end
	end)
	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		while true do
			triggers()
			pick()
			task.wait(TICK)
		end
	end)
end

return HintsController
