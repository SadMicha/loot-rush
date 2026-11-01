--!nocheck
-- UI check without Roblox Studio:
--   1. builds the game (rojo), starts server + client headless in the sandbox
--   2. checks the UI at several screen sizes (overflow, clipped text, image IDs, touch targets,
--      Roblox topbar, text behind icons/on text/past the panel edge, empty rows/capsules, close buttons)
--   3. clicks every button with a handler once (fresh sandbox per button) and presses typical keys
--   4. writes HTML snapshots + report to .tools/out/ui (PNG screenshots: tools/screenshot.mjs)
--
--   lune run tools/lune/ui [--images DIR]... [--out DIR] [--no-clicks] [--seconds N]
-- Exit code 1 if runtime errors or findings of level "error" were found.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Checks = require("./lib/Checks")
local Place = require("./lib/Place")
local Render = require("./lib/Render")
local Sandbox = require("./lib/Sandbox")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

-------------------------------------------------------------------------------
-- Arguments

local args = { images = {}, out = ".tools/out/ui", clicks = true, seconds = 3 }
do
	local i = 1
	local a = process.args
	while i <= #a do
		local v = a[i]
		if v == "--images" then
			table.insert(args.images, a[i + 1])
			i += 1
		elseif v == "--out" then
			args.out = a[i + 1]
			i += 1
		elseif v == "--seconds" then
			args.seconds = tonumber(a[i + 1]) or 3
			i += 1
		elseif v == "--no-clicks" then
			args.clicks = false
		elseif v == "--place" then
			args.place = a[i + 1]
			i += 1
		else
			error("unknown argument: " .. tostring(v))
		end
		i += 1
	end
	local env = process.env.LOOTRUSH_IMAGES
	if env and env ~= "" then
		for dir in env:gmatch("[^;]+") do
			table.insert(args.images, dir)
		end
	end
end

local PROFILES = {
	{ name = "desktop", size = Vector2.new(1920, 1080), touch = false, render = true },
	{ name = "laptop", size = Vector2.new(1366, 768), touch = false, render = true },
	{ name = "tablet", size = Vector2.new(1024, 768), touch = true, render = true },
	{ name = "phone", size = Vector2.new(844, 390), touch = true, render = true },
}

local placePath = args.place or Place.build()
local dumpPath = Place.apiDump()
local sourceFiles = Place.sourceFiles()

fs.writeDir(args.out)
for _, f in fs.readDir(args.out) do
	if f:match("%.html$") or f:match("%.png$") then
		fs.removeFile(args.out .. "/" .. f)
	end
end

local placeRoot = roblox.deserializePlace(fs.readFile(placePath))
local images =
	Render.imageSource(Render.assetNames(placeRoot), Render.indexImages(args.images), args.out)

local function newSandbox()
	return Sandbox.new({
		placePath = placePath,
		dumpPath = dumpPath,
		sourceFiles = sourceFiles,
		quiet = true,
	})
end

-------------------------------------------------------------------------------
-- Report

local runtime = {} -- { context, level, kind, message, trace, side }
local layout = {} -- [profile] = { findings }
local pages = {} -- { file, title }
local stubs = {}

local function issueKey(i)
	return i.level .. "|" .. i.kind .. "|" .. i.message
end

local net = {} -- "C→S Equip" → count

local function collect(sb, context: string, baseline: { [string]: boolean }?)
	for _, n in sb.netLog do
		local k = n.dir .. " " .. n.name
		net[k] = (net[k] or 0) + 1
	end
	for _, i in sb.issues do
		if i.level == "info" and i.kind == "stub" then
			stubs[i.message] = true
		elseif not (baseline and baseline[issueKey(i)]) then
			table.insert(runtime, {
				context = context,
				level = i.level,
				kind = i.kind,
				message = i.message,
				trace = i.trace,
				side = i.side,
				count = i.count,
			})
		end
	end
end

local function addFindings(profile: string, state: string, findings)
	layout[profile] = layout[profile] or {}
	local seen = {}
	for _, f in layout[profile] do
		seen[f.kind .. f.path .. f.message] = true
	end
	for _, f in findings do
		local k = f.kind .. f.path .. f.message
		if not seen[k] then
			seen[k] = true
			f.state = state
			table.insert(layout[profile], f)
		end
	end
end

local function slug(s: string): string
	return (s:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""):sub(1, 60))
end

local closeButtons = {} -- [profile] = { { path, look } } across all states

local function snapshot(sb, profile, state: string, title: string)
	sb:setViewport(profile.size, profile.touch)
	sb:run(0.5)
	local findings = Checks.run(sb, profile)
	closeButtons[profile.name] = closeButtons[profile.name] or {}
	for _, c in Checks.closeButtons(sb) do
		table.insert(closeButtons[profile.name], c)
	end
	addFindings(profile.name, state, findings)
	if profile.render then
		local file = string.format("%s__%s.html", slug(state), profile.name)
		fs.writeFile(
			args.out .. "/" .. file,
			Render.page(sb, images, title .. " – " .. profile.name, findings)
		)
		table.insert(pages, { file = file, title = title, profile = profile.name })
	end
end

-------------------------------------------------------------------------------
-- 1. Start

print("▶ starting server + client headless …")
local base = newSandbox()
base:boot({ seconds = args.seconds })
collect(base, "Start")
local baseline = {}
for _, i in base.issues do
	baseline[issueKey(i)] = true
end
for _, profile in PROFILES do
	snapshot(base, profile, "start", "Start")
end
base:setViewport(PROFILES[1].size, false)

local function guiCount(sb): number
	local n = 0
	local pg = sb:nativeOf(sb:playerGui())
	for _, d in pg:GetDescendants() do
		if d:IsA("GuiObject") and require("./lib/Layout").isShown(d) then
			n += 1
		end
	end
	return n
end

-- Buttons with a handler; key = child indices ("3.1.7"), because names are often duplicated
local function clickable(sb): { { key: string, path: string } }
	local out = {}
	local pg = sb:nativeOf(sb:playerGui())
	local Layout = require("./lib/Layout")
	local function visit(node, key: string)
		for i, c in node:GetChildren() do
			local k = if key == "" then tostring(i) else key .. "." .. i
			if c:IsA("GuiButton") and Layout.isShown(c) and sb:hasHandlers(sb:wrap(c)) then
				table.insert(out, { key = k, path = Checks.pathOf(c, pg) })
			end
			visit(c, k)
		end
	end
	visit(pg, "")
	return out
end

local function find(sb, key: string)
	local node = sb:nativeOf(sb:playerGui())
	for part in key:gmatch("%d+") do
		node = node and node:GetChildren()[tonumber(part)]
	end
	return node and sb:wrap(node)
end

-------------------------------------------------------------------------------
-- 2. Press every button once (fresh sandbox per button so the states stay clean)

local clicked = 0
if args.clicks then
	local buttons = clickable(base)
	print(string.format("▶ pressing %d buttons …", #buttons))
	for _, entry in buttons do
		local path = entry.path
		local sb = newSandbox()
		sb:boot({ seconds = args.seconds })
		sb:setViewport(PROFILES[1].size, false)
		local button = find(sb, entry.key)
		if button then
			local before = guiCount(sb)
			local beforeButtons = {}
			for _, b in clickable(sb) do
				beforeButtons[b.key] = true
			end
			sb:click(button)
			sb:run(1.5)
			clicked += 1
			local after = guiCount(sb)
			if process.env.UI_DEBUG then
				print("  click", path, before, "→", after)
			end
			if math.abs(after - before) >= 5 then
				for _, profile in PROFILES do
					snapshot(sb, profile, "click " .. path, "After clicking " .. path)
				end
				sb:setViewport(PROFILES[1].size, false)
				-- Second level: only test newly visible buttons for errors
				for _, inner in clickable(sb) do
					if not beforeButtons[inner.key] then
						local b = find(sb, inner.key)
						if b and b.Parent then
							sb:click(b)
							sb:run(0.5)
						end
					end
				end
			end
			collect(sb, "Click on " .. path, baseline)
		end
	end

	-- Scenario: open a full inventory and click items (the server adds real items)
	do
		local sb = newSandbox()
		sb:boot({ seconds = args.seconds })
		sb:runAs("server", function(req)
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local Items = req("ReplicatedStorage.Shared.Items")
			for i = 1, 24 do
				Inventory.add(sb.player, Items.roll(1 + i % 12, Sandbox.Random.new(i)))
			end
			Inventory.addGold(sb.player, 123456)
			-- One worn piece in every slot so the paper doll shows all nine slots
			local Data = req("ServerScriptService.Server.Systems.Data")
			local profile = Data.get(sb.player)
			if profile then
				local rng = Sandbox.Random.new(777)
				for _, slot in Items.Slots do
					for _ = 1, 500 do
						local item = Items.roll(8, rng)
						if item.slot == slot then
							profile.equipped[slot] = item
							break
						end
					end
				end
				Inventory.sync(sb.player)
			end
		end)
		sb:run(0.5)
		local before = {}
		for _, b in clickable(sb) do
			before[b.key] = true
		end
		local open = nil
		for _, b in clickable(sb) do
			if b.path:match("%.inventory$") then
				open = find(sb, b.key)
			end
		end
		if open then
			sb:click(open)
			sb:run(1)
			for _, profile in PROFILES do
				snapshot(sb, profile, "inventory full", "Inventory with 24 items")
			end
			sb:setViewport(PROFILES[1].size, false)
			-- first item in the grid (button in a ScrollingFrame)
			local first = nil
			for _, b in clickable(sb) do
				local node = sb:nativeOf(find(sb, b.key))
				if
					not first
					and b.path:find("LootRushInventory")
					and node:FindFirstAncestorWhichIsA("ScrollingFrame")
				then
					first = b
				end
			end
			if first then
				local beforeSelect = {}
				for _, b in clickable(sb) do
					beforeSelect[b.key] = true
				end
				sb:click(find(sb, first.key))
				sb:run(0.5)
				snapshot(sb, PROFILES[1], "inventory selection", "Inventory: item selected")
				sb:setViewport(PROFILES[1].size, false)
				-- new buttons of the detail view (Equip, Sell …) tested for errors
				for _, b in clickable(sb) do
					if not beforeSelect[b.key] then
						local node = find(sb, b.key)
						if node and node.Parent then
							sb:click(node)
							sb:run(0.5)
						end
					end
				end
			end
		end
		collect(sb, "Scenario inventory", baseline)
	end

	-- Scenario: windows with a full inventory and materials (the Forge needs items) and the debug menu
	for _, name in { "forge", "skills", "star_net", "atlas", "Shop_gold", "pets", "Dbg" } do
		local sb = newSandbox()
		sb:boot({ seconds = args.seconds })
		sb:runAs("server", function(req)
			local Inventory = req("ServerScriptService.Server.Systems.Inventory")
			local Progress = req("ServerScriptService.Server.Systems.Progress")
			local Items = req("ReplicatedStorage.Shared.Items")
			for i = 1, 12 do
				Inventory.add(sb.player, Items.roll(1 + i % 12, Sandbox.Random.new(100 + i)))
			end
			-- Candy and dust are missing on purpose: shows the long "Not enough …" texts of the Forge
			Progress.addMaterials(sb.player, { shards = 120 })
			Progress.sync(sb.player)
			Inventory.addGold(sb.player, 300) -- Shop: some things affordable, some too expensive
		end)
		sb:run(0.5)
		local open = nil
		for _, b in clickable(sb) do
			if b.path:match("%." .. name .. "$") then
				open = find(sb, b.key)
			end
		end
		if open then
			sb:click(open)
			sb:run(1)
			for _, profile in PROFILES do
				snapshot(sb, profile, "full " .. name, "With items: " .. name)
			end
			sb:setViewport(PROFILES[1].size, false)
		end
		collect(sb, "Scenario " .. name, baseline)
	end

	-- Keys
	local sb = newSandbox()
	sb:boot({ seconds = args.seconds })
	local keys = {
		"I",
		"Tab",
		"F3",
		"M",
		"E",
		"Q",
		"R",
		"F",
		"One",
		"Two",
		"Three",
		"Four",
		"Space",
		"LeftShift",
		"Escape",
		"B",
		"C",
	}
	for _, k in keys do
		sb:pressKey(Enum.KeyCode[k])
		sb:run(0.3)
	end
	collect(sb, "Keys " .. table.concat(keys, " "), baseline)
end

-------------------------------------------------------------------------------
-- 3. Output

-- Compare the close buttons of all states (same look in every window)
for _, profile in PROFILES do
	addFindings(
		profile.name,
		"close buttons",
		Checks.compareClose(closeButtons[profile.name] or {})
	)
end

local counts = { error = 0, warn = 0, info = 0 }
for _, r in runtime do
	counts[r.level] += 1
end
local layoutCounts = { error = 0, warn = 0, info = 0 }
for _, list in layout do
	for _, f in list do
		layoutCounts[f.level] += 1
	end
end

local md = { "# UI-Check", "" }
table.insert(
	md,
	string.format(
		"Buttons pressed: %d · runtime: %d errors, %d warnings · layout: %d errors, %d warnings",
		clicked,
		counts.error,
		counts.warn,
		layoutCounts.error,
		layoutCounts.warn
	)
)
table.insert(md, "")
table.insert(md, "## Runtime")
if #runtime == 0 then
	table.insert(md, "No errors.")
end
for _, r in runtime do
	table.insert(
		md,
		string.format(
			"- **%s** [%s/%s] (%s, %s×) %s",
			r.level,
			r.side or "?",
			r.kind,
			r.context,
			r.count,
			r.message
		)
	)
	if r.trace and r.trace ~= "" then
		table.insert(md, "  ```\n  " .. r.trace:gsub("\n", "\n  ") .. "\n  ```")
	end
end
for _, profile in PROFILES do
	local list = layout[profile.name] or {}
	table.insert(md, "")
	table.insert(
		md,
		string.format(
			"## Layout %s (%d×%d%s)",
			profile.name,
			profile.size.X,
			profile.size.Y,
			if profile.touch then ", Touch" else ""
		)
	)
	if #list == 0 then
		table.insert(md, "No findings.")
	end
	table.sort(list, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.path < b.path
	end)
	for _, f in list do
		table.insert(
			md,
			string.format("- %s [%s] `%s` %s (%s)", f.level, f.kind, f.path, f.message, f.state)
		)
	end
end
local netList = {}
for k, n in net do
	table.insert(netList, string.format("%s ×%d", k, n))
end
table.sort(netList)
table.insert(md, "")
table.insert(md, "## Network (remotes, all runs)")
table.insert(md, if #netList > 0 then table.concat(netList, " · ") else "none")
local stubList = {}
for s in stubs do
	table.insert(stubList, s)
end
table.sort(stubList)
if #stubList > 0 then
	table.insert(md, "")
	table.insert(md, "## Sandbox stubs (not really simulated)")
	for _, s in stubList do
		table.insert(md, "- " .. s)
	end
end
fs.writeFile(args.out .. "/report.md", table.concat(md, "\n") .. "\n")
fs.writeFile(
	args.out .. "/report.json",
	serde.encode(
		"json",
		{ runtime = runtime, layout = layout, pages = pages, stubs = stubList },
		true
	)
)

local index = {
	"<!doctype html><meta charset=utf-8><title>UI-Check</title><style>body{font:14px system-ui;background:#111;color:#ddd;padding:20px}a{color:#7cf}</style><h1>UI-Check</h1><ul>",
}
for _, p in pages do
	table.insert(
		index,
		string.format('<li><a href="%s">%s – %s</a></li>', p.file, p.title, p.profile)
	)
end
table.insert(index, '</ul><p><a href="report.md">report.md</a></p>')
fs.writeFile(args.out .. "/index.html", table.concat(index))

print(string.format("✔ %d pages, report: %s/report.md", #pages, args.out))
print(
	string.format(
		"  runtime: %d errors, %d warnings · layout: %d errors, %d warnings, %d notes",
		counts.error,
		counts.warn,
		layoutCounts.error,
		layoutCounts.warn,
		layoutCounts.info
	)
)
for _, r in runtime do
	if r.level == "error" then
		print(string.format("  ✖ [%s] %s: %s", r.context, r.kind, r.message))
	end
end

if counts.error > 0 or layoutCounts.error > 0 then
	process.exit(1)
end
