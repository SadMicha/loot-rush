--!strict
-- Toolchain paths and Rojo build for the Lune scripts.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Place = {}

Place.OUT = ".tools/out"
Place.PLACE = ".tools/out/LootRush.rbxl"
Place.DUMP = ".tools/roblox/API-Dump.json"

-- Build the game fresh with Rojo (always, so an outdated state is never checked)
function Place.build(): string
	fs.writeDir(Place.OUT)
	local result = process.exec("rojo", { "build", "default.project.json", "-o", Place.PLACE })
	if not result.ok then
		error("rojo build failed:\n" .. result.stderr .. result.stdout)
	end
	return Place.PLACE
end

-- Roblox API dump (events/methods of all classes); without it the sandbox knows fewer events
function Place.apiDump(): string?
	if fs.isFile(Place.DUMP) then
		return Place.DUMP
	end
	print(
		"Hint: "
			.. Place.DUMP
			.. " missing - run tools/setup.sh. The sandbox runs with less API knowledge."
	)
	return nil
end

-- Instance path ("ServerScriptService.Server.Systems.Combat") → source file, from `rojo sourcemap`
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
