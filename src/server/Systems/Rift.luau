--!strict
-- Rift flow: choose a region (Atlas) → waves → boss → choice "deeper" or "back to the Hub".
-- Every region starts at its own depth and rolls its waves from its enemy mix
-- (Shared/Atlas). Cleared depths go into the save (atlas, per tier in reach) and unlock follow-up
-- regions; a new run resumes at the first depth not cleared yet (or a lower one the player picks).
-- Every player has their own Rift on their own arena slot (World, Config.RIFT_SLOTS);
-- enemies carry the run number and only count for their run. State lives as attributes on the
-- owner (see Types.luau), the client only reads. Leaving or aborting end the run. Dying inside a
-- trail costs one of Config.RIFT_REVIVES per depth: the player respawns at the last lit waypoint
-- (or the start pad) and the run goes on; dying without a revive left fails the run.
-- Along the way the server counts kills, XP, gold, items and materials and sends a summary
-- after every boss and at the end via Net.RiftResult (Shared/RiftRun) - data for the
-- reward screen. At the end, loot left lying around is collected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RiftRun = require(ReplicatedStorage.Shared.RiftRun)
local RiftVariants = require(ReplicatedStorage.Shared.RiftVariants)
local Smoothing = require(ReplicatedStorage.Shared.Smoothing)
local Trail = require(ReplicatedStorage.Shared.Trail)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local Analytics = require(script.Parent.Analytics)
local Combat = require(script.Parent.Combat)
local CombatState = require(script.Parent.CombatState)
local Data = require(script.Parent.Data)
local Loot = require(script.Parent.Loot)
local Metrics = require(script.Parent.Metrics)
local Movement = require(script.Parent.Movement)
local Enemies = require(script.Parent.Enemies)
local Leaderboard = require(script.Parent.Leaderboard)
local Progress = require(script.Parent.Progress)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local World = require(script.Parent.World)

type Run = {
	owner: Player,
	id: number, -- run number (enemy attribute "Run")
	slot: number, -- arena slot (World)
	center: Vector3, -- center of the arena
	region: Atlas.Region,
	depth: number, -- absolute depth (scales the enemies)
	depth0: number, -- depth the run started at (region start, or deeper when resumed)
	tier: number, -- World Tier (Shared/WorldTiers), chosen before the run
	wave: number,
	variant: string, -- rift variant of the current depth (Shared/RiftVariants, "" = normal)
	restored: number, -- The Smoothing: how far the owner restored this region (0..1)
	tally: RiftRun.Tally,
	died: RBXScriptConnection?,
	respawned: RBXScriptConnection?, -- waits for the new character after a death with a revive left
	revives: number, -- revives left in this depth (Config.RIFT_REVIVES)
	downed: boolean, -- dead and waiting for the respawn; the run keeps going
	checkpoint: Vector3?, -- last lit waypoint shrine (FallGuard puts the player back there)
	strikes: number, -- Movement strikes at run start: a run with a new strike never reaches a leaderboard
}

type EndReason = "left" | "abandoned" | "failed" | "gone"

local Rift = {
	forceVariant = nil :: string?, -- tests / debug: every depth gets this variant
}

local FAILED_SHOWN = 4 -- seconds "failed" stays in the HUD
local POLL = 0.3

local runs: { [Player]: Run } = {}
local slots: { [number]: Run } = {}
local nextId = 0
local rng = Random.new()

local function character(player: Player): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid then
		return model, root, humanoid
	end
	return nil, nil, nil
end

local function alive(r: Run): boolean
	if runs[r.owner] ~= r or not r.owner.Parent then
		return false
	end
	if r.downed then
		return true -- respawning: the packs wait, the run is not over
	end
	local _, _, humanoid = character(r.owner)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Best result per region (0 = never cleared)
local function bestOf(player: Player): (string) -> number
	local profile = Data.get(player)
	return function(id: string): number
		return if profile then profile.atlas[id] or 0 else 0
	end
end

-- Best values as attributes: AtlasBest_<id> per region and BestDepth (across all, shop prices)
function Rift.publishBest(player: Player)
	local best = bestOf(player)
	for _, region in Atlas.Regions do
		local depth = best(region.id)
		player:SetAttribute(Atlas.attr(region.id), if depth > 0 then depth else nil)
	end
	local profile = Data.get(player)
	-- Deepest start depth per region on the selected tier (the Atlas depth picker)
	for _, region in Atlas.Regions do
		player:SetAttribute(
			Atlas.startAttr(region.id),
			if profile
				then Atlas.maxStart(region.id, profile.tier.selected, profile.reach, profile.atlas)
				else region.depth
		)
	end
	player:SetAttribute("BestDepth", if profile then Atlas.bestDepth(profile.atlas) else 0)
	-- World Tier: chosen and highest unlocked (the client shows the picker)
	player:SetAttribute("WorldTier", if profile then profile.tier.selected else 1)
	player:SetAttribute("WorldTierUnlocked", if profile then profile.tier.unlocked else 1)
end

local function record(r: Run)
	local profile = Data.get(r.owner)
	if not profile then
		return
	end
	-- A new World Tier: the client toasts on the attribute change (AtlasController)
	local unlocked = WorldTiers.unlockAfter(profile.tier, r.tier, r.depth)
	local key = Atlas.reachKey(r.tier, r.region.id)
	local reached = r.depth > (profile.reach[key] or 0)
	if reached then
		profile.reach[key] = r.depth -- the next run on this tier may start one deeper
	end
	if unlocked or reached or r.depth > (profile.atlas[r.region.id] or 0) then
		profile.atlas[r.region.id] = math.max(r.depth, profile.atlas[r.region.id] or 0)
		Rift.publishBest(r.owner)
	end
	-- Leaderboards: the run's best goes out once at the run end (Leaderboard.flush). Runs with a
	-- movement strike (speed/teleport hack, Systems/Movement) are left out, and so are resumed
	-- runs (started deeper than the region start): their run time would not compare.
	if r.depth0 == r.region.depth and Movement.strikes(r.owner) == r.strikes then
		Leaderboard.note(r.owner, r.tier, profile.class, r.depth, os.clock() - r.tally.startedAt)
	end
end

-- Choose the World Tier for the next run (only between runs, only unlocked tiers)
local function chooseTier(player: Player, n: any)
	local profile = Data.get(player)
	if not profile or runs[player] or typeof(n) ~= "number" or n ~= math.floor(n) then
		return
	end
	if n < 1 or n > profile.tier.unlocked then
		return
	end
	profile.tier.selected = n
	Rift.publishBest(player)
end

-- Is a Rift of this player currently running?
function Rift.isRunning(player: Player): boolean
	return runs[player] ~= nil
end

-- Run number of the player's running Rift (enemy attribute "Run"), nil = none
function Rift.runOf(player: Player): number?
	local r = runs[player]
	return if r then r.id else nil
end

-- Running Rifts (for tests and metrics)
function Rift.count(): number
	local n = 0
	for _ in runs do
		n += 1
	end
	return n
end

local function level(player: Player): number
	return (player:GetAttribute("Level") or 1) :: number
end

local function report(r: Run, kind: "clear" | "end", reason: ("left" | "abandoned" | "failed")?)
	local summary =
		RiftRun.summary(r.tally, kind, reason, r.depth, bestOf(r.owner), level(r.owner), os.clock())
	Net.RiftResult:FireClient(r.owner, summary)
end

local function publish(r: Run, phase: string)
	r.owner:SetAttribute("RiftRegion", r.region.id)
	r.owner:SetAttribute("RiftDepth", r.depth)
	r.owner:SetAttribute("RiftWave", r.wave)
	r.owner:SetAttribute("RiftWaves", Config.TRAIL_CLEARINGS)
	r.owner:SetAttribute("RiftVariant", r.variant)
	r.owner:SetAttribute("RiftPhase", phase)
end

local function mark(r: Run, model: Model?)
	if model then
		Enemies.setRegion(model, r.region.id)
	end
end

local function spawnPoint(r: Run): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0, Config.ENEMY_ZONE_RADIUS)
	return r.center
		+ Config.ENEMY_ZONE
		+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Random point inside a trail clearing (world), one tile away from its edge
local function clearingPoint(lo: Vector3, hi: Vector3): Vector3
	local T = Config.TILE_SIZE
	return Vector3.new(rng:NextNumber(lo.X + T, hi.X - T), 0, rng:NextNumber(lo.Z + T, hi.Z - T))
end

local function spawn(
	r: Run,
	kind: string,
	pos: Vector3,
	elite: boolean?,
	goblin: boolean?,
	bounds: { min: Vector3, max: Vector3 }?
)
	mark(
		r,
		Enemies.spawn(kind, pos, r.depth, {
			tier = r.tier,
			center = r.center,
			bounds = bounds,
			run = r.id,
			elite = elite,
			goblin = goblin,
			smoothed = not goblin and rng:NextNumber() < Smoothing.enemyChance(r.restored),
			healthMult = if r.variant == "swarm"
					and not elite
					and not goblin
				then RiftVariants.SWARM_HEALTH
				else nil,
		})
	)
end

-- Waits until all enemies are dead. false = run was aborted.
local function waitClear(r: Run): boolean
	while alive(r) do
		local left = Enemies.count(r.id)
		if r.owner:GetAttribute("RiftLeft") ~= left then
			r.owner:SetAttribute("RiftLeft", left)
		end
		if left == 0 then
			return true
		end
		task.wait(POLL)
	end
	return false
end

-- Loads the map around `pos` for the player before a teleport (StreamingEnabled: otherwise the
-- character can land before the floor has streamed in). Yields; failures are harmless.
local function streamAround(player: Player, pos: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(pos, Config.STREAM_AROUND_TIMEOUT)
	end)
end

local function returnToHub(player: Player)
	local model = character(player)
	if model then
		streamAround(player, Config.HUB_POS)
		Movement.teleported(player)
		model:PivotTo(CFrame.new(Config.HUB_POS))
		Combat.refreshStats(player, true)
		CombatState.reset(player)
	end
end

-- Ends the run (reason see RiftRun; "gone" = player left the game)
local function finish(r: Run, reason: EndReason)
	if runs[r.owner] ~= r then
		return
	end
	runs[r.owner] = nil
	if r.died then
		r.died:Disconnect()
		r.died = nil
	end
	if r.respawned then
		r.respawned:Disconnect()
		r.respawned = nil
	end
	local failed = reason == "failed"
	Metrics.report(
		r.owner,
		string.format("Depth %d %s", r.depth, if failed then "failed" else "left")
	)
	local owner = r.owner
	Analytics.riftEnd(owner, failed, r.region.id)
	Leaderboard.flush(owner)
	if reason ~= "gone" then
		local gold, items = Loot.collect(owner)
		r.tally.gold += gold
		table.move(items, 1, #items, #r.tally.items + 1, r.tally.items)
		-- the run's gold as one economy event (pickups are not logged one by one; shards come
		-- from salvage, pooled in Progress.salvage)
		local profile = Data.get(owner)
		if profile then
			Analytics.economy(owner, "Gold", r.tally.gold, profile.gold, "Gameplay", "rift")
		end
	end
	Enemies.clear(r.id)
	-- After death the body stays in the arena until respawn: only tear down the floor after that
	local function release()
		World.release(r.slot)
		slots[r.slot] = nil
	end
	if failed and reason ~= "gone" then
		task.delay(Config.RESPAWN_TIME + 1, release)
	else
		release()
	end
	owner:SetAttribute("RiftRegion", nil)
	owner:SetAttribute("RiftRevives", nil)
	owner:SetAttribute("RiftDowned", nil)
	if reason == "gone" or not owner.Parent then
		return
	end
	owner:SetAttribute("RiftLeft", 0)
	report(r, "end", reason)
	if failed then
		owner:SetAttribute("RiftPhase", "failed") -- respawn brings the player to the Hub by itself
		task.delay(FAILED_SHOWN, function()
			if owner.Parent and owner:GetAttribute("RiftPhase") == "failed" then
				owner:SetAttribute("RiftPhase", "")
			end
		end)
	else
		owner:SetAttribute("RiftPhase", "")
		returnToHub(owner)
	end
end

local function setRevives(r: Run)
	r.owner:SetAttribute("RiftRevives", r.revives)
end

local onDied: (r: Run) -> ()

local function watchDeath(r: Run, humanoid: Humanoid)
	if r.died then
		r.died:Disconnect()
	end
	r.died = humanoid.Died:Connect(function()
		onDied(r)
	end)
end

-- The new character after a death with a revive left: back to the last lit waypoint (or the
-- start pad), full life, and the run goes on.
local function revive(r: Run, model: Model)
	if runs[r.owner] ~= r or not r.downed then
		return
	end
	local humanoid = model:WaitForChild("Humanoid", 5)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if runs[r.owner] ~= r or r.owner.Character ~= model then
		return
	end
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return finish(r, "failed")
	end
	-- Watch the new body before anything yields: FallGuard may already put it on the trail, and
	-- a death from here on must count (no revive left = the run fails)
	watchDeath(r, humanoid)
	r.downed = false
	r.owner:SetAttribute("RiftDowned", nil)
	local spot = r.checkpoint or World.startOf(r.slot) -- same as Rift.safeSpot
	streamAround(r.owner, spot)
	task.wait() -- after the engine has placed the new character on its spawn
	if runs[r.owner] ~= r or r.owner.Character ~= model or humanoid.Health <= 0 then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	Movement.teleported(r.owner)
	model:PivotTo(CFrame.new(spot))
	Combat.refreshStats(r.owner, true)
	CombatState.reset(r.owner)
end

-- Death inside a running Rift: spend a revive, or fail the run when none is left
onDied = function(r: Run)
	if runs[r.owner] ~= r or r.downed then
		return
	end
	if r.revives <= 0 then
		return finish(r, "failed")
	end
	r.revives -= 1
	r.downed = true
	setRevives(r)
	r.owner:SetAttribute("RiftDowned", true)
	if r.respawned then
		r.respawned:Disconnect()
	end
	r.respawned = r.owner.CharacterAdded:Connect(function(model: Model)
		if r.respawned then
			r.respawned:Disconnect()
			r.respawned = nil
		end
		revive(r, model)
	end)
	-- Safety net: no new character in time (respawn blocked, left mid-load) ends the run
	task.delay(Config.RESPAWN_TIME + Config.RIFT_REVIVE_GRACE, function()
		if runs[r.owner] == r and r.downed then
			finish(r, "failed")
		end
	end)
end

local function play(r: Run)
	Metrics.begin(r.owner, r.id)
	Analytics.riftStart(r.owner, r.depth, r.region.id)
	r.variant = Rift.forceVariant or RiftVariants.roll(rng, r.depth)
	local deadline = os.clock() + RiftVariants.TIMED_LIMIT
	-- Rift Trail (Shared/Trail): one pack per clearing, in walking order. The next pack spawns
	-- when the last one is down; it waits in its clearing (aggro radius) until the player arrives.
	local waves = Config.TRAIL_CLEARINGS
	for wave = 1, waves do
		r.wave = wave
		publish(r, "wave")
		local lo, hi = World.clearing(r.slot, wave)
		local bounds = if lo and hi then { min = lo, max = hi } else nil
		local function at(): Vector3
			return if lo and hi then clearingPoint(lo, hi) else spawnPoint(r)
		end
		local sinceStart = r.depth - r.region.depth -- depths since the region start
		local count = math.min(
			Config.RIFT_WAVE_BASE + Config.RIFT_WAVE_STEP * ((wave - 1) + sinceStart),
			Config.RIFT_WAVE_MAX
		)
		if r.variant == "swarm" then
			count = math.floor(count * RiftVariants.SWARM_COUNT)
		end
		local mix = r.region.enemies
		-- the last RIFT_ELITES packs open with elites: one, plus one per World Tier above Normal
		local elite = r.variant == "elite_hunt" or wave > waves - Config.RIFT_ELITES
		for i = 1, count do
			spawn(r, mix[rng:NextInteger(1, #mix)], at(), elite and i <= r.tier, nil, bounds)
		end
		if r.variant == "goblin" and wave == 1 then
			spawn(r, mix[1], at(), false, true, bounds)
		end
		if not waitClear(r) then
			return finish(r, "failed")
		end
		-- Waypoint: the shrine lights up and becomes the safe spot for the rest of this depth
		World.lightWaypoint(r.slot, wave, r.region.color)
		if lo and hi then
			r.checkpoint = Vector3.new((lo.X + hi.X) / 2, 4, (lo.Z + hi.Z) / 2)
		end
		-- Area clear moment for the owner (toast, chime, stud burst: FeelController)
		local _, ownRoot = character(r.owner)
		Net.Fx:FireClient(r.owner, "areaclear", {
			pos = if ownRoot then ownRoot.Position else r.checkpoint,
			wave = wave,
			waves = waves,
			color = r.region.color,
		})
		task.wait(Config.RIFT_WAVE_PAUSE)
		if not alive(r) then
			return finish(r, "failed")
		end
	end

	publish(r, "boss")
	local bossAt = r.center + Config.ENEMY_ZONE
	spawn(r, r.region.bossKind, bossAt)
	local intro = Smoothing.BossIntro[r.region.id]
	if intro then
		Net.Fx:FireClient(r.owner, "intro", { text = intro, color = r.region.color })
	end
	if not waitClear(r) then
		return finish(r, "failed")
	end
	if r.variant == "timed" and os.clock() <= deadline and r.owner.Parent then
		Loot.bonus(r.owner, bossAt, r.depth, r.region.id, RiftVariants.TIMED_ITEMS)
		r.owner:SetAttribute("RiftVariantDone", r.variant)
	end
	record(r)
	r.tally.cleared += 1
	Metrics.report(r.owner, string.format("Depth %d cleared", r.depth))
	Analytics.riftClear(r.owner, r.depth, r.region.id)
	-- Let the boss loot land, then pick up the leftovers before the choice (and its summary)
	task.wait(Loot.VACUUM_DELAY)
	if runs[r.owner] ~= r then
		return -- the run ended meanwhile (death, leave)
	end
	Loot.vacuum(r.owner)
	task.wait() -- Picked handlers (tally, quests) run before the summary goes out
	if runs[r.owner] ~= r then
		return
	end
	-- Summary first, then the phase: the client's cleared card shows the fresh totals at once
	report(r, "clear", nil)
	publish(r, "clear")
end

local function begin(player: Player, regionId: any, wanted: any)
	local model, _, humanoid = character(player)
	if runs[player] or not model or not humanoid or humanoid.Health <= 0 then
		return
	end
	local id = if typeof(regionId) == "string" then regionId else Atlas.Start
	local region = Atlas.ById[id]
	if not region or not Atlas.isOpen(id, bestOf(player)) then
		return
	end
	local profile = Data.get(player)
	local tier = if profile then profile.tier.selected else 1
	local max = if profile
		then Atlas.maxStart(id, tier, profile.reach, profile.atlas)
		else region.depth
	local depth = Atlas.startDepth(id, wanted, max)
	local slot = 0
	for i = 1, Config.RIFT_SLOTS do
		if not slots[i] then
			slot = i
			break
		end
	end
	if slot == 0 then
		return -- server full (more players than slots)
	end
	nextId += 1
	local r: Run = {
		id = nextId,
		slot = slot,
		center = World.center(slot),
		owner = player,
		region = region,
		depth = depth,
		depth0 = depth,
		tier = tier,
		wave = 0,
		variant = "",
		restored = Smoothing.restored(region.depth, bestOf(player)(region.id)),
		tally = RiftRun.newTally(id, depth, bestOf(player), level(player), os.clock()),
		revives = Config.RIFT_REVIVES,
		downed = false,
		strikes = Movement.strikes(player),
	}
	runs[player] = r
	slots[slot] = r
	-- Death costs a revive (back to the last waypoint) or ends the run, also during pauses and
	-- the choice after the boss
	watchDeath(r, humanoid)
	setRevives(r)
	World.build(region, slot, Trail.seed(region.id, r.depth))
	World.smooth(slot, Smoothing.arenaShare(r.restored))
	streamAround(player, World.startOf(slot))
	if runs[player] ~= r then
		return -- left or died while the map streamed in
	end
	Movement.teleported(player)
	model:PivotTo(CFrame.new(World.startOf(slot)))
	task.spawn(play, r)
	Actions.fire(player, "rift")
end

local function deeper(player: Player)
	local r = runs[player]
	if not r or r.downed or player:GetAttribute("RiftPhase") ~= "clear" then
		return -- dead and respawning: the choice waits for the new character
	end
	r.depth += 1
	r.wave = 0
	r.checkpoint = nil
	r.revives = Config.RIFT_REVIVES -- every depth refills the revives
	setRevives(r)
	-- every depth is a new trail: rebuild the map, back to its start pad
	World.build(r.region, r.slot, Trail.seed(r.region.id, r.depth))
	World.smooth(r.slot, Smoothing.arenaShare(r.restored))
	streamAround(player, World.startOf(r.slot))
	if runs[player] ~= r then
		return
	end
	local model = character(player)
	if model then
		Movement.teleported(player)
		model:PivotTo(CFrame.new(World.startOf(r.slot)))
	end
	Combat.refreshStats(player, true)
	task.spawn(play, r)
end

local allow = RateLimit.new(1, 3) -- entering builds a whole arena: slow down spam
local allowTier = RateLimit.new(4, 8) -- tier picker steps are cheap and must not eat the enter budget

local function onAction(player: Player, action: any, regionId: any, depth: any)
	if action == "tier" then
		if allowTier(player) then
			chooseTier(player, regionId)
		end
		return
	end
	if not allow(player) then
		return
	end
	if action == "enter" then
		begin(player, regionId, depth)
	elseif action == "deeper" then
		deeper(player)
	elseif action == "leave" then
		local r = runs[player]
		if r then
			finish(r, if player:GetAttribute("RiftPhase") == "clear" then "left" else "abandoned")
		end
	end
end

-- Counting for the summary (only the owner of the running Rift)
local function tallyOf(player: any): RiftRun.Tally?
	local r = if typeof(player) == "Instance" and player:IsA("Player") then runs[player] else nil
	return if r then r.tally else nil
end

local function onKilled(player: any, _pos: any, _level: any, boss: any, _skill: any, xp: any)
	local t = tallyOf(player)
	if t then
		t.kills += 1
		t.bosses += if boss == true then 1 else 0
		t.xp += if typeof(xp) == "number" then xp else 0
	end
end

local function onPicked(player: any, gold: any, item: any)
	local t = tallyOf(player)
	if t then
		t.gold += if typeof(gold) == "number" then gold else 0
		if typeof(item) == "table" then
			table.insert(t.items, item)
		end
	end
end

local function onLooted(player: any, delta: any)
	local t = tallyOf(player)
	if t and typeof(delta) == "table" then
		RiftRun.addMaterials(t, delta)
	end
end

function Rift.init()
	Net.Rift.OnServerEvent:Connect(onAction)
	Combat.EnemyKilled.Event:Connect(onKilled)
	Loot.Picked.Event:Connect(onPicked)
	Progress.Looted.Event:Connect(onLooted)
	Players.PlayerRemoving:Connect(function(player: Player)
		local r = runs[player]
		if r then
			finish(r, "gone")
		end
	end)
end

-- Arena center of the player's running Rift (nil = not in a Rift; FallGuard uses it)
function Rift.centerOf(player: Player): Vector3?
	local r = runs[player]
	return if r then r.center else nil
end

-- Map slot of the player's running Rift (nil = not in a Rift)
function Rift.slotOf(player: Player): number?
	local r = runs[player]
	return if r then r.slot else nil
end

-- Where FallGuard puts a player of a running Rift back: last lit waypoint, else the start pad
function Rift.safeSpot(player: Player): Vector3?
	local r = runs[player]
	if not r then
		return nil
	end
	return r.checkpoint or World.startOf(r.slot)
end

-- Best results for the Atlas (the client reads the attributes)
function Rift.start()
	local function onPlayer(player: Player)
		if Data.waitFor(player) then
			Rift.publishBest(player)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Rift
