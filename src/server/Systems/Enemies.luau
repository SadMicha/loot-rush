--!strict
-- Gegner-Pool und KI. Jeder Gegnertyp hat einen Archetyp (Balancing-Blatt „Archetypen“) und
-- eine Angriffsart; jeder Angriff zeigt vorher einen roten Boden-Telegraph (Ausweichen per Dash):
--   slam    – läuft heran, Flächenschlag um sich (Schwarm, Tank)
--   charge  – Linie am Boden, dann Ansturm entlang der Linie (Lader)
--   ranged  – hält Abstand, Kreis unter dem Ziel, Geschoss schlägt dort ein (Fernkämpfer)
--   summon  – hält Abstand und ruft Minis (Beschwörer)
-- Bosse rufen bei halbem Leben einmal Helfer (`adds`); `summonEvery` ruft regelmäßig welche.
-- Gespawnt wird nur auf Abruf (Systems/Rift, Gegner-Mix je Gebiet in Shared/Atlas).
-- Leben/XP/Farbe liegen als Attribute am Model; Schaden an Gegnern macht Systems/Combat.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Config = require(ReplicatedStorage.Shared.Config)
local Creatures = require(ReplicatedStorage.Shared.Models.Creatures)
local Net = require(ReplicatedStorage.Shared.Net)
local Combat = require(script.Parent.Combat)

type Ai = "slam" | "charge" | "ranged" | "summon"

type Kind = {
	name: string,
	ai: Ai,
	health: number,
	damage: number,
	xp: number,
	speed: number,
	attackRange: number, -- ab dieser Entfernung wird angegriffen
	keepAway: number, -- ranged/summon weichen zurück, wenn der Spieler näher ist
	radius: number, -- slam/ranged: Kreisradius · charge: halbe Linienbreite
	windup: number,
	cooldown: number,
	scale: number,
	hover: number, -- Schwebehöhe über dem normalen Körpermittelpunkt
	shots: number, -- ranged: Einschläge pro Angriff
	boss: boolean,
	adds: string?, -- Gegnertyp, den Bosse/Beschwörer rufen
	summonEvery: number?, -- Sekunden zwischen Beschwörungen (nil = nur Boss bei halbem Leben)
	color: Color3, -- Farbe für Tod-Effekt und Treffer-Anzeige
	build: (s: number) -> Model,
}

type Enemy = {
	model: Model,
	kind: Kind,
	damage: number,
	depth: number,
	summoned: boolean,
	phase: number,
	nextAttack: number,
	nextSummon: number,
	minions: { Model },
	windupEnd: number, -- 0 = kein Angriff in Vorbereitung
	telegraphs: { BasePart },
	targets: { Vector3 }, -- slam/ranged: Kreismitten · charge: Start der Linie
	dir: Vector3, -- charge: Richtung der Linie
	dashFrom: Vector3,
	dashTo: Vector3,
	dashEnd: number, -- 0 = kein Ansturm
}

local Enemies = {}

local BASE = { health = 90, damage = 20, xp = 28, speed = 9.2 }
-- Leben ×, Schaden ×, Tempo ×, Gold/XP × (LootRush_Balancing.xlsx, Blatt „Archetypen“)
local ARCH = {
	swarm = { 0.5, 0.6, 1.2, 0.5 },
	ranged = { 0.8, 1, 0.9, 1 },
	tank = { 2.5, 0.8, 0.7, 2 },
	charger = { 1.2, 1.6, 1.4, 1.2 },
	summoner = { 1, 0.6, 0.9, 1.5 },
}
local CHARGE_LENGTH = 18
local CHARGE_TIME = 0.3
local MAX_MINIONS = 4
local BOSS_SUMMONS = 4
local BASE_BODY_Y = Creatures.BODY_Y
-- Laufbereich: Arena-Raster ohne erhöhten Nordrand und Seitenklippen (siehe Systems/World)
local MAX_X = math.floor(Config.ARENA_TILES_X / 2) * Config.TILE_SIZE - 10
local MAX_Z = math.floor(Config.ARENA_TILES_Z / 2) * Config.TILE_SIZE - 6
local MIN_Z = -MAX_Z + 6
local DANGER = Color3.fromHex("#FF6A3A")
local DANGER_CORE = Color3.fromHex("#FF3A2A")

local function archetype(arch: string, k: { [string]: any }): Kind
	local m = ARCH[arch]
	local out = {
		health = math.floor(BASE.health * m[1]),
		damage = math.floor(BASE.damage * m[2] + 0.5),
		speed = BASE.speed * m[3],
		xp = math.floor(BASE.xp * m[4]),
		keepAway = 0,
		hover = 0,
		shots = 1,
		boss = false,
	}
	for key, value in k do
		out[key] = value
	end
	return table.freeze(out) :: any
end

local function boss(k: { [string]: any }): Kind
	k.boss = true
	return archetype("tank", k)
end

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local KINDS: { [string]: Kind } = {
	-- Grüne Ebenen
	slime = archetype("swarm", {
		name = "Kristallschleim",
		ai = "slam",
		attackRange = 5,
		radius = 7,
		windup = 0.9,
		cooldown = 2,
		scale = 1,
		color = hex("#49D8D8"),
		build = function(s)
			return Creatures.slime(s, hex("#49D8D8"), hex("#4FD8F5"))
		end,
	}),
	beetle = archetype("charger", {
		name = "Stachelkäfer",
		ai = "charge",
		attackRange = 14,
		radius = 2.5,
		windup = 0.8,
		cooldown = 3,
		scale = 0.9,
		color = hex("#E0A030"),
		build = function(s)
			return Creatures.beetle(s)
		end,
	}),
	kristallkoenig = boss({
		name = "Kristallkönig",
		ai = "slam",
		health = 700,
		damage = 26,
		xp = 160,
		speed = 8,
		attackRange = 11,
		radius = 14,
		windup = 1.3,
		cooldown = 3,
		scale = 3,
		adds = "slime",
		color = hex("#9B6BFF"),
		build = function(s)
			return Creatures.slime(s, hex("#9B6BFF"), hex("#E8B04A"))
		end,
	}),

	-- Kristallhöhlen
	crab = archetype("tank", {
		name = "Kristallkrabbe",
		ai = "slam",
		attackRange = 6,
		radius = 8,
		windup = 1.1,
		cooldown = 2.6,
		scale = 1,
		color = hex("#5A6FD0"),
		build = function(s)
			return Creatures.crab(s)
		end,
	}),
	lantern = archetype("ranged", {
		name = "Fledermaus-Lampion",
		ai = "ranged",
		attackRange = 26,
		keepAway = 12,
		radius = 4.5,
		windup = 1.1,
		cooldown = 2.4,
		scale = 0.9,
		hover = 2.5,
		color = hex("#FFC24A"),
		build = function(s)
			return Creatures.lantern(s)
		end,
	}),
	splitterwurm = boss({
		name = "Splitterwurm",
		ai = "charge",
		health = 760,
		damage = 34,
		xp = 180,
		speed = 9,
		attackRange = 24,
		radius = 4,
		windup = 1.1,
		cooldown = 2.6,
		scale = 2.2,
		adds = "lantern",
		color = hex("#6B4FB0"),
		build = function(s)
			return Creatures.crown(Creatures.worm(s), s, 1.4)
		end,
	}),

	-- Pilzsumpf
	frog = archetype("charger", {
		name = "Sporenfrosch",
		ai = "charge",
		attackRange = 12,
		radius = 2.5,
		windup = 0.7,
		cooldown = 2.6,
		scale = 0.9,
		color = hex("#6FA83A"),
		build = function(s)
			return Creatures.frog(s)
		end,
	}),
	snail = archetype("summoner", {
		name = "Giftschnecke",
		ai = "summon",
		attackRange = 22,
		keepAway = 12,
		radius = 0,
		windup = 0,
		cooldown = 0,
		scale = 1,
		adds = "sporeling",
		summonEvery = 6,
		color = hex("#8A4FC8"),
		build = function(s)
			return Creatures.snail(s)
		end,
	}),
	sporeling = archetype("swarm", {
		name = "Sporling",
		ai = "slam",
		xp = 4, -- gerufene Minis: kaum XP, sonst lohnt Farmen am Beschwörer
		attackRange = 4,
		radius = 5,
		windup = 0.8,
		cooldown = 2,
		scale = 0.6,
		color = hex("#E85AA8"),
		build = function(s)
			return Creatures.slime(s, hex("#E85AA8"), hex("#FFE27A"))
		end,
	}),
	sporenmutter = boss({
		name = "Sporenmutter",
		ai = "slam",
		health = 820,
		damage = 24,
		xp = 200,
		speed = 5,
		attackRange = 10,
		radius = 13,
		windup = 1.3,
		cooldown = 3.2,
		scale = 2.4,
		adds = "sporeling",
		summonEvery = 9,
		color = hex("#E85AA8"),
		build = function(s)
			return Creatures.mushroom(s)
		end,
	}),

	-- Feuerwüste
	golem = archetype("tank", {
		name = "Toast-Golem",
		ai = "slam",
		attackRange = 6,
		radius = 8,
		windup = 1.1,
		cooldown = 2.6,
		scale = 1,
		color = hex("#E8B868"),
		build = function(s)
			return Creatures.golem(s)
		end,
	}),
	imp = archetype("ranged", {
		name = "Funkenwicht",
		ai = "ranged",
		attackRange = 22,
		keepAway = 10,
		radius = 4,
		windup = 0.9,
		cooldown = 2.2,
		scale = 0.8,
		hover = 2,
		color = hex("#FF8A3D"),
		build = function(s)
			return Creatures.imp(s)
		end,
	}),
	ofenfuerst = boss({
		name = "Ofenfürst Krust",
		ai = "slam",
		health = 900,
		damage = 30,
		xp = 220,
		speed = 7,
		attackRange = 11,
		radius = 14,
		windup = 1.2,
		cooldown = 2.8,
		scale = 2.6,
		adds = "imp",
		color = hex("#FF8A3D"),
		build = function(s)
			return Creatures.crown(Creatures.golem(s), s, 3.1)
		end,
	}),

	-- Himmelsinseln
	wisp = archetype("ranged", {
		name = "Windgeist",
		ai = "ranged",
		attackRange = 28,
		keepAway = 14,
		radius = 4.5,
		windup = 1,
		cooldown = 2.4,
		scale = 0.9,
		hover = 3,
		color = hex("#9CE5FF"),
		build = function(s)
			return Creatures.wisp(s)
		end,
	}),
	statue = archetype("tank", {
		name = "Wächterstatue",
		ai = "slam",
		attackRange = 6,
		radius = 9,
		windup = 1.2,
		cooldown = 2.8,
		scale = 1,
		color = hex("#C2BBA8"),
		build = function(s)
			return Creatures.statue(s)
		end,
	}),
	wolkenkoenigin = boss({
		name = "Wolkenkönigin",
		ai = "ranged",
		health = 760,
		damage = 26,
		xp = 240,
		speed = 8,
		attackRange = 30,
		keepAway = 12,
		radius = 5,
		windup = 1.2,
		cooldown = 2.6,
		scale = 2.4,
		hover = 2,
		shots = 3,
		adds = "wisp",
		color = hex("#9CE5FF"),
		build = function(s)
			return Creatures.crown(Creatures.wisp(s), s, 1.6)
		end,
	}),

	-- Veränderte Welt (Gegner der anderen Gebiete gemischt, siehe Atlas)
	riss = boss({
		name = "Der Riss",
		ai = "slam",
		health = 1000,
		damage = 32,
		xp = 280,
		speed = 8,
		attackRange = 12,
		radius = 15,
		windup = 1.2,
		cooldown = 2.6,
		scale = 3.2,
		adds = "beetle",
		summonEvery = 12,
		color = hex("#FF4FD8"),
		build = function(s)
			return Creatures.crown(
				Creatures.slime(s, hex("#B03AA0"), hex("#FF4FD8")),
				s,
				2.3,
				hex("#FF4FD8")
			)
		end,
	}),
}

local list: { Enemy } = {}
local folder: Folder
local rng = Random.new()

local function flat(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	transparency: number,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Parent = parent
	return p
end

function Enemies.has(kindName: string): boolean
	return KINDS[kindName] ~= nil
end

function Enemies.kindNames(): { string }
	local out = {}
	for name in KINDS do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function bodyY(kind: Kind): number
	return BASE_BODY_Y * kind.scale + kind.hover
end

local function clampArena(p: Vector3): Vector3
	return Vector3.new(math.clamp(p.X, -MAX_X, MAX_X), p.Y, math.clamp(p.Z, MIN_Z, MAX_Z))
end

-- Erzeugt einen Gegner. depth skaliert Leben, Schaden und XP (siehe Config.RIFT_*_PER_DEPTH).
function Enemies.spawn(kindName: string, pos: Vector3, depth: number): Model?
	local kind = KINDS[kindName]
	if not kind then
		warn("[Enemies] unbekannter Gegnertyp " .. tostring(kindName))
		return nil
	end
	local steps = depth - 1
	local health = math.floor(kind.health * (1 + Config.RIFT_HP_PER_DEPTH * steps))
	local model = kind.build(kind.scale)
	model.Name = kind.name
	model:PivotTo(CFrame.new(pos.X, bodyY(kind), pos.Z))
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("XP", math.floor(kind.xp * (1 + Config.RIFT_XP_PER_DEPTH * steps)))
	model:SetAttribute("Color", kind.color)
	model:SetAttribute("Depth", depth)
	if kind.boss then
		model:SetAttribute("Boss", true)
	end
	CollectionService:AddTag(model, "Enemy")
	model.Parent = folder
	local now = os.clock()
	table.insert(list, {
		model = model,
		kind = kind,
		damage = math.floor(kind.damage * (1 + Config.RIFT_DMG_PER_DEPTH * steps) + 0.5),
		depth = depth,
		summoned = false,
		phase = rng:NextNumber(0, 6),
		nextAttack = now + 1,
		nextSummon = now + (kind.summonEvery or 0) / 2,
		minions = {},
		windupEnd = 0,
		telegraphs = {},
		targets = {},
		dir = Vector3.zAxis,
		dashFrom = pos,
		dashTo = pos,
		dashEnd = 0,
	})
	return model
end

-- Gebiet am Gegner vermerken (Beute-Boni in Systems/Loot) und den Erfahrungs-Bonus anwenden
function Enemies.setRegion(model: Model, regionId: string)
	model:SetAttribute("Region", regionId)
	local region = Atlas.ById[regionId]
	local xp = region and region.bonus.xp
	if xp then
		model:SetAttribute("XP", math.floor((model:GetAttribute("XP") or 0) :: number * (1 + xp)))
	end
end

function Enemies.clear()
	for _, e in list do
		e.model:Destroy() -- step() räumt Liste und Telegraphen beim nächsten Frame auf
	end
end

local function nearestPlayer(from: Vector3): (Player?, Vector3?, number)
	local best: Player? = nil
	local bestPos: Vector3? = nil
	local bestD = Config.AGGRO_RADIUS
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local d = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z).Magnitude
			if d <= bestD then
				bestD = d
				best = player
				bestPos = root.Position
			end
		end
	end
	return best, bestPos, bestD
end

-- Ruft fn(player, flacher Abstand zum Punkt, Position) für jeden lebenden Spieler-Körper
local function eachPlayer(fn: (Player, Vector3) -> ())
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			fn(player, Vector3.new(root.Position.X, 0, root.Position.Z))
		end
	end
end

local function clearTelegraph(e: Enemy)
	for _, t in e.telegraphs do
		t:Destroy()
	end
	table.clear(e.telegraphs)
end

local ROT = CFrame.Angles(0, 0, math.rad(90))

local function circle(e: Enemy, at: Vector3, radius: number)
	local d = radius * 2
	local outer =
		flat(CFrame.new(at.X, 0.2, at.Z) * ROT, Vector3.new(0.2, d, d), DANGER, 0.7, folder)
	outer.Shape = Enum.PartType.Cylinder
	local inner =
		flat(CFrame.new(at.X, 0.25, at.Z) * ROT, Vector3.new(0.25, 1, 1), DANGER_CORE, 0.45, outer)
	inner.Shape = Enum.PartType.Cylinder
	TweenService:Create(
		inner,
		TweenInfo.new(e.kind.windup, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.25, d, d) }
	):Play()
	table.insert(e.telegraphs, outer)
end

local function line(e: Enemy, from: Vector3, dir: Vector3)
	local w = e.kind.radius * 2
	local base =
		CFrame.lookAt(Vector3.new(from.X, 0.2, from.Z), Vector3.new(from.X, 0.2, from.Z) + dir)
	local outer = flat(
		base * CFrame.new(0, 0, -CHARGE_LENGTH / 2),
		Vector3.new(w, 0.2, CHARGE_LENGTH),
		DANGER,
		0.7,
		folder
	)
	local inner =
		flat(base * CFrame.new(0, 0.05, -0.05), Vector3.new(w, 0.25, 0.1), DANGER_CORE, 0.45, outer)
	TweenService:Create(inner, TweenInfo.new(e.kind.windup, Enum.EasingStyle.Linear), {
		Size = Vector3.new(w, 0.25, CHARGE_LENGTH),
		CFrame = base * CFrame.new(0, 0.05, -CHARGE_LENGTH / 2),
	}):Play()
	table.insert(e.telegraphs, outer)
end

local function beginWindup(e: Enemy, pos: Vector3, targetPos: Vector3, now: number)
	local kind = e.kind
	e.windupEnd = now + kind.windup
	table.clear(e.targets)
	local ground = Vector3.new(pos.X, 0, pos.Z)
	local goal = Vector3.new(targetPos.X, 0, targetPos.Z)
	if kind.ai == "charge" then
		local d = goal - ground
		e.dir = if d.Magnitude > 0.1 then d.Unit else Vector3.zAxis
		table.insert(e.targets, ground)
		line(e, ground, e.dir)
	elseif kind.ai == "ranged" then
		for i = 1, kind.shots do
			local at = goal
			if i > 1 then
				local a = (i / kind.shots) * math.pi * 2 + rng:NextNumber(0, 1)
				at += Vector3.new(math.cos(a), 0, math.sin(a)) * kind.radius * 1.6
			end
			at = clampArena(at)
			table.insert(e.targets, at)
			circle(e, at, kind.radius)
			Net.Fx:FireAllClients("proj", {
				from = pos,
				to = at + Vector3.new(0, 0.5, 0),
				time = kind.windup,
				color = kind.color,
				size = 0.8 * kind.scale,
			})
		end
	else
		table.insert(e.targets, ground)
		circle(e, ground, kind.radius)
	end
end

local function resolveAttack(e: Enemy, now: number)
	clearTelegraph(e)
	e.windupEnd = 0
	e.nextAttack = now + e.kind.cooldown
	local kind = e.kind
	local hit: { [Player]: boolean } = {}
	if kind.ai == "charge" then
		local from = e.targets[1]
		eachPlayer(function(player, at)
			local rel = at - from
			local along = rel:Dot(e.dir)
			local side = (rel - e.dir * along).Magnitude
			if along >= -1 and along <= CHARGE_LENGTH and side <= kind.radius + 1 then
				hit[player] = true
			end
		end)
		e.dashFrom = from
		e.dashTo = clampArena(from + e.dir * CHARGE_LENGTH)
		e.dashEnd = now + CHARGE_TIME
	else
		for _, center in e.targets do
			eachPlayer(function(player, at)
				if (at - center).Magnitude <= kind.radius then
					hit[player] = true
				end
			end)
		end
	end
	for player in hit do
		Combat.hurtPlayer(player, e.damage)
	end
end

-- Ruft `count` Helfer im Kreis um `around`
local function summon(e: Enemy, around: Vector3, count: number)
	local addKind = e.kind.adds
	if not addKind then
		return
	end
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local at = clampArena(around + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6))
		local m = Enemies.spawn(addKind, Vector3.new(at.X, 0, at.Z), e.depth)
		if m then
			local region = e.model:GetAttribute("Region")
			if typeof(region) == "string" then
				Enemies.setRegion(m, region) -- Gebiets-Boni gelten auch für Helfer
			end
			table.insert(e.minions, m)
		end
	end
end

local function minionsAlive(e: Enemy): number
	for i = #e.minions, 1, -1 do
		if not e.minions[i].Parent then
			table.remove(e.minions, i)
		end
	end
	return #e.minions
end

local function step(dt: number)
	local now = os.clock()
	for i = #list, 1, -1 do
		local e = list[i]
		local model = e.model
		if not model.Parent then
			clearTelegraph(e)
			table.remove(list, i)
			continue
		end

		local kind = e.kind
		local baseY = bodyY(kind)
		local pos = model:GetPivot().Position
		local target, targetPos, dist = nearestPlayer(pos)
		local y = baseY
		local dir = Vector3.zero

		if
			kind.boss
			and not e.summoned
			and (model:GetAttribute("Health") or 0) :: number
				<= ((model:GetAttribute("MaxHealth") or 0) :: number) / 2
		then
			e.summoned = true
			summon(e, pos, BOSS_SUMMONS)
		end
		if kind.summonEvery and target and now >= e.nextSummon then
			e.nextSummon = now + kind.summonEvery
			local free = MAX_MINIONS - minionsAlive(e)
			if free > 0 then
				summon(e, pos, math.min(2, free))
				Net.Fx:FireAllClients(
					"nova",
					{ pos = Vector3.new(pos.X, 0.5, pos.Z), radius = 6, color = kind.color }
				)
			end
		end

		if e.dashEnd > 0 then
			-- Ansturm entlang der Telegraph-Linie
			local t = 1 - math.max(e.dashEnd - now, 0) / CHARGE_TIME
			local p = e.dashFrom:Lerp(e.dashTo, t)
			pos = Vector3.new(p.X, pos.Y, p.Z)
			dir = e.dir
			if now >= e.dashEnd then
				e.dashEnd = 0
			end
		elseif e.windupEnd > 0 then
			-- Vorbereitung: stehen bleiben, zusammendrücken
			y = baseY
				- 0.3 * kind.scale * math.sin((1 - (e.windupEnd - now) / kind.windup) * math.pi)
			if kind.ai == "charge" then
				dir = e.dir
			end
			if now >= e.windupEnd then
				resolveAttack(e, now)
			end
		elseif target and targetPos then
			dir = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
			local move = 0
			if dist > kind.attackRange then
				move = 1
			elseif kind.ai ~= "summon" and now >= e.nextAttack then
				beginWindup(e, pos, targetPos, now)
			elseif dist < kind.keepAway then
				move = -1
			end
			if move ~= 0 and dir.Magnitude > 0.01 then
				local speed = kind.speed * move
				if now < ((model:GetAttribute("SlowUntil") or 0) :: number) then
					speed *= (model:GetAttribute("SlowFactor") or 1) :: number
				end
				local step3 = dir.Unit * speed * dt
				local np = clampArena(Vector3.new(pos.X + step3.X, pos.Y, pos.Z + step3.Z))
				y = baseY + math.abs(math.sin(now * 7 + e.phase)) * 0.8 * kind.scale
				pos = np
			end
		else
			y = baseY + math.abs(math.sin(now * 3 + e.phase)) * 0.25 * kind.scale
		end

		local here = Vector3.new(pos.X, y, pos.Z)
		if dir.Magnitude > 0.01 then
			model:PivotTo(CFrame.lookAt(here, here + dir.Unit))
		else
			model:PivotTo(CFrame.new(here) * model:GetPivot().Rotation)
		end
	end
end

function Enemies.init()
	folder = Instance.new("Folder")
	folder.Name = "Gegner"
	folder.Parent = workspace
end

function Enemies.start()
	RunService.Heartbeat:Connect(step)
end

return Enemies
