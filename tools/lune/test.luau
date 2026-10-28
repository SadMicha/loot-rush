--!nocheck
-- Unit-Tests ohne Roblox Studio: führt tests/**/*.spec.luau in der Sandbox aus.
--
--   lune run tools/lune/test [filter]
--
-- In einer Spec-Datei stehen zur Verfügung:
--   describe(name, fn) · it(name, fn) · expect(wert).toBe(…) (siehe lib/Expect.luau)
--   require("ReplicatedStorage.Shared.Items") – Pfad im Spiel (wie im Rojo-Build)
--   sim – die Sandbox: sim:boot(), sim:run(sek), sim.player, sim:runAs("server", fn), sim.issues …
--   alle Roblox-Globals der Sandbox (game, Instance, Vector3, task, Random …)
-- Jede Spec-Datei bekommt eine frische Sandbox; jeder Test läuft in einem eigenen Thread.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Expect = require("./lib/Expect")
local Place = require("./lib/Place")
local Sandbox = require("./lib/Sandbox")

local filter = process.args[1]
local placePath = Place.build()
local dumpPath = Place.apiDump()
local sourceFiles = Place.sourceFiles()

local function findSpecs(dir: string, out: { string })
	if not fs.isDir(dir) then
		return out
	end
	for _, entry in fs.readDir(dir) do
		local p = dir .. "/" .. entry
		if fs.isDir(p) then
			findSpecs(p, out)
		elseif entry:match("%.spec%.luau$") and (not filter or p:find(filter, 1, true)) then
			table.insert(out, p)
		end
	end
	table.sort(out)
	return out
end

local passed, failed = 0, 0
local failures = {}

for _, file in findSpecs("tests", {}) do
	local sb = Sandbox.new({
		placePath = placePath,
		dumpPath = dumpPath,
		sourceFiles = sourceFiles,
		quiet = true,
	})
	local tests = {}
	local prefix = {}

	local env = sb:makeEnv(nil, "server")
	env.sim = sb
	env.expect = Expect
	env.describe = function(name, fn)
		table.insert(prefix, name)
		fn()
		table.remove(prefix)
	end
	env.it = function(name, fn)
		local full = table.concat(prefix, " › ")
		table.insert(
			tests,
			{ name = (if full ~= "" then full .. " › " else "") .. name, fn = fn }
		)
	end
	local sandboxRequire = env.require
	env.require = function(m)
		if type(m) == "string" then
			local inst = sb:find(m)
			if not inst then
				error("Modul nicht gefunden: " .. m, 2)
			end
			return sandboxRequire(inst)
		end
		return sandboxRequire(m)
	end

	print(file)
	local ok, chunk = pcall(luau.load, fs.readFile(file), { debugName = file, environment = env })
	if not ok then
		failed += 1
		table.insert(failures, { name = file, err = tostring(chunk) })
		print("  ✖ Syntaxfehler: " .. tostring(chunk))
		continue
	end
	local collected, err = pcall(chunk)
	if not collected then
		failed += 1
		table.insert(failures, { name = file, err = tostring(err) })
		print("  ✖ Fehler beim Laden: " .. tostring(err))
		continue
	end

	for _, t in tests do
		local done, result = false, nil
		local issuesBefore = #sb.issues
		sb.sched:spawnAs("server", function()
			local good, e = xpcall(t.fn, function(e)
				return { msg = tostring(e), trace = debug.traceback() }
			end)
			done, result = true, if good then nil else e
		end)
		local guard = 0
		while not done and guard < 60 * 30 do
			sb.sched:step(1 / 30)
			guard += 1
		end
		if not done then
			result = { msg = "Zeitüberschreitung (60 s virtuelle Zeit)", trace = "" }
		end
		-- Fehler in Threads, die der Test gestartet hat, zählen auch
		if not result then
			for i = issuesBefore + 1, #sb.issues do
				local issue = sb.issues[i]
				if issue.level == "error" then
					result = {
						msg = "Fehler im Spielcode: " .. issue.message,
						trace = issue.trace or "",
					}
					break
				end
			end
		end
		if result then
			failed += 1
			local where = ""
			for line in tostring(result.trace):gmatch("[^\n]+") do
				if line:find("%.spec") then
					where = line
					break
				end
			end
			table.insert(failures, { name = t.name, err = result.msg, where = where })
			print(string.format("  ✖ %s\n      %s %s", t.name, result.msg, where))
		else
			passed += 1
			print("  ✔ " .. t.name)
		end
	end
end

print(string.format("\n%d bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
	process.exit(1)
end
