--!nocheck
-- Unit tests without Roblox Studio: runs tests/**/*.spec.luau in the sandbox.
--
--   lune run tools/lune/test [filter] [--shard=i/n]
--   --shard=i/n runs only part i of n (CI); files are spread by tests/timings.json (seconds).
--
-- Available in a spec file:
--   describe(name, fn) · it(name, fn) · expect(value).toBe(…) (see lib/Expect.luau)
--   require("ReplicatedStorage.Shared.Items") - path in the game (as in the Rojo build)
--   sim - the sandbox: sim:boot(), sim:run(sec), sim.player, sim:runAs("server", fn), sim.issues …
--   layoutCheck(size, touch) - layout findings of the current UI like the UI check (lib/Checks.luau)
--   closeButtons(), compareClose(list) - collect and compare close buttons
--   all Roblox globals of the sandbox (game, Instance, Vector3, task, Random …)
-- Every spec file gets a fresh sandbox; every test runs in its own thread.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Checks = require("./lib/Checks")
local Expect = require("./lib/Expect")
local Matrix = require("./lib/Matrix")
local Place = require("./lib/Place")
local Sandbox = require("./lib/Sandbox")

local filter: string? = nil
local shardIndex, shardCount = 1, 1
for _, arg in process.args do
	local i, n = arg:match("^%-%-shard=(%d+)/(%d+)$")
	if i then
		shardIndex, shardCount = tonumber(i) :: number, tonumber(n) :: number
	else
		filter = arg
	end
end
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

-- Longest specs first, each onto the shard with the least time so far (same result on every shard)
local function shard(files: { string }): { string }
	if shardCount <= 1 then
		return files
	end
	local okRead, weights = pcall(function()
		return serde.decode("json", fs.readFile("tests/timings.json"))
	end)
	if not okRead then
		weights = {}
	end
	local function weight(f: string): number
		return weights[f] or 20
	end
	local sorted = table.clone(files)
	table.sort(sorted, function(a, b)
		if weight(a) ~= weight(b) then
			return weight(a) > weight(b)
		end
		return a < b
	end)
	local load = table.create(shardCount, 0)
	local mine = {}
	for _, f in sorted do
		local best = 1
		for k = 2, shardCount do
			if load[k] < load[best] then
				best = k
			end
		end
		load[best] += weight(f)
		if best == shardIndex then
			table.insert(mine, f)
		end
	end
	table.sort(mine)
	return mine
end

local passed, failed = 0, 0
local failures = {}

for _, file in shard(findSpecs("tests", {})) do
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
	env.layoutCheck = function(size, touch)
		sb:setViewport(size, touch)
		return Checks.run(sb, { name = "test", touch = touch })
	end
	env.closeButtons = function()
		return Checks.closeButtons(sb)
	end
	env.compareClose = Checks.compareClose
	-- Layout matrix (lib/Matrix.luau): a fresh sandbox per screen, checked on device profiles ×
	-- HUD sizes; returns the strict findings as lines
	env.matrix = function(screenNames: { string }, deviceNames: { string }?, scales: { number }?)
		return Matrix.run({
			placePath = placePath,
			dumpPath = dumpPath,
			sourceFiles = sourceFiles,
		}, screenNames, deviceNames, scales)
	end
	env.expect = Expect
	-- the Rojo project as a table (the sandbox does not keep texture-map properties)
	-- (read once here: a yielding fs call inside a test thread would hang the sandbox scheduler)
	local project = serde.decode("json", fs.readFile("default.project.json"))
	env.projectJson = function()
		return project
	end
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
				error("module not found: " .. m, 2)
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
		print("  ✖ syntax error: " .. tostring(chunk))
		continue
	end
	local collected, err = pcall(chunk)
	if not collected then
		failed += 1
		table.insert(failures, { name = file, err = tostring(err) })
		print("  ✖ error while loading: " .. tostring(err))
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
			result = { msg = "timeout (60 s virtual time)", trace = "" }
		end
		-- errors in threads the test started count too
		if not result then
			for i = issuesBefore + 1, #sb.issues do
				local issue = sb.issues[i]
				if issue.level == "error" then
					result = {
						msg = "error in game code: " .. issue.message,
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

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
