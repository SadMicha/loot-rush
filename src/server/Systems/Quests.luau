--!strict
-- Onboarding quest chain and window unlocks on the server (rules: Shared/Quests).
--   • count goals come from Util/Actions (other systems fire them) plus kills and item pickups
--   • state goals (level, best depth) are re-checked when the attributes "Level"/"BestDepth" change
--   • rewards are gold plus optional Forge materials / spell stones (Rules reward); every finished quest is one onboarding funnel step (Systems/Analytics)
-- The client only reads: snapshots via Net.Quest (no client → server remote).
-- Unlocks are pacing, not security: the server does not refuse Forge/Star/Pet requests of
-- locked windows (nothing to gain from it), the client hides them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Quests)
local SpellStones = require(ReplicatedStorage.Shared.SpellStones)
local Actions = require(script.Parent.Parent.Util.Actions)
local Analytics = require(script.Parent.Analytics)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Loot = require(script.Parent.Loot)
local Progress = require(script.Parent.Progress)

local Quests = {}

local rng = Random.new()

-- Level and best depth; the depth also from the save, since the BestDepth attribute may not be
-- published yet at join (an old save would otherwise get its unlocks later, with a "New:" toast)
local function stateOf(player: Player): (number, number)
	local level = player:GetAttribute("Level")
	local depth = player:GetAttribute("BestDepth")
	local profile = Data.get(player)
	local saved = if profile then Atlas.bestDepth(profile.atlas) else 0
	return if typeof(level) == "number" then level else 1,
		math.max(if typeof(depth) == "number" then depth else 0, saved)
end

local function unlockList(data: Rules.Data): { string }
	local out = {}
	for id in data.unlocks do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

local function send(player: Player, data: Rules.Data, done: { string }?, unlocked: { string }?)
	local level, depth = stateOf(player)
	local q = Rules.active(data)
	local now, target = Rules.progress(data, level, depth)
	Net.Quest:FireClient(player, {
		step = data.step,
		total = #Rules.Chain,
		text = if q then q.text else nil,
		gold = if q then q.gold else nil,
		count = now,
		target = target,
		unlocks = unlockList(data),
		done = done,
		unlocked = unlocked,
	})
end

-- Extra quest reward (Forge materials, spell stones): what the next step teaches
local function grant(player: Player, q: Rules.Quest)
	local r = q.reward
	local profile = Data.get(player)
	if not r or not profile then
		return
	end
	Progress.addMaterials(
		player,
		{ candy = r.candy or 0, shards = r.shards or 0, dust = r.dust or 0 },
		"Onboarding",
		q.id
	)
	for _ = 1, r.stones or 0 do
		local id = SpellStones.roll(rng)
		profile.progress.stones[id] = (profile.progress.stones[id] or 0) + 1
	end
	Progress.sync(player)
end

-- Counts an action (goal = nil: only re-check level/depth) and pays finished quests
function Quests.advance(player: Player, goal: Rules.Goal?, amount: number)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local data = profile.quests
	local level, depth = stateOf(player)
	local stepBefore, countBefore = data.step, data.count
	local had = table.clone(data.unlocks)
	local finished = Rules.advance(data, goal, amount, level, depth)
	-- "Equip an item" is already done when the hero wears gear: empty-slot loot goes on at once
	-- (Inventory.add), often while an earlier quest is still active, and the Inventory button is
	-- hidden in the Rift
	local active = Rules.active(data)
	if active and active.goal == "equip" and next(profile.equipped) ~= nil then
		for _, more in Rules.advance(data, "equip", 1, level, depth) do
			table.insert(finished, more)
		end
	end
	Rules.refreshUnlocks(data, level, depth)
	-- only windows that were locked before this call (no repeated "New:" toast)
	local unlocked = {}
	for id in data.unlocks do
		if not had[id] then
			table.insert(unlocked, id)
		end
	end
	table.sort(unlocked)
	local doneTexts = {}
	for i, q in finished do
		Inventory.addGold(player, q.gold, "Onboarding", q.id)
		grant(player, q)
		table.insert(doneTexts, q.text)
		Analytics.quest(player, stepBefore + i - 1, q.id)
	end
	if #finished > 0 or #unlocked > 0 or data.count ~= countBefore then
		send(
			player,
			data,
			if #doneTexts > 0 then doneTexts else nil,
			if #unlocked > 0 then unlocked else nil
		)
	end
end

local function onAction(player: any, kind: any, amount: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(kind) ~= "string" then
		return
	end
	Quests.advance(player, kind :: Rules.Goal, if typeof(amount) == "number" then amount else 1)
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	local function recheck()
		Quests.advance(player, nil, 0)
	end
	player:GetAttributeChangedSignal("Level"):Connect(recheck)
	player:GetAttributeChangedSignal("BestDepth"):Connect(recheck)
	-- Quietly bring old saves up to date (unlocks by level/depth), then the first snapshot
	local level, depth = stateOf(player)
	Rules.refreshUnlocks(profile.quests, level, depth)
	send(player, profile.quests)
	recheck()
end

function Quests.init()
	Actions.Event.Event:Connect(onAction)
	Combat.EnemyKilled.Event:Connect(function(player: any)
		onAction(player, "kill", 1)
	end)
	Loot.Picked.Event:Connect(function(player: any, _gold: any, item: any)
		if typeof(item) == "table" then
			onAction(player, "pickup", 1)
		end
	end)
end

function Quests.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Quests
