--!strict
-- Daily rewards (Shared/Daily, docs/ROADMAP-1.0.md §4.2): one claim per UTC day per account, a
-- 7-day calendar that never resets. The reward lands on the active hero (gold, materials, spell
-- stones) and the account (Soulstars). The day comes from the server clock only: the client
-- just says "claim". After loading and after every claim the state goes out (Net.DailyState).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Daily)
local SpellStones = require(ReplicatedStorage.Shared.SpellStones)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)
local Shop = require(script.Parent.Shop)

local Daily = {
	clock = os.time, -- tests swap the clock
}

local allow = RateLimit.new(2, 4)
local rng = Random.new()

local function bestDepth(player: Player): number
	local profile = Data.get(player)
	return if profile then Atlas.bestDepth(profile.atlas) else 1
end

-- Calendar state for the client
function Daily.state(player: Player): { [string]: any }?
	local account = Data.account(player)
	if not account then
		return nil
	end
	local now = Daily.clock()
	local best = bestDepth(player)
	local rewards = {}
	for i = 1, Rules.CYCLE do
		rewards[i] = Rules.reward(i, best)
	end
	return {
		claimed = account.daily.claimed,
		index = Rules.nextIndex(account.daily),
		canClaim = Rules.canClaim(account.daily, now),
		secondsLeft = Rules.secondsLeft(account.daily, now),
		rewards = rewards,
	}
end

function Daily.sync(player: Player, paid: number?)
	local state = Daily.state(player)
	if state then
		state.paid = paid
		Net.DailyState:FireClient(player, state)
	end
end

-- Claims today's reward; returns the calendar index paid or nil (already claimed, no save, no hero)
function Daily.claim(player: Player): number?
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile or not profile.setupDone then
		return nil
	end
	local reward = Rules.reward(Rules.nextIndex(account.daily), bestDepth(player))
	local index = Rules.claim(account.daily, Daily.clock())
	if not index then
		return nil
	end
	if reward.gold > 0 then
		Inventory.addGold(player, reward.gold)
	end
	Progress.addMaterials(
		player,
		{ candy = reward.candy, shards = reward.shards, dust = reward.dust }
	)
	for _ = 1, reward.stones do
		local id = SpellStones.roll(rng)
		profile.progress.stones[id] = (profile.progress.stones[id] or 0) + 1
	end
	Progress.sync(player)
	if reward.soulstars > 0 then
		Shop.grant(player, "soulstars", reward.soulstars)
	end
	return index
end

-- Test command (Systems/Debug "day"): pretend the last claim was yesterday
function Daily.rewind(player: Player)
	local account = Data.account(player)
	if account and account.daily.last > 0 then
		account.daily.last = math.min(account.daily.last, Rules.dayOf(Daily.clock()) - 1)
		Daily.sync(player)
	end
end

local function onPlayer(player: Player)
	if Data.waitForAccount(player) and player.Parent then
		Daily.sync(player)
	end
end

function Daily.init()
	Net.Daily.OnServerEvent:Connect(function(player: Player, action: any)
		if action ~= "claim" or not allow(player) then
			return
		end
		local index = Daily.claim(player)
		Daily.sync(player, index)
	end)
end

function Daily.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Daily
