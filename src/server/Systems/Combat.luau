--!strict
-- Server-side combat: basic attack (auto), 4 skills, dash invulnerability,
-- damage to enemies, XP and level, special effects of Skill Blooms and protection stars
-- (armor, block, Arcane Shield). The client only sends "slot + target point" - the server checks everything else.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Balance)
local Config = require(ReplicatedStorage.Shared.Config)
local Crit = require(ReplicatedStorage.Shared.Crit)
local Net = require(ReplicatedStorage.Shared.Net)
local Classes = require(ReplicatedStorage.Shared.Classes)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Rush = require(ReplicatedStorage.Shared.Rush)
local Skills = require(ReplicatedStorage.Shared.Skills)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Movement = require(script.Parent.Movement)
local Status = require(script.Parent.Status)

type PState = {
	cdUntil: { [string]: number }, -- per skill id (swapping the bar does not reset cooldowns)
	basicUntil: number,
	iframesUntil: number,
	dashCharges: number,
	dashStamp: number,
	haste: number, -- Bloom "Storm Rider": % move speed until hasteUntil
	hasteUntil: number,
	chill: number, -- Frozen aura elites: % move speed lost until chillUntil
	chillUntil: number,
	armorBuff: number, -- Bloom "Ice Armor": % armor until armorUntil
	armorUntil: number,
	shield: number, -- Star "Arcane Shield": life points until shieldUntil
	shieldUntil: number,
	buffDamage: number, -- buff skills (Battle Cry): % damage until buffUntil
	buffUntil: number,
}

local Combat = {
	-- (player, position, playerLevel, boss, skillId, xp, depth, regionId?, gold), for Systems/Loot and Systems/Progress
	EnemyKilled = Instance.new("BindableEvent"),
	PlayerHurt = Instance.new("BindableEvent"), -- (player, amount), for Systems/Metrics
	EnemyDied = Instance.new("BindableEvent"), -- (enemy, pos, killer) right before the model is destroyed
	EnemyHit = Instance.new("BindableEvent"), -- (enemy, from: Vector3, crit), direct hits; knockback in Systems/Enemies
}

local states: { [Player]: PState } = {}
-- Remote throttle (cast checks cooldowns itself; this only slows down spam)
local allowCast = RateLimit.new(20, 30)
local allowAction = RateLimit.new(8, 12)
local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end
local BODY_RADIUS = 1.7 -- enemy body, added to the hit radius

-- Special effects (own assumptions, not in the balancing sheet)
local MAX_ARMOR = 0.75 -- armor %: at most 75% less damage
local MAX_BLOCK = 0.75
local SHIELD_TIME = 4 -- Arcane Shield lasts this long
local SPLINTER_RANGE = 16 -- Crit Shard looks for the nearest other enemy
local BURN_TICKS, BURN_TICK = 4, 0.5 -- Burn: 2 s
local SPARK_RANGE, SPARK_SHARE = 14, 0.25 -- Spark Flight
local JUMP_SPARK_RADIUS = 4 -- Spark Rain around every chain jump
local SHATTER_RADIUS = 6 -- Ice Shards
local FIELD_TICKS, FIELD_TICK, FIELD_RADIUS, FIELD_SLOW = 6, 0.5, 0.6, 0.6 -- Frost Field: 3 s, 60% radius
local BOLT_SHARE, BOLT_RANGE, BOLT_SPEED = 0.4, 20, 60 -- Bolt Rain
local PULL_MIN = 2.5 -- Pull does not pull any closer
local HASTE_TIME, ARMOR_TIME = 3, 3 -- Storm Rider, Ice Armor
local TWIN_DELAY = 0.15 -- Twin Ball
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

-- Tells every client to animate an attack, cast or dash of `player` (AnimController, Shared/Anim).
-- Purely visual: the client picks the move from the class weapon and the skill kind.
local function act(player: Player, kind: string, skillId: string?, basic: boolean, at: Vector3?)
	Net.Fx:FireAllClients("act", {
		by = player.UserId,
		kind = kind,
		skill = skillId,
		basic = basic,
		at = at,
	})
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

-- Skill with level, Skill Bloom and Star Net applied (Shared.Progression)
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
-- XP from level L to L + 1 (balancing: 100 × L^1.6)
local function xpFor(level: number): number
	return Balance.xpForLevel(level)
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
	humanoid.MaxHealth = (Balance.life(level) + bonus)
		* (1 + num(player, "StatLifePct") / 100)
		* (1 + num(player, "BonusLife") / 100) -- pet, passes … (Systems/Boosts)
	if fill then
		humanoid.Health = humanoid.MaxHealth
	end
end

-- Move speed from StatSpeed (gear + stars) and short-term speed (bloom "Storm Rider")
local function applySpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local st = states[player]
	local now = os.clock()
	local haste = if st and now < st.hasteUntil then st.haste else 0
	local chill = if st and now < st.chillUntil then st.chill else 0
	local rush = if player:GetAttribute("Rushing") == true then Rush.SPEED else 0
	humanoid.WalkSpeed = Config.WALK_SPEED
		* (1 + (num(player, "StatSpeed") + haste + rush) / 100)
		* (1 - math.clamp(chill, 0, 90) / 100)
end

-- Move speed changed from outside (Stud Rush start/end, Systems/Rush)
function Combat.speedChanged(player: Player)
	applySpeed(player)
end

-- Frozen aura (Systems/Enemies): slows the player by `pct` % until `untilT`; refreshing is cheap
function Combat.chill(player: Player, untilT: number, pct: number)
	local st = states[player]
	if not st then
		return
	end
	local fresh = os.clock() >= st.chillUntil
	st.chill = pct
	st.chillUntil = math.max(st.chillUntil, untilT)
	Status.set(player, "chill", st.chillUntil - os.clock())
	if fresh then
		applySpeed(player)
		player:SetAttribute("Chilled", true)
		task.spawn(function()
			while states[player] == st and os.clock() < st.chillUntil do
				task.wait(st.chillUntil - os.clock() + 0.05)
			end
			if player.Parent then
				player:SetAttribute("Chilled", nil)
				Status.clear(player, "chill")
				applySpeed(player)
			end
		end)
	end
end

-- Call after changes to level/gear
function Combat.refreshStats(player: Player, fill: boolean)
	applyLevelStats(player, fill)
	applySpeed(player)
end

local function addXP(player: Player, amount: number)
	local xp = ((player:GetAttribute("XP") or 0) :: number) + amount
	local level = (player:GetAttribute("Level") or 1) :: number
	local need = xpFor(level)
	local leveled = false
	while xp >= need and level < Balance.P.level_max do
		xp -= need
		level += 1
		need = xpFor(level)
		leveled = true
	end
	if level >= Balance.P.level_max then
		xp = math.min(xp, need)
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
			Net.Fx:FireAllClients(
				"levelup",
				{ pos = root.Position, level = level, who = player.UserId }
			)
		end
	end
end

-- Set level and XP directly (test commands); refills life
function Combat.setLevel(player: Player, level: number, xp: number)
	player:SetAttribute("Level", level)
	player:SetAttribute("XP", xp)
	player:SetAttribute("XPNext", xpFor(level))
	local profile = Data.get(player)
	if profile then
		profile.level, profile.xp = level, xp
	end
	Combat.refreshStats(player, true)
end

-- ------------------------------------------------------------------ Damage
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

-- Bloom "Ice Shards": slowed enemies (until untilT) shatter on death
local shatterOn: { [Model]: { amount: number, untilT: number } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

-- proc = follow-up damage (burn, sparks, shards …): never crits and triggers nothing further
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

-- Star "Crystal Blade": a crit throws a shard at the nearest other enemy
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
	if not enemy.Parent then -- already destroyed (e.g. by a chain reaction)
		return
	end
	local hp = (enemy:GetAttribute("Health") or 0) :: number
	if hp <= 0 then
		return
	end
	local level = (player:GetAttribute("Level") or 1) :: number
	local critChance = Config.CRIT_CHANCE + ((player:GetAttribute("StatCrit") or 0) :: number) / 100
	local bonus = ((player:GetAttribute("StatDamage") or 0) :: number) / 100
	local pst = states[player]
	if pst and os.clock() < pst.buffUntil then
		bonus += pst.buffDamage / 100
	end
	local _, humanoid = body(player)
	if humanoid and humanoid.Health < humanoid.MaxHealth * 0.3 then
		bonus += num(player, "StatLowLife") / 100
	end
	local tier = if proc then 0 else Crit.rollTier(critChance, roll) -- overcrit: Shared/Crit
	local crit = tier >= 1
	local critMult = Config.CRIT_MULT + num(player, "StatCritDamage") / 100
	local weapon = num(player, "StatWeapon") -- weapon base damage as a factor (Systems/Stats)
	local amount = Crit.damage(
		base
			* (if weapon > 0 then weapon else 1)
			* (1 + (level - 1) * Config.DAMAGE_PER_LEVEL + bonus)
			* (1 + num(player, "BonusDamage") / 100), -- pet, passes … (Systems/Boosts)
		tier,
		critMult
	)
	amount = math.max(1, math.floor(amount + 0.5))
	-- Shielded elites (Shared/EliteMods): the shield takes the damage first
	local toLife = amount
	local shield = enemy:GetAttribute("Shield")
	if typeof(shield) == "number" and shield > 0 then
		local absorbed = math.min(shield, toLife)
		enemy:SetAttribute("Shield", shield - absorbed)
		toLife -= absorbed
	end
	hp = math.max(0, hp - toLife)
	enemy:SetAttribute("Health", hp)
	local pos = enemyPos(enemy)
	local big = enemy:GetAttribute("Boss") == true or enemy:GetAttribute("Elite") == true
	-- target/by/big drive the client juice (hit flash, chips, hitstop, shake: FeelController)
	Net.Fx:FireAllClients("dmg", {
		pos = pos + Vector3.new(0, 3.5, 0),
		amount = amount,
		crit = crit,
		critTier = if crit then tier else nil,
		target = enemy,
		by = player.UserId,
		big = big,
	})
	if not proc and hp > 0 then
		local root = body(player)
		if root then
			Combat.EnemyHit:Fire(enemy, root.Position, crit)
		end
	end

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
		Net.Fx:FireAllClients("death", {
			pos = pos,
			color = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1),
			by = player.UserId,
			big = big,
			boss = enemy:GetAttribute("Boss") == true,
		})
		local xp = math.floor(
			((enemy:GetAttribute("XP") or 0) :: number) * (1 + num(player, "BonusXP") / 100) + 0.5
		)
		local boss = enemy:GetAttribute("Boss") == true
		local elite = enemy:GetAttribute("Elite") == true
		local depth = enemy:GetAttribute("Depth")
		local region = enemy:GetAttribute("Region")
		local gold = enemy:GetAttribute("Gold")
		local burst = shatterOn[enemy]
		shatterOn[enemy] = nil
		Combat.EnemyDied:Fire(enemy, pos, player)
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
				region,
				if typeof(gold) == "number" then gold else 0,
				elite
			)
		end
	end
end

-- One hit with the full damage formula (crit tiers included); also used by the specs
Combat.damageEnemy = damageEnemy

-- Test command (Systems/Debug): defeat an enemy instantly, loot and XP as with a real kill
function Combat.slay(player: Player, enemy: Model)
	damageEnemy(enemy, 1e9, player, nil, true)
end

-- Called by the enemy AI. Returns true if the hit got through.
function Combat.hurtPlayer(player: Player, amount: number): boolean
	local st = states[player]
	local root, humanoid = body(player)
	if not st or not root or not humanoid then
		return false
	end
	if os.clock() < st.iframesUntil then
		Net.Fx:FireAllClients("dmg", {
			pos = root.Position + Vector3.new(0, 3, 0),
			text = "Dodged",
			dodge = true,
			who = player.UserId,
		})
		return false
	end
	-- Star "Shield Wall"
	if rng:NextNumber() < math.min(MAX_BLOCK, num(player, "StatBlock") / 100) then
		Net.Fx:FireAllClients("dmg", {
			pos = root.Position + Vector3.new(0, 3, 0),
			text = "Blocked!",
			color = ICE,
			who = player.UserId,
		})
		return false
	end
	-- Armor % = less damage (star "Iron Skin" + bloom "Ice Armor")
	local now = os.clock()
	local armor = num(player, "StatArmor") + (if now < st.armorUntil then st.armorBuff else 0)
	if armor > 0 then
		amount = math.max(1, math.floor(amount * (1 - math.min(MAX_ARMOR, armor / 100)) + 0.5))
	end
	-- Arcane Shield absorbs first
	if st.shield > 0 and now < st.shieldUntil then
		local absorbed = math.min(st.shield, amount)
		st.shield -= absorbed
		amount -= absorbed
		player:SetAttribute("Shield", math.floor(st.shield + 0.5))
		if st.shield <= 0 then
			Status.clear(player, "shield")
		end
		if amount <= 0 then
			Net.Fx:FireAllClients("dmg", {
				pos = root.Position + Vector3.new(0, 3, 0),
				text = "Shield",
				color = CRYSTAL,
				who = player.UserId,
			})
			return true
		end
	end
	humanoid.Health -= amount
	Combat.PlayerHurt:Fire(player, amount)
	Net.Fx:FireAllClients("dmg", {
		pos = root.Position + Vector3.new(0, 3, 0),
		amount = amount,
		hurt = true,
		who = player.UserId,
	})
	return true
end

-- ------------------------------------------------------------------ Skills

local AIM_ASSIST = 6 -- studs: enemies this close to the mouse pointer get targeted

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

	-- The first enemy on the line stops the projectile (bloom "Pierce": only the second one)
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
		-- Bloom "Spark Flight": sparks to the nearest enemies, those outside the explosion first
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

-- Arrow Volley and friends: `count` projectiles spread over `spread` degrees around the aim
local function castFan(
	player: Player,
	root: BasePart,
	skill: Skills.Skill,
	aim: Vector3,
	from: Vector3
): boolean
	local count = math.max(1, math.floor(skill.count or 1))
	if count == 1 then
		return castProjectile(player, root, skill, aim, from)
	end
	local dir = flat(aim - from)
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	local spread = math.rad(skill.spread or 30)
	local one = table.clone(skill)
	one.count = nil
	local single = table.freeze(one) :: Skills.Skill
	for i = 1, count do
		local a = -spread / 2 + spread * (i - 1) / (count - 1)
		local d = CFrame.Angles(0, a, 0):VectorToWorldSpace(dir.Unit)
		castProjectile(player, root, single, from + d * skill.range, from)
	end
	return true
end

-- Melee arc: everything inside the cone toward the aim (sword swings, Shield Bash)
local function castArc(player: Player, root: BasePart, skill: Skills.Skill, aim: Vector3): boolean
	local from = root.Position
	local dir = flat(aim - from)
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	dir = dir.Unit
	local half = math.rad(skill.arc or 90) / 2
	local reach = skill.range
	Net.Fx:FireAllClients("arc", {
		pos = ground(from),
		dir = dir,
		radius = reach,
		arc = skill.arc or 90,
		color = skill.color,
	})
	for _, e in enemiesNear(from, reach) do
		local rel = flat(enemyPos(e) - from)
		if
			rel.Magnitude < BODY_RADIUS + 1
			or math.acos(math.clamp(rel.Unit:Dot(dir), -1, 1)) <= half
		then
			damageEnemy(e, skill.damage, player, skill)
			if skill.slow then
				e:SetAttribute("SlowUntil", os.clock() + (skill.slowTime or 1))
				e:SetAttribute("SlowFactor", skill.slow)
			end
		end
	end
	return true
end

-- Leap: jump to the aim (at most `range` away, inside the own arena) and hit around the landing
local function castLeap(player: Player, root: BasePart, skill: Skills.Skill, aim: Vector3): boolean
	local from = root.Position
	local rel = flat(aim - from)
	if rel.Magnitude > skill.range then
		rel = rel.Unit * skill.range
	end
	local land = from + rel
	-- never leap through walls: stop in front of the first obstacle
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	if rel.Magnitude > 0.5 then
		local hit = workspace:Raycast(from, rel, params)
		if hit then
			land = hit.Position - rel.Unit * 2
		end
	end
	Movement.teleported(player)
	root.CFrame = CFrame.new(Vector3.new(land.X, from.Y, land.Z)) * root.CFrame.Rotation
	local st = states[player]
	if st then -- short invulnerability while flying in
		st.iframesUntil = math.max(st.iframesUntil, os.clock() + 0.25)
	end
	Net.Fx:FireAllClients(
		"nova",
		{ pos = ground(land), radius = skill.radius, color = skill.color }
	)
	for _, e in enemiesNear(land, skill.radius) do
		damageEnemy(e, skill.damage, player, skill)
	end
	return true
end

-- Zone: ground area at the aim (or around you with range 0) that hits every `tick`
local function castZone(player: Player, root: BasePart, skill: Skills.Skill, aim: Vector3): boolean
	local follow = skill.range <= 0
	local center = root.Position
	if not follow then
		local rel = flat(aim - center)
		if rel.Magnitude > skill.range then
			rel = rel.Unit * skill.range
		end
		center += rel
	end
	local duration = skill.duration or 3
	local tick = math.max(0.2, skill.tick or 0.5)
	task.spawn(function()
		local t = 0
		local n = 0
		while t < duration and player.Parent do
			local r = body(player)
			if follow then
				if not r then
					return
				end
				center = r.Position
			end
			if n % 2 == 0 then
				Net.Fx:FireAllClients(
					"nova",
					{ pos = ground(center), radius = skill.radius, color = skill.color }
				)
			end
			for _, e in enemiesNear(center, skill.radius) do
				if skill.slow then
					local untilT = os.clock() + (skill.slowTime or tick * 2)
					if ((e:GetAttribute("SlowUntil") or 0) :: number) < untilT then
						e:SetAttribute("SlowUntil", untilT)
						e:SetAttribute("SlowFactor", skill.slow)
					end
				end
				damageEnemy(e, skill.damage, player, skill, n > 0)
			end
			n += 1
			task.wait(tick)
			t += tick
		end
	end)
	return true
end

-- Buff: damage/armor/speed for a while, or an instant heal
local function castBuff(player: Player, root: BasePart, skill: Skills.Skill): boolean
	local st = states[player]
	local _, humanoid = body(player)
	if not st or not humanoid then
		return false
	end
	local now = os.clock()
	local duration = skill.duration or 0
	if skill.buffDamage then
		st.buffDamage = skill.buffDamage
		st.buffUntil = now + duration
		Status.set(player, "damage", duration)
	end
	if skill.buffArmor then
		st.armorBuff = skill.buffArmor
		st.armorUntil = now + duration
		Status.set(player, "armor", duration)
	end
	if skill.buffHaste then
		st.haste = skill.buffHaste
		st.hasteUntil = now + duration
		Status.set(player, "haste", duration)
		applySpeed(player)
		task.delay(duration + 0.05, applySpeed, player)
	end
	if skill.heal then
		humanoid.Health =
			math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * skill.heal)
	end
	Net.Fx:FireAllClients("nova", { pos = ground(root.Position), radius = 5, color = skill.color })
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
	-- Bloom "Eye of the Storm": pull survivors toward the center
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
	-- Bloom "Bolt Rain": bolts fly outward, evenly spread
	local bolts = skill.bolts
	if bolts then
		local bolt: Skills.Skill = table.freeze({
			id = skill.id,
			name = skill.name,
			desc = skill.desc,
			icon = skill.icon,
			color = skill.color,
			kind = "projectile" :: Skills.Kind,
			damage = skill.damage * BOLT_SHARE,
			cooldown = 0,
			range = BOLT_RANGE,
			radius = 1.5,
			speed = BOLT_SPEED,
		})
		local turn = rng:NextNumber() * math.pi * 2
		for i = 1, bolts do
			local a = turn + i / bolts * math.pi * 2
			castProjectile(
				player,
				root,
				bolt,
				center + Vector3.new(math.cos(a), 0, math.sin(a)) * BOLT_RANGE,
				center
			)
		end
	end
	-- Bloom "Storm Rider": briefly faster after a hit
	if st and skill.haste and #hits > 0 then
		st.haste = skill.haste
		st.hasteUntil = now + HASTE_TIME
		Status.set(player, "haste", HASTE_TIME)
		applySpeed(player)
		task.delay(HASTE_TIME + 0.05, applySpeed, player)
	end
	-- Bloom "Ice Armor"
	if st and skill.armorBuff then
		st.armorBuff = skill.armorBuff
		st.armorUntil = now + ARMOR_TIME
		Status.set(player, "armor", ARMOR_TIME)
	end
	-- Bloom "Frost Field": ice field at the spot, slows and hits every 0.5 s
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
	-- Skill Bloom "Thunderclap": second strike shortly after
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
		-- Bloom "Spark Rain": sparks around every jump
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
	-- Bloom "Branching": from the first hit to the 2 nearest other enemies
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

local function cast(player: Player, slot: number, aim: Vector3, origin: Vector3): boolean
	local profile = Data.get(player)
	local base = if profile then Progression.barSkill(profile.progress, slot) else nil
	local st = states[player]
	local root = body(player)
	if not base or not st or not root then
		return false
	end
	if base.class ~= Classes.valid(profile and profile.class) then
		return false -- a skill of another class (bar is refitted on class change)
	end
	local skill = effective(player, base)
	local now = os.clock()
	if now < (st.cdUntil[base.id] or 0) then
		return false
	end
	-- The client knows its own position more precisely (server lags while walking); only accept plausible values
	if flat(origin - root.Position).Magnitude > 12 then
		origin = root.Position
	end
	local ok = false
	if skill.kind == "projectile" then
		ok = castFan(player, root, skill, aim, origin)
	elseif skill.kind == "nova" then
		ok = castNova(player, root, skill)
	elseif skill.kind == "chain" then
		ok = castChain(player, root, skill, aim)
	elseif skill.kind == "arc" then
		ok = castArc(player, root, skill, aim)
	elseif skill.kind == "leap" then
		ok = castLeap(player, root, skill, aim)
	elseif skill.kind == "zone" then
		ok = castZone(player, root, skill, aim)
	elseif skill.kind == "buff" then
		ok = castBuff(player, root, skill)
	end
	if not ok then
		return false
	end
	st.cdUntil[base.id] = now + skill.cooldown
	Net.SkillCast:FireClient(player, base.id, skill.cooldown)
	act(player, skill.kind, base.id, false, aim)
	-- Bloom "Twin Ball": second ball shortly after
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
	-- Star "Arcane Shield": a shield after every skill (refreshes, does not stack)
	local _, humanoid = body(player)
	local pct = num(player, "StatArcaneShield")
	if humanoid and pct > 0 then
		if now >= st.shieldUntil then
			st.shield = 0
		end
		st.shield = math.max(st.shield, humanoid.MaxHealth * pct / 100)
		st.shieldUntil = now + SHIELD_TIME
		Status.set(player, "shield", SHIELD_TIME)
		player:SetAttribute("Shield", math.floor(st.shield + 0.5))
		task.delay(SHIELD_TIME, function()
			if states[player] == st and os.clock() >= st.shieldUntil - 0.01 then
				st.shield = 0
				player:SetAttribute("Shield", 0)
			end
		end)
	end
	return true
end

-- ------------------------------------------------------------------ Dash
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
	act(player, "dash", nil, false, nil)
end

-- ------------------------------------------------------------------ Lifecycle
local function onPlayer(player: Player)
	states[player] = {
		cdUntil = {},
		basicUntil = 0,
		iframesUntil = 0,
		dashCharges = Config.DASH_CHARGES,
		dashStamp = os.clock(),
		haste = 0,
		hasteUntil = 0,
		chill = 0,
		chillUntil = 0,
		buffDamage = 0,
		buffUntil = 0,
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
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		-- Death animation instead of falling apart: the body stays whole and in place, every
		-- client plays the collapse and breaks it into bricks (AnimController)
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Once(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = true
			end
			-- the fallen (later hidden) body must not block anyone until the respawn
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
				end
			end
		end)
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
		if not allowCast(player) then
			return
		end
		if typeof(slot) ~= "number" or typeof(aim) ~= "Vector3" or typeof(origin) ~= "Vector3" then
			return
		end
		if slot ~= math.floor(slot) or slot < 1 or slot > Skills.SLOTS then
			return
		end
		if not ((aim :: Vector3).Magnitude < 1e6 and (origin :: Vector3).Magnitude < 1e6) then -- catches NaN and infinity
			return
		end
		cast(player, slot, aim, origin)
	end)
	Net.Dash.OnServerEvent:Connect(function(player: Player)
		if allowAction(player) then
			dash(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

function Combat.start()
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	-- Basic attack: automatically at the nearest enemy in range
	while true do
		task.wait(0.1)
		local now = os.clock()
		local pool = aliveEnemies()
		for player, st in states do
			if now >= st.basicUntil then
				local root = body(player)
				if root then
					local kit = Skills.forClass(Classes.valid(player:GetAttribute("Class")))
					local basic = effective(player, kit.basic)
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
						local rushing = player:GetAttribute("Rushing") == true
						st.basicUntil = now
							+ basic.cooldown
								/ (if rushing then 1 + Rush.ATTACK_SPEED / 100 else 1)
						-- Star "Double Strike": chance for a double hit
						if rng:NextNumber() < num(player, "StatDouble") / 100 then
							local double = table.clone(basic)
							double.damage *= 2
							basic = double
						end
						act(player, basic.kind, basic.id, true, enemyPos(target))
						if basic.kind == "arc" then
							castArc(player, root, basic, enemyPos(target))
						else
							castProjectile(player, root, basic, enemyPos(target), root.Position)
						end
					end
				end
			end
		end
	end
end

return Combat
