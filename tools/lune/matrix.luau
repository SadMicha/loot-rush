--!nocheck
-- Layout matrix without Roblox Studio: opens every window / HUD state and checks it on several
-- real device profiles (safe-area insets, Roblox topbar) at every HUD size of the Settings window.
--
--   lune run tools/lune/matrix [--screens inventory,hud] [--devices phone,tablet] [--scales 0.8,1.2]
--                              [--render all|phone|none] [--out DIR] [--images DIR]
--
-- Writes .tools/out/matrix/report.md (findings per screen × device × size) and HTML snapshots
-- (PNG: node tools/screenshot.mjs .tools/out/matrix). Exit code 1 when a strict finding exists.
-- The same matrix runs as a test in tests/Matrix.spec.luau (a smaller cut, see there).

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Matrix = require("./lib/Matrix")
local Place = require("./lib/Place")
local Render = require("./lib/Render")

local args = { out = ".tools/out/matrix", render = "phone", images = {} }
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k, v = a[i], a[i + 1]
		if k == "--screens" then
			args.screens = v
		elseif k == "--devices" then
			args.devices = v
		elseif k == "--scales" then
			args.scales = v
		elseif k == "--render" then
			args.render = v
		elseif k == "--out" then
			args.out = v
		elseif k == "--images" then
			table.insert(args.images, v)
		else
			error("unknown argument: " .. tostring(k))
		end
		i += 2
	end
	local env = process.env.LOOTRUSH_IMAGES
	if env and env ~= "" then
		for dir in env:gmatch("[^;]+") do
			table.insert(args.images, dir)
		end
	end
end

local function pick(list, csv, key)
	if not csv then
		return list
	end
	local want = {}
	for p in csv:gmatch("[^,]+") do
		want[p] = true
	end
	local out = {}
	for _, x in list do
		if want[tostring(x[key])] then
			table.insert(out, x)
		end
	end
	return out
end

local screens = pick(Matrix.SCREENS, args.screens, "name")
local devices = pick(Matrix.DEVICES, args.devices, "name")
local scales = pick(Matrix.SCALES, args.scales, "value")

fs.writeDir(args.out)
for _, f in fs.readDir(args.out) do
	if f:match("%.html$") or f:match("%.png$") then
		fs.removeFile(args.out .. "/" .. f)
	end
end

local placePath = Place.build()
local dumpPath = Place.apiDump()
local sourceFiles = Place.sourceFiles()
local placeRoot = roblox.deserializePlace(fs.readFile(placePath))
local images =
	Render.imageSource(Render.assetNames(placeRoot), Render.indexImages(args.images), args.out)

local md = { "# Layout matrix", "" }
local strictCount = 0
local counts = {} -- [screen][device .. "|" .. size] = number of strict findings

local names = {}
for _, sc in screens do
	table.insert(names, sc.name)
end
local deviceNames, scaleValues = {}, {}
for _, d in devices do
	table.insert(deviceNames, d.name)
end
for _, sc in scales do
	table.insert(scaleValues, sc.value)
end

local result = Matrix.run(
	{ placePath = placePath, dumpPath = dumpPath, sourceFiles = sourceFiles },
	names,
	deviceNames,
	scaleValues,
	function(sb, screen, device, scale, findings)
		counts[screen.name] = counts[screen.name] or {}
		counts[screen.name][device.name .. "|" .. scale.label] = #Matrix.strict(findings, screen)
		local render = args.render == "all"
			or (args.render == "phone" and device.touch and device.size.Y < 500)
			or (args.render == "phone" and scale.value == 1)
		if render then
			local file = string.format("%s__%s__%s.html", screen.name, device.name, scale.label)
			fs.writeFile(
				args.out .. "/" .. file,
				Render.page(
					sb,
					images,
					string.format("%s – %s – HUD %s", screen.name, device.name, scale.label),
					findings
				)
			)
		end
	end
)

for _, name in names do
	local lines = result[name] or {}
	strictCount += #lines
	print(string.format("%s %s (%d)", if #lines == 0 then "✔" else "✖", name, #lines))
	table.insert(md, "## " .. name)
	if #lines == 0 then
		table.insert(md, "No strict findings.")
	end
	for _, l in lines do
		table.insert(md, "- " .. l)
	end
	table.insert(md, "")
end

-- Summary table: screens × (device, size), number of strict findings (✖ = did not open)
local head = { "| screen |" }
local line = { "|---|" }
for _, device in devices do
	for _, scale in scales do
		table.insert(head, string.format(" %s %s |", device.name, scale.label))
		table.insert(line, "---|")
	end
end
local rows = { table.concat(head), table.concat(line) }
for _, name in names do
	local cells = { "| " .. name .. " |" }
	for _, device in devices do
		for _, scale in scales do
			local n = counts[name] and counts[name][device.name .. "|" .. scale.label]
			table.insert(
				cells,
				if n == nil then " ✖ |" elseif n == 0 then " ✔ |" else " " .. n .. " |"
			)
		end
	end
	table.insert(rows, table.concat(cells))
end
table.insert(md, 3, table.concat(rows, "\n") .. "\n")
fs.writeFile(args.out .. "/report.md", table.concat(md, "\n") .. "\n")
print(string.format("✔ report: %s/report.md · strict findings: %d", args.out, strictCount))
if strictCount > 0 then
	process.exit(1)
end
