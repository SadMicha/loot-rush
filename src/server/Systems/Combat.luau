--!strict
-- Serverseitiger Kampf: Grundangriff (auto), 4 Skills, Trank, Dash-Unverwundbarkeit,
-- Schaden an Gegnern, XP und Level, Sonderwirkungen der Skill-Blüten und Schutz-Sterne
-- (Rüstung, Block, Arkaner Schild). Der Client schickt nur „Slot + Zielpunkt“ – alles andere prüft der Server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Data = require(script.Parent.Data)

type PState = {
	cdUntil: { number },
	basicUntil: number,
	potionUntil: number,
	iframesUntil: number,
	dashCharges: number,
	dashStamp: number,
	haste: number, -- Blüte „Tanz“: % Lauftempo bis hasteUntil
	hasteUntil: number,
	armorBuff: number, -- Blüte „Eispanzer“: % Rüstung bis armorUntil
	armorUntil: number,
	shield: number, -- Stern „Arkaner Schild“: Lebenspunkte bis shieldUntil
	shieldUntil: number,
}

local Combat = {
	-- (player, position, playerLevel, boss, skillId, xp, depth, regionId?), für Systems/Loot und Systems/Progress
	EnemyKilled = Instance.new("BindableEvent"),
	PlayerHurt = Instance.new("BindableEvent"), -- (player, amount), für Systems/Metrics
}

local states: { [Player]: PState } = {}
local rng = Random.new()
local BODY_RADIUS = 1.7 -- Gegner-Körper, wird zum Trefferradius addiert

-- Sonderwirkungen (eigene Annahmen, nicht im Balancing-Blatt)
local MAX_ARMOR = 0.75 -- Rüstung %: höchstens 75 % weniger Schaden
local MAX_BLOCK = 0.75
local SHIELD_TIME = 4 -- Arkaner Schild hält so lange
local SPLINTER_RANGE = 16 -- Krit-Splitter sucht den nächsten anderen Gegner
local BURN_TICKS, BURN_TICK = 4, 0.5 -- Brand: 2 s
local SPARK_RANGE, SPARK_SHARE = 14, 0.25 -- Funkenflug
local JUMP_SPARK_RADIUS = 4 -- Funkenregen um jeden Kettensprung
local SHATTER_RADIUS = 6 -- Eissplitter
local FIELD_TICKS, FIELD_TICK, FIELD_RADIUS, FIELD_SLOW = 6, 0.5, 0.6, 0.6 -- Frostfeld: 3 s, 60 % Radius
local BLADE_SHARE, BLADE_RANGE, BLADE_SPEED = 0.4, 20, 60 -- Klingenregen
local PULL_MIN = 2.5 -- Sog zieht nicht näher heran
local HASTE_TIME, ARMOR_TIME = 3, 3 -- Tanz, Eispanzer
local TWIN_DELAY = 0.15 -- Doppelball
local CRYSTAL = Color3.fromHex("#C9A6FF")
local ICE = Color3.fromHex("#9CE5FF")

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ground(p: Vector3): Vector3
	return Vector3.new(p.X, 0.3, p.Z)
end

local function enemyPos(e: Model): Vector3
	return e:GetPivot().Position
end

local function aliveEnemies(): { Model }
	local list: { Model } = {}
	for _, inst in CollectionService:GetTagged("Enemy") do
		if inst:IsA("Model") and (inst:GetAttribute("Health") or 0) > 0 then
			table.insert(list, inst)
		end
	end
	return list
end

local function body(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function num(player: Player, attr: string): number
	local v = player:GetAttribute(attr)
	return if typeof(v) == "number" then v else 0
end

-- Skill mit Stufe, Skill-Blüte und Sternennetz verrechnet (Shared.Progression)
local function effective(player: Player, skill: Skills.Skill): Skills.Skill
	local profile = Data.get(player)
	if not profile then
		return skill
	end
	return Progression.effectiveSkill(skill, profile.progress)
end

local function dashMax(player: Player): number
	return Config.DASH_CHARGES + num(player, "StatDash")
end

-- ------------------------------------------------------------------ Level & XP
local function xpFor(level: number): number
	return math.floor(40 * level ^ 1.5)
end
Combat.xpFor = xpFor

local function applyLevelStats(player: Player, fill: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local level = (player:GetAttribute("Level") or 1) :: number
	local bonus = (player:GetAttribute("StatLife") or 0) :: number
	humanoid.MaxHealth = (Config.BASE_HEALTH + (level - 1) * Config.HEALTH_PER_LEVEL + bonus)
		* (1 + num(player, "StatLifePct") / 100)
	if fill then
		humanoid.Health = humanoid.MaxHealth
	end
end

-- Lauftempo aus StatSpeed (Ausrüstung + Sterne) und kurzzeitigem Tempo (Blüte „Tanz“)
local function applySpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local st = states[player]
	local haste = if st and os.clock() < st.hasteUntil then st.haste else 0
	humanoid.WalkSpeed = Config.WALK_SPEED * (1 + (num(player, "StatSpeed") + haste) / 100)
end

-- Nach Änderungen an Level/Ausrüstung aufrufen
function Combat.refreshStats(player: Player, fill: boolean)
	applyLevelStats(player, fill)
	applySpeed(player)
end

local function addXP(player: Player, amount: number)
	local xp = ((player:GetAttribute("XP") or 0) :: number) + amount
	local level = (player:GetAttribute("Level") or 1) :: number
	local need = xpFor(level)
	local leveled = false
	while xp >= need do
		xp -= need
		level += 1
		need = xpFor(level)
		leveled = true
	end
	player:SetAttribute("Level", level)
	player:SetAttribute("XPNext", need)
	player:SetAttribute("XP", xp)
	local profile = Data.get(player)
	if profile then
		profile.level, profile.xp = level, xp
	end
	if leveled then
		applyLevelStats(player, true)
		local root = body(player)
		if root then
			Net.Fx:FireAllClients("levelup", { pos = root.Position, level = level })
		end
	end
end

-- ------------------------------------------------------------------ Schaden
local function enemiesNear(center: Vector3, radius: number): { Model }
	local out: { Model } = {}
	for _, e in aliveEnemies() do
		if flat(enemyPos(e) - center).Magnitude <= radius + BODY_RADIUS then
			table.insert(out, e)
		end
	end
	return out
end

local function sparkFx(from: Vector3, to: Vector3, speed: number, color: Color3): number
	local travel = flat(to - from).Magnitude / speed
	local lift = Vector3.new(0, 1.5, 0)
	Net.Fx:FireAllClients(
		"proj",
		{ from = from + lift, to = to + lift, time = travel, color = color, size = 0.6 }
	)
	return travel
end

-- Blüte „Eissplitter“: verlangsamte Gegner (bis untilT) platzen beim Tod
local shatterOn: { [Model]: { amount: number, untilT: number } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

-- proc = Folgeschaden (Brand, Funken, Splitter …): trifft nie kritisch und löst nichts weiter aus
local damageEnemy: (
	enemy: Model,
	base: number,
	player: Player,
	skill: Skills.Skill?,
	proc: boolean?
) -> ()

local function burn(enemy: Model, total: number, player: Player, skill: Skills.Skill)
	task.spawn(function()
		for _ = 1, BURN_TICKS do
			task.wait(BURN_TICK)
			if not enemy.Parent or not player.Parent then
				return
			end
			damageEnemy(enemy, total / BURN_TICKS, player, skill, true)
		end
	end)
end

-- Stern „Kristallklinge“: ein Krit wirft einen Splitter auf den nächsten anderen Gegner
local function splinter(
	from: Vector3,
	source: Model,
	amount: number,
	player: Player,
	skill: Skills.Skill?
)
	local target: Model? = nil
	local best = SPLINTER_RANGE
	for _, e in aliveEnemies() do
		local d = flat(enemyPos(e) - from).Magnitude
		if e ~= source and d <= best then
			best = d
			target = e
		end
	end
	if not target then
		return
	end
	local hit = target
	task.delay(sparkFx(from, enemyPos(hit), 80, CRYSTAL), function()
		if player.Parent then
			damageEnemy(hit, amount, player, skill, true)
		end
	end)
end

local function shatter(pos: Vector3, amount: number, player: Player, skill: Skills.Skill?)
	Net.Fx:FireAllClients("nova", { pos = ground(pos), radius = SHATTER_RADIUS, color = ICE })
	for _, e in enemiesNear(pos, SHATTER_RADIUS) do
		damageEnemy(e, amount, player, skill, true)
	end
end

damageEnemy = function(
	enemy: Model,
	base: number,
	player: Player,
	skill: Skills.Skill?,
	proc: boolean?
)
	if not enemy.Parent then -- schon zerstört (z. B. von einer Kettenreaktion)
		return
	end
	local hp = (enemy:GetAttribute("Health") or 0) :: number
	if hp <= 0 then
		return
	end
	local level = (player:GetAttribute("Level") or 1) :: number
	local critChance = Config.CRIT_CHANCE + ((player:GetAttribute("StatCrit") or 0) :: number) / 100
	local bonus = ((player:GetAttribute("StatDamage") or 0) :: number) / 100
	local _, humanoid = body(player)
	if humanoid and humanoid.Health < humanoid.MaxHealth * 0.3 then
		bonus += num(player, "StatLowLife") / 100
	end
	local crit = not proc and rng:NextNumber() < critChance
	local critMult = Config.CRIT_MULT + num(player, "StatCritDamage") / 100
	local amount = base
		* (1 + (level - 1) * Config.DAMAGE_PER_LEVEL + bonus)
		* (if crit then critMult else 1)
	amount = math.max(1, math.floor(amount + 0.5))
	hp = math.max(0, hp - amount)
	enemy:SetAttribute("Health", hp)
	local pos = enemyPos(enemy)
	Net.Fx:FireAllClients(
		"dmg",
		{ pos = pos + Vector3.new(0, 3.5, 0), amount = amount, crit = crit }
	)

	if skill and not proc then
		if skill.slow then
			local untilT = os.clock() + (skill.slowTime or 2)
			enemy:SetAttribute("SlowUntil", untilT)
			enemy:SetAttribute("SlowFactor", skill.slow)
			if skill.shatter then
				shatterOn[enemy] = { amount = skill.damage * skill.shatter, untilT = untilT }
			end
		end
		if skill.burn and hp > 0 then
			burn(enemy, base * skill.burn, player, skill)
		end
	end
	local shardPct = num(player, "StatCritShard")
	if crit and shardPct > 0 then
		splinter(pos, enemy, base * critMult * shardPct / 100, player, skill)
	end

	if hp <= 0 then
		local color = enemy:GetAttribute("Color")
		Net.Fx:FireAllClients(
			"death",
			{ pos = pos, color = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1) }
		)
		local xp = (enemy:GetAttribute("XP") or 0) :: number
		local boss = enemy:GetAttribute("Boss") == true
		local depth = enemy:GetAttribute("Depth")
		local region = enemy:GetAttribute("Region")
		local burst = shatterOn[enemy]
		shatterOn[enemy] = nil
		enemy:Destroy()
		if burst and os.clock() < burst.untilT and player.Parent then
			shatter(pos, burst.amount, player, skill)
		end
		if player.Parent then
			addXP(player, xp)
			Combat.EnemyKilled:Fire(
				player,
				pos,
				(player:GetAttribute("Level") or 1) :: number,
				boss,
				if skill then skill.id else nil,
				xp,
				if typeof(depth) == "number" then depth else 1,
				region
			)
		end
	end
end

-- Wird von der Gegner-KI aufgerufen. Gibt true zurück, wenn der Treffer durchkam.
function Combat.hurtPlayer(player: Player, amount: number): boolean
	local st = states[player]
	local root, humanoid = body(player)
	if not st or not root or not humanoid then
		return false
	end
	if os.clock() < st.iframesUntil then
		Net.Fx:FireAllClients(
			"dmg",
			{ pos = root.Position + Vector3.new(0, 3, 0), text = "Ausgewichen", dodge = true }
		)
		return false
	end
	-- Stern „Schildwall“
	if rng:NextNumber() < math.min(MAX_BLOCK, num(player, "StatBlock") / 100) then
		Net.Fx:FireAllClients(
			"dmg",
			{ pos = root.Position + Vector3.new(0, 3, 0), text = "Geblockt!", color = ICE }
		)
		return false
	end
	-- Rüstung % = weniger Schaden (Stern „Eisenhaut“ + Blüte „Eispanzer“)
	local now = os.clock()
	local armor = num(player, "StatArmor") + (if now < st.armorUntil then st.armorBuff else 0)
	if armor > 0 then
		amount = math.max(1, math.floor(amount * (1 - math.min(MAX_ARMOR, armor / 100)) + 0.5))
	end
	-- Arkaner Schild fängt zuerst ab
	if st.shield > 0 and now < st.shieldUntil then
		local absorbed = math.min(st.shield, amount)
		st.shield -= absorbed
		amount -= absorbed
		player:SetAttribute("Shield", math.floor(st.shield + 0.5))
		if amount <= 0 then
			Net.Fx:FireAllClients(
				"dmg",
				{ pos = root.Position + Vector3.new(0, 3, 0), text = "Schild", color = CRYSTAL }
			)
			return true
		end
	end
	humanoid.Health -= amount
	Combat.PlayerHurt:Fire(player, amount)
	Net.Fx:FireAllClients(
		"dmg",
		{ pos = root.Position + Vector3.new(0, 3, 0), amount = amount, hurt = true }
	)
	return true
end

-- ------------------------------------------------------------------ Skills

local AIM_ASSIST = 6 -- Studs: Gegner in dieser Nähe zum Mauszeiger werden anvisiert

local function castProjectile(
	player: Player,
	root: BasePart,
	skill: Skills.Skill,
	aim: Vector3,
	from: Vector3
): boolean
	local assist = math.huge
	for _, e in aliveEnemies() do
		local p = enemyPos(e)
		local d = flat(p - aim).Magnitude
		if d <= AIM_ASSIST and d < assist and flat(p - from).Magnitude <= skill.range + 5 then
			assist = d
			aim = p
		end
	end
	local dir = flat(aim - from)
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	dir = dir.Unit

	-- Erster Gegner auf der Linie stoppt das Projektil (Blüte „Durchschlag“: erst der zweite)
	local reach, second = skill.range, skill.range
	local first: Model? = nil
	for _, e in aliveEnemies() do
		local rel = flat(enemyPos(e) - from)
		local t = rel:Dot(dir)
		if t > 0 and t < second and (rel - dir * t).Magnitude <= BODY_RADIUS + 0.8 then
			if t < reach then
				reach, second, first = t, reach, e
			else
				second = t
			end
		end
	end
	local speed = skill.speed or 60
	if first and skill.pierce and rng:NextNumber() < skill.pierce then
		local pierced = first
		task.delay(reach / speed, function()
			if player.Parent then
				damageEnemy(pierced, skill.damage, player, skill)
			end
		end)
		reach = second
	end
	local finish = from + dir * reach
	local travel = reach / speed
	local lift = Vector3.new(0, 0.5, 0)
	Net.Fx:FireAllClients("proj", {
		from = from + lift,
		to = finish + lift,
		time = travel,
		color = skill.color,
		size = if skill.radius > 3 then 1.8 else 0.9,
	})
	task.delay(travel, function()
		if skill.radius > 3 then
			Net.Fx:FireAllClients(
				"nova",
				{ pos = ground(finish), radius = skill.radius, color = skill.color }
			)
		end
		if not player.Parent then
			return
		end
		for _, e in enemiesNear(finish, skill.radius) do
			damageEnemy(e, skill.damage, player, skill)
		end
		-- Blüte „Funkenflug“: Funken zu den nächsten Gegnern, zuerst die außerhalb der Explosion
		local sparks = skill.sparks
		if sparks then
			local list = enemiesNear(finish, SPARK_RANGE)
			local function key(e: Model): number
				local d = flat(enemyPos(e) - finish).Magnitude
				return if d <= skill.radius + BODY_RADIUS then d + 1000 else d
			end
			table.sort(list, function(a, b)
				return key(a) < key(b)
			end)
			for i = 1, math.min(sparks, #list) do
				local e = list[i]
				task.delay(sparkFx(finish, enemyPos(e), 60, skill.color), function()
					if player.Parent then
						damageEnemy(e, skill.damage * SPARK_SHARE, player, skill, true)
					end
				end)
			end
		end
	end)
	return true
end

local function castNova(player: Player, root: BasePart, skill: Skills.Skill): boolean
	local center = root.Position
	local st = states[player]
	local now = os.clock()
	Net.Fx:FireAllClients(
		"nova",
		{ pos = ground(center), radius = skill.radius, color = skill.color }
	)
	local hits = enemiesNear(center, skill.radius)
	for _, e in hits do
		damageEnemy(e, skill.damage, player, skill)
	end
	-- Blüte „Sog“: Überlebende zur Mitte ziehen
	local pull = skill.pull
	if pull then
		for _, e in hits do
			if e.Parent then
				local p = enemyPos(e)
				local rel = flat(p - center)
				local d = rel.Magnitude
				if d > PULL_MIN then
					e:PivotTo(
						CFrame.new(p - rel.Unit * math.min(pull, d - PULL_MIN))
							* e:GetPivot().Rotation
					)
				end
			end
		end
	end
	-- Blüte „Klingenregen“: Klingen fliegen gleichmäßig verteilt nach außen
	local blades = skill.blades
	if blades then
		local blade: Skills.Skill = table.freeze({
			id = skill.id,
			name = skill.name,
			desc = skill.desc,
			icon = skill.icon,
			color = skill.color,
			kind = "projectile" :: Skills.Kind,
			damage = skill.damage * BLADE_SHARE,
			cooldown = 0,
			range = BLADE_RANGE,
			radius = 1.5,
			speed = BLADE_SPEED,
		})
		local turn = rng:NextNumber() * math.pi * 2
		for i = 1, blades do
			local a = turn + i / blades * math.pi * 2
			castProjectile(
				player,
				root,
				blade,
				center + Vector3.new(math.cos(a), 0, math.sin(a)) * BLADE_RANGE,
				center
			)
		end
	end
	-- Blüte „Tanz“: nach einem Treffer kurz schneller
	if st and skill.haste and #hits > 0 then
		st.haste = skill.haste
		st.hasteUntil = now + HASTE_TIME
		applySpeed(player)
		task.delay(HASTE_TIME + 0.05, applySpeed, player)
	end
	-- Blüte „Eispanzer“
	if st and skill.armorBuff then
		st.armorBuff = skill.armorBuff
		st.armorUntil = now + ARMOR_TIME
	end
	-- Blüte „Frostfeld“: Eisfeld an der Stelle, verlangsamt und trifft alle 0,5 s
	local field = skill.field
	if field then
		local r = skill.radius * FIELD_RADIUS
		task.spawn(function()
			for i = 1, FIELD_TICKS do
				task.wait(FIELD_TICK)
				if not player.Parent then
					return
				end
				if i % 2 == 1 then
					Net.Fx:FireAllClients("nova", { pos = ground(center), radius = r, color = ICE })
				end
				for _, e in enemiesNear(center, r) do
					local untilT = os.clock() + FIELD_TICK * 2
					if ((e:GetAttribute("SlowUntil") or 0) :: number) < untilT then
						e:SetAttribute("SlowUntil", untilT)
						e:SetAttribute("SlowFactor", skill.slow or FIELD_SLOW)
					end
					damageEnemy(e, skill.damage * field, player, skill, true)
				end
			end
		end)
	end
	-- Skill-Blüte „Nachhall“: zweiter Wirbel kurz danach
	local echo = skill.echo
	if echo then
		task.delay(0.35, function()
			local r = body(player)
			if not r or not player.Parent then
				return
			end
			Net.Fx:FireAllClients(
				"nova",
				{ pos = ground(r.Position), radius = skill.radius, color = skill.color }
			)
			for _, e in enemiesNear(r.Position, skill.radius) do
				damageEnemy(e, skill.damage * echo, player, skill)
			end
		end)
	end
	return true
end

local function castChain(player: Player, root: BasePart, skill: Skills.Skill, aim: Vector3): boolean
	local pool = aliveEnemies()
	local current: Model? = nil
	local best = math.huge
	for _, e in pool do
		local p = enemyPos(e)
		if flat(p - root.Position).Magnitude <= skill.range then
			local d = flat(p - aim).Magnitude
			if d < best then
				best = d
				current = e
			end
		end
	end
	if not current then
		return false
	end

	local points: { Vector3 } = { root.Position }
	local hit: { [Model]: boolean } = {}
	local left = skill.chains or 3
	local first, firstPos = current, enemyPos(current)
	while current and left > 0 do
		local e = current
		hit[e] = true
		local p = enemyPos(e)
		table.insert(points, p)
		local last = if left == 1 then skill.lastHit else nil
		damageEnemy(e, skill.damage * (if last then 1 + last else 1), player, skill)
		-- Blüte „Funkenregen“: Funken um jeden Sprung
		if skill.jumpSpark then
			Net.Fx:FireAllClients(
				"nova",
				{ pos = ground(p), radius = JUMP_SPARK_RADIUS, color = skill.color }
			)
			for _, o in enemiesNear(p, JUMP_SPARK_RADIUS) do
				if o ~= e then
					damageEnemy(o, skill.damage * skill.jumpSpark, player, skill, true)
				end
			end
		end
		left -= 1
		current = nil
		local nearest = skill.radius
		for _, other in pool do
			if not hit[other] and (other:GetAttribute("Health") or 0) > 0 then
				local d = flat(enemyPos(other) - p).Magnitude
				if d <= nearest then
					nearest = d
					current = other
				end
			end
		end
	end
	Net.Fx:FireAllClients("chain", { points = points, color = skill.color })
	-- Blüte „Verzweigung“: vom ersten Treffer auf die 2 nächsten anderen Gegner
	local fork = skill.fork
	if fork then
		local near = enemiesNear(firstPos, skill.radius)
		table.sort(near, function(a, b)
			return flat(enemyPos(a) - firstPos).Magnitude < flat(enemyPos(b) - firstPos).Magnitude
		end)
		local n = 0
		for _, o in near do
			if o ~= first and n < 2 then
				n += 1
				Net.Fx:FireAllClients(
					"chain",
					{ points = { firstPos, enemyPos(o) }, color = skill.color }
				)
				damageEnemy(o, skill.damage * fork, player, skill, true)
			end
		end
	end
	return true
end

local function cast(player: Player, slot: number, aim: Vector3, origin: Vector3)
	local base = Skills.bar[slot]
	local st = states[player]
	local root = body(player)
	if not base or not st or not root then
		return
	end
	local skill = effective(player, base)
	local now = os.clock()
	if now < st.cdUntil[slot] then
		return
	end
	-- Der Client kennt seine eigene Position genauer (Server hinkt beim Laufen); nur glaubhafte Werte nehmen
	if flat(origin - root.Position).Magnitude > 12 then
		origin = root.Position
	end
	local ok = false
	if skill.kind == "projectile" then
		ok = castProjectile(player, root, skill, aim, origin)
	elseif skill.kind == "nova" then
		ok = castNova(player, root, skill)
	elseif skill.kind == "chain" then
		ok = castChain(player, root, skill, aim)
	end
	if not ok then
		return
	end
	st.cdUntil[slot] = now + skill.cooldown
	-- Blüte „Doppelball“: zweiter Ball kurz danach
	local twin = skill.twin
	if skill.kind == "projectile" and twin then
		local copy = table.clone(skill)
		copy.damage *= twin
		copy.twin = nil
		task.delay(TWIN_DELAY, function()
			local r = body(player)
			if r and player.Parent then
				castProjectile(player, r, copy, aim, r.Position)
			end
		end)
	end
	-- Stern „Arkaner Schild“: nach jedem Skill ein Schild (frischt auf, stapelt nicht)
	local _, humanoid = body(player)
	local pct = num(player, "StatArcaneShield")
	if humanoid and pct > 0 then
		if now >= st.shieldUntil then
			st.shield = 0
		end
		st.shield = math.max(st.shield, humanoid.MaxHealth * pct / 100)
		st.shieldUntil = now + SHIELD_TIME
		player:SetAttribute("Shield", math.floor(st.shield + 0.5))
		task.delay(SHIELD_TIME, function()
			if states[player] == st and os.clock() >= st.shieldUntil - 0.01 then
				st.shield = 0
				player:SetAttribute("Shield", 0)
			end
		end)
	end
end

-- ------------------------------------------------------------------ Dash & Trank
local function dash(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local now = os.clock()
	local max = dashMax(player)
	if st.dashCharges < max then
		local gained = math.floor((now - st.dashStamp) / Config.DASH_RECHARGE)
		if gained > 0 then
			st.dashCharges = math.min(max, st.dashCharges + gained)
			st.dashStamp += gained * Config.DASH_RECHARGE
		end
	end
	if st.dashCharges >= max then
		st.dashStamp = now
	end
	if st.dashCharges <= 0 then
		return
	end
	st.dashCharges -= 1
	st.iframesUntil = now + Config.DASH_IFRAMES
end

local function usePotion(player: Player)
	local st = states[player]
	local root, humanoid = body(player)
	if not st or not root or not humanoid then
		return
	end
	local now = os.clock()
	if now < st.potionUntil or humanoid.Health >= humanoid.MaxHealth then
		return
	end
	st.potionUntil = now + Config.POTION_COOLDOWN
	local heal = math.floor(humanoid.MaxHealth * Config.POTION_HEAL)
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
	Net.Fx:FireAllClients(
		"dmg",
		{ pos = root.Position + Vector3.new(0, 3, 0), amount = heal, heal = true }
	)
end

-- ------------------------------------------------------------------ Lebenszyklus
local function onPlayer(player: Player)
	states[player] = {
		cdUntil = { 0, 0, 0, 0 },
		basicUntil = 0,
		potionUntil = 0,
		iframesUntil = 0,
		dashCharges = Config.DASH_CHARGES,
		dashStamp = os.clock(),
		haste = 0,
		hasteUntil = 0,
		armorBuff = 0,
		armorUntil = 0,
		shield = 0,
		shieldUntil = 0,
	}
	player:SetAttribute("Level", 1)
	player:SetAttribute("XP", 0)
	player:SetAttribute("XPNext", xpFor(1))
	task.spawn(function()
		local profile = Data.waitFor(player)
		if profile then
			player:SetAttribute("Level", profile.level)
			player:SetAttribute("XP", profile.xp)
			player:SetAttribute("XPNext", xpFor(profile.level))
			applyLevelStats(player, true)
		end
	end)

	local function onCharacter(character: Model)
		character:WaitForChild("Humanoid")
		applyLevelStats(player, true)
		applySpeed(player)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

function Combat.init()
	Players.RespawnTime = Config.RESPAWN_TIME

	Net.CastSkill.OnServerEvent:Connect(function(player: Player, slot: any, aim: any, origin: any)
		if typeof(slot) ~= "number" or typeof(aim) ~= "Vector3" or typeof(origin) ~= "Vector3" then
			return
		end
		if not ((aim :: Vector3).Magnitude < 1e6 and (origin :: Vector3).Magnitude < 1e6) then -- fängt NaN und unendlich ab
			return
		end
		cast(player, slot, aim, origin)
	end)
	Net.UsePotion.OnServerEvent:Connect(usePotion)
	Net.Dash.OnServerEvent:Connect(dash)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

function Combat.start()
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	-- Grundangriff: automatisch auf den nächsten Gegner in Reichweite
	while true do
		task.wait(0.1)
		local now = os.clock()
		local pool = aliveEnemies()
		for player, st in states do
			if now >= st.basicUntil then
				local root = body(player)
				if root then
					local basic = effective(player, Skills.basic)
					local target: Model? = nil
					local best = basic.range
					for _, e in pool do
						local d = flat(enemyPos(e) - root.Position).Magnitude
						if d <= best then
							best = d
							target = e
						end
					end
					if target then
						st.basicUntil = now + basic.cooldown
						-- Stern „Doppelschlag“: Chance auf doppelten Treffer
						if rng:NextNumber() < num(player, "StatDouble") / 100 then
							local double = table.clone(basic)
							double.damage *= 2
							basic = double
						end
						castProjectile(player, root, basic, enemyPos(target), root.Position)
					end
				end
			end
		end
	end
end

return Combat
