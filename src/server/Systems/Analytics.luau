--!strict
-- Analytics facade (docs/ROADMAP.md N10, D2): Roblox AnalyticsService only, for the Creator Hub
-- dashboards (onboarding funnel, progression, custom events). UserId only (the service adds it),
-- never names or free text, never per hit. Every call is pcall'd: analytics must never break play.
--   • Onboarding funnel: 1 "joined" (first join, hero not set up yet), 2 "hero_created" (setup
--     done), then one step per finished guide quest (Systems/Quests: step = chain index + 2).
--   • Progression "Rift": start / complete / fail per depth, level = depth, levelName = region id.
--     Leaving mid-depth is not a fail (only a death without revives is).
--   • Custom event "LevelUp" (value = new hero level), logged by Combat when XP crosses a level
--     (not on the Level attribute: the join restore writes it too).
--   • Economy: Gold, Shards, Soulstars with transaction type (Enum.AnalyticsEconomyTransactionType
--     name: Onboarding, TimedReward, Gameplay, Shop, IAP) and a short sku. Rift gold is logged once
--     per run (Systems/Rift), never per pickup; salvage shards are pooled (Analytics.pool). Callers pass the txn to
--     Inventory.addGold / Progress.addMaterials / Shop.grant; no txn = not logged.
-- Analytics.recent keeps the last events (tests, debug); nothing else reads it.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Data = require(script.Parent.Data)

local Analytics = {}

Analytics.FUNNEL_JOINED = 1
Analytics.FUNNEL_HERO = 2
Analytics.FUNNEL_QUESTS = 3 -- funnel step of the first guide quest
Analytics.RIFT_PATH = "Rift"

local RECENT = 50

export type Entry = { kind: string, userId: number, step: number?, name: string?, value: number? }

Analytics.recent = {} :: { Entry }

local POOL_FLUSH = 60 -- seconds between flushes of pooled economy flows (salvage)

-- Depth of the player's Rift depth that started and has not ended yet
local open: { [Player]: number } = {}

local function remember(entry: Entry)
	table.insert(Analytics.recent, entry)
	if #Analytics.recent > RECENT then
		table.remove(Analytics.recent, 1)
	end
end

local function call(method: string, ...: any)
	local args = table.pack(...)
	pcall(function()
		(AnalyticsService :: any)[method](AnalyticsService, table.unpack(args, 1, args.n))
	end)
end

function Analytics.funnel(player: Player, step: number, name: string)
	remember({ kind = "funnel", userId = player.UserId, step = step, name = name })
	call("LogOnboardingFunnelStepEvent", player, step, name)
end

-- Guide quest at chain index `index` finished
function Analytics.quest(player: Player, index: number, id: string)
	Analytics.funnel(player, Analytics.FUNNEL_QUESTS + index - 1, id)
end

function Analytics.riftStart(player: Player, depth: number, region: string)
	open[player] = depth
	remember({ kind = "rift_start", userId = player.UserId, value = depth, name = region })
	call("LogProgressionStartEvent", player, Analytics.RIFT_PATH, depth, region)
end

function Analytics.riftClear(player: Player, depth: number, region: string)
	open[player] = nil
	remember({ kind = "rift_clear", userId = player.UserId, value = depth, name = region })
	call("LogProgressionCompleteEvent", player, Analytics.RIFT_PATH, depth, region)
end

-- Run ended: a fail only when it ended by death while a depth was still open
function Analytics.riftEnd(player: Player, failed: boolean, region: string)
	local depth = open[player]
	open[player] = nil
	if depth and failed then
		remember({ kind = "rift_fail", userId = player.UserId, value = depth, name = region })
		call("LogProgressionFailEvent", player, Analytics.RIFT_PATH, depth, region)
	end
end

-- One economy flow: amount > 0 = source, < 0 = sink; balance = after the change
function Analytics.economy(
	player: Player,
	currency: string,
	amount: number,
	balance: number,
	txn: string,
	sku: string?
)
	if amount == 0 or amount ~= amount then
		return
	end
	remember({
		kind = "economy",
		userId = player.UserId,
		name = currency .. ":" .. txn,
		value = amount,
	})
	pcall(function()
		local flow = if amount > 0
			then Enum.AnalyticsEconomyFlowType.Source
			else Enum.AnalyticsEconomyFlowType.Sink
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			currency,
			math.abs(amount),
			math.max(0, balance),
			txn,
			sku
		)
	end)
end

-- Frequent small flows (salvage shards): summed per player and logged every POOL_FLUSH seconds
-- and when the player leaves, so auto-salvage does not send one event per item
type Pool = { currency: string, amount: number, balance: number, txn: string, sku: string? }
local pools: { [Player]: { [string]: Pool } } = {}

function Analytics.pool(
	player: Player,
	currency: string,
	amount: number,
	balance: number,
	txn: string,
	sku: string?
)
	if amount == 0 or amount ~= amount then
		return
	end
	local mine = pools[player] or {}
	pools[player] = mine
	local key = currency .. ":" .. txn .. ":" .. (sku or "")
	local p = mine[key]
	if p then
		p.amount += amount
		p.balance = balance
	else
		mine[key] =
			{ currency = currency, amount = amount, balance = balance, txn = txn, sku = sku }
	end
end

function Analytics.flush(player: Player)
	local mine = pools[player]
	pools[player] = nil
	if mine then
		for _, p in mine do
			Analytics.economy(player, p.currency, p.amount, p.balance, p.txn, p.sku)
		end
	end
end

function Analytics.custom(player: Player, name: string, value: number)
	remember({ kind = "custom", userId = player.UserId, name = name, value = value })
	call("LogCustomEvent", player, name, value)
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile or not player.Parent then
		return
	end
	if not profile.setupDone then
		Analytics.funnel(player, Analytics.FUNNEL_JOINED, "joined")
	end
end

function Analytics.init() end

function Analytics.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		open[player] = nil
		Analytics.flush(player)
	end)
	while true do
		task.wait(POOL_FLUSH)
		for player in pools do
			Analytics.flush(player)
		end
	end
end

return Analytics
