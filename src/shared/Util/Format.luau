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

-- Thousands separators: 1240 → "1,240"
function Format.int(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

return Format
