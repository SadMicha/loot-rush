--!strict
-- Number format for big incremental numbers: 950 · 12.4K · 3.1M · 870B · 42T · 1.2aa …

local Format = {}

local SUFFIX = { "", "K", "M", "B", "T", "aa", "ab", "ac", "ad", "ae" }

function Format.big(n: number): string
	if n < 1000 then
		return tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIX - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text = if scaled >= 100
		then string.format("%d", math.floor(scaled))
		else string.format("%.1f", scaled)
	return text .. SUFFIX[tier + 1]
end

-- Currency amounts (gold, crystal shards, soulstars, materials) in EVERY window: balances, prices
-- and rewards alike. Whole below 1,000, compact above like Format.big, without a trailing ".0":
-- 950 · 1K · 1.2K · 8.1K · 250K · 1.2M
function Format.currency(n: number): string
	if n ~= n then
		return "0"
	end
	if n < 0 then
		return "-" .. Format.currency(-n)
	end
	local text = Format.big(n)
	return (text:gsub("%.0(%a+)$", "%1"))
end

-- Thousands separators (counts that are not currency: item power, kills, points): 1240 → "1,240"
function Format.int(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

return Format
