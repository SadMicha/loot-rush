--!strict
-- Player settings (settings window, docs/ROADMAP-1.0.md S1/U1, C4, A3): one table per ACCOUNT,
-- so they apply to every hero. Pure rules (defaults, validation, sanitizing) shared by the
-- server (Systems/Settings saves them) and the client (Client/Prefs applies them live).
--
-- Every setting is one of three kinds:
--   number  min..max, snapped to `step` (volumes 0..1, shake 0/0.5/1, HUD scale, camera speed)
--   bool    on/off
--   choice  one of `options` (effects quality)
-- New setting? Add it to Settings.Defs (append to Settings.Order for the window). Saved keys are
-- stable English ids; unknown keys in a save are dropped on load.

local Settings = {}

export type Kind = "number" | "bool" | "choice"

export type Def = {
	kind: Kind,
	default: any,
	min: number?,
	max: number?,
	step: number?,
	options: { string }?,
}

export type Data = { [string]: any }

Settings.Defs = table.freeze({
	-- Audio (volume channels of Client/Audio)
	master = { kind = "number", default = 1, min = 0, max = 1, step = 0.05 },
	music = { kind = "number", default = 0.6, min = 0, max = 1, step = 0.05 },
	sfx = { kind = "number", default = 1, min = 0, max = 1, step = 0.05 },
	ambience = { kind = "number", default = 1, min = 0, max = 1, step = 0.05 },
	ui = { kind = "number", default = 1, min = 0, max = 1, step = 0.05 },
	muted = { kind = "bool", default = false },
	-- Gameplay and display
	shake = { kind = "number", default = 1, min = 0, max = 1, step = 0.5 }, -- camera shake 0/50/100 %
	damageNumbers = { kind = "bool", default = true },
	quality = { kind = "choice", default = "auto", options = { "auto", "low", "medium", "high" } },
	minimap = { kind = "bool", default = true },
	hudScale = { kind = "number", default = 1, min = 0.8, max = 1.2, step = 0.1 },
	camera = { kind = "number", default = 1, min = 0.5, max = 2, step = 0.1 }, -- turn speed
	-- One-time hints already shown (HintsController, roadmap O4): not in the window; the Defaults
	-- button clears them, so the hints come back once
	hintSkills = { kind = "bool", default = false },
	hintDodge = { kind = "bool", default = false },
	hintRush = { kind = "bool", default = false },
	hintBreak = { kind = "bool", default = false },
	hintCounter = { kind = "bool", default = false },
	hintEquip = { kind = "bool", default = false },
} :: { [string]: Def })

-- Net.Setting key that puts every setting back to its default in one request (Defaults button)
Settings.RESET = "defaults"

Settings.VOLUMES = table.freeze({ "master", "music", "sfx", "ambience", "ui" })

-- Shown under "About" in the window (the build number comes from game.PlaceVersion)
Settings.GAME_VERSION = "1.0 Beta"
Settings.CREDITS = "Made by SadMicha"

-- Snaps a number to the step grid of `def` (from min) and clamps it
local function snap(def: Def, v: number): number
	local min, max = def.min or 0, def.max or 1
	local step = def.step
	if step and step > 0 then
		v = min + math.floor((v - min) / step + 0.5) * step
		v = math.floor(v * 1000 + 0.5) / 1000 -- no 0.30000000000000004
	end
	return math.clamp(v, min, max)
end

-- The valid value for `key`, or nil when the key is unknown or the value cannot be used
-- (wrong type, NaN, infinity, unknown option). Numbers are clamped and snapped.
function Settings.validate(key: any, value: any): any
	if typeof(key) ~= "string" then
		return nil
	end
	local def = Settings.Defs[key]
	if not def then
		return nil
	end
	if def.kind == "number" then
		if
			typeof(value) ~= "number"
			or value ~= value
			or value == math.huge
			or value == -math.huge
		then
			return nil
		end
		return snap(def, value)
	elseif def.kind == "bool" then
		if typeof(value) ~= "boolean" then
			return nil
		end
		return value
	else
		if typeof(value) ~= "string" then
			return nil
		end
		local options: { string } = def.options or {}
		for _, option in options do
			if option == value then
				return value
			end
		end
		return nil
	end
end

-- Default settings (own table)
function Settings.fresh(): Data
	local out: Data = {}
	for key, def in Settings.Defs do
		out[key] = def.default
	end
	return out
end

-- Sanitized copy of a saved settings table: every known key valid, unknown keys dropped
function Settings.reconcile(raw: any): Data
	local out = Settings.fresh()
	if typeof(raw) ~= "table" then
		return out
	end
	for key in Settings.Defs do
		local v = Settings.validate(key, raw[key])
		if v ~= nil then
			out[key] = v
		end
	end
	return out
end

-- Effects quality as a level for the effect code: "auto" picks low on touch devices
-- (phones and tablets) and on a low manual Roblox graphics level, else high.
function Settings.effectLevel(quality: string, touch: boolean, robloxLevel: number?): string
	if quality == "low" or quality == "medium" or quality == "high" then
		return quality
	end
	if robloxLevel and robloxLevel > 0 and robloxLevel <= 3 then
		return "low"
	end
	return if touch then "medium" else "high"
end

return Settings
