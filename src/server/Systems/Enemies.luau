--!strict
-- Gegner-Pool und KI: Kristallschleime hüpfen auf den nächsten Spieler zu und machen
-- einen Flächenschlag mit rotem Boden-Telegraph (Ausweichen per Dash). Der Kristallkönig
-- ist ein großer Schleim, der bei halbem Leben Schleimlinge ruft.
-- Gespawnt wird nur auf Abruf (Systems/Rift). Leben/XP/Farbe liegen als Attribute am Model;
-- Schaden an Gegnern macht Systems/Combat.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Creatures = require(ReplicatedStorage.Shared.Models.Creatures)
local Combat = require(script.Parent.Combat)

type Kind = {
	name: string,
	health: number,
	damage: number,
	xp: number,
	speed: number,
	attackRange: number,
	slamRadius: number,
	windup: number,
	cooldown: number,
	scale: number,
	boss: boolean,
	color: Color3,
	core: Color3,
	ink: Color3,
}

type Enemy = {
	model: Model,
	kind: Kind,
	damage: number,
	depth: number,
	summoned: boolean,
	phase: number,
	nextAttack: number,
	windupEnd: number, -- 0 = kein Angriff in Vorbereitung
	telegraph: Part?,
	center: Vector3,
}

local Enemies = {}

local KINDS: { [string]: Kind } = {
	slime = {
		name = "Kristallschleim",
		health = 45,
		damage = 12,
		xp = 14,
		speed = 11,
		attackRange = 5,
		slamRadius = 7,
		windup = 0.9,
		cooldown = 2,
		scale = 1,
		boss = false,
		color = Color3.fromHex("#49D8D8"),
		core = Color3.fromHex("#4FD8F5"),
		ink = Color3.fromHex("#1B1830"),
	},
	boss = {
		name = "Kristallkönig",
		health = 700,
		damage = 26,
		xp = 160,
		speed = 8,
		attackRange = 11,
		slamRadius = 14,
		windup = 1.3,
		cooldown = 3,
		scale = 3,
		boss = true,
		color = Color3.fromHex("#9B6BFF"),
		core = Color3.fromHex("#E8B04A"),
		ink = Color3.fromHex("#1B1830"),
	},
}
local BOSS_SUMMONS = 4
local BASE_BODY_Y = Creatures.BODY_Y
local MIN_Z, MAX_Z, MAX_X = -26, 36, 42

local list: { Enemy } = {}
local folder: Folder
local rng = Random.new()

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildModel(kind: Kind, pos: Vector3): Model
	local m = Creatures.slime(kind.scale, kind.color, kind.core, kind.ink)
	m.Name = kind.name
	m:PivotTo(CFrame.new(pos.X, BASE_BODY_Y * kind.scale, pos.Z))
	return m
end

-- Erzeugt einen Gegner. depth skaliert Leben, Schaden und XP (siehe Config.RIFT_*_PER_DEPTH).
function Enemies.spawn(kindName: string, pos: Vector3, depth: number)
	local kind = KINDS[kindName]
	local steps = depth - 1
	local health = math.floor(kind.health * (1 + Config.RIFT_HP_PER_DEPTH * steps))
	local model = buildModel(kind, pos)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("XP", math.floor(kind.xp * (1 + Config.RIFT_XP_PER_DEPTH * steps)))
	model:SetAttribute("Color", kind.color)
	if kind.boss then
		model:SetAttribute("Boss", true)
	end
	CollectionService:AddTag(model, "Enemy")
	model.Parent = folder
	table.insert(list, {
		model = model,
		kind = kind,
		damage = math.floor(kind.damage * (1 + Config.RIFT_DMG_PER_DEPTH * steps) + 0.5),
		depth = depth,
		summoned = false,
		phase = rng:NextNumber(0, 6),
		nextAttack = os.clock() + 1,
		windupEnd = 0,
		telegraph = nil,
		center = pos,
	})
end

function Enemies.clear()
	for _, e in list do
		e.model:Destroy() -- step() räumt Liste und Telegraph beim nächsten Frame auf
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

local function clearTelegraph(e: Enemy)
	if e.telegraph then
		e.telegraph:Destroy()
		e.telegraph = nil
	end
end

local function beginWindup(e: Enemy, at: Vector3, now: number)
	local kind = e.kind
	e.windupEnd = now + kind.windup
	e.center = at
	local d = kind.slamRadius * 2
	local rot = CFrame.Angles(0, 0, math.rad(90))
	local outer = part(
		folder,
		Vector3.new(0.2, d, d),
		CFrame.new(at.X, 0.2, at.Z) * rot,
		Color3.fromHex("#FF6A3A"),
		Enum.Material.Neon
	)
	outer.Shape = Enum.PartType.Cylinder
	outer.Transparency = 0.7
	outer.CanQuery = false
	local inner = part(
		outer,
		Vector3.new(0.25, 1, 1),
		CFrame.new(at.X, 0.25, at.Z) * rot,
		Color3.fromHex("#FF3A2A"),
		Enum.Material.Neon
	)
	inner.Shape = Enum.PartType.Cylinder
	inner.Transparency = 0.45
	inner.CanQuery = false
	TweenService:Create(
		inner,
		TweenInfo.new(kind.windup, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.25, d, d) }
	):Play()
	e.telegraph = outer
end

local function resolveSlam(e: Enemy, now: number)
	clearTelegraph(e)
	e.windupEnd = 0
	e.nextAttack = now + e.kind.cooldown
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d =
				Vector3.new(root.Position.X - e.center.X, 0, root.Position.Z - e.center.Z).Magnitude
			if d <= e.kind.slamRadius then
				Combat.hurtPlayer(player, e.damage)
			end
		end
	end
end

-- Boss ruft bei halbem Leben einmal Schleimlinge um sich
local function summonAdds(e: Enemy, around: Vector3)
	e.summoned = true
	for i = 1, BOSS_SUMMONS do
		local a = (i / BOSS_SUMMONS) * math.pi * 2
		local at = around + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
		Enemies.spawn(
			"slime",
			Vector3.new(math.clamp(at.X, -MAX_X, MAX_X), 0, math.clamp(at.Z, MIN_Z, MAX_Z)),
			e.depth
		)
	end
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
		local bodyY = BASE_BODY_Y * kind.scale
		local pos = model:GetPivot().Position
		local target, targetPos, dist = nearestPlayer(pos)
		local y = bodyY
		local dir = Vector3.zero

		if
			kind.boss
			and not e.summoned
			and (model:GetAttribute("Health") or 0) :: number
				<= ((model:GetAttribute("MaxHealth") or 0) :: number) / 2
		then
			summonAdds(e, pos)
		end

		if e.windupEnd > 0 then
			-- Vorbereitung: stehen bleiben, zusammendrücken
			y = bodyY
				- 0.3 * kind.scale * math.sin((1 - (e.windupEnd - now) / kind.windup) * math.pi)
			if now >= e.windupEnd then
				resolveSlam(e, now)
			end
		elseif target and targetPos then
			dir = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
			if dist > kind.attackRange then
				dir = dir.Unit
				local speed = kind.speed
				if now < ((model:GetAttribute("SlowUntil") or 0) :: number) then
					speed *= (model:GetAttribute("SlowFactor") or 1) :: number
				end
				local nx = math.clamp(pos.X + dir.X * speed * dt, -MAX_X, MAX_X)
				local nz = math.clamp(pos.Z + dir.Z * speed * dt, MIN_Z, MAX_Z)
				y = bodyY + math.abs(math.sin(now * 7 + e.phase)) * 0.8 * kind.scale
				pos = Vector3.new(nx, pos.Y, nz)
			else
				if now >= e.nextAttack then
					beginWindup(e, Vector3.new(pos.X, 0, pos.Z), now)
				end
			end
		else
			y = bodyY + math.abs(math.sin(now * 3 + e.phase)) * 0.25 * kind.scale
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
