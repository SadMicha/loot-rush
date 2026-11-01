--!strict
-- Simple throttle per player and key (token bucket): protects remotes from spam.
--   local limit = RateLimit.new(5, 10) -- 5 requests per second, burst 10
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
