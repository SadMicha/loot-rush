--!strict
-- Fortschritt neben der Ausrüstung: Skill-Stufen, Skill-Blüten, Sternennetz und Schmiede-Material.
-- Reine Daten und Regeln (speicherbar, ohne Instanzen) für Server und Client.
-- Der Server (Systems/Progress, Systems/Forge) ändert die Daten, der Client zeigt sie nur an.
-- Spielstand-Felder: profile.progress (Data) und profile.materials (Materials).

local Skills = require(script.Parent.Skills)
local StarNet = require(script.Parent.StarNet)

export type SkillProgress = {
	level: number,
	xp: number,
	bloom: { [string]: number }, -- Knoten-Schlüssel ("trunk1" …) → Punkte
}
export type Data = {
	skills: { [string]: SkillProgress },
	stars: { [string]: boolean }, -- zugewiesene Sterne (ohne Herz)
}
export type Materials = { candy: number, shards: number, dust: number }

local Progression = {}

-- Spieler-Werte, die Sterne geben können (StarNet.Star.mods); Prozent außer life und dash.
-- "<skillId>.<stat>" wirkt nur auf einen Skill (stat wie bei Skill-Blüten).
Progression.StarStats = table.freeze({
	damage = "Schaden %",
	life = "Leben",
	lifePct = "maximales Leben %",
	crit = "Krit-Chance %",
	critDamage = "Krit-Schaden %",
	speed = "Lauftempo %",
	attackSpeed = "Angriffstempo %",
	skillDamage = "Skill-Schaden %",
	cdr = "Abklingzeit −%",
	dash = "Dash-Ladungen",
	double = "Doppeltreffer-Chance %",
	lowLifeDamage = "Schaden unter 30 % Leben %",
	shardFind = "Splitter beim Verwerten %",
} :: { [string]: string })

Progression.MIN_COOLDOWN = 0.3

-- ------------------------------------------------------------------ Spielstand
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

-- Gespeicherte Rohdaten säubern: Unbekanntes fliegt raus, Zahlen werden begrenzt
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

-- ------------------------------------------------------------------ Skill-Stufen
-- XP von Stufe L auf L+1 (eigene Kurve, nicht im Balancing-Blatt)
function Progression.skillXpFor(level: number): number
	return math.floor(30 * level ^ 1.6)
end

local EMPTY: SkillProgress = table.freeze({ level = 1, xp = 0, bloom = table.freeze({}) })

-- Lesen ohne anzulegen
function Progression.skill(data: Data, id: string): SkillProgress
	return data.skills[id] or EMPTY
end

-- Schreibend: legt den Eintrag an
function Progression.skillMut(data: Data, id: string): SkillProgress
	local sp = data.skills[id]
	if not sp then
		sp = { level = 1, xp = 0, bloom = {} }
		data.skills[id] = sp
	end
	return sp
end

-- Gibt die Zahl gewonnener Stufen zurück
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

-- ------------------------------------------------------------------ Skill-Blüten
function Progression.bloomSpent(sp: SkillProgress): number
	local n = 0
	for _, pts in sp.bloom do
		n += pts
	end
	return n
end

-- Jede Skill-Stufe über 1 gibt einen Blüten-Punkt
function Progression.bloomPoints(sp: SkillProgress): number
	return sp.level - 1 - Progression.bloomSpent(sp)
end

function Progression.canBloom(sp: SkillProgress, skillId: string, key: string): (boolean, string?)
	local node, branch, index = Skills.bloomNode(skillId, key)
	if not node or not branch or not index then
		return false, "Unbekannter Knoten"
	end
	if not node.effect then
		return false, "Kommt bald"
	end
	if (sp.bloom[key] or 0) >= Skills.BloomMax then
		return false, "Voll ausgebaut"
	end
	if index > 1 and (sp.bloom[branch .. tostring(index - 1)] or 0) <= 0 then
		return false, "Erst den Knoten davor ausbauen"
	end
	if Progression.bloomPoints(sp) <= 0 then
		return false, "Keine Blüten-Punkte"
	end
	return true, nil
end

-- ------------------------------------------------------------------ Sternennetz
function Progression.isAllocated(data: Data, id: string): boolean
	return id == "herz" or data.stars[id] == true
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

-- 1 Punkt je Level ab Level 2
function Progression.starPoints(data: Data, level: number): number
	return math.max(0, level - 1) - Progression.starSpent(data)
end

function Progression.canAllocate(data: Data, id: string, level: number): (boolean, string?)
	local s = StarNet.ById[id]
	if not s or s.kind == "core" then
		return false, "Unbekannter Stern"
	end
	if data.stars[id] then
		return false, "Schon zugewiesen"
	end
	if not s.from or not Progression.isAllocated(data, s.from) then
		return false, "Nicht verbunden"
	end
	if Progression.starPoints(data, level) < StarNet.Cost[s.kind] then
		return false, "Zu wenig Punkte"
	end
	return true, nil
end

-- Entfernen nur am Ende eines Astes, damit nichts in der Luft hängt
function Progression.canRemove(data: Data, id: string): (boolean, string?)
	if not data.stars[id] then
		return false, "Nicht zugewiesen"
	end
	for _, other in StarNet.Stars do
		if other.from == id and data.stars[other.id] then
			return false, "Erst die Sterne dahinter entfernen"
		end
	end
	return true, nil
end

-- Summe aller Stern-Wirkungen
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

-- ------------------------------------------------------------------ Wirkung auf Skills
-- Skill mit Stufe, Blüte und Sternen verrechnet. `mods` = Progression.starMods(data) (optional vorab).
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
		local id, stat = string.match(k, "^(%w+)%.(%w+)$")
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
		-- Grundangriff: Angriffstempo statt Abklingzeit
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
	if (add.echo or 0) > 0 then
		out.echo = add.echo
	end
	if (add.lastHit or 0) > 0 then
		out.lastHit = add.lastHit
	end
	return table.freeze(out) :: Skills.Skill
end

return table.freeze(Progression)
