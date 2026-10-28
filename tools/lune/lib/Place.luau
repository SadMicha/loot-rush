--!strict
-- Pfade der Werkzeugkette und Rojo-Build für die Lune-Skripte.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Place = {}

Place.OUT = ".tools/out"
Place.PLACE = ".tools/out/LootRush.rbxl"
Place.DUMP = ".tools/roblox/API-Dump.json"

-- Spiel frisch mit Rojo bauen (immer, damit nie ein veralteter Stand geprüft wird)
function Place.build(): string
	fs.writeDir(Place.OUT)
	local result = process.exec("rojo", { "build", "default.project.json", "-o", Place.PLACE })
	if not result.ok then
		error("rojo build fehlgeschlagen:\n" .. result.stderr .. result.stdout)
	end
	return Place.PLACE
end

-- Roblox-API-Dump (Events/Methoden aller Klassen); ohne ihn kennt die Sandbox weniger Events
function Place.apiDump(): string?
	if fs.isFile(Place.DUMP) then
		return Place.DUMP
	end
	print(
		"Hinweis: "
			.. Place.DUMP
			.. " fehlt – tools/setup.sh ausführen. Sandbox läuft mit weniger API-Wissen."
	)
	return nil
end

-- Instanzpfad ("ServerScriptService.Server.Systems.Combat") → Quelldatei, aus `rojo sourcemap`
function Place.sourceFiles(): { [string]: string }
	local result = process.exec("rojo", { "sourcemap", "default.project.json" })
	if not result.ok then
		return {}
	end
	local map = {}
	local function visit(node: any, path: string?)
		for _, f in node.filePaths or {} do
			if f:match("%.luau?$") then
				map[path or ""] = f
			end
		end
		for _, child in node.children or {} do
			visit(child, if path then path .. "." .. child.name else child.name)
		end
	end
	visit(serde.decode("json", result.stdout), nil)
	return map
end

return Place
