--!strict
-- Analytics facade (docs/ROADMAP.md N10, D2): Roblox AnalyticsService only, for the Creator Hub
-- dashboards (onboarding funnel, progression, custom events). UserId only (the service adds it),
-- never names or free text, never per hit. Every call is pcall'd: analytics must never break play.
--   • Onboarding funnel: 1 "joined" (first join, hero not set up yet), 2 "hero_created" (setup
--     done), then one step per finished guide quest (Systems/Quests: step = chain index + 2).
--   • Progression "Rift": start / complete / fail per depth, level = depth, levelName = region id.
--     Leaving mid-depth is not a fail (only a death without revives is).
--   • Custom event "LevelUp" (value = new hero level).
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
	local last = player:GetAttribute("Level")
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local level = player:GetAttribute("Level")
		if typeof(level) == "number" and typeof(last) == "number" and level > last then
			Analytics.custom(player, "LevelUp", level)
		end
		last = level
	end)
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
	end)
end

return Analytics
