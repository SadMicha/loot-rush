--!strict
-- Einfache Drossel je Spieler und Schlüssel (Token-Bucket): schützt Remotes vor Spam.
--   local limit = RateLimit.new(5, 10) -- 5 Anfragen pro Sekunde, Spitze 10
--   if not limit(player) then return end

local Players = game:GetService("Players")

local RateLimit = {}

function RateLimit.new(perSecond: number, burst: number): (player: Player) -> boolean
	local buckets: { [Player]: { tokens: number, stamp: number } } = {}
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
	return function(player: Player): boolean
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = { tokens = burst, stamp = now }
			buckets[player] = b
		end
		b.tokens = math.min(burst, b.tokens + (now - b.stamp) * perSecond)
		b.stamp = now
		if b.tokens < 1 then
			return false
		end
		b.tokens -= 1
		return true
	end
end

return RateLimit
