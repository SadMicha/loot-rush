--!strict
-- Save schema: defaults and migration of old saves (the session lock is ProfileStore's job).
-- Pure logic without DataStore (testable). Loading/saving itself is done by Systems/Data.
--
-- New field? Add it to the Data type and to DEFAULTS - missing fields are filled in on load.
-- Fields with their own validation (e.g. Progression) are appended in Profile.reconcile instead.
-- Renaming/restructuring a field? Bump VERSION and add a step to MIGRATIONS.
-- JSON-safe values only: numbers, strings, bools, lists and tables with string keys.

local Items = require(script.Parent.Items)
local Monetization = require(script.Parent.Monetization)
local Pets = require(script.Parent.Pets)
local Progression = require(script.Parent.Progression)
local Rebirth = require(script.Parent.Rebirth)

local Profile = {}

export type Data = {
	gold: number,
	level: number,
	xp: number,
	inventory: { Items.Item },
	equipped: { [string]: Items.Item }, -- slot → item
	progress: Progression.Data, -- skill levels, Skill Blooms, Star Net
	materials: Progression.Materials, -- Forge materials
	atlas: { [string]: number }, -- region → highest Rift depth cleared (Shared/Atlas)
	soulstars: number, -- Soulstars (shop, later also for Robux)
	receipts: { string }, -- recently booked Robux purchases (PurchaseId), against double crediting
	rebirths: number, -- number of Rebirths (Shared/Rebirth)
	pets: Pets.Data, -- pets (Shared/Pets)
	passes: { [string]: boolean }, -- last known game pass ownership (outage buffer, Systems/Monetization)
}

-- The versioned save (ProfileStore's profile.Data; the session lock belongs to ProfileStore)
export type Record = {
	v: number,
	data: Data,
}

Profile.VERSION = 3
Profile.MAX_RECEIPTS = 50
Profile.MAX_UNKNOWN_PASSES = 20 -- game passes only a newer server knows (stay saved)
Profile.MAX_KEY_LEN = 64

local DEFAULTS: Data = {
	gold = 0,
	level = 1,
	xp = 0,
	inventory = {},
	equipped = {},
	progress = Progression.fresh(), -- contents checked by Progression.reconcile
	materials = Progression.freshMaterials(),
	atlas = {},
	soulstars = 0,
	receipts = {},
	rebirths = 0,
	pets = Pets.fresh(),
	passes = {},
}

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

function Profile.reconcile(raw: any): Data
	local data = if typeof(raw) == "table" then raw else {}
	fill(data, DEFAULTS)
	data.level = math.max(1, math.floor(data.level))
	data.xp = math.max(0, data.xp)
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
	data.rebirths = math.min(whole(data.rebirths), Rebirth.MAX)
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
	return data :: Data
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

-- Fresh save for new players (own tables, never the DEFAULTS themselves)
function Profile.fresh(): Data
	return Profile.reconcile({})
end

-- Brings a loaded value up to the current version.
-- nil = no save yet. Errors if the save is newer than this server.
function Profile.migrate(raw: any): Record
	if raw == nil then
		return { v = Profile.VERSION, data = Profile.fresh() }
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
	record.data = Profile.reconcile(record.data)
	return record
end

return Profile
