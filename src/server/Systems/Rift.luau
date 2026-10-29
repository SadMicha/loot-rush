--!strict
-- Rift-Ablauf: Gebiet wählen (Atlas) → Wellen → Boss → Wahl „tiefer“ oder „zurück ins Dorf“.
-- Jedes Gebiet startet auf seiner eigenen Tiefe und würfelt die Wellen aus seinem Gegner-Mix
-- (Shared/Atlas). Geschaffte Tiefen landen im Spielstand (atlas) und schalten Folgegebiete frei.
-- Ein Rift gleichzeitig pro Server; der Starter ist der Besitzer. Zustand liegt als Attribute am
-- Besitzer (siehe Types.luau), der Client liest nur. Tod, Verlassen oder Abbruch beenden den Lauf.
-- Unterwegs zählt der Server Kills, XP, Gold, Items und Material mit und schickt nach jedem Boss
-- und am Ende eine Zusammenfassung über Net.RiftResult (Shared/RiftRun) – Daten für den
-- Belohnungsbildschirm. Beim Ende wird liegengebliebene Beute eingesammelt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RiftRun = require(ReplicatedStorage.Shared.RiftRun)
local Combat = require(script.Parent.Combat)
local CombatState = require(script.Parent.CombatState)
local Data = require(script.Parent.Data)
local Loot = require(script.Parent.Loot)
local Metrics = require(script.Parent.Metrics)
local Enemies = require(script.Parent.Enemies)
local Progress = require(script.Parent.Progress)
local World = require(script.Parent.World)

type Run = {
	owner: Player,
	region: Atlas.Region,
	depth: number, -- absolute Tiefe (skaliert die Gegner)
	wave: number,
	tally: RiftRun.Tally,
	died: RBXScriptConnection?,
}

type EndReason = "left" | "abandoned" | "failed" | "gone"

local Rift = {}

local FAILED_SHOWN = 4 -- Sekunden, die „gescheitert“ im HUD steht
local POLL = 0.3

local run: Run? = nil
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
	if run ~= r or not r.owner.Parent then
		return false
	end
	local _, _, humanoid = character(r.owner)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Bestleistung je Gebiet (0 = nie geschafft)
local function bestOf(player: Player): (string) -> number
	local profile = Data.get(player)
	return function(id: string): number
		return if profile then profile.atlas[id] or 0 else 0
	end
end

local function publishBest(player: Player)
	local best = bestOf(player)
	for _, region in Atlas.Regions do
		local depth = best(region.id)
		player:SetAttribute(Atlas.attr(region.id), if depth > 0 then depth else nil)
	end
end

local function record(r: Run)
	local profile = Data.get(r.owner)
	if profile and r.depth > (profile.atlas[r.region.id] or 0) then
		profile.atlas[r.region.id] = r.depth
		r.owner:SetAttribute(Atlas.attr(r.region.id), r.depth)
	end
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
	r.owner:SetAttribute("RiftWaves", Config.RIFT_WAVES)
	r.owner:SetAttribute("RiftPhase", phase)
end

local function mark(r: Run, model: Model?)
	if model then
		Enemies.setRegion(model, r.region.id)
	end
end

local function enemiesLeft(): number
	return #CollectionService:GetTagged("Enemy")
end

local function spawnPoint(): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0, Config.ENEMY_ZONE_RADIUS)
	return Config.ENEMY_ZONE + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Wartet, bis alle Gegner tot sind. false = Lauf wurde abgebrochen.
local function waitClear(r: Run): boolean
	while alive(r) do
		local left = enemiesLeft()
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

local function returnToHub(player: Player)
	local model = character(player)
	if model then
		model:PivotTo(CFrame.new(Config.HUB_POS))
		Combat.refreshStats(player, true)
		CombatState.reset(player)
	end
end

-- Beendet den Lauf (Grund siehe RiftRun; "gone" = Spieler hat das Spiel verlassen)
local function finish(r: Run, reason: EndReason)
	if run ~= r then
		return
	end
	run = nil
	if r.died then
		r.died:Disconnect()
		r.died = nil
	end
	local failed = reason == "failed"
	Metrics.report(
		string.format("Tiefe %d %s", r.depth, if failed then "gescheitert" else "verlassen")
	)
	local owner = r.owner
	if reason ~= "gone" then
		local gold, items = Loot.collect(owner)
		r.tally.gold += gold
		table.move(items, 1, #items, #r.tally.items + 1, r.tally.items)
	end
	Enemies.clear()
	World.build(nil)
	owner:SetAttribute("RiftRegion", nil)
	if reason == "gone" or not owner.Parent then
		return
	end
	owner:SetAttribute("RiftLeft", 0)
	report(r, "end", reason)
	if failed then
		owner:SetAttribute("RiftPhase", "failed") -- Respawn bringt den Spieler selbst zum Hub
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

local function play(r: Run)
	Metrics.begin(r.owner)
	for wave = 1, Config.RIFT_WAVES do
		r.wave = wave
		publish(r, "wave")
		local sinceStart = r.depth - r.region.depth -- Tiefen seit Gebietsbeginn
		local count = math.min(
			Config.RIFT_WAVE_BASE + Config.RIFT_WAVE_STEP * ((wave - 1) + sinceStart),
			Config.RIFT_WAVE_MAX
		)
		local mix = r.region.enemies
		for _ = 1, count do
			mark(r, Enemies.spawn(mix[rng:NextInteger(1, #mix)], spawnPoint(), r.depth))
		end
		if not waitClear(r) then
			return finish(r, "failed")
		end
		task.wait(Config.RIFT_WAVE_PAUSE)
		if not alive(r) then
			return finish(r, "failed")
		end
	end

	publish(r, "boss")
	mark(r, Enemies.spawn(r.region.bossKind, Config.ENEMY_ZONE, r.depth))
	if not waitClear(r) then
		return finish(r, "failed")
	end
	record(r)
	r.tally.cleared += 1
	Metrics.report(string.format("Tiefe %d geschafft", r.depth))
	publish(r, "clear")
	report(r, "clear", nil)
end

local function begin(player: Player, regionId: any)
	local model, _, humanoid = character(player)
	if run or not model or not humanoid or humanoid.Health <= 0 then
		return
	end
	local id = if typeof(regionId) == "string" then regionId else Atlas.Start
	local region = Atlas.ById[id]
	if not region or not Atlas.isOpen(id, bestOf(player)) then
		return
	end
	local r: Run = {
		owner = player,
		region = region,
		depth = region.depth,
		wave = 0,
		tally = RiftRun.newTally(id, region.depth, bestOf(player), level(player), os.clock()),
	}
	run = r
	-- Tod beendet den Lauf sofort, auch in Pausen und bei der Wahl nach dem Boss
	r.died = humanoid.Died:Connect(function()
		finish(r, "failed")
	end)
	World.build(region)
	model:PivotTo(CFrame.new(Config.RIFT_START))
	task.spawn(play, r)
end

local function deeper(player: Player)
	local r = run
	if not r or r.owner ~= player or player:GetAttribute("RiftPhase") ~= "clear" then
		return
	end
	r.depth += 1
	r.wave = 0
	Combat.refreshStats(player, true)
	task.spawn(play, r)
end

local function onAction(player: Player, action: any, regionId: any)
	if action == "enter" then
		begin(player, regionId)
	elseif action == "deeper" then
		deeper(player)
	elseif action == "leave" then
		local r = run
		if r and r.owner == player then
			finish(r, if player:GetAttribute("RiftPhase") == "clear" then "left" else "abandoned")
		end
	end
end

-- Mitzählen für die Zusammenfassung (nur der Besitzer des laufenden Rifts)
local function tallyOf(player: any): RiftRun.Tally?
	local r = run
	return if r and r.owner == player then r.tally else nil
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
		local r = run
		if r and r.owner == player then
			finish(r, "gone")
		end
	end)
end

-- Bestleistungen für den Atlas (Client liest die Attribute)
function Rift.start()
	local function onPlayer(player: Player)
		if Data.waitFor(player) then
			publishBest(player)
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
