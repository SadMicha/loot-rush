--!strict
-- Timed buffs and debuffs on the player, shown in the HUD buff bar.
-- The server (Systems/Status) sets one player attribute per active effect:
--   Status_<id>       = end time in workspace:GetServerTimeNow() (missing = not active)
--   StatusStacks_<id> = optional stack count (missing = no stacks shown)
-- Ids are persisted nowhere, but they are attribute names: English and stable.

local Rush = require(script.Parent.Rush)

local Status = {}

export type Def = {
	id: string,
	name: string,
	text: string, -- short line for the tap hint / activation banner (fits a toast)
	icon: string, -- Assets.Icon key (Kit.icon)
	debuff: boolean,
	order: number, -- position in the bar (buffs first, then debuffs)
}

export type Active = {
	def: Def,
	left: number, -- seconds
	stacks: number, -- 0 = none
}

Status.PREFIX = "Status_"
Status.STACKS_PREFIX = "StatusStacks_"

local function def(
	id: string,
	name: string,
	text: string,
	icon: string,
	debuff: boolean,
	order: number
): Def
	return table.freeze({
		id = id,
		name = name,
		text = text,
		icon = icon,
		debuff = debuff,
		order = order,
	})
end

Status.Defs = table.freeze({
	rush = def(
		"rush",
		"Stud Rush",
		`+{Rush.SPEED}% Move · +{Rush.ATTACK_SPEED}% Attack Speed`,
		"fire",
		false,
		1
	),
	damage = def("damage", "Empowered", "More damage", "sword", false, 2),
	armor = def("armor", "Armored", "Less damage taken", "shield_buff", false, 3),
	haste = def("haste", "Haste", "More move speed", "wings", false, 4),
	shield = def("shield", "Arcane Shield", "Absorbs damage", "crystal", false, 5),
	chill = def("chill", "Chilled", "Less move speed (Frozen aura)", "ice", true, 20),
} :: { [string]: Def })

function Status.attr(id: string): string
	return Status.PREFIX .. id
end

function Status.stacksAttr(id: string): string
	return Status.STACKS_PREFIX .. id
end

-- Active effects from a player's attributes (Instance:GetAttributes()), sorted for the bar
function Status.active(attrs: { [string]: any }, now: number): { Active }
	local out: { Active } = {}
	for id, d in Status.Defs do
		local untilT = attrs[Status.PREFIX .. id]
		if typeof(untilT) == "number" and untilT > now then
			local stacks = attrs[Status.STACKS_PREFIX .. id]
			table.insert(out, {
				def = d,
				left = untilT - now,
				stacks = if typeof(stacks) == "number" and stacks > 0
					then math.floor(stacks)
					else 0,
			})
		end
	end
	table.sort(out, function(a: Active, b: Active): boolean
		return a.def.order < b.def.order
	end)
	return out
end

return table.freeze(Status)
