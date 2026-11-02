--!strict
-- All Robux IDs in one place: Developer Products (Soulstars) and game passes.
-- IDs come from the Creator Hub (experience → Monetization → Developer Products / Passes).
-- 0 = not created yet: the buy button stays off, the server accepts nothing.
-- Robux prices here are display only - the price in the Creator Hub is authoritative.
-- Server: Systems/Monetization (ProcessReceipt, game pass ownership). Guide: docs/MONETIZATION.md

local Monetization = {}

-- Developer Products (can be bought repeatedly). Key = Shop.OFFERS[].product
Monetization.ProductIds = table.freeze({
	soulstars_s = 0,
	soulstars_m = 0,
	soulstars_l = 0,
} :: { [string]: number })

export type Pass = {
	key: string,
	id: number, -- game pass ID; 0 = placeholder
	name: string,
	text: string,
	robux: number,
	icon: string,
	bonus: { [string]: number }, -- permanent bonuses like Systems/Boosts (percent, magnet = studs)
	attr: string?, -- extra player attribute = true (e.g. PassPetSlot for Systems/Pets)
}

local PASSES: { Pass } = {
	{
		key = "vip",
		id = 0,
		name = "VIP",
		text = "+25% gold and +25% XP forever.",
		robux = 299,
		icon = "crown",
		bonus = { gold = 25, xp = 25 },
	},
	{
		key = "pet_slot",
		id = 0,
		name = "Pet Slot",
		text = "A second pet joins you.",
		robux = 199,
		icon = "heart",
		bonus = {},
		attr = "PassPetSlot",
	},
	{
		key = "magnet",
		id = 0,
		name = "Loot Magnet",
		text = "+8 studs pickup radius and +10% item chance.",
		robux = 149,
		icon = "chest",
		bonus = { magnet = 8, items = 10 },
	},
}

local byKey: { [string]: Pass } = {}
for _, p in PASSES do
	table.freeze(p.bonus)
	byKey[p.key] = table.freeze(p)
end
Monetization.Passes = table.freeze(PASSES)
Monetization.PassByKey = table.freeze(byKey)

-- Attribute on the player when they own the pass (set by the server)
function Monetization.passAttr(key: string): string
	return "Pass_" .. key
end

function Monetization.passById(id: number): Pass?
	if id <= 0 then
		return nil
	end
	for _, p in PASSES do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Sum of the bonuses of all passes for which owned(key) is true
function Monetization.bonus(owned: (string) -> boolean): { [string]: number }
	local sum: { [string]: number } = {}
	for _, p in PASSES do
		if owned(p.key) then
			for stat, v in p.bonus do
				sum[stat] = (sum[stat] or 0) + v
			end
		end
	end
	return sum
end

return table.freeze(Monetization)
