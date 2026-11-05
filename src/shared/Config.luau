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
	DASH_SKIN = 2.5, -- studs ahead of the body a dash stops in front of a wall (no ramming into parts)
	DASH_LOW = 1.6, -- the low wall probe runs this far below the root (railings, ledges)
	DASH_HIGH = 1.5, -- the high wall probe runs this far above the root (overhangs, head height)
	DASH_MAX_RISE = 8, -- studs per second a dash may lift the character (stairs yes, popping onto walls no)
	-- Server movement check (Systems/Movement): speed/teleport hacks get pulled back
	MOVE_SAMPLE = 0.25, -- seconds between position samples
	MOVE_SLACK = 1.35, -- walk speed factor allowed (lag, slopes, knockback)
	MOVE_GRACE = 4, -- studs per sample on top (replication jitter)
	-- seconds after a server teleport in which samples only re-base: the owning client keeps sending
	-- its old position until the teleport reaches it (ping), which must never anchor a pull-back
	MOVE_TELEPORT_SETTLE = 2,
	HINT_SKILL_RANGE = 35, -- studs: the first enemy this close shows the skills hint
	HINT_TELEGRAPH_RANGE = 40, -- studs: the first enemy telegraph this close shows the dodge hint
	HINT_CALM_RANGE = 20, -- studs: hints wait until no enemy is this close (and no telegraph near)
	HINT_RUSH_AT = 0.5, -- Rush meter share that queues the Rush hint
	HINT_SHOW_TIME = 8, -- seconds a hint callout stays up unless the player acts or taps it
	HINT_MIN_SEEN = 1.5, -- seconds on screen before a hint counts as seen when it closes by itself
	HINT_HIDDEN_GIVE_UP = 1, -- seconds the target may be hidden before the callout closes
	WAYPOINT_HIDE = 14, -- studs from the quest station where the waypoint beam and marker hide
	MOVE_BURST = 40, -- studs of extra distance banked for dashes (refills over DASH_RECHARGE)

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
	HUB_TOP = 15, -- root higher than this above the Hub floor = on a roof or cliff, back to spawn
	-- Never fall off a map: invisible walls around every map (Util/Fence) + FallGuard rescue
	BOUNDARY_HEIGHT = 200, -- studs of invisible wall, starting FALL_DEPTH below the floor
	BOUNDARY_THICK = 8, -- studs; thick enough that no dash or physics step tunnels through
	FALL_DEPTH = 20, -- this far below the map floor = fallen, back to a safe spot
	FALL_MARGIN = 3, -- studs outside the walls before the server guard steps in
	BOUNDS_REACH = 40, -- up to this far outside a map the player is pushed back to the edge
	BOUNDS_PAD = 1.5, -- studs inside the edge where a pushed-back player lands
	BOUNDS_SNAP = 120, -- client: past BOUNDS_REACH but this close to the last spot inside = back there
	BOUNDS_DROP = 6, -- push back only down to this far below map level (river, pools); lower = full rescue
	FALL_TICK = 0.1, -- seconds between guard checks (the authoritative Hub/map clamp)

	-- Combat (player)
	RESPAWN_TIME = 3,
	RIFT_REVIVES = 1, -- deaths per Rift depth that respawn you at the last waypoint instead of failing
	RIFT_REVIVE_GRACE = 10, -- seconds after RESPAWN_TIME a revive waits for the new character
	STREAM_AROUND_TIMEOUT = 2, -- seconds a teleport waits for the target area to stream in
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
	RIFT_REENTER_DELAY = 0.4, -- seconds after a run ends in which "enter" is ignored (double taps)
	RIFT_SLOTS = 12, -- this many Rifts run at once on a server (one per player)
	ARENA_SPACING = 1000, -- studs between arena slots along +X (slot 1 at the origin); no map sees the next

	-- Loot: level, gold, drop chance and rarity per depth from Shared/Balance
	LOOT_BOSS_ILVL = 1, -- boss items are this many levels (10 IP each) higher (own assumption)
	LOOT_BOSS_GOLD_DROPS = 5, -- boss gold split across this many coins

	-- Stash in the hub (Shared/Stash, Systems/Stash): account-wide storage shared by all heroes
	STASH_TABS = 4, -- tabs of the stash
	STASH_TAB_SLOTS = 42, -- items per tab (7 × 6 grid, the most that stays tappable on phones)
	STASH_RANGE = 24, -- studs from the stash station a move is allowed (the prompt reaches 12)
})
