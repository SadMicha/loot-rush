--!strict
-- Village on the server (rules: Shared/Village). Buildings produce in real time while the player
-- is online and at the offline rate for the time away (capped, game pass "offline_2x" doubles
-- the cap). Upgrades cost gold and are validated here; the client only sends the building id.
--   Village      (C→S): "upgrade", buildingId
--   VillageState (S→C): { levels, rates, offline? = { seconds, pay } }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Village)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Monetization = require(script.Parent.Monetization)
local Shop = require(script.Parent.Shop)

local Village = {}

local TICK = 5 -- seconds between payouts while online
local MAX_TICK_GAP = 60 -- a stalled server never pays more than this per tick

local allow = RateLimit.new(4, 8)
local ready: { [Player]: boolean } = {}

local function pay(player: Player, amounts: { [string]: number })
	for resource, n in amounts do
		Shop.grant(player, resource, n)
	end
end

local function send(player: Player, data: Rules.Data, offline: { [string]: any }?)
	Net.VillageState:FireClient(player, {
		levels = data.levels,
		rates = Rules.rates(data),
		offline = offline,
	})
end

-- Pays the production since the last tick (online rate)
local function tick(player: Player, now: number)
	local profile = Data.get(player)
	if not profile or not ready[player] then
		return
	end
	local data = profile.village
	local seconds = math.clamp(now - data.seen, 0, MAX_TICK_GAP)
	data.seen = now
	pay(player, Rules.produce(data, seconds))
end

local function onUpgrade(player: Player, action: any, id: any)
	if not allow(player) or action ~= "upgrade" or typeof(id) ~= "string" then
		return
	end
	local profile = Data.get(player)
	local building = Rules.ById[id]
	if not profile or not building or not ready[player] then
		return
	end
	local data = profile.village
	local level = Rules.level(data, id)
	local cost = Rules.cost(building, level)
	if not cost or profile.gold < cost then
		return
	end
	tick(player, os.time()) -- pay the old rate up to now
	Shop.grant(player, "gold", -cost)
	data.levels[id] = level + 1
	send(player, data)
	Actions.fire(player, "village")
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	local data = profile.village
	local now = os.time()
	-- ownership check may still run: the saved buffer (profile.passes) counts too
	local hasPass = Monetization.owns(player, "offline_2x") or profile.passes.offline_2x == true
	local seconds = Rules.offlineSeconds(data.seen, now, hasPass)
	local amounts = Rules.produce(data, seconds)
	data.seen = now
	ready[player] = true
	pay(player, amounts)
	send(
		player,
		data,
		if next(amounts)
			then { seconds = math.floor(seconds / Rules.OFFLINE_RATE), pay = amounts }
			else nil
	)
end

-- Observatory: Soulstar bonus in percent (Systems/Rebirth)
function Village.soulstarBonus(player: Player): number
	local profile = Data.get(player)
	return if profile then Rules.soulstarBonus(profile.village) else 0
end

function Village.init()
	Net.Village.OnServerEvent:Connect(onUpgrade)
	Players.PlayerRemoving:Connect(function(player: Player)
		tick(player, os.time())
		ready[player] = nil
	end)
end

function Village.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
	while true do
		task.wait(TICK)
		local now = os.time()
		for player in ready do
			tick(player, now)
		end
	end
end

return Village
