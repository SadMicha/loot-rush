--!strict
-- All tunable game values in one place.
-- Note: replicated to clients - nothing secret here, and the server
-- never trusts a value the client reports.

return table.freeze({
	-- Combat/calm state (drives the UI flying in and out)
	COMBAT_RADIUS = 40, -- studs: enemies in this radius = combat
	CALM_DELAY = 3, -- seconds without combat until "calm"
	COMBAT_TICK = 0.25, -- seconds between server checks

	-- Camera (isometric ARPG camera)
	CAMERA_PITCH = 52, -- degrees from above
	CAMERA_YAW = 20, -- degrees around the vertical axis (0 = facing north)
	CAMERA_DISTANCE = 46,
	CAMERA_MIN_DISTANCE = 26,
	CAMERA_MAX_DISTANCE = 72,
	CAMERA_SMOOTHING = 12, -- higher = more direct

	-- Movement
	WALK_SPEED = 20,
	DASH_SPEED = 72, -- studs per second during the dash
	DASH_DURATION = 0.2,
	DASH_CHARGES = 2,
	DASH_RECHARGE = 2.5, -- seconds per charge

	-- World
	TILE_SIZE = 8,
	ARENA_TILES_X = 17, -- tiles per region arena (same grid in all regions)
	ARENA_TILES_Z = 15,
	-- Rift Trail (Shared/Trail): start → corridor → clearings with packs → boss arena
	TRAIL_CLEARINGS = 3, -- clearings per depth, one enemy pack each (shown as "Area 1/3")
	TRAIL_CLEARING = 8, -- tiles per clearing side
	TRAIL_CORRIDOR = 3, -- tiles of corridor between two clearings
	TRAIL_CORRIDOR_WIDTH = 3, -- tiles across a corridor
	TRAIL_SWAY = 3, -- tiles a clearing may shift sideways (winding path)
	HUB_HALF = 80, -- half size of the walkable Hub plan (20 cells × 8 studs)
	-- Never fall off a map: invisible walls around every map (Util/Fence) + FallGuard rescue
	BOUNDARY_HEIGHT = 200, -- studs of invisible wall, starting FALL_DEPTH below the floor
	BOUNDARY_THICK = 8, -- studs; thick enough that no dash or physics step tunnels through
	FALL_DEPTH = 20, -- this far below the map floor = fallen, back to a safe spot
	FALL_MARGIN = 3, -- studs outside the walls before the server guard steps in
	BOUNDS_REACH = 40, -- up to this far outside a map the player is pushed back to the edge
	BOUNDS_PAD = 1.5, -- studs inside the edge where a pushed-back player lands
	BOUNDS_DROP = 6, -- push back only down to this far below map level (river, pools); lower = full rescue
	FALL_TICK = 0.25, -- seconds between guard checks

	-- Combat (player)
	RESPAWN_TIME = 3,
	DASH_IFRAMES = 0.3, -- seconds of invulnerability per dash (checked by the server)
	CRIT_CHANCE = 0.1,
	CRIT_MULT = 2,
	-- No caps on StatSpeed / StatCrit. Crit chance above 100% overcrits (see Shared/Crit).
	-- Life per level, XP curve, enemy, gold and loot values per depth: Shared/Balance (table)
	DAMAGE_PER_LEVEL = 0.02, -- +2% damage per level (own assumption; the table scales via the weapon)

	-- Enemies
	ENEMY_ZONE = Vector3.new(0, 0, -20), -- center of the spawn area
	ENEMY_ZONE_RADIUS = 16,
	AGGRO_RADIUS = 75, -- a pack notices the player early and closes in (was 45, docs/balancing.md)

	-- Metrics (M5): debug overlay with F3 or the "Dbg" button bottom left
	DEBUG_OVERLAY = true,

	-- Rift (waves → boss → deeper or back)
	RIFT_START = Vector3.new(0, 4, 16), -- the player lands here on entering
	HUB_ORIGIN = Vector3.new(-1200, 0, 0), -- center of the Hub map "Lumenhaven" (far from every arena)
	HUB_POS = Vector3.new(-1200, 4, 60), -- spawn in the Hub and return from the Rift
	RIFT_WAVES = 3, -- waves before the boss
	RIFT_WAVE_BASE = 6, -- enemies in wave 1 at depth 1
	RIFT_WAVE_STEP = 2, -- extra enemies per wave and per depth
	RIFT_WAVE_MAX = 24, -- cap on enemies per wave (server/network load at high depth)
	RIFT_WAVE_PAUSE = 1.5, -- seconds between waves
	RIFT_ELITES = 2, -- elites per depth: one each in the last waves (spreadsheet: 3 per 150 enemies)
	RIFT_SLOTS = 12, -- this many Rifts run at once on a server (one per player)
	ARENA_SPACING = 1000, -- studs between arena slots along +X (slot 1 at the origin); no map sees the next

	-- Loot: level, gold, drop chance and rarity per depth from Shared/Balance
	LOOT_BOSS_ILVL = 1, -- boss items are this many levels (10 IP each) higher (own assumption)
	LOOT_BOSS_GOLD_DROPS = 5, -- boss gold split across this many coins
})
