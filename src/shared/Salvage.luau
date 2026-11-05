--!strict
-- Salvage rules shared by the server (Systems/Inventory) and the bag window: item lock, the
-- auto-salvage rule on pickup and the bulk "Salvage all downgrades". Pure (testable).
--
-- Item lock: Item.locked = true (saved on the item, so it travels into the stash and back).
-- A locked item is never salvaged: not by a tap, not by bulk salvage, not by auto-salvage, and
-- the Forge never uses it up as a Fuse duplicate. Uniques and worn gear are never part of bulk or
-- auto-salvage either (worn gear is not in the bag at all).
--
-- Auto-salvage (per hero, unlocked at depth 10): rarity limit (Profile.autoSalvage, "" = off) and
-- keep upgrades (Profile.autoKeep, default on): loot up to the limit is salvaged on pickup unless
-- it beats the worn piece of its slot (Shared/Upgrade).

local Items = require(script.Parent.Items)
local Upgrade = require(script.Parent.Upgrade)

local Salvage = {}

Salvage.MAX_BULK = 300 -- most ids one bulk request may carry (bags are smaller)
Salvage.MAX_ID = 64

-- Rarity limits the auto-salvage button cycles through ("" = off); never uniques
Salvage.AUTO_LIMITS = table.freeze({ "", "normal", "magic", "rare", "epic" })

function Salvage.isLocked(item: Items.Item): boolean
	return item.locked == true
end

-- May the player salvage this item by hand (tap, compare card)? Locked items never.
function Salvage.canSalvage(item: Items.Item): boolean
	return not Salvage.isLocked(item)
end

-- Never part of a bulk or automatic salvage: locked items and uniques
function Salvage.protected(item: Items.Item): boolean
	return Salvage.isLocked(item) or item.rarity == "unique"
end

-- Valid auto-salvage limit: "" (off) or a rarity below unique
function Salvage.validLimit(v: any): boolean
	if typeof(v) ~= "string" then
		return false
	end
	return v == "" or (Items.rank(v) > 0 and v ~= "unique")
end

-- Does auto-salvage take this loot on pickup? `hero` = the hero's comparison (Upgrade.hero), only
-- needed when keepUpgrades is on (nil hero: nothing counts as an upgrade).
function Salvage.auto(
	limit: string,
	keepUpgrades: boolean,
	item: Items.Item,
	hero: Upgrade.Hero?
): boolean
	local max = Items.rank(limit)
	if max <= 0 or Salvage.protected(item) or Items.rank(item.rarity) > max then
		return false
	end
	if keepUpgrades and hero and Upgrade.isUpgrade(hero, item) then
		return false
	end
	return true
end

-- Is this bag item a downgrade for bulk salvage? Same verdict as the red arrow (Upgrade.marks
-- "down"): it has an equipment slot, the hero can wear it and it does not beat the worn piece.
-- Locked items and uniques are left out. Items the hero cannot wear yet (level, class) are kept.
function Salvage.isDowngrade(item: Items.Item, hero: Upgrade.Hero): boolean
	if Salvage.protected(item) or not Items.SlotName[item.slot] then
		return false
	end
	if not Items.canWear(item, hero.level, hero.class) then
		return false
	end
	return not Upgrade.isUpgrade(hero, item)
end

-- Every bulk-salvageable downgrade of the bag, in bag order
function Salvage.downgrades(bag: { Items.Item }, hero: Upgrade.Hero): { Items.Item }
	local out = {}
	for _, item in bag do
		if Salvage.isDowngrade(item, hero) then
			table.insert(out, item)
		end
	end
	return out
end

export type Yield = { count: number, gold: number, shards: number, candy: number, dust: number }

-- Expected yield of salvaging `list` (for the confirm dialog): gold and shards exact, Forge Candy
-- and Glitter Dust as expected values (they roll per item, Systems/Progress). shardFind = Star Web
-- "Shards from Salvage %".
function Salvage.expected(list: { Items.Item }, shardFind: number?): Yield
	local find = (if typeof(shardFind) == "number" and shardFind == shardFind then shardFind else 0)
		/ 100
	local y: Yield = { count = 0, gold = 0, shards = 0, candy = 0, dust = 0 }
	for _, item in list do
		y.count += 1
		y.gold += Items.sellValue(item)
		local s = Items.Salvage[item.rarity]
		if s then
			y.shards += math.floor(s.shards * (1 + find) + 0.5)
			y.candy += s.candy
			y.dust += s.dust
		end
	end
	return y
end

-- Item ids of a bulk request: an array of distinct short strings, at most MAX_BULK. nil = invalid.
function Salvage.validIds(raw: any): { string }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local n = #raw
	if n == 0 or n > Salvage.MAX_BULK then
		return nil
	end
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local count = 0
	for k, v in raw do
		count += 1
		if typeof(k) ~= "number" or typeof(v) ~= "string" or #v == 0 or #v > Salvage.MAX_ID then
			return nil
		end
		if not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	if count ~= n then
		return nil -- holes or extra keys
	end
	return out
end

-- Normalizes the lock flag of a loaded item (true or absent, never another value)
function Salvage.cleanLock(item: any)
	if typeof(item) == "table" and item.locked ~= nil and item.locked ~= true then
		item.locked = nil
	end
end

Salvage.Text = table.freeze({
	locked = "This item is locked. Unlock it to salvage it.",
	none = "No downgrades to salvage.",
} :: { [string]: string })

return table.freeze(Salvage)
