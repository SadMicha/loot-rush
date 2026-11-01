--!strict
-- Metrics for balancing and performance (M5).
--  • Run reports: duration, kills, damage taken, levels gained per Rift section (Output + workspace "LastReport")
--  • Server health: once per second as workspace attributes (ServerFrameMs, ServerSendKbps, ServerEnemies)
-- Rift calls begin() / report(); the rest comes via combat events and Heartbeat.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Combat = require(script.Parent.Combat)

type Window = {
	player: Player,
	startedAt: number,
	level: number,
	kills: number,
	hits: number,
	damage: number,
	peak: number,
}

local Metrics = {}

local SAMPLE = 1 -- seconds between server samples

local window: Window? = nil
local frames = 0
local frameSum = 0
local frameMax = 0

-- Stats values are not available everywhere → read defensively
local function stat(name: string): number?
	local ok, value = pcall(function()
		return (Stats :: any)[name]
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return nil
end

-- New measurement section (Rift start, next depth)
function Metrics.begin(player: Player)
	window = {
		player = player,
		startedAt = os.clock(),
		level = (player:GetAttribute("Level") or 1) :: number,
		kills = 0,
		hits = 0,
		damage = 0,
		peak = 0,
	}
end

-- Closes the section: a line in the Output and in the workspace attribute "LastReport"
function Metrics.report(label: string)
	local w = window
	if not w then
		return
	end
	window = nil
	local level = (w.player:GetAttribute("Level") or w.level) :: number
	local line = string.format(
		"%s · %d s · %d kills · %d damage (%d hits) · level %d→%d · enemies max %d",
		label,
		math.floor(os.clock() - w.startedAt + 0.5),
		w.kills,
		w.damage,
		w.hits,
		w.level,
		level,
		w.peak
	)
	print("[LootRush][Metrics] " .. line)
	workspace:SetAttribute("LastReport", line)
end

function Metrics.init()
	Combat.EnemyKilled.Event:Connect(function(player: any)
		local w = window
		if w and player == w.player then
			w.kills += 1
		end
	end)
	Combat.PlayerHurt.Event:Connect(function(player: any, amount: any)
		local w = window
		if w and player == w.player and typeof(amount) == "number" then
			w.hits += 1
			w.damage += amount
		end
	end)
end

function Metrics.start()
	RunService.Heartbeat:Connect(function(dt: number)
		frames += 1
		frameSum += dt
		frameMax = math.max(frameMax, dt)
	end)

	while true do
		task.wait(SAMPLE)
		local enemies = #CollectionService:GetTagged("Enemy")
		if window then
			window.peak = math.max(window.peak, enemies)
		end
		if frames > 0 then
			workspace:SetAttribute(
				"ServerFrameMs",
				math.floor(frameSum / frames * 10000 + 0.5) / 10
			)
			workspace:SetAttribute("ServerFrameMaxMs", math.floor(frameMax * 10000 + 0.5) / 10)
		end
		workspace:SetAttribute("ServerEnemies", enemies)
		local sent = stat("DataSendKbps")
		if sent then
			workspace:SetAttribute("ServerSendKbps", math.floor(sent + 0.5))
		end
		frames, frameSum, frameMax = 0, 0, 0
	end
end

return Metrics
