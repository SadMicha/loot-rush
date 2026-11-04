--!strict
-- Onboarding: a fixed quest chain that introduces one system at a time, and the unlock rules
-- for the hub windows ("new toys", concept: the first 30 minutes only show walking, skills and
-- loot). Pure rules without instances (testable); Systems/Quests counts and pays out,
-- QuestController shows the active quest and locks the hub bar buttons.
--
-- Goal kinds:
--   count goals (counted by server actions): "rift" (enter a Rift), "kill", "pickup" (items),
--   "equip", "star" (allocate a star), "forge" (any Forge action), "salvage", "hatch"
--   state goals (checked against the player): "depth" (best cleared depth), "level"
-- Unlocks are saved once reached and never lock again.
-- The save stores the chain index: only append new quests at the end, never insert or reorder.

local Quests = {}

export type Goal =
	"rift"
	| "kill"
	| "pickup"
	| "equip"
	| "star"
	| "forge"
	| "salvage"
	| "hatch"
	| "depth"
	| "level"

export type Quest = {
	id: string, -- stable, used for analytics
	text: string,
	goal: Goal,
	target: number,
	gold: number, -- reward
	unlocks: string?, -- window opened by finishing this quest (shown in the toast)
}

export type Data = {
	step: number, -- index of the active quest; #Chain + 1 = chain done
	count: number, -- progress of count goals for the active quest
	unlocks: { [string]: boolean }, -- unlocked windows (saved, never lost)
}

Quests.Chain = table.freeze({
	{
		id = "enter_rift",
		text = "Enter a Rift from the Atlas",
		goal = "rift",
		target = 1,
		gold = 20,
	},
	{ id = "first_kills", text = "Defeat 10 enemies", goal = "kill", target = 10, gold = 30 },
	{ id = "first_loot", text = "Pick up 3 items", goal = "pickup", target = 3, gold = 30 },
	{ id = "equip", text = "Equip an item", goal = "equip", target = 1, gold = 40 },
	{ id = "depth_3", text = "Clear depth 3", goal = "depth", target = 3, gold = 60 },
	{
		id = "level_5",
		text = "Reach level 5",
		goal = "level",
		target = 5,
		gold = 80,
		unlocks = "star_net",
	},
	{
		id = "first_star",
		text = "Place a star in the Star Web",
		goal = "star",
		target = 1,
		gold = 80,
	},
	{
		id = "depth_5",
		text = "Clear depth 5",
		goal = "depth",
		target = 5,
		gold = 120,
		unlocks = "forge",
	},
	{ id = "first_forge", text = "Use the Forge once", goal = "forge", target = 1, gold = 120 },
	{ id = "salvage", text = "Salvage 5 items", goal = "salvage", target = 5, gold = 150 },
	{
		id = "depth_8",
		text = "Clear depth 8",
		goal = "depth",
		target = 8,
		gold = 250,
		unlocks = "pets",
	},
	{ id = "first_pet", text = "Hatch a pet", goal = "hatch", target = 1, gold = 250 },
	{ id = "level_15", text = "Reach level 15", goal = "level", target = 15, gold = 500 },
	{ id = "depth_15", text = "Clear depth 15", goal = "depth", target = 15, gold = 800 },
	{ id = "depth_20", text = "Clear depth 20", goal = "depth", target = 20, gold = 1500 },
} :: { Quest })

-- Windows behind an unlock: reached by level OR best depth (whatever comes first), or by
-- finishing the quest that names them. Windows not listed are always open.
Quests.Unlocks = table.freeze({
	star_net = { level = 5, caption = "Reach level 5" },
	forge = { depth = 5, caption = "Clear depth 5" },
	pets = { depth = 8, caption = "Clear depth 8" },
	auto_salvage = { depth = 10, caption = "Clear depth 10" },
} :: { [string]: { level: number?, depth: number?, caption: string } })

Quests.Names = table.freeze({
	star_net = "Star Web",
	forge = "Forge",
	pets = "Pets",
	auto_salvage = "Auto-Salvage",
} :: { [string]: string })

-- Quest waypoint (docs/ROADMAP-1.0.md O1): the hub station a goal is done at, by the window name
-- of its prompt (Hub builds a part "Station_<window>"). Goals that happen in a Rift or in a
-- window have none.
Quests.Waypoints = table.freeze({
	rift = "Atlas",
	depth = "Atlas",
	forge = "Forge",
	salvage = "Inventory",
	hatch = "Pets",
} :: { [string]: string })

-- Station window the quest at this chain step points to, nil = no waypoint
function Quests.waypoint(step: number): string?
	local q = Quests.Chain[step]
	return if q then Quests.Waypoints[q.goal] else nil
end

function Quests.fresh(): Data
	return { step = 1, count = 0, unlocks = {} }
end

local function whole(v: any, max: number): number
	if typeof(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.floor(math.min(v, max))
end

-- Repairs a loaded save (wrong types, out of range, unknown unlock keys dropped)
function Quests.reconcile(raw: any): Data
	local data = if typeof(raw) == "table" then raw else {}
	local step = whole(data.step, #Quests.Chain + 1)
	local out: Data = { step = math.max(1, step), count = whole(data.count, 1e9), unlocks = {} }
	if typeof(data.unlocks) == "table" then
		for id, on in data.unlocks do
			if typeof(id) == "string" and Quests.Unlocks[id] and on == true then
				out.unlocks[id] = true
			end
		end
	end
	return out
end

function Quests.active(data: Data): Quest?
	return Quests.Chain[data.step]
end

-- Progress of the active quest for the display: (current, target)
function Quests.progress(data: Data, level: number, depth: number): (number, number)
	local q = Quests.active(data)
	if not q then
		return 0, 0
	end
	local now = if q.goal == "level" then level elseif q.goal == "depth" then depth else data.count
	return math.min(now, q.target), q.target
end

-- Is the window open? (always for windows without an unlock rule)
function Quests.isOpen(data: Data, id: string, level: number, depth: number): boolean
	local rule = Quests.Unlocks[id]
	if not rule or data.unlocks[id] then
		return true
	end
	return (rule.level ~= nil and level >= rule.level)
		or (rule.depth ~= nil and depth >= rule.depth)
end

-- Saves every unlock reached by level/depth. Returns the newly unlocked ids.
function Quests.refreshUnlocks(data: Data, level: number, depth: number): { string }
	local new = {}
	for id in Quests.Unlocks do
		if not data.unlocks[id] and Quests.isOpen(data, id, level, depth) then
			data.unlocks[id] = true
			table.insert(new, id)
		end
	end
	table.sort(new)
	return new
end

-- Counts an action and advances the chain as far as possible.
-- Returns the quests finished by this call (in order) - the caller pays the rewards.
function Quests.advance(
	data: Data,
	goal: Goal?,
	amount: number,
	level: number,
	depth: number
): { Quest }
	local done = {}
	local q = Quests.active(data)
	if q and goal and q.goal == goal and amount > 0 then
		data.count += amount
	end
	while q do
		local now, target = Quests.progress(data, level, depth)
		if now < target then
			break
		end
		table.insert(done, q)
		if q.unlocks then
			data.unlocks[q.unlocks] = true
		end
		data.step += 1
		data.count = 0
		q = Quests.active(data)
	end
	return done
end

return Quests
