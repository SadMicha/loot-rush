--!strict
-- Spielstand-Schema: Standardwerte, Migration alter Stände und die Session-Lock-Regeln.
-- Reine Logik ohne DataStore (testbar). Laden/Speichern selbst macht Systems/Data.
--
-- Neues Feld? Im Typ Data und in DEFAULTS eintragen – fehlende Felder werden beim Laden ergänzt.
-- Felder mit eigener Prüfung (z. B. Progression) stattdessen in Profile.reconcile anhängen.
-- Feld umbenennen/umbauen? VERSION erhöhen und einen Schritt in MIGRATIONS anlegen.
-- Nur JSON-taugliche Werte: Zahlen, Strings, Bools, Listen und Tabellen mit String-Schlüsseln.

local Items = require(script.Parent.Items)

local Profile = {}

export type Data = {
	gold: number,
	level: number,
	xp: number,
	inventory: { Items.Item },
	equipped: { [string]: Items.Item }, -- Slot → Item
}

export type Lock = { job: string, t: number }

-- So liegt ein Spielstand im DataStore
export type Record = {
	v: number,
	data: Data,
	lock: Lock?,
}

Profile.VERSION = 2

local DEFAULTS: Data = {
	gold = 0,
	level = 1,
	xp = 0,
	inventory = {},
	equipped = {},
}

-- MIGRATIONS[n] hebt einen Record von Version n auf n + 1
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1: der Spielstand lag direkt im Key ({ version = 1, gold, inventory, equipped })
	[1] = function(raw)
		local data = table.clone(raw)
		data.version = nil
		return { v = 2, data = data }
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

function Profile.reconcile(raw: any): Data
	local data = if typeof(raw) == "table" then raw else {}
	fill(data, DEFAULTS)
	data.level = math.max(1, math.floor(data.level))
	data.xp = math.max(0, data.xp)
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
