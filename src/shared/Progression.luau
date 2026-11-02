--!strict
-- Progress besides gear: skill levels, Skill Blooms, Star Net and Forge materials.
-- Pure data and rules (saveable, no instances) for server and client.
-- The server (Systems/Progress, Systems/Forge) changes the data, the client only displays it.
-- Save fields: profile.progress (Data) and profile.materials (Materials).

local Balance = require(script.Parent.Balance)
local Skills = require(script.Parent.Skills)
local SpellStones = require(script.Parent.SpellStones)
local StarNet = require(script.Parent.StarNet)

export type SkillProgress = {
	level: number,
	xp: number,
	bloom: { [string]: number }, -- node key ("trunk1" …) → points
}
export type Data = {
	skills: { [string]: SkillProgress },
	stars: { [string]: boolean }, -- allocated stars (without the heart)
	bar: { string }, -- skill id per bar slot (Skills.SLOTS entries)
	stones: { [string]: number }, -- owned spell stones by id (Shared/SpellStones)
	sockets: { [string]: { string } }, -- skill id → socketed stone ids (up to SpellStones.SOCKETS)
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
	lowLifeDamage = "Damage below 30% Life %",
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
	return {
		skills = {},
		stars = {},
		bar = table.clone(Skills.DefaultBar),
		stones = {},
		sockets = {},
	}
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
	if typeof(raw.bar) == "table" then
		-- valid, distinct ids; gaps are filled with starting skills that are not on the bar yet
		local used: { [string]: boolean } = {}
		local bar: { string? } = {}
		for slot = 1, Skills.SLOTS do
			local id = raw.bar[slot]
			if typeof(id) == "string" and Skills.ById[id] and not used[id] then
				bar[slot] = id
				used[id] = true
			end
		end
		for slot = 1, Skills.SLOTS do
			if not bar[slot] then
				for _, id in Skills.DefaultBar do
					if not used[id] then
						bar[slot] = id
						used[id] = true
						break
					end
				end
			end
		end
		data.bar = bar :: { string }
	end
	if typeof(raw.stones) == "table" then
		for id, n in raw.stones do
			if typeof(id) == "string" and SpellStones.ById[id] and count(n) > 0 then
				data.stones[id] = count(n)
			end
		end
	end
	if typeof(raw.sockets) == "table" then
		local used: { [string]: number } = {}
		for skillId, list in raw.sockets do
			local skill = if typeof(skillId) == "string" then Skills.ById[skillId] else nil
			if skill and typeof(list) == "table" then
				local keep = {}
				for _, stoneId in list do
					if
						#keep < SpellStones.SOCKETS
						and typeof(stoneId) == "string"
						and SpellStones.fits(stoneId, skill.kind)
						and (used[stoneId] or 0) < (data.stones[stoneId] or 0)
					then
						used[stoneId] = (used[stoneId] or 0) + 1
						table.insert(keep, stoneId)
					end
				end
				if #keep > 0 then
					data.sockets[skill.id] = keep
				end
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

-- ------------------------------------------------------------------ Bar
-- Skill in a bar slot (nil for an invalid slot)
function Progression.barSkill(data: Data, slot: number): Skills.Skill?
	local id = data.bar[slot]
	return if id then Skills.ById[id] else nil
end

-- Can the skill go on the bar at this player level (and, if given, for this class)?
function Progression.canEquip(
	skillId: string,
	playerLevel: number,
	classId: string?
): (boolean, string?)
	local skill = Skills.ById[skillId]
	if not skill then
		return false, "Unknown skill"
	end
	if classId and skill.class ~= classId then
		return false, "Another class's skill"
	end
	if playerLevel < (skill.unlock or 1) then
		return false, string.format("Unlocks at level %d", skill.unlock or 1)
	end
	return true, nil
end

-- Puts a skill into a slot; if it already sits in another slot, the two swap places.
-- Returns false if the move is not allowed (nothing changes then).
function Progression.equip(
	data: Data,
	slot: number,
	skillId: string,
	playerLevel: number,
	classId: string?
): boolean
	if slot ~= math.floor(slot) or slot < 1 or slot > Skills.SLOTS then
		return false
	end
	if not Progression.canEquip(skillId, playerLevel, classId) then
		return false
	end
	local old = data.bar[slot]
	for i, id in data.bar do
		if id == skillId then
			data.bar[i] = old
		end
	end
	data.bar[slot] = skillId
	return true
end

-- ------------------------------------------------------------------ Spell stones
-- How many copies of a stone are socketed anywhere
function Progression.stonesUsed(data: Data, stoneId: string): number
	local n = 0
	for _, list in data.sockets do
		for _, id in list do
			if id == stoneId then
				n += 1
			end
		end
	end
	return n
end

-- Puts a stone into socket `index` of a skill ("" empties it). Returns false if not allowed.
function Progression.socket(data: Data, skillId: string, index: number, stoneId: string): boolean
	local skill = Skills.ById[skillId]
	if not skill or index ~= math.floor(index) or index < 1 or index > SpellStones.SOCKETS then
		return false
	end
	local list = table.clone(data.sockets[skillId] or {})
	if stoneId == "" then
		if not list[index] then
			return false
		end
		table.remove(list, index)
	else
		if not SpellStones.fits(stoneId, skill.kind) then
			return false
		end
		local old = list[index]
		local free = (data.stones[stoneId] or 0) - Progression.stonesUsed(data, stoneId)
		if old == stoneId or free <= 0 then
			return false
		end
		if old then
			list[index] = stoneId
		else
			table.insert(list, stoneId)
		end
	end
	if #list > 0 then
		data.sockets[skillId] = list
	else
		data.sockets[skillId] = nil
	end
	return true
end

-- Makes the bar fit a class: skills of another class are replaced by the class's starting
-- skills (on load and after a class change). Returns true if something changed.
function Progression.fitBar(data: Data, classId: string): boolean
	local kit = Skills.forClass(classId)
	local used: { [string]: boolean } = {}
	local keep: { string? } = {}
	for slot = 1, Skills.SLOTS do
		local id = data.bar[slot]
		local skill = if id then Skills.ById[id] else nil
		if skill and skill.class == classId and not used[skill.id] then
			keep[slot] = skill.id
			used[skill.id] = true
		end
	end
	local changed = false
	for slot = 1, Skills.SLOTS do
		if not keep[slot] then
			for _, id in kit.bar do
				if not used[id] then
					keep[slot] = id
					used[id] = true
					break
				end
			end
		end
		if keep[slot] ~= data.bar[slot] then
			changed = true
		end
	end
	data.bar = keep :: { string }
	return changed
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
	local onBar = Skills.ById[skill.id] ~= nil

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
	if onBar then
		local socketed: { string } = data.sockets[skill.id] or {}
		for _, stoneId in socketed do
			local stone = SpellStones.ById[stoneId]
			if stone and SpellStones.fits(stoneId, skill.kind) then
				for stat, v in stone.add do
					add[stat] = (add[stat] or 0) + v
				end
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
	if (add.count or 0) > 0 then
		out.count = (skill.count or 1) + math.floor(add.count)
		out.spread = skill.spread or 30
	end
	if skill.duration and (add.durationPct or 0) > 0 then
		out.duration = skill.duration * (1 + add.durationPct)
	end
	for _, k in Progression.SpecialStats do
		if (add[k] or 0) > 0 then
			out[k] = ((skill :: any)[k] or 0) + add[k]
		end
	end
	return table.freeze(out) :: Skills.Skill
end

return table.freeze(Progression)
