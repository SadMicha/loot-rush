--!strict
-- Progress besides gear: skill levels, Skill Blooms, Star Net and Forge materials.
-- Pure data and rules (saveable, no instances) for server and client.
-- The server (Systems/Progress, Systems/Forge) changes the data, the client only displays it.
-- Save fields: profile.progress (Data) and profile.materials (Materials).

local Balance = require(script.Parent.Balance)
local Skills = require(script.Parent.Skills)
local StarNet = require(script.Parent.StarNet)

export type SkillProgress = {
	level: number,
	xp: number,
	bloom: { [string]: number }, -- node key ("trunk1" …) → points
}
export type Data = {
	skills: { [string]: SkillProgress },
	stars: { [string]: boolean }, -- allocated stars (without the heart)
}
export type Materials = { candy: number, shards: number, dust: number }

local Progression = {}

-- Player stats stars can give (StarNet.Star.mods); percent except life and dash.
-- "<skillId>.<stat>" only affects one skill (stat as with Skill Blooms).
Progression.StarStats = table.freeze({
	damage = "Damage %",
	life = "Life",
	lifePct = "Max Life %",
	crit = "Crit Chance %",
	critDamage = "Crit Damage %",
	speed = "Move Speed %",
	attackSpeed = "Attack Speed %",
	skillDamage = "Skill Damage %",
	cdr = "Cooldown −%",
	dash = "Dash Charges",
	double = "Double Hit Chance %",
	lowLifeDamage = "Damage below 30 % Life %",
	shardFind = "Shards from Salvage %",
	armor = "Armor % (less damage taken)",
	block = "Block Chance %",
	critShard = "Crit Shards: Damage % of Crit",
	arcaneShield = "Shield after Skill: % Max Life",
} :: { [string]: string })

Progression.MIN_COOLDOWN = 0.3

-- Special effects of Skill Blooms that carry over 1:1 into the skill (Skills.Skill, Systems/Combat)
Progression.SpecialStats = table.freeze({
	"echo",
	"lastHit",
	"pull",
	"bolts",
	"haste",
	"burn",
	"sparks",
	"twin",
	"pierce",
	"fork",
	"jumpSpark",
	"shatter",
	"field",
	"armorBuff",
})

-- ------------------------------------------------------------------ Save data
function Progression.fresh(): Data
	return { skills = {}, stars = {} }
end

function Progression.freshMaterials(): Materials
	return { candy = 0, shards = 0, dust = 0 }
end

local function count(v: any): number
	if typeof(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
		return 0
	end
	return math.floor(v)
end

-- Clean up saved raw data: unknown entries are dropped, numbers are clamped
function Progression.reconcile(raw: any): Data
	local data = Progression.fresh()
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.skills) == "table" then
		for id, sp in raw.skills do
			if typeof(id) == "string" and Skills.Blooms[id] and typeof(sp) == "table" then
				local bloom: { [string]: number } = {}
				if typeof(sp.bloom) == "table" then
					for key, pts in sp.bloom do
						if typeof(key) == "string" and Skills.bloomNode(id, key) then
							local n = math.min(count(pts), Skills.BloomMax)
							if n > 0 then
								bloom[key] = n
							end
						end
					end
				end
				data.skills[id] = {
					level = math.clamp(count(sp.level), 1, Skills.MaxLevel),
					xp = count(sp.xp),
					bloom = bloom,
				}
			end
		end
	end
	if typeof(raw.stars) == "table" then
		for id, on in raw.stars do
			local s = if typeof(id) == "string" then StarNet.ById[id] else nil
			if s and s.kind ~= "core" and on == true then
				data.stars[id] = true
			end
		end
	end
	return data
end

function Progression.reconcileMaterials(raw: any): Materials
	local m = Progression.freshMaterials()
	if typeof(raw) == "table" then
		m.candy = count(raw.candy)
		m.shards = count(raw.shards)
		m.dust = count(raw.dust)
	end
	return m
end

-- ------------------------------------------------------------------ Skill levels
-- XP from level L to L+1 (own assumption: same curve as the player level, Balance.xpForLevel;
-- each skill only gets the XP of its killing blows)
function Progression.skillXpFor(level: number): number
	return Balance.xpForLevel(level)
end

local EMPTY: SkillProgress = table.freeze({ level = 1, xp = 0, bloom = table.freeze({}) })

-- Read without creating
function Progression.skill(data: Data, id: string): SkillProgress
	return data.skills[id] or EMPTY
end

-- Writing: creates the entry
function Progression.skillMut(data: Data, id: string): SkillProgress
	local sp = data.skills[id]
	if not sp then
		sp = { level = 1, xp = 0, bloom = {} }
		data.skills[id] = sp
	end
	return sp
end

-- Returns the number of levels gained
function Progression.addSkillXp(sp: SkillProgress, amount: number): number
	if sp.level >= Skills.MaxLevel then
		return 0
	end
	sp.xp += math.max(0, math.floor(amount))
	local gained = 0
	while sp.level < Skills.MaxLevel and sp.xp >= Progression.skillXpFor(sp.level) do
		sp.xp -= Progression.skillXpFor(sp.level)
		sp.level += 1
		gained += 1
	end
	if sp.level >= Skills.MaxLevel then
		sp.xp = 0
	end
	return gained
end

-- ------------------------------------------------------------------ Skill Blooms
function Progression.bloomSpent(sp: SkillProgress): number
	local n = 0
	for _, pts in sp.bloom do
		n += pts
	end
	return n
end

-- Every skill level above 1 gives a Bloom Point
function Progression.bloomPoints(sp: SkillProgress): number
	return sp.level - 1 - Progression.bloomSpent(sp)
end

function Progression.canBloom(sp: SkillProgress, skillId: string, key: string): (boolean, string?)
	local node, branch, index = Skills.bloomNode(skillId, key)
	if not node or not branch or not index then
		return false, "Unknown node"
	end
	if not node.effect then
		return false, "Coming soon"
	end
	if (sp.bloom[key] or 0) >= Skills.BloomMax then
		return false, "Maxed out"
	end
	if index > 1 and (sp.bloom[branch .. tostring(index - 1)] or 0) <= 0 then
		return false, "Upgrade the previous node first"
	end
	if Progression.bloomPoints(sp) <= 0 then
		return false, "No Bloom Points"
	end
	return true, nil
end

-- ------------------------------------------------------------------ Star Net
function Progression.isAllocated(data: Data, id: string): boolean
	return id == "heart" or data.stars[id] == true
end

function Progression.starSpent(data: Data): number
	local n = 0
	for id in data.stars do
		local s = StarNet.ById[id]
		if s then
			n += StarNet.Cost[s.kind]
		end
	end
	return n
end

-- 1 point per level from level 2
function Progression.starPoints(data: Data, level: number): number
	return math.max(0, level - 1) - Progression.starSpent(data)
end

function Progression.canAllocate(data: Data, id: string, level: number): (boolean, string?)
	local s = StarNet.ById[id]
	if not s or s.kind == "core" then
		return false, "Unknown star"
	end
	if data.stars[id] then
		return false, "Already allocated"
	end
	if not s.from or not Progression.isAllocated(data, s.from) then
		return false, "Not connected"
	end
	if Progression.starPoints(data, level) < StarNet.Cost[s.kind] then
		return false, "Not enough points"
	end
	return true, nil
end

-- Remove only at the end of a branch, so nothing is left dangling
function Progression.canRemove(data: Data, id: string): (boolean, string?)
	if not data.stars[id] then
		return false, "Not allocated"
	end
	for _, other in StarNet.Stars do
		if other.from == id and data.stars[other.id] then
			return false, "Remove the stars behind it first"
		end
	end
	return true, nil
end

-- Sum of all star effects
function Progression.starMods(data: Data): { [string]: number }
	local sum: { [string]: number } = {}
	for id in data.stars do
		local s = StarNet.ById[id]
		if s and s.mods then
			for k, v in s.mods do
				sum[k] = (sum[k] or 0) + v
			end
		end
	end
	return sum
end

-- ------------------------------------------------------------------ Effect on skills
-- Skill with level, bloom and stars applied. `mods` = Progression.starMods(data) (optional, precomputed).
function Progression.effectiveSkill(
	skill: Skills.Skill,
	data: Data,
	mods: { [string]: number }?
): Skills.Skill
	local m = mods or Progression.starMods(data)
	local out = table.clone(skill) :: any
	local onBar = Skills.BarIndex[skill.id] ~= nil

	local add: { [string]: number } = {}
	local damage = 1
	if onBar then
		local sp = Progression.skill(data, skill.id)
		damage += (sp.level - 1) * Skills.DamagePerLevel + (m.skillDamage or 0) / 100
		for key, pts in sp.bloom do
			local node = Skills.bloomNode(skill.id, key)
			if node and node.effect then
				add[node.effect.stat] = (add[node.effect.stat] or 0) + node.effect.per * pts
			end
		end
	end
	for k, v in m do
		local id, stat = string.match(k, "^([%w_]+)%.(%w+)$")
		if id == skill.id and stat then
			add[stat] = (add[stat] or 0) + (if stat == "damage" then v / 100 else v)
		end
	end

	damage += add.damage or 0
	out.damage = skill.damage * damage
	out.radius = skill.radius + (add.radius or 0)
	local cd = (skill.cooldown - (add.cooldown or 0)) * (1 - math.min(0.5, (m.cdr or 0) / 100))
	if onBar then
		out.cooldown = math.max(Progression.MIN_COOLDOWN, cd)
	else
		-- Basic attack: attack speed instead of cooldown
		out.cooldown = math.max(0.15, skill.cooldown / (1 + (m.attackSpeed or 0) / 100))
	end
	if skill.speed then
		out.speed = skill.speed * (1 + (add.speed or 0))
	end
	if skill.chains then
		out.chains = skill.chains + math.floor(add.chains or 0)
	end
	if skill.slowTime then
		out.slowTime = skill.slowTime + (add.slowTime or 0)
	end
	for _, k in Progression.SpecialStats do
		if (add[k] or 0) > 0 then
			out[k] = add[k]
		end
	end
	return table.freeze(out) :: Skills.Skill
end

return table.freeze(Progression)
