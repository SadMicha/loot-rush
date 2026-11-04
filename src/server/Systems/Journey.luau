--!strict
-- Journey (Shared/Journey): permanent milestones of the active hero, read from the save (best
-- depth, World Tier, level, region bosses, guide quests, Star Web). The client only says "claim
-- <id>"; the server checks the milestone is finished and not claimed, then pays it once.
-- The state (facts + claimed ids) goes out after loading, on a claim, when the window asks, and
-- shortly after anything that can move a fact (attributes, player actions).
-- Journey.grant pays a reward table (also used by Systems/Seasons).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Journey)
local SpellStones = require(ReplicatedStorage.Shared.SpellStones)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Cosmetics = require(script.Parent.Cosmetics)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)
local Shop = require(script.Parent.Shop)

local Journey = {}

local SYNC_DELAY = 1 -- seconds: many fact changes in a row go out as one state
local WATCHED = { "Level", "BestDepth", "WorldTierUnlocked", "SetupDone", "CharacterName" }

local allow = RateLimit.new(4, 8)
local rng = Random.new()
local pending: { [Player]: boolean } = {}

-- Pays a reward to the active hero (gold, materials, spell stones) and the account (Soulstars,
-- cosmetics). Gold is scaled to the hero's best depth. Returns false without a loaded save.
function Journey.grant(player: Player, reward: Rules.Reward): boolean
	local profile = Data.get(player)
	if not profile or not Data.account(player) then
		return false
	end
	local r = Rules.scaled(reward, Atlas.bestDepth(profile.atlas))
	if (r.gold or 0) > 0 then
		Inventory.addGold(player, r.gold :: number)
	end
	local candy, shards, dust = r.candy or 0, r.shards or 0, r.dust or 0
	if candy + shards + dust > 0 then
		Progress.addMaterials(player, { candy = candy, shards = shards, dust = dust })
	end
	for _ = 1, r.stones or 0 do
		local id = SpellStones.roll(rng)
		profile.progress.stones[id] = (profile.progress.stones[id] or 0) + 1
	end
	Progress.sync(player)
	if (r.soulstars or 0) > 0 then
		Shop.grant(player, "soulstars", r.soulstars :: number)
	end
	if r.cosmetic then
		Cosmetics.give(player, r.cosmetic)
		Cosmetics.sync(player)
	end
	return true
end

-- Facts of the active hero (nil without a save)
function Journey.facts(player: Player): Rules.Facts?
	local profile = Data.get(player)
	return if profile then Rules.facts(profile) else nil
end

function Journey.state(player: Player): { [string]: any }?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	local claimed = {}
	for id in profile.journey do
		table.insert(claimed, id)
	end
	table.sort(claimed)
	return { facts = Rules.facts(profile), claimed = claimed }
end

function Journey.sync(player: Player, paid: string?)
	pending[player] = nil
	local state = Journey.state(player)
	if state then
		state.paid = paid
		Net.JourneyState:FireClient(player, state)
	end
end

-- Sends the state once after a short delay (collects bursts of changes)
function Journey.touch(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(SYNC_DELAY, function()
		if pending[player] and player.Parent then
			Journey.sync(player)
		end
		pending[player] = nil
	end)
end

-- Claims a finished milestone; returns its id or nil (unknown, open, claimed, no save/hero)
function Journey.claim(player: Player, id: any): string?
	local profile = Data.get(player)
	if not profile or not profile.setupDone or typeof(id) ~= "string" then
		return nil
	end
	if not Rules.canClaim(id, Rules.facts(profile), profile.journey) then
		return nil
	end
	local ms = Rules.ById[id]
	profile.journey[id] = true -- booked before paying: a failed grant can never be claimed twice
	Journey.grant(player, ms.reward)
	return id
end

local function onPlayer(player: Player)
	if not Data.waitFor(player) or not player.Parent then
		return
	end
	for _, name in WATCHED do
		player:GetAttributeChangedSignal(name):Connect(function()
			Journey.touch(player)
		end)
	end
	Journey.sync(player)
end

function Journey.init()
	Net.Journey.OnServerEvent:Connect(function(player: Player, action: any, id: any)
		if not allow(player) then
			return
		end
		if action == "claim" then
			Journey.sync(player, Journey.claim(player, id))
		elseif action == "sync" then
			Journey.sync(player)
		end
	end)
	Actions.Event.Event:Connect(function(player: any)
		if typeof(player) == "Instance" and player:IsA("Player") then
			Journey.touch(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
end

function Journey.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Journey
