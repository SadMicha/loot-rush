--!strict
-- Serverseitiger Kampf: Grundangriff (auto), 4 Skills, Trank, Dash-Unverwundbarkeit,
-- Schaden an Gegnern, XP und Level. Der Client schickt nur „Slot + Zielpunkt“ – alles andere prüft der Server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Data = require(script.Parent.Data)

type PState = {
	cdUntil: { number },
	basicUntil: number,
	potionUntil: number,
	iframesUntil: number,
	dashCharges: number,
	dashStamp: number,
}

local Combat = {
	EnemyKilled = Instance.new("BindableEvent"), -- (player, position, playerLevel, boss), für Systems/Loot
	PlayerHurt = Instance.new("BindableEvent"), -- (player, amount), für Systems/Metrics
}

local states: { [Player]: PState } = {}
local rng = Random.new()
local BODY_RADIUS = 1.7 -- Gegner-Körper, wird zum Trefferradius addiert

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

-- ------------------------------------------------------------------ Level & XP
local function xpFor(level: number): number
	return math.floor(40 * level ^ 1.5)
end

local function applyLevelStats(player: Player, fill: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local level = (player:GetAttribute("Level") or 1) :: number
	local bonus = (player:GetAttribute("StatLife") or 0) :: number
	humanoid.MaxHealth = Config.BASE_HEALTH + (level - 1) * Config.HEALTH_PER_LEVEL + bonus
	if fill then
		humanoid.Health = humanoid.MaxHealth
	end
end

-- Nach Änderungen an Level/Ausrüstung aufrufen
function Combat.refreshStats(player: Player, fill: boolean)
	applyLevelStats(player, fill)
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
local function damageEnemy(enemy: Model, base: number, player: Player, skill: Skills.Skill?)
	local hp = (enemy:GetAttribute("Health") or 0) :: number
	if hp <= 0 then
		return
	end
	local level = (player:GetAttribute("Level") or 1) :: number
	local critChance = Config.CRIT_CHANCE + ((player:GetAttribute("StatCrit") or 0) :: number) / 100
	local bonus = ((player:GetAttribute("StatDamage") or 0) :: number) / 100
	local crit = rng:NextNumber() < critChance
	local amount = base
		* (1 + (level - 1) * Config.DAMAGE_PER_LEVEL + bonus)
		* (if crit then Config.CRIT_MULT else 1)
	amount = math.max(1, math.floor(amount + 0.5))
	hp = math.max(0, hp - amount)
	enemy:SetAttribute("Health", hp)
	local pos = enemyPos(enemy)
	Net.Fx:FireAllClients(
		"dmg",
		{ pos = pos + Vector3.new(0, 3.5, 0), amount = amount, crit = crit }
	)

	if skill and skill.slow then
		enemy:SetAttribute("SlowUntil", os.clock() + (skill.slowTime or 2))
		enemy:SetAttribute("SlowFactor", skill.slow)
	end

	if hp <= 0 then
		local color = enemy:GetAttribute("Color")
		Net.Fx:FireAllClients(
			"death",
			{ pos = pos, color = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1) }
		)
		local xp = (enemy:GetAttribute("XP") or 0) :: number
		local boss = enemy:GetAttribute("Boss") == true
		enemy:Destroy()
		if player.Parent then
			addXP(player, xp)
			Combat.EnemyKilled:Fire(
				player,
				pos,
				(player:GetAttribute("Level") or 1) :: number,
				boss
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
	humanoid.Health -= amount
	Combat.PlayerHurt:Fire(player, amount)
	Net.Fx:FireAllClients(
		"dmg",
		{ pos = root.Position + Vector3.new(0, 3, 0), amount = amount, hurt = true }
	)
	return true
end

-- ------------------------------------------------------------------ Skills
local function enemiesNear(center: Vector3, radius: number): { Model }
	local out: { Model } = {}
	for _, e in aliveEnemies() do
		if flat(enemyPos(e) - center).Magnitude <= radius + BODY_RADIUS then
			table.insert(out, e)
		end
	end
	return out
end

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

	-- Erster Gegner auf der Linie stoppt das Projektil
	local reach = skill.range
	for _, e in aliveEnemies() do
		local rel = flat(enemyPos(e) - from)
		local t = rel:Dot(dir)
		if t > 0 and t < reach and (rel - dir * t).Magnitude <= BODY_RADIUS + 0.8 then
			reach = t
		end
	end
	local finish = from + dir * reach
	local travel = reach / (skill.speed or 60)
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
	end)
	return true
end

local function castNova(player: Player, root: BasePart, skill: Skills.Skill): boolean
	local center = root.Position
	Net.Fx:FireAllClients(
		"nova",
		{ pos = ground(center), radius = skill.radius, color = skill.color }
	)
	for _, e in enemiesNear(center, skill.radius) do
		damageEnemy(e, skill.damage, player, skill)
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
	while current and left > 0 do
		local e = current
		hit[e] = true
		local p = enemyPos(e)
		table.insert(points, p)
		damageEnemy(e, skill.damage, player, skill)
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
	return true
end

local function cast(player: Player, slot: number, aim: Vector3, origin: Vector3)
	local skill = Skills.bar[slot]
	local st = states[player]
	local root = body(player)
	if not skill or not st or not root then
		return
	end
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
	if ok then
		st.cdUntil[slot] = now + skill.cooldown
	end
end

-- ------------------------------------------------------------------ Dash & Trank
local function dash(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local now = os.clock()
	if st.dashCharges < Config.DASH_CHARGES then
		local gained = math.floor((now - st.dashStamp) / Config.DASH_RECHARGE)
		if gained > 0 then
			st.dashCharges = math.min(Config.DASH_CHARGES, st.dashCharges + gained)
			st.dashStamp += gained * Config.DASH_RECHARGE
		end
	end
	if st.dashCharges >= Config.DASH_CHARGES then
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
	local basic = Skills.basic
	while true do
		task.wait(0.1)
		local now = os.clock()
		local pool = aliveEnemies()
		for player, st in states do
			if now >= st.basicUntil then
				local root = body(player)
				if root then
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
						castProjectile(player, root, basic, enemyPos(target), root.Position)
					end
				end
			end
		end
	end
end

return Combat
