--!strict
-- Pets: catalog, eggs and rules (pure, for server and UI).
--   • Pets hatch from eggs (gold or Soulstars) and give permanent bonuses while they are
--     equipped (Systems/Boosts). Equipped pets follow the player (PetController).
--   • Duplicates raise the level (max. MAX_LEVEL, bonus × levelMult). At max level they give
--     Crystal Shards instead.
--   • Slots: 1, 2 with the "Pet Slot" game pass (Shared/Monetization).
-- Save field: profile.pets = { owned = { [id] = level }, equipped = { id } }.
-- Values are own assumptions, see docs/PETS.md.

local Balance = require(script.Parent.Balance)

local Pets = {}

export type Stat = "damage" | "life" | "gold" | "xp" | "items" | "magnet"
export type Pet = {
	id: string,
	name: string,
	rarity: string, -- normal | magic | rare | epic | legend (frame color like items)
	text: string,
	bonus: { [string]: number }, -- stat → percent (magnet = pickup radius in studs)
	look: string, -- blueprint in PetController (Creatures.*) until there is a "Pet_<id>" model
	color: Color3,
	glow: Color3,
	icon: string?, -- Assets.Icon key for the Pet window; nil = the generic companion icon
}
export type Egg = {
	id: string,
	name: string,
	text: string,
	price: { kind: string, amount: number }, -- "gold" (grows with depth) or "soulstars"
	weights: { [string]: number }, -- rarity → weight
	icon: string?, -- Assets.Icon/IconImage key for the egg card; nil = the generic companion icon
}
export type Data = { owned: { [string]: number }, equipped: { string } }

Pets.MAX_LEVEL = 5
Pets.BASE_SLOTS = 1
Pets.MAX_SLOTS = 2
Pets.DUPE_SHARDS = 100 -- Crystal Shards for a duplicate at max level

Pets.StatName = table.freeze({
	damage = "Damage %",
	life = "Life %",
	gold = "Gold %",
	xp = "XP %",
	items = "Item Chance %",
	magnet = "Pickup Radius (studs)",
} :: { [string]: string })

local LIST: { Pet } = {
	{
		id = "firefly",
		name = "Firefly",
		icon = "pet_firefly",
		rarity = "normal",
		text = "Lights your way to more gold.",
		bonus = { gold = 10 },
		look = "wisp",
		color = Color3.fromHex("#FFF3B0"),
		glow = Color3.fromHex("#FFD54A"),
	},
	{
		id = "moss_frog",
		name = "Moss Frog",
		icon = "pet_moss_frog",
		rarity = "normal",
		text = "Croaks after every win - you learn faster.",
		bonus = { xp = 10 },
		look = "frog",
		color = Color3.fromHex("#7FD96A"),
		glow = Color3.fromHex("#C8F27A"),
	},
	{
		id = "crystal_beetle",
		name = "Crystal Beetle",
		icon = "pet_crystal_beetle",
		rarity = "magic",
		text = "Pulls in loot from farther away.",
		bonus = { magnet = 6 },
		look = "beetle",
		color = Color3.fromHex("#4FD8F5"),
		glow = Color3.fromHex("#B8F4FF"),
	},
	{
		id = "shroomling",
		name = "Shroomling",
		icon = "pet_shroomling",
		rarity = "magic",
		text = "A tough companion that makes you tougher.",
		bonus = { life = 10 },
		look = "mushroom",
		color = Color3.fromHex("#F2E3C9"),
		glow = Color3.fromHex("#E86A9A"),
	},
	{
		id = "spark_fox",
		name = "Spark Fox",
		icon = "pet_spark_fox",
		rarity = "rare",
		text = "Its sparks hit harder.",
		bonus = { damage = 10 },
		look = "imp",
		color = Color3.fromHex("#FF8A3D"),
		glow = Color3.fromHex("#FFD27A"),
	},
	{
		id = "cloud_whale",
		name = "Cloud Whale",
		icon = "pet_cloud_whale",
		rarity = "rare",
		text = "Finds items more often.",
		bonus = { items = 15 },
		look = "wisp",
		color = Color3.fromHex("#DDEBFF"),
		glow = Color3.fromHex("#9CE5FF"),
	},
	{
		id = "star_cat",
		name = "Star Cat",
		icon = "pet_star_cat",
		rarity = "epic",
		text = "Brings luck with gold and XP.",
		bonus = { gold = 15, xp = 15 },
		look = "lantern",
		color = Color3.fromHex("#B57BFF"),
		glow = Color3.fromHex("#E7D2FF"),
	},
	{
		id = "rune_dragon",
		name = "Rune Dragon",
		icon = "pet_rune_dragon",
		rarity = "legend",
		text = "Ancient and mighty: more damage and more loot.",
		bonus = { damage = 15, items = 10 },
		look = "imp",
		color = Color3.fromHex("#FFB23F"),
		glow = Color3.fromHex("#FFF0B0"),
	},
}

local EGGS: { Egg } = {
	{
		id = "meadow_egg",
		name = "Meadow Egg",
		icon = "egg_meadow",
		text = "Mostly common companions, rarely something special.",
		price = { kind = "gold", amount = 600 },
		weights = { normal = 60, magic = 28, rare = 10, epic = 2 },
	},
	{
		id = "star_egg",
		name = "Star Egg",
		icon = "egg_star",
		text = "Better odds - even for the Rune Dragon.",
		price = { kind = "soulstars", amount = 75 },
		weights = { normal = 20, magic = 40, rare = 28, epic = 10, legend = 2 },
	},
}

-- Fixed order so equal random numbers roll the same (also the display order).
-- odds and roll only walk this list: a weight key missing here would silently never roll,
-- so the module checks at load time that every egg only uses these keys.
local RARITY_ORDER = table.freeze({ "normal", "magic", "rare", "epic", "legend" })
Pets.RarityOrder = RARITY_ORDER

local byId: { [string]: Pet } = {}
for _, p in LIST do
	assert(table.find(RARITY_ORDER, p.rarity), `pet {p.id}: unknown rarity {p.rarity}`)
	table.freeze(p.bonus)
	byId[p.id] = table.freeze(p)
end
local eggById: { [string]: Egg } = {}
for _, e in EGGS do
	for r, w in e.weights do
		assert(table.find(RARITY_ORDER, r), `egg {e.id}: weight key {r} missing from RARITY_ORDER`)
		assert(w >= 0, `egg {e.id}: negative weight for {r}`)
	end
	table.freeze(e.price)
	table.freeze(e.weights)
	eggById[e.id] = table.freeze(e)
end

Pets.List = table.freeze(LIST)
Pets.ById = table.freeze(byId)
Pets.Eggs = table.freeze(EGGS)
Pets.EggById = table.freeze(eggById)

-- Icon for a pet in the UI (falls back to the generic companion icon)
function Pets.iconOf(pet: Pet): string
	return pet.icon or "companion"
end

-- Icon for an egg card (falls back to the generic companion icon)
function Pets.eggIconOf(egg: Egg): string
	return egg.icon or "companion"
end

-- Price of an egg for a player with this best depth (gold grows like in the shop,
-- Soulstars stay fixed). Systems/Pets charges exactly this; the UI shows it.
-- The first gold egg is free (audit #13): the Pets window opens at depth 8, when a Meadow Egg
-- costs several times what the player has, so "Hatch a pet" hands over what it teaches.
-- `owned` = number of pets the player has (nil = not known, normal price).

function Pets.eggPrice(egg: Egg, bestDepth: number, owned: number?): number
	if egg.price.kind ~= "gold" then
		return egg.price.amount
	end
	if owned == 0 then
		return 0
	end
	return math.floor(egg.price.amount * Balance.shopFactor(bestDepth) + 0.5)
end

-- Number of pets owned (for eggPrice)
function Pets.ownedCount(data: Data): number
	local n = 0
	for _ in data.owned do
		n += 1
	end
	return n
end

function Pets.fresh(): Data
	return { owned = {}, equipped = {} }
end

-- Clean up saved raw data. Unknown pets (from a newer server) stay owned, otherwise they
-- would be gone forever after visiting an old server. They never count anywhere (bonuses,
-- display and equipping check Pets.ById); only known pets stay equipped. Capped at
-- MAX_UNKNOWN entries so junk cannot bloat the save.
Pets.MAX_UNKNOWN = 100
Pets.MAX_ID_LEN = 64

function Pets.reconcile(raw: any): Data
	local data = Pets.fresh()
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.owned) == "table" then
		local unknown = 0
		for id, lvl in raw.owned do
			if
				typeof(id) == "string"
				and #id > 0
				and #id <= Pets.MAX_ID_LEN
				and typeof(lvl) == "number"
				and lvl == lvl
			then
				local keep = byId[id] ~= nil
				if not keep and unknown < Pets.MAX_UNKNOWN then
					unknown += 1
					keep = true
				end
				if keep then
					data.owned[id] = math.clamp(math.floor(lvl), 1, Pets.MAX_LEVEL)
				end
			end
		end
	end
	if typeof(raw.equipped) == "table" then
		for _, id in raw.equipped do
			if
				typeof(id) == "string"
				and byId[id]
				and data.owned[id]
				and not table.find(data.equipped, id)
				and #data.equipped < Pets.MAX_SLOTS
			then
				table.insert(data.equipped, id)
			end
		end
	end
	return data
end

-- Only the pets this server knows (for display/payload; unknown ones stay saved)
function Pets.knownOwned(data: Data): { [string]: number }
	local out: { [string]: number } = {}
	for id, lvl in data.owned do
		if byId[id] then
			out[id] = lvl
		end
	end
	return out
end

-- Bonus factor per level: 1, 1.5, 2, 2.5, 3
function Pets.levelMult(level: number): number
	return 1 + 0.5 * (math.clamp(level, 1, Pets.MAX_LEVEL) - 1)
end

-- Bonus of a pet at its level
function Pets.bonusOf(id: string, level: number): { [string]: number }
	local pet = byId[id]
	local out: { [string]: number } = {}
	if pet then
		for stat, v in pet.bonus do
			out[stat] = v * Pets.levelMult(level)
		end
	end
	return out
end

-- Sum of the equipped pets (at most `slots`, unknown ones take no slot)
function Pets.total(data: Data, slots: number): { [string]: number }
	local sum: { [string]: number } = {}
	local used = 0
	for _, id in data.equipped do
		if not byId[id] then
			continue
		end
		used += 1
		if used > slots then
			break
		end
		for stat, v in Pets.bonusOf(id, data.owned[id] or 1) do
			sum[stat] = (sum[stat] or 0) + v
		end
	end
	return sum
end

local function weightTotal(egg: Egg): number
	local total = 0
	for _, w in egg.weights do
		total += w
	end
	return total
end

export type Odd = { rarity: string, percent: number }

-- Odds of an egg in percent (required for paid random items). Comes from the same
-- `weights` Pets.roll rolls with. Only rarities with weight > 0, in RARITY_ORDER.
-- Percent unrounded (sum 100); the display rounds itself.
function Pets.odds(egg: Egg): { Odd }
	local total = weightTotal(egg)
	local out: { Odd } = {}
	if total <= 0 then
		return out
	end
	for _, r in RARITY_ORDER do
		local w = egg.weights[r] or 0
		if w > 0 then
			table.insert(out, { rarity = r, percent = w / total * 100 })
		end
	end
	return out
end

-- Rolls the rarity from the egg weights, then a pet of that rarity
function Pets.roll(egg: Egg, rng: Random): Pet
	local pick = rng:NextNumber() * weightTotal(egg)
	local rarity = "normal"
	for _, r in RARITY_ORDER do
		local w = egg.weights[r] or 0
		if w > 0 then
			rarity = r
			if pick < w then
				break
			end
			pick -= w
		end
	end
	local pool = {}
	for _, p in LIST do
		if p.rarity == rarity then
			table.insert(pool, p)
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- Result when `pet` hatches: new level, or shards at max level
function Pets.hatchResult(data: Data, id: string): (number, number)
	local level = data.owned[id]
	if not level then
		return 1, 0
	end
	if level >= Pets.MAX_LEVEL then
		return level, Pets.DUPE_SHARDS
	end
	return level + 1, 0
end

return table.freeze(Pets)
