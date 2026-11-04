--!strict
-- Seasons (Shared/Seasons, docs/ROADMAP.md §6): the season clock and the Season Journey.
-- Challenge progress lives on the account (account.season) and only moves while the season is
-- live; it is fed from server events only (kills, Rift clears, pickups, player actions) plus hero
-- facts read from the save. The client only says "claim <step>"; the server checks the points.
-- Also sets the player attributes SeasonId / SeasonPhase for the HUD badge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JourneyRules = require(ReplicatedStorage.Shared.Journey)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Seasons)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Journey = require(script.Parent.Journey)
local Loot = require(script.Parent.Loot)

local Seasons = {
	clock = os.time, -- tests swap the clock
}

local SYNC_DELAY = 1.5 -- seconds: a burst of kills goes out as one state
local WATCHED = { "Level", "BestDepth", "SetupDone", "CharacterName" }
-- Player actions (Util/Actions) that are season counters as they are
local COUNTED = { salvage = true, forge = true, star = true, hatch = true, daily = true }

local allow = RateLimit.new(4, 8)
local pending: { [Player]: boolean } = {}
local finished: { [Player]: { string } } = {} -- challenges finished since the last state

local function note(player: Player, ids: { string })
	if #ids == 0 then
		return
	end
	local list = finished[player] or {}
	for _, id in ids do
		table.insert(list, id)
	end
	finished[player] = list
end

-- Hero facts the fact challenges read: the Journey facts plus socketed spell stones
local function facts(player: Player): { [string]: number }?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	local f = JourneyRules.facts(profile)
	local sockets = 0
	for _, stones in profile.progress.sockets do
		sockets += #stones
	end
	f.sockets = sockets
	return f
end

-- Reads the hero facts into the season (fact challenges)
local function observe(player: Player)
	local account = Data.account(player)
	local f = facts(player)
	if account and f then
		note(player, Rules.observe(account.season, f, Seasons.clock()))
	end
end

function Seasons.state(player: Player): { [string]: any }?
	local account = Data.account(player)
	if not account then
		return nil
	end
	local now = Seasons.clock()
	local claimed = {}
	for key in account.season.claimed do
		table.insert(claimed, tonumber(key))
	end
	table.sort(claimed)
	return {
		id = account.season.id,
		phase = Rules.phase(now),
		secondsLeft = Rules.secondsLeft(now),
		counts = table.clone(account.season.counts),
		claimed = claimed,
	}
end

function Seasons.sync(player: Player, paid: number?)
	pending[player] = nil
	observe(player)
	local state = Seasons.state(player)
	if state then
		state.paid = paid
		state.finished = finished[player]
		finished[player] = nil
		Net.SeasonState:FireClient(player, state)
	end
	player:SetAttribute("SeasonId", Rules.Current.id)
	player:SetAttribute("SeasonPhase", Rules.phase(Seasons.clock()))
end

-- After a short delay: reads the hero facts and sends the state only when a challenge finished
-- (counts alone go out when the window asks, so kills do not cause traffic)
function Seasons.touch(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(SYNC_DELAY, function()
		if pending[player] and player.Parent then
			pending[player] = nil
			observe(player)
			if finished[player] then
				Seasons.sync(player)
			end
		end
		pending[player] = nil
	end)
end

-- Counts a season counter (server events only)
function Seasons.add(player: Player, kind: string, amount: number?)
	local account = Data.account(player)
	if not account then
		return
	end
	note(player, Rules.add(account.season, kind, amount or 1, Seasons.clock()))
	Seasons.touch(player)
end

-- Claims a track step; returns its index or nil (points missing, claimed, no save/hero)
function Seasons.claim(player: Player, index: any): number?
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile or not profile.setupDone then
		return nil
	end
	observe(player)
	local s = Rules.claim(account.season, index)
	if not s then
		return nil
	end
	Journey.grant(player, s.reward) -- booked before paying: never twice
	return index
end

-- Test command (Systems/Debug "season"): finishes the next unfinished challenge
function Seasons.completeNext(player: Player)
	local account = Data.account(player)
	if not account then
		return
	end
	for _, ch in Rules.Current.challenges do
		if not Rules.done(account.season, ch) then
			account.season.counts[ch.id] = ch.target
			note(player, { ch.id })
			break
		end
	end
	Seasons.sync(player)
end

local function onPlayer(player: Player)
	if not Data.waitForAccount(player) or not player.Parent then
		return
	end
	for _, name in WATCHED do
		player:GetAttributeChangedSignal(name):Connect(function()
			Seasons.touch(player)
		end)
	end
	-- Every cleared depth (the Rift sets the phase "clear" once per depth); the World Tier
	-- attribute is the run's tier (it only changes between runs)
	player:GetAttributeChangedSignal("RiftPhase"):Connect(function()
		if player:GetAttribute("RiftPhase") == "clear" then
			Seasons.add(player, "clear")
			local tier = player:GetAttribute("WorldTier")
			if typeof(tier) == "number" and tier >= 2 then
				Seasons.add(player, "clear_veteran")
			end
		end
	end)
	Seasons.sync(player)
end

local function isPlayer(v: any): boolean
	return typeof(v) == "Instance" and v:IsA("Player")
end

function Seasons.init()
	Net.Season.OnServerEvent:Connect(function(player: Player, action: any, index: any)
		if not allow(player) then
			return
		end
		if action == "claim" then
			Seasons.sync(player, Seasons.claim(player, index))
		elseif action == "sync" then
			Seasons.sync(player)
		end
	end)
	Actions.Event.Event:Connect(function(player: any, kind: any, amount: any)
		if isPlayer(player) and typeof(kind) == "string" and COUNTED[kind] then
			Seasons.add(player, kind, if typeof(amount) == "number" then amount else 1)
		elseif isPlayer(player) then
			if kind == "socket" then
				observe(player) -- read the sockets now: a later unsocket must not lose the count
			end
			Seasons.touch(player)
		end
	end)
	Combat.EnemyKilled.Event:Connect(function(player: any)
		if not isPlayer(player) then
			return
		end
		Seasons.add(player, "kill")
		if player:GetAttribute("Rushing") == true then
			Seasons.add(player, "rush_kill")
		end
	end)
	Loot.Picked.Event:Connect(function(player: any, _gold: any, item: any)
		if isPlayer(player) and typeof(item) == "table" and item.rarity == "unique" then
			Seasons.add(player, "unique")
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
		finished[player] = nil
	end)
end

function Seasons.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Seasons
