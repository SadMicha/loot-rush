--!strict
-- Spell stones (concept "Zaubersteine", docs/SPELL-STONES.md): support stones socketed into a
-- skill, up to SOCKETS per skill. Every stone adds bloom-style stats (Progression.effectiveSkill).
-- Some only fit certain skill kinds (`kinds`); in other skills they do nothing and cannot be
-- socketed. Stones drop from bosses and elites and are kept as counts; a socketed stone is in use.

export type Stone = {
	id: string,
	name: string, -- English, shown in the Skills window
	text: string,
	add: { [string]: number }, -- stat → value, same keys as bloom effects
	kinds: { [string]: boolean }?, -- nil = fits every skill
	color: Color3,
}

local SpellStones = {}

SpellStones.SOCKETS = 3
SpellStones.BOSS_CHANCE = 0.35 -- per boss kill
SpellStones.ELITE_CHANCE = 0.12 -- per elite kill

local function kinds(...: string): { [string]: boolean }
	local out = {}
	for _, k in { ... } do
		out[k] = true
	end
	return table.freeze(out)
end

SpellStones.List = table.freeze({
	{
		id = "power",
		name = "Power Stone",
		text = "+30% damage, +0.5 s cooldown",
		add = { damage = 0.3, cooldown = -0.5 },
		color = Color3.fromHex("#FF6A3D"),
	},
	{
		id = "haste",
		name = "Haste Stone",
		text = "−0.6 s cooldown, −10% damage",
		add = { cooldown = 0.6, damage = -0.1 },
		color = Color3.fromHex("#9CE5FF"),
	},
	{
		id = "wide",
		name = "Wide Stone",
		text = "+2 studs radius",
		add = { radius = 2 },
		color = Color3.fromHex("#E8B04A"),
	},
	{
		id = "ember",
		name = "Ember Stone",
		text = "Hits burn for 30% damage",
		add = { burn = 0.3 },
		color = Color3.fromHex("#FF9A4A"),
	},
	{
		id = "echo",
		name = "Echo Stone",
		text = "A second wave with 35% damage",
		add = { echo = 0.35 },
		kinds = kinds("nova"),
		color = Color3.fromHex("#C77DFF"),
	},
	{
		id = "link",
		name = "Link Stone",
		text = "+2 jumps",
		add = { chains = 2 },
		kinds = kinds("chain"),
		color = Color3.fromHex("#4FD8F5"),
	},
	{
		id = "split",
		name = "Split Stone",
		text = "+2 projectiles in a fan",
		add = { count = 2 },
		kinds = kinds("projectile"),
		color = Color3.fromHex("#7FD27A"),
	},
	{
		id = "pierce",
		name = "Pierce Stone",
		text = "50% chance to fly through the first enemy",
		add = { pierce = 0.5 },
		kinds = kinds("projectile"),
		color = Color3.fromHex("#BDEFFF"),
	},
	{
		id = "linger",
		name = "Linger Stone",
		text = "Zones and buffs last 50% longer",
		add = { durationPct = 0.5 },
		kinds = kinds("zone", "buff"),
		color = Color3.fromHex("#6FCF6A"),
	},
} :: { Stone })

local byId: { [string]: Stone } = {}
for _, s in SpellStones.List do
	byId[s.id] = s
end
SpellStones.ById = table.freeze(byId)

-- Can this stone go into a skill of this kind?
function SpellStones.fits(stoneId: string, kind: string): boolean
	local s = byId[stoneId]
	return s ~= nil and (s.kinds == nil or s.kinds[kind] == true)
end

-- Random stone id (drops)
function SpellStones.roll(rng: Random): string
	return SpellStones.List[rng:NextInteger(1, #SpellStones.List)].id
end

return table.freeze(SpellStones)
