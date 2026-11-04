--!strict
-- Roblox badges (Shared/Badges, docs/BADGES.md). Awarded from server events only: loading in,
-- hero facts (Journey facts, read shortly after an attribute or action moved them), player actions
-- (Util/Actions) and item pickups (Loot.Picked). No remote: the client can never ask for a badge.
--  • A badge with ID 0 (not created yet) is skipped without a BadgeService call.
--  • Each badge is tried once per session; a failed call (Studio, outage) is retried a few times
--    on later triggers. Roblox ignores an award of a badge the player already owns.
--  • Heroes touched by a test command (profile.debugged, Systems/Debug) earn no progress badges.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JourneyRules = require(ReplicatedStorage.Shared.Journey)
local Rules = require(ReplicatedStorage.Shared.Badges)
local SeasonRules = require(ReplicatedStorage.Shared.Seasons)
local Actions = require(script.Parent.Parent.Util.Actions)
local Data = require(script.Parent.Data)
local Loot = require(script.Parent.Loot)

local Badges = {
	ids = Rules.Ids, -- tests swap in real-looking ids
	clock = os.time, -- tests swap the clock (season window)
	award = function(userId: number, badgeId: number): boolean
		return BadgeService:AwardBadgeAsync(userId, badgeId)
	end,
}

local CHECK_DELAY = 1 -- seconds: a burst of fact changes is read once
local MAX_TRIES = 3 -- failed BadgeService calls per badge and session
local WATCHED = { "Level", "BestDepth", "WorldTierUnlocked", "RiftPhase" }

type State = { done: { [string]: boolean }, tries: { [string]: number }, pending: boolean }
local states: { [Player]: State } = {}

local function stateOf(player: Player): State?
	if not player.Parent then
		return nil
	end
	local s = states[player]
	if not s then
		s = { done = {}, tries = {}, pending = false }
		states[player] = s
	end
	return s
end

-- Awards one badge (async). Returns true when a BadgeService call was started.
function Badges.give(player: Player, key: string): boolean
	local s = stateOf(player)
	local id = Rules.idFor(key, Badges.ids)
	if not s or id == 0 or s.done[key] or (s.tries[key] or 0) >= MAX_TRIES then
		return false
	end
	s.done[key] = true -- booked before the call: two triggers in a row make one call
	task.spawn(function()
		local ok, err = pcall(Badges.award, player.UserId, id)
		if not ok then
			warn(string.format("[Badges] %s for %d failed: %s", key, player.UserId, tostring(err)))
			local now = states[player]
			if now == s then
				s.done[key] = nil
				s.tries[key] = (s.tries[key] or 0) + 1
			end
		end
	end)
	return true
end

local function giveAll(player: Player, keys: { string })
	for _, key in keys do
		Badges.give(player, key)
	end
end

-- Progress badges only for a real hero (set up, not touched by a test command)
local function realHero(player: Player): any?
	local profile = Data.get(player)
	if not profile or not profile.setupDone or profile.debugged then
		return nil
	end
	return profile
end

-- Reads the hero facts now and awards every fact badge they reach
function Badges.check(player: Player)
	local profile = realHero(player)
	if profile then
		giveAll(player, Rules.fromFacts(JourneyRules.facts(profile)))
	end
end

-- Checks after a short delay (collects bursts of attribute changes)
function Badges.touch(player: Player)
	local s = stateOf(player)
	if not s or s.pending then
		return
	end
	s.pending = true
	task.delay(CHECK_DELAY, function()
		s.pending = false
		if player.Parent then
			Badges.check(player)
		end
	end)
end

local function onPlayer(player: Player)
	if not Data.waitForAccount(player) or not player.Parent then
		return
	end
	local now = Badges.clock()
	giveAll(player, Rules.onJoin(SeasonRules.Current.id, SeasonRules.phase(now) == "live"))
	for _, name in WATCHED do
		player:GetAttributeChangedSignal(name):Connect(function()
			Badges.touch(player)
		end)
	end
	player:GetAttributeChangedSignal("SetupDone"):Connect(function()
		Badges.touch(player)
	end)
	Badges.touch(player)
end

local function isPlayer(v: any): boolean
	return typeof(v) == "Instance" and v:IsA("Player")
end

function Badges.init()
	Actions.Event.Event:Connect(function(player: any, kind: any)
		if isPlayer(player) and realHero(player) then
			giveAll(player, Rules.fromAction(kind))
			Badges.touch(player)
		end
	end)
	Loot.Picked.Event:Connect(function(player: any, _gold: any, item: any)
		if isPlayer(player) and typeof(item) == "table" and realHero(player) then
			giveAll(player, Rules.fromPickup(item.rarity))
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

function Badges.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Badges
