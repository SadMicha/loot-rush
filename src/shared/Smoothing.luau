--!strict
-- The Smoothing (docs/IDEAS.md #6, docs/SMOOTHING.md): a grey, glossy force that erases studs.
-- Its creatures are smooth, studless plastic; untouched regions are partly smoothed too.
-- Clearing depths restores studs and colour: the more depths of a region a player has cleared
-- (profile.atlas, the best depth per region), the fewer smoothed enemies and arena parts.
-- Bosses are famous builders the Smoothing got to; each one gets an intro line.

local Smoothing = {}

Smoothing.SPAN = 5 -- depths per region until it counts as fully restored
Smoothing.ARENA_MAX = 0.45 -- share of arena decoration smoothed in an untouched region
Smoothing.ENEMY_MIN = 0.1 -- smoothed enemy chance in a fully restored region
Smoothing.ENEMY_MAX = 0.5 -- … and in an untouched one
Smoothing.HEALTH = 1.25 -- smoothed enemies are a bit tougher
Smoothing.REWARD = 1.5 -- … and pay more XP and gold
Smoothing.GREY = Color3.fromRGB(176, 180, 188) -- the Smoothing's colour
Smoothing.FADE = 0.65 -- how far a smoothed part's colour moves toward GREY

-- Boss intro lines (shown when the boss appears)
Smoothing.BossIntro = table.freeze({
	green_plains = "The Crystal King once built these hills. Now he only polishes.",
	crystal_caves = "The Shard Worm carved every cave. The Smoothing filed its teeth flat.",
	mushroom_swamp = "The Spore Mother planted the first studs. She forgot why.",
	fire_desert = "The Furnace Lord forged bricks for the world. Now he melts them.",
	sky_islands = "The Cloud Queen stacked the sky. The Smoothing wants it clean.",
	altered_world = "The Rift: where the Smoothing began. Every stud here is a battle.",
} :: { [string]: string })

-- How far a region is restored, 0 (untouched) .. 1 (restored), from the player's best depth there
function Smoothing.restored(regionStartDepth: number, bestDepth: number): number
	if bestDepth < regionStartDepth then
		return 0
	end
	return math.clamp((bestDepth - regionStartDepth + 1) / Smoothing.SPAN, 0, 1)
end

-- Share of arena decoration that is smoothed
function Smoothing.arenaShare(restored: number): number
	return Smoothing.ARENA_MAX * (1 - math.clamp(restored, 0, 1))
end

-- Chance that a rift enemy belongs to the Smoothing
function Smoothing.enemyChance(restored: number): number
	local r = math.clamp(restored, 0, 1)
	return Smoothing.ENEMY_MAX + (Smoothing.ENEMY_MIN - Smoothing.ENEMY_MAX) * r
end

-- The smoothed colour of a part colour
function Smoothing.fade(c: Color3): Color3
	return c:Lerp(Smoothing.GREY, Smoothing.FADE)
end

return table.freeze(Smoothing)
