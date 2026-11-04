--!strict
-- Bag upgrades (docs/GAMEPLAY.md "Bag"): pure rules shared by Systems/Inventory and the windows.
--   • Capacity = Balance.Bag.base + step × level, level 0 to maxLevel (40 → 100 slots).
--   • The level is ACCOUNT-WIDE and belongs to the SEASON: it is saved in account.season.bag
--     (Shared/Seasons), so Seasons.reconcile drops it with the rest of the season data when the
--     season id changes. Every hero of the account gets the same bag.
--   • Bought with the active hero's gold, one level at a time (Bag.check).
--   • A smaller bag never deletes items: a bag over capacity keeps them and only refuses new ones.

local Balance = require(script.Parent.Balance)
local Shop = require(script.Parent.Shop)
local Format = require(script.Parent.Util.Format)

local Bag = {}

local B = Balance.Bag

Bag.BASE = B.base
Bag.STEP = B.step
Bag.MAX_LEVEL = B.maxLevel
Bag.MAX_CAPACITY = B.base + B.step * B.maxLevel

-- "ok" = buy now; "max" = largest bag; "gold" = not enough gold;
-- "stale" = the client asked for another level than the next one (double tap, old window)
export type Reason = "ok" | "max" | "gold" | "stale"

Bag.Text = table.freeze({
	max = "Your bag is already at its largest size",
	gold = "Not enough gold",
	stale = "The bag size changed, try again",
} :: { [string]: string })

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Sanitized level of a saved / sent value: whole number 0 to MAX_LEVEL, junk = 0
function Bag.level(raw: any): number
	if not finite(raw) then
		return 0
	end
	return math.clamp(math.floor(raw), 0, Bag.MAX_LEVEL)
end

function Bag.capacity(level: number): number
	return Bag.BASE + Bag.STEP * Bag.level(level)
end

-- Gold for the step from `level` to level + 1; nil at the largest bag
function Bag.price(level: number): number?
	local l = Bag.level(level)
	if l >= Bag.MAX_LEVEL then
		return nil
	end
	return Shop.round(B.price * B.growth ^ l)
end

-- Capacity from the BagMax player attribute (the client's view); BASE until the server set it
function Bag.fromAttribute(raw: any): number
	if not finite(raw) then
		return Bag.BASE
	end
	return math.clamp(math.floor(raw), Bag.BASE, Bag.MAX_CAPACITY)
end

-- Is `target` a level the client may ask for at all (whole number 1 to MAX_LEVEL)?
function Bag.validTarget(target: any): boolean
	return finite(target)
		and target == math.floor(target)
		and target >= 1
		and target <= Bag.MAX_LEVEL
end

-- Can a hero with `gold` buy `target` (= the next level) now? Returns the reason and the price.
function Bag.check(level: number, target: number, gold: number): (Reason, number)
	local price = Bag.price(level)
	if price == nil then
		return "max", 0
	end
	if target ~= Bag.level(level) + 1 then
		return "stale", price
	end
	if not finite(gold) or gold < price then
		return "gold", price
	end
	return "ok", price
end

-- Text after a successful upgrade
function Bag.doneText(level: number): string
	return `Bag upgraded to {Format.int(Bag.capacity(level))} slots`
end

return table.freeze(Bag)
