--!strict
-- Permanent percent bonuses from several sources (pets, game passes) in one place.
-- Every source registers via Boosts.source and returns { [stat]: percent }; the sum ends up as a
-- player attribute read by combat, loot and UI:
--   BonusDamage (damage %), BonusLife (max. life %), BonusGold (gold %), BonusXP (XP %),
--   BonusItems (item chance %), BonusMagnet (extra pickup radius in studs)
-- Call Boosts.refresh(player) after every change to a source.

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
	magnet = "BonusMagnet",
} :: { [string]: string })

local sources: { [string]: Source } = {}

-- Register a source (name only to tell them apart, same name replaces)
function Boosts.source(name: string, fn: Source)
	sources[name] = fn
end

-- Sum of all sources (also for tests)
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
			warn("[Boosts] source " .. name .. " failed:", bonus)
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

-- Factor for a value (1 + percent / 100), reads the attribute
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
