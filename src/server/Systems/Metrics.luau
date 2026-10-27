--!strict
-- Messung für Balancing und Performance (M5).
--  • Lauf-Berichte: Dauer, Kills, erlittener Schaden, Level-Gewinn pro Rift-Abschnitt (Output + workspace "LastReport")
--  • Server-Gesundheit: einmal pro Sekunde als workspace-Attribute (ServerFrameMs, ServerSendKbps, ServerEnemies)
-- Rift ruft begin() / report(); der Rest kommt über Combat-Events und Heartbeat.

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

local SAMPLE = 1 -- Sekunden zwischen Server-Messungen

local window: Window? = nil
local frames = 0
local frameSum = 0
local frameMax = 0

-- Stats-Werte sind nicht überall verfügbar → defensiv lesen
local function stat(name: string): number?
	local ok, value = pcall(function()
		return (Stats :: any)[name]
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return nil
end

-- Neuer Messabschnitt (Rift-Start, nächste Tiefe)
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

-- Schließt den Abschnitt ab: Zeile in den Output und ins workspace-Attribut "LastReport"
function Metrics.report(label: string)
	local w = window
	if not w then
		return
	end
	window = nil
	local level = (w.player:GetAttribute("Level") or w.level) :: number
	local line = string.format(
		"%s · %d s · %d Kills · %d Schaden (%d Treffer) · Level %d→%d · Gegner max %d",
		label,
		math.floor(os.clock() - w.startedAt + 0.5),
		w.kills,
		w.damage,
		w.hits,
		w.level,
		level,
		w.peak
	)
	print("[LootRush][Messung] " .. line)
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
