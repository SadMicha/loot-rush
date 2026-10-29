--!strict
-- Spielstand-Schema: Standardwerte, Migration alter Stände und die Session-Lock-Regeln.
-- Reine Logik ohne DataStore (testbar). Laden/Speichern selbst macht Systems/Data.
--
-- Neues Feld? Im Typ Data und in DEFAULTS eintragen – fehlende Felder werden beim Laden ergänzt.
-- Felder mit eigener Prüfung (z. B. Progression) stattdessen in Profile.reconcile anhängen.
-- Feld umbenennen/umbauen? VERSION erhöhen und einen Schritt in MIGRATIONS anlegen.
-- Nur JSON-taugliche Werte: Zahlen, Strings, Bools, Listen und Tabellen mit String-Schlüsseln.

local Config = require(script.Parent.Config)
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
	equipped: { [string]: Items.Item }, -- Slot → Item
	progress: Progression.Data, -- Skill-Stufen, Skill-Blüten, Sternennetz
	materials: Progression.Materials, -- Schmiede-Material
	atlas: { [string]: number }, -- Gebiet → höchste geschaffte Rift-Tiefe (Shared/Atlas)
	potions: number, -- Heiltränke (Shop, Taste 1)
	soulstars: number, -- Seelensterne (Shop, später auch für Robux)
	receipts: { string }, -- zuletzt verbuchte Robux-Käufe (PurchaseId), gegen doppeltes Gutschreiben
	rebirths: number, -- Anzahl Wiedergeburten (Shared/Rebirth)
	pets: Pets.Data, -- Haustiere (Shared/Pets)
	passes: { [string]: boolean }, -- zuletzt bekannter Gamepass-Besitz (Ausfall-Puffer, Systems/Monetization)
}

export type Lock = { job: string, t: number }

-- So liegt ein Spielstand im DataStore
export type Record = {
	v: number,
	data: Data,
	lock: Lock?,
}

Profile.VERSION = 3
Profile.MAX_RECEIPTS = 50

local DEFAULTS: Data = {
	gold = 0,
	level = 1,
	xp = 0,
	inventory = {},
	equipped = {},
	progress = Progression.fresh(), -- Inhalt prüft Progression.reconcile
	materials = Progression.freshMaterials(),
	atlas = {},
	potions = Config.POTION_START,
	soulstars = 0,
	receipts = {},
	rebirths = 0,
	pets = Pets.fresh(),
	passes = {},
}

-- MIGRATIONS[n] hebt einen Record von Version n auf n + 1
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1: der Spielstand lag direkt im Key ({ version = 1, gold, inventory, equipped })
	[1] = function(raw)
		local data = table.clone(raw)
		data.version = nil
		return { v = 2, data = data }
	end,
	-- v2 → v3: Beute-Stufe war Tiefe × 2 − 1, jetzt Tiefe (Item-Power = Tiefe × 10, Balancing-Tabelle).
	-- Alte Items auf die neue Stufe ihrer Tiefe ziehen, sonst wäre ihr Waffen-Grundschaden viel zu hoch.
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

-- Ergänzt fehlende Felder und ersetzt Felder mit falschem Typ durch den Standard.
-- Felder, die DEFAULTS nicht kennt, bleiben erhalten (z. B. von einem neueren Server).
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

-- Ganze Zahl ≥ 0 (NaN und Unendlich → 0)
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
	data.potions = math.clamp(whole(data.potions), 0, Config.POTION_MAX)
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
	local passes = {}
	for key, owned in data.passes do
		if typeof(key) == "string" and Monetization.PassByKey[key] and owned == true then
			passes[key] = true
		end
	end
	data.passes = passes
	return data :: Data
end

-- Frischer Stand für neue Spieler (eigene Tabellen, nie die DEFAULTS selbst)
function Profile.fresh(): Data
	return Profile.reconcile({})
end

-- Bringt einen gelesenen Wert auf die aktuelle Version.
-- nil = noch kein Spielstand. Fehler, wenn der Stand neuer ist als dieser Server.
function Profile.migrate(raw: any): Record
	if raw == nil then
		return { v = Profile.VERSION, data = Profile.fresh() }
	end
	assert(typeof(raw) == "table", "Spielstand ist keine Tabelle")
	local record = raw
	if record.v == nil then
		record = MIGRATIONS[1](record) -- Format v1 hatte noch kein v
	end
	assert(typeof(record.v) == "number", "Spielstand ohne Version")
	assert(record.v <= Profile.VERSION, "NEWER")
	while record.v < Profile.VERSION do
		local step = MIGRATIONS[record.v]
		assert(step, `keine Migration von v{record.v}`)
		local from = record.v
		record = step(record)
		assert(record.v == from + 1, `Migration v{from} setzt v falsch`)
	end
	record.data = Profile.reconcile(record.data)
	return record
end

-- Gehört der Key gerade einem anderen Server? Ein Lock älter als staleAfter gilt als verwaist
-- (Server abgestürzt), weil jeder Autosave ihn auffrischt.
function Profile.lockedByOther(record: any, job: string, now: number, staleAfter: number): boolean
	local lock = typeof(record) == "table" and record.lock
	if typeof(lock) ~= "table" or lock.job == job then
		return false
	end
	return typeof(lock.t) == "number" and now - lock.t < staleAfter
end

return Profile
