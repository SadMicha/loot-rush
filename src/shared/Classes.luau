--!strict
-- The four classes (concept "Klassen & Skills", owner decision 2026-11-02: four classes at launch).
-- Ids are stable (saved in profile.class, attribute "Class") and match Theme.Class.SkillName and
-- the skill icon folders in assets/ui/icons/skills/. Skills per class follow in the class PR.

export type ClassId = string -- "warrior" | "ranger" | "mage" | "mushroom"
export type Class = {
	id: ClassId,
	name: string, -- class name shown in the game
	short: string, -- one word for tight spots (class-lock chip on item cells)
	hero: string, -- the hero's name (concept)
	role: string,
	weapon: string, -- key in Shared/Weapons
}

local Classes = {}

Classes.DEFAULT = "mage" -- the class the slice was built with

Classes.List = table.freeze({
	table.freeze({
		id = "warrior",
		name = "Knight",
		short = "Knight",
		hero = "Brix",
		role = "Melee, tank",
		weapon = "warrior_sword",
	}),
	table.freeze({
		id = "ranger",
		name = "Ranger",
		short = "Ranger",
		hero = "Fynn",
		role = "Ranged, movement",
		weapon = "ranger_bow",
	}),
	table.freeze({
		id = "mage",
		name = "Spark Mage",
		short = "Mage",
		hero = "Zap",
		role = "Elemental caster",
		weapon = "mage_staff",
	}),
	table.freeze({
		id = "mushroom",
		name = "Mushroom Shaman",
		short = "Shaman",
		hero = "Mora",
		role = "Summoner",
		weapon = "druid_scepter",
	}),
} :: { Class })

local byId: { [string]: Class } = {}
for _, c in Classes.List do
	byId[c.id] = c
end
Classes.ById = table.freeze(byId)

-- Valid class id or the default (saves, attributes)
function Classes.valid(id: any): ClassId
	if typeof(id) == "string" and byId[id] then
		return byId[id].id
	end
	return Classes.DEFAULT
end

return table.freeze(Classes)
