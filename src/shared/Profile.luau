--!strict
-- Save schema: defaults, migration of old saves, sanitizing. Pure logic without DataStore
-- (testable); loading, saving and sessions are Systems/Data on ProfileStore.
--
-- Since v4 the save is an ACCOUNT holding CHARACTERS (docs/specs/SEASONS.md §6, docs/CLASSES.md):
--   Account   = account-wide values (Soulstars, Robux receipts, game passes, pets, cosmetics) +
--               characters
--   Character = everything a hero owns (gold, level, gear, skills, atlas, class …); the class is
--               locked once the character is set up (name + class on the setup screen)
-- Gameplay sees the active character (Data.get); account values through Data.account.
--
-- New field? Add it to the Data (character) or Account type and DEFAULTS - missing fields are
-- filled in on load. Fields with their own validation (e.g. Progression) are appended in
-- Profile.reconcile / Profile.reconcileAccount instead.
-- Renaming/restructuring a field? Bump VERSION and add a step to MIGRATIONS.
-- JSON-safe values only: numbers, strings, bools, lists and tables with string keys.

local Classes = require(script.Parent.Classes)
local Cosmetics = require(script.Parent.Cosmetics)
local Daily = require(script.Parent.Daily)
local Items = require(script.Parent.Items)
local Leaderboard = require(script.Parent.Leaderboard)
local Monetization = require(script.Parent.Monetization)
local Pets = require(script.Parent.Pets)
local Progression = require(script.Parent.Progression)
local Quests = require(script.Parent.Quests)
local Settings = require(script.Parent.Settings)
local WorldTiers = require(script.Parent.WorldTiers)

local Profile = {}

-- One character (hero) of the account
export type Data = {
	id: string, -- stable within the account ("c1", "c2", …)
	name: string, -- chosen on the setup screen ("" = not set up yet / pre-v4 save)
	league: string, -- "legacy" (Season leagues later, docs/specs/SEASONS.md)
	created: number, -- os.time() of creation (0 = migrated)
	migratedFrom: string, -- league it came from (season end), "" otherwise
	setupDone: boolean, -- name + class confirmed; from then on the class is locked
	gold: number,
	level: number,
	xp: number,
	inventory: { Items.Item },
	equipped: { [string]: Items.Item }, -- slot → item
	progress: Progression.Data, -- skill levels, Skill Blooms, Star Net
	materials: Progression.Materials, -- Forge materials
	atlas: { [string]: number }, -- region → highest Rift depth cleared (Shared/Atlas)
	tier: WorldTiers.Data, -- World Tier unlocked/selected (Shared/WorldTiers)
	quests: Quests.Data, -- onboarding quest chain and window unlocks (Shared/Quests)
	class: string, -- class of this character (Shared/Classes id), locked after setup
	autoSalvage: string, -- "" = off, else loot up to this rarity is salvaged on pickup
	debugged: boolean, -- a test command (Systems/Debug) touched it: never written to leaderboards
	starters: number, -- guaranteed first drops already given (Balance.FirstDrops, Systems/Loot)
}

-- The whole save of one Roblox account
export type Account = {
	soulstars: number, -- Soulstars (shop, Robux), shared by all characters
	receipts: { string }, -- recently booked Robux purchases (PurchaseId), against double crediting
	pets: Pets.Data, -- pets (Shared/Pets), shared by all characters
	passes: { [string]: boolean }, -- last known game pass ownership (outage buffer, Systems/Monetization)
	settings: Settings.Data, -- settings window (Shared/Settings), the same for every character
	cosmetics: { [string]: boolean }, -- owned cosmetics (Shared/Cosmetics ids)
	wear: { [string]: string }, -- slot → worn cosmetic id ("" = none)
	bought: { [string]: boolean }, -- one-time Robux products already bought (Monetization once)
	daily: Daily.Data, -- daily reward calendar (Shared/Daily)
	boards: { [string]: number }, -- best value per leaderboard (Shared/Leaderboard ids)
	unsent: { [string]: number }, -- bests whose board write is not confirmed yet (retried on join)
	characters: { Data },
	active: string, -- id of the character played this session
}

-- The versioned save (stored as ProfileStore's profile.Data)
export type Record = {
	v: number,
	data: Account,
}

Profile.VERSION = 4
Profile.MAX_CHARACTERS = 12
Profile.NAME_MIN = 3
Profile.NAME_MAX = 16
Profile.MAX_RECEIPTS = 50
Profile.MAX_UNKNOWN_PASSES = 20 -- game passes only a newer server knows (stay saved)
Profile.MAX_KEY_LEN = 64
Profile.MAX_FLAGS = 64 -- cap for unknown keys in account.cosmetics / account.bought

local DEFAULTS: Data = {
	id = "",
	name = "",
	league = "legacy",
	created = 0,
	migratedFrom = "",
	setupDone = false,
	gold = 0,
	level = 1,
	xp = 0,
	inventory = {},
	equipped = {},
	progress = Progression.fresh(), -- contents checked by Progression.reconcile
	materials = Progression.freshMaterials(),
	atlas = {},
	tier = WorldTiers.fresh(),
	quests = Quests.fresh(),
	class = Classes.DEFAULT,
	autoSalvage = "",
	debugged = false,
	starters = 0,
}

local ACCOUNT_DEFAULTS = {
	soulstars = 0,
	receipts = {},
	pets = Pets.fresh(),
	passes = {},
	settings = Settings.fresh(), -- contents checked by Settings.reconcile
	cosmetics = {},
	wear = { trail = "", aura = "" },
	bought = {},
	daily = Daily.fresh(), -- contents checked by Daily.reconcile
	boards = {},
	unsent = {},
	characters = {},
	active = "",
}

-- Values that moved from the character to the account in v4
local ACCOUNT_FIELDS = { "soulstars", "receipts", "pets", "passes" }

-- MIGRATIONS[n] lifts a record from version n to n + 1
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1: the save sat directly in the key ({ version = 1, gold, inventory, equipped })
	[1] = function(raw)
		local data = table.clone(raw)
		data.version = nil
		return { v = 2, data = data }
	end,
	-- v2 → v3: loot level was depth × 2 − 1, now depth (item power = depth × 10, balancing table).
	-- Pull old items to the new level of their depth, otherwise their weapon base damage would be far too high.
	[2] = function(raw)
		local record = table.clone(raw)
		local data: any = if typeof(record.data) == "table" then table.clone(record.data) else {}
		local function rescale(item: any): any
			if typeof(item) ~= "table" or typeof(item.ilvl) ~= "number" then
				return item
			end
			local out = table.clone(item)
			out.ilvl = math.max(1, math.ceil((item.ilvl + 1) / 2))
			return out
		end
		if typeof(data.inventory) == "table" then
			local inv = {}
			for i, item in data.inventory do
				inv[i] = rescale(item)
			end
			data.inventory = inv
		end
		if typeof(data.equipped) == "table" then
			local eq = {}
			for slot, item in data.equipped do
				eq[slot] = rescale(item)
			end
			data.equipped = eq
		end
		record.data = data
		record.v = 3
		return record
	end,
	-- v3 → v4: the save becomes an account; the old save is its first (Legacy) character.
	-- Soulstars, receipts, passes and pets move up to the account. A class picked before stays
	-- (setup counts as done), the name is asked for later only if missing.
	[3] = function(raw)
		local record = table.clone(raw)
		local old: any = if typeof(record.data) == "table" then table.clone(record.data) else {}
		local account: any = {}
		for _, key in ACCOUNT_FIELDS do
			account[key] = old[key]
			old[key] = nil
		end
		old.id = "c1"
		old.league = "legacy"
		old.setupDone = old.classChosen == true
		old.classChosen = nil
		account.characters = { old }
		account.active = "c1"
		record.data = account
		record.v = 4
		return record
	end,
}

local function copy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end
	return out
end

Profile.copy = copy

-- Fills in missing fields and replaces fields of the wrong type with the default.
-- Fields DEFAULTS does not know are kept (e.g. from a newer server).
local function fill(target: { [any]: any }, defaults: { [any]: any })
	for k, def in defaults do
		local value = target[k]
		if typeof(value) ~= typeof(def) then
			target[k] = copy(def)
		elseif typeof(def) == "table" and next(def) ~= nil then
			fill(value, def)
		end
	end
end

-- Whole number ≥ 0 (NaN and infinity → 0)
local function whole(v: number): number
	if v ~= v or v < 0 or v == math.huge then
		return 0
	end
	return math.floor(v)
end

-- Sanitizes one character (in place where possible)
function Profile.reconcile(raw: any): Data
	local data = if typeof(raw) == "table" then raw else {}
	fill(data, DEFAULTS)
	if #data.id > Profile.MAX_KEY_LEN then
		data.id = string.sub(data.id, 1, Profile.MAX_KEY_LEN)
	end
	if Profile.validName(data.name) ~= data.name then
		data.name = "" -- asked again on the setup screen
	end
	data.created = whole(data.created)
	data.level = math.max(1, math.floor(data.level))
	data.xp = math.max(0, data.xp)
	data.starters = whole(data.starters)
	data.progress = Progression.reconcile(data.progress)
	data.materials = Progression.reconcileMaterials(data.materials)
	local atlas = {}
	for id, depth in data.atlas do
		if
			typeof(id) == "string"
			and typeof(depth) == "number"
			and depth == depth
			and depth >= 1
		then
			atlas[id] = math.floor(math.min(depth, 1e6))
		end
	end
	data.atlas = atlas
	data.rebirths = nil -- Rebirth was removed (pure ARPG, 2026-11-02)
	data.tier = WorldTiers.reconcile(data.tier)
	data.quests = Quests.reconcile(data.quests)
	data.class = Classes.valid(data.class)
	if
		data.autoSalvage ~= ""
		and (Items.rank(data.autoSalvage) == 0 or data.autoSalvage == "unique")
	then
		data.autoSalvage = ""
	end
	return data :: Data
end

-- Sanitizes the whole account: account values, every character (unique ids), the active one.
-- An account without characters gets one fresh character that still needs its setup.
function Profile.reconcileAccount(raw: any): Account
	local data = if typeof(raw) == "table" then raw else {}
	fill(data, ACCOUNT_DEFAULTS)
	data.soulstars = whole(data.soulstars)
	local receipts = {}
	for _, id in data.receipts do
		if typeof(id) == "string" and #id <= 128 then
			table.insert(receipts, id)
		end
	end
	while #receipts > Profile.MAX_RECEIPTS do
		table.remove(receipts, 1)
	end
	data.receipts = receipts
	data.pets = Pets.reconcile(data.pets)
	-- Unknown pass keys (newer server) are kept; Systems/Monetization only reads
	-- the known ones from Monetization.Passes. Capped so no junk gets saved.
	local passes = {}
	local unknownPasses = 0
	for key, owned in data.passes do
		if
			typeof(key) == "string"
			and #key > 0
			and #key <= Profile.MAX_KEY_LEN
			and owned == true
		then
			local keep = Monetization.PassByKey[key] ~= nil
			if not keep and unknownPasses < Profile.MAX_UNKNOWN_PASSES then
				unknownPasses += 1
				keep = true
			end
			if keep then
				passes[key] = true
			end
		end
	end
	data.passes = passes
	data.settings = Settings.reconcile(data.settings)
	-- Cosmetics and one-time purchases: string keys with true; unknown keys (newer server) stay,
	-- capped. Worn cosmetics must be owned and fit their slot.
	local function flags(input: any): { [string]: boolean }
		local out = {}
		local unknown = 0
		for key, on in input do
			if
				typeof(key) == "string"
				and #key > 0
				and #key <= Profile.MAX_KEY_LEN
				and on == true
			then
				if Cosmetics.ById[key] == nil and Monetization.ProductByKey[key] == nil then
					unknown += 1
					if unknown > Profile.MAX_FLAGS then
						continue
					end
				end
				out[key] = true
			end
		end
		return out
	end
	data.cosmetics = flags(data.cosmetics)
	data.bought = flags(data.bought)
	local wear = {}
	for _, slot in Cosmetics.Slots do
		local id = data.wear[slot]
		wear[slot] = if typeof(id) == "string"
				and data.cosmetics[id]
				and Cosmetics.fits(slot, id)
			then id
			else ""
	end
	data.wear = wear
	data.daily = Daily.reconcile(data.daily)
	-- Leaderboard bests and unsent writes: only known boards, whole numbers
	local function boardValues(input: any): { [string]: number }
		local out = {}
		for id, value in input do
			if
				typeof(id) == "string"
				and Leaderboard.ById[id]
				and typeof(value) == "number"
				and value == value
				and value > 0
				and value < 1e12
			then
				out[id] = math.floor(value)
			end
		end
		return out
	end
	data.boards = boardValues(data.boards)
	data.unsent = boardValues(data.unsent)
	-- Characters: drop junk, give every one a unique id (nothing is deleted for being over the cap)
	local list: { Data } = {}
	local seen: { [string]: boolean } = {}
	for _, c in data.characters do
		if typeof(c) == "table" then
			local char = Profile.reconcile(c)
			if char.id == "" or seen[char.id] then
				char.id = Profile.nextId(list)
			end
			seen[char.id] = true
			table.insert(list, char)
		end
	end
	if #list == 0 then
		local char = Profile.reconcile({})
		char.id = "c1"
		table.insert(list, char)
	end
	data.characters = list
	if not seen[data.active] then
		data.active = list[1].id
	end
	return data :: Account
end

-- First free id "c<n>" for a new character
function Profile.nextId(list: { Data }): string
	local n = #list + 1
	while true do
		local id = "c" .. n
		local taken = false
		for _, c in list do
			if c.id == id then
				taken = true
				break
			end
		end
		if not taken then
			return id
		end
		n += 1
	end
end

-- Active character of an account (reconciled accounts always have one)
function Profile.active(account: Account): Data
	for _, c in account.characters do
		if c.id == account.active then
			return c
		end
	end
	return account.characters[1]
end

function Profile.character(account: Account, id: string): Data?
	for _, c in account.characters do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- Trimmed name if it is allowed (3-16 letters, digits, single spaces), else nil.
-- Roblox text filtering happens on the server on top of this (Systems/Characters).
function Profile.validName(name: any): string?
	if typeof(name) ~= "string" or #name > 64 then
		return nil
	end
	local trimmed = string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")
	if #trimmed < Profile.NAME_MIN or #trimmed > Profile.NAME_MAX then
		return nil
	end
	if string.find(trimmed, "[^%w ]") or string.find(trimmed, "  ") then
		return nil
	end
	return trimmed
end

-- New, set-up character added to the account (not made active). nil when the account is full.
function Profile.newCharacter(account: Account, name: string, class: string, now: number): Data?
	if #account.characters >= Profile.MAX_CHARACTERS then
		return nil
	end
	local char = Profile.reconcile({
		name = name,
		class = class,
		setupDone = true,
		created = now,
	})
	char.id = Profile.nextId(account.characters)
	table.insert(account.characters, char)
	return char
end

-- Makes a save storable without swapping tables (other systems hold references):
-- NaN/infinite → 0, values without a JSON form (instances, functions …) and keys that are
-- neither string nor number are dropped. Returns the number of repairs.
function Profile.sanitize(data: any): number
	local fixed = 0
	local function walk(t: { [any]: any }, depth: number)
		for k, v in t do
			local kt, vt = typeof(k), typeof(v)
			local badKey = (kt ~= "string" and kt ~= "number") or depth > 20
			local plain = vt == "string" or vt == "boolean" or vt == "number" or vt == "table"
			if badKey or not plain then
				t[k] = nil
				fixed += 1
			elseif vt == "number" and (v ~= v or v == math.huge or v == -math.huge) then
				t[k] = 0
				fixed += 1
			elseif vt == "table" then
				walk(v, depth + 1)
			end
		end
	end
	if typeof(data) == "table" then
		walk(data, 0)
	end
	return fixed
end

-- Fresh character (own tables, never the DEFAULTS themselves)
function Profile.fresh(): Data
	return Profile.reconcile({})
end

-- Fresh account for new players: one character that still needs its setup
function Profile.freshAccount(): Account
	return Profile.reconcileAccount({})
end

-- Brings a loaded value up to the current version.
-- nil = no save yet. Errors if the save is newer than this server.
function Profile.migrate(raw: any): Record
	if raw == nil then
		return { v = Profile.VERSION, data = Profile.freshAccount() }
	end
	assert(typeof(raw) == "table", "save is not a table")
	local record = raw
	if record.v == nil then
		record = MIGRATIONS[1](record) -- format v1 had no v yet
	end
	assert(typeof(record.v) == "number", "save without version")
	assert(record.v <= Profile.VERSION, "NEWER")
	while record.v < Profile.VERSION do
		local step = MIGRATIONS[record.v]
		assert(step, `no migration from v{record.v}`)
		local from = record.v
		record = step(record)
		assert(record.v == from + 1, `migration v{from} sets v incorrectly`)
	end
	record.data = Profile.reconcileAccount(record.data)
	return record
end

return Profile
