--!strict
-- Stash: account-wide item storage in the hub, shared by every hero of the account (like the
-- stash of a classic ARPG). Pure rules without remotes (testable); Systems/Stash moves items
-- between the active hero's bag and the stash, Client/StashController draws it.
--
-- Save field: Account.stash = { tabs = { { Item } × Config.STASH_TABS } }.
-- An item lives in exactly one place: a move removes it from one list and inserts it into the
-- other in the same step, and both lists sit in the same save (no duplicates across a crash).

local Config = require(script.Parent.Config)
local Items = require(script.Parent.Items)

local Stash = {}

export type Data = {
	tabs: { { Items.Item } },
}

Stash.TABS = Config.STASH_TABS
Stash.TAB_SLOTS = Config.STASH_TAB_SLOTS
Stash.MAX_ID = 64 -- longest item id accepted from a remote or a save

function Stash.fresh(): Data
	local tabs = {}
	for i = 1, Stash.TABS do
		tabs[i] = {}
	end
	return { tabs = tabs }
end

-- An item as the server stores it: string id and slot, the rest is repaired where it is read
local function validItem(v: any): boolean
	return typeof(v) == "table"
		and typeof(v.id) == "string"
		and #v.id > 0
		and #v.id <= Stash.MAX_ID
		and typeof(v.slot) == "string"
		and typeof(v.rarity) == "string"
		and typeof(v.name) == "string"
		and typeof(v.ilvl) == "number"
		and typeof(v.affixes) == "table"
end

-- Repairs a loaded stash: exactly Stash.TABS tabs, junk dropped, every item id once.
-- `taken` = item ids already owned elsewhere (heroes' bags and gear): such a copy is dropped
-- from the stash, never from the hero. Items of tabs past Stash.TABS (an older layout) move into
-- the last tab; a tab may hold more than TAB_SLOTS then (nothing is deleted for the cap, it just
-- takes no new items until there is room).
function Stash.reconcile(raw: any, taken: { [string]: boolean }?): Data
	local out = Stash.fresh()
	if typeof(raw) ~= "table" or typeof(raw.tabs) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for i, tab in raw.tabs do
		if typeof(i) ~= "number" or typeof(tab) ~= "table" then
			continue
		end
		local into = out.tabs[math.clamp(math.floor(i), 1, Stash.TABS)]
		for _, item in tab do
			if validItem(item) and not seen[item.id] and not (taken and taken[item.id]) then
				seen[item.id] = true
				table.insert(into, item :: Items.Item)
			end
		end
	end
	return out
end

-- Ids of everything a list of heroes owns (bag + gear), for Stash.reconcile
function Stash.owned(characters: { any }): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for _, c in characters do
		if typeof(c) ~= "table" then
			continue
		end
		if typeof(c.inventory) == "table" then
			for _, item in c.inventory do
				if typeof(item) == "table" and typeof(item.id) == "string" then
					ids[item.id] = true
				end
			end
		end
		if typeof(c.equipped) == "table" then
			for _, item in c.equipped do
				if typeof(item) == "table" and typeof(item.id) == "string" then
					ids[item.id] = true
				end
			end
		end
	end
	return ids
end

function Stash.validTab(tab: any): boolean
	return typeof(tab) == "number"
		and tab == tab
		and tab % 1 == 0
		and tab >= 1
		and tab <= Stash.TABS
end

-- Free slots in a tab (0 when over the cap)
function Stash.room(data: Data, tab: number): number
	local list = data.tabs[tab]
	return if list then math.max(0, Stash.TAB_SLOTS - #list) else 0
end

-- Where an item sits in the stash: tab and index, nil if it is not stored
function Stash.find(data: Data, id: string): (number?, number?)
	for t, list in data.tabs do
		for i, item in list do
			if item.id == id then
				return t, i
			end
		end
	end
	return nil, nil
end

local function indexIn(list: { Items.Item }, id: string): number?
	for i, item in list do
		if item.id == id then
			return i
		end
	end
	return nil
end

export type Reason = "ok" | "missing" | "tab" | "full" | "bag_full" | "duplicate"

-- Bag → stash tab. Returns "ok" or why nothing moved.
function Stash.deposit(data: Data, bag: { Items.Item }, id: string, tab: number): Reason
	if not Stash.validTab(tab) then
		return "tab"
	end
	local index = indexIn(bag, id)
	if not index then
		return "missing"
	end
	if Stash.find(data, id) then
		return "duplicate" -- never a second copy (a broken save, or a race)
	end
	if Stash.room(data, tab) <= 0 then
		return "full"
	end
	local item = table.remove(bag, index) :: Items.Item
	table.insert(data.tabs[tab], item)
	return "ok"
end

-- Stash → bag (from whichever tab holds it). Returns "ok" or why nothing moved.
function Stash.withdraw(data: Data, bag: { Items.Item }, id: string, bagMax: number): Reason
	local tab, index = Stash.find(data, id)
	if not tab or not index then
		return "missing"
	end
	if indexIn(bag, id) then
		return "duplicate"
	end
	if #bag >= bagMax then
		return "bag_full"
	end
	local item = table.remove(data.tabs[tab], index) :: Items.Item
	table.insert(bag, item)
	return "ok"
end

-- Whole bag → one tab, oldest first, as long as the tab has room. Returns how many moved.
function Stash.depositAll(data: Data, bag: { Items.Item }, tab: number): number
	if not Stash.validTab(tab) then
		return 0
	end
	local moved = 0
	local i = 1
	while i <= #bag and Stash.room(data, tab) > 0 do
		local item = bag[i]
		if Stash.find(data, item.id) then
			i += 1 -- a duplicate stays in the bag
		else
			table.remove(bag, i)
			table.insert(data.tabs[tab], item)
			moved += 1
		end
	end
	return moved
end

-- Player-facing line for a failed move (English; the Roblox translator localizes)
Stash.Text = table.freeze({
	missing = "That item is no longer there.",
	tab = "Pick a stash tab first.",
	full = "This stash tab is full. Pick another tab.",
	bag_full = "Your bag is full. Store or salvage something first.",
	duplicate = "That item is already stored.",
	far = "Walk to the stash in the hub to use it.",
} :: { [string]: string })

return Stash
