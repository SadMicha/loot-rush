--!strict
-- Metrics for balancing and performance (M5).
--  • Run reports: duration, kills, damage taken, levels gained per Rift section. One window per
--    player (several Rifts run at once); the line goes to the Output (with player and run) and
--    into the player attribute "LastReport". workspace "LastReport" keeps the newest line of any
--    player, prefixed with the name (debug overlay).
--  • Server health: once per second as workspace attributes (ServerFrameMs, ServerSendKbps, ServerEnemies)
-- Rift calls begin() / report(); the rest comes via combat events and Heartbeat.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Combat = require(script.Parent.Combat)

type Window = {
	run: number, -- run number (enemy attribute "Run")
	startedAt: number,
	level: number,
	kills: number,
	hits: number,
	damage: number,
	peak: number,
}

local Metrics = {}

local SAMPLE = 1 -- seconds between server samples

local windows: { [Player]: Window } = {}
local perRun: { [number]: number } = {} -- reused every sample: enemies alive per run
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

-- New measurement section of this player's run (Rift start, next depth)
function Metrics.begin(player: Player, run: number)
	windows[player] = {
		run = run,
		startedAt = os.clock(),
		level = (player:GetAttribute("Level") or 1) :: number,
		kills = 0,
		hits = 0,
		damage = 0,
		peak = 0,
	}
end

-- Open window of a player (for tests)
function Metrics.windowOf(player: Player): Window?
	return windows[player]
end

-- Closes the player's section: a line in the Output and in the attribute "LastReport"
function Metrics.report(player: Player, label: string)
	local w = windows[player]
	if not w then
		return
	end
	windows[player] = nil
	local level = (player:GetAttribute("Level") or w.level) :: number
	local line = string.format(
		"%s - %d s - %d kills - %d damage (%d hits) - level %d→%d - enemies max %d",
		label,
		math.floor(os.clock() - w.startedAt + 0.5),
		w.kills,
		w.damage,
		w.hits,
		w.level,
		level,
		w.peak
	)
	print(`[LootRush][Metrics] {player.Name} (run {w.run}): {line}`)
	if player.Parent then
		player:SetAttribute("LastReport", line)
	end
	workspace:SetAttribute("LastReport", `{player.Name}: {line}`)
end

function Metrics.init()
	Combat.EnemyKilled.Event:Connect(function(player: any)
		local w = if typeof(player) == "Instance" and player:IsA("Player")
			then windows[player]
			else nil
		if w then
			w.kills += 1
		end
	end)
	Combat.PlayerHurt.Event:Connect(function(player: any, amount: any)
		local w = if typeof(player) == "Instance" and player:IsA("Player")
			then windows[player]
			else nil
		if w and typeof(amount) == "number" and amount == amount then
			w.hits += 1
			w.damage += amount
		end
	end)
	-- Deferred so Rift's own PlayerRemoving can still close the window with a report first
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			windows[player] = nil
		end)
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
		local tagged = CollectionService:GetTagged("Enemy")
		if next(windows) then
			table.clear(perRun)
			for _, enemy in tagged do
				local run = enemy:GetAttribute("Run")
				if typeof(run) == "number" then
					perRun[run] = (perRun[run] or 0) + 1
				end
			end
			for _, w in windows do
				w.peak = math.max(w.peak, perRun[w.run] or 0)
			end
		end
		if frames > 0 then
			workspace:SetAttribute(
				"ServerFrameMs",
				math.floor(frameSum / frames * 10000 + 0.5) / 10
			)
			workspace:SetAttribute("ServerFrameMaxMs", math.floor(frameMax * 10000 + 0.5) / 10)
		end
		workspace:SetAttribute("ServerEnemies", #tagged)
		local sent = stat("DataSendKbps")
		if sent then
			workspace:SetAttribute("ServerSendKbps", math.floor(sent + 0.5))
		end
		frames, frameSum, frameMax = 0, 0, 0
	end
end

return Metrics
