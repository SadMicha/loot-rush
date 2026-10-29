--!strict
-- Dauerhafte Prozent-Boni aus mehreren Quellen (Wiedergeburt, Haustier, Gamepässe) an einem Ort.
-- Jede Quelle meldet sich mit Boosts.source an und liefert { [stat]: Prozent }; die Summe landet als
-- Player-Attribut, das Kampf, Beute und UI lesen:
--   BonusDamage (Schaden %), BonusLife (max. Leben %), BonusGold (Gold %), BonusXP (Erfahrung %),
--   BonusItems (Item-Chance %)
-- Nach jeder Änderung an einer Quelle Boosts.refresh(player) aufrufen.

local Players = game:GetService("Players")

local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)

local Boosts = {}

export type Bonus = { [string]: number }
type Source = (player: Player, profile: Data.Profile) -> Bonus

Boosts.Attr = table.freeze({
	damage = "BonusDamage",
	life = "BonusLife",
	gold = "BonusGold",
	xp = "BonusXP",
	items = "BonusItems",
} :: { [string]: string })

local sources: { [string]: Source } = {}

-- Quelle anmelden (name nur zur Unterscheidung, gleicher Name ersetzt)
function Boosts.source(name: string, fn: Source)
	sources[name] = fn
end

-- Summe aller Quellen (auch für Tests)
function Boosts.total(player: Player): Bonus
	local profile = Data.get(player)
	local sum: Bonus = {}
	for stat in Boosts.Attr do
		sum[stat] = 0
	end
	if not profile then
		return sum
	end
	for name, fn in sources do
		local ok, bonus = pcall(fn, player, profile)
		if ok and typeof(bonus) == "table" then
			for stat, pct in bonus do
				if sum[stat] and typeof(pct) == "number" and pct == pct then
					sum[stat] += pct
				end
			end
		elseif not ok then
			warn("[Boosts] Quelle " .. name .. " fehlgeschlagen:", bonus)
		end
	end
	return sum
end

function Boosts.refresh(player: Player)
	local sum = Boosts.total(player)
	for stat, attr in Boosts.Attr do
		player:SetAttribute(attr, sum[stat])
	end
	Combat.refreshStats(player, false)
end

-- Faktor für einen Wert (1 + Prozent / 100), liest das Attribut
function Boosts.mult(player: Player, stat: string): number
	local v = player:GetAttribute(Boosts.Attr[stat] or "")
	return 1 + (if typeof(v) == "number" then v else 0) / 100
end

function Boosts.start()
	local function onPlayer(player: Player)
		if Data.waitFor(player) then
			Boosts.refresh(player)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Boosts
