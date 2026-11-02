--!strict
-- Rift variants (docs/RIFT-VARIANTS.md): each depth from FROM_DEPTH on may roll a twist.
--   swarm      – many more, weaker enemies
--   elite_hunt – every wave opens with elites
--   goblin     – a Treasure Goblin flees through the first wave: catch it for a gold shower
--   timed      – clear the depth within the time limit for bonus items from the boss
-- Rolled by Systems/Rift per depth; attribute RiftVariant on the player ("" = normal).

export type Variant = {
	id: string,
	name: string, -- English, shown in the HUD
	text: string,
	weight: number,
}

local RiftVariants = {}

RiftVariants.FROM_DEPTH = 3 -- the first depths stay plain (onboarding)
RiftVariants.NORMAL_WEIGHT = 55 -- weight of "no variant"

RiftVariants.List = table.freeze({
	{ id = "swarm", name = "Swarm", text = "Twice the enemies, half their life", weight = 12 },
	{ id = "elite_hunt", name = "Elite Hunt", text = "Every wave brings elites", weight = 12 },
	{
		id = "goblin",
		name = "Treasure Goblin",
		text = "Catch the goblin before it escapes",
		weight = 11,
	},
	{
		id = "timed",
		name = "Against the Clock",
		text = "Clear in time for bonus loot",
		weight = 10,
	},
} :: { Variant })

local byId: { [string]: Variant } = {}
for _, v in RiftVariants.List do
	byId[v.id] = v
end
RiftVariants.ById = table.freeze(byId)

-- Tuning
RiftVariants.SWARM_COUNT = 2 -- enemy count factor
RiftVariants.SWARM_HEALTH = 0.5 -- enemy life factor
RiftVariants.GOBLIN_TIME = 18 -- seconds before the goblin escapes
RiftVariants.GOBLIN_GOLD = 25 -- gold factor of the goblin
RiftVariants.GOBLIN_HEALTH = 3 -- life factor
RiftVariants.GOBLIN_SPEED = 1.3 -- flees a bit faster than it chases
RiftVariants.TIMED_LIMIT = 75 -- seconds for the whole depth (waves and boss)
RiftVariants.TIMED_ITEMS = 3 -- bonus items (Rare or better) on success

-- Variant id for a depth ("" = normal); rng: Random
function RiftVariants.roll(rng: Random, depth: number): string
	if depth < RiftVariants.FROM_DEPTH then
		return ""
	end
	local total = RiftVariants.NORMAL_WEIGHT
	for _, v in RiftVariants.List do
		total += v.weight
	end
	local pick = rng:NextNumber() * total
	if pick < RiftVariants.NORMAL_WEIGHT then
		return ""
	end
	pick -= RiftVariants.NORMAL_WEIGHT
	for _, v in RiftVariants.List do
		if pick < v.weight then
			return v.id
		end
		pick -= v.weight
	end
	return ""
end

return table.freeze(RiftVariants)
