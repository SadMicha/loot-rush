-- Erzeugt selenes Roblox-Standardbibliothek (roblox.yml) aus einem lokalen API-Dump.
-- Nur nötig, wenn `selene generate-roblox-std` das Internet nicht erreicht (z. B. hinter einem Proxy).
-- Nachbau von selene/src/roblox/generate_std.rs (selene 0.27.1).
--
--   lune run tools/lune/selene-std <roblox_base.yml> <API-Dump.json> <ausgabe.yml> <selene-version>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local basePath, dumpPath, outPath, seleneVersion =
	process.args[1], process.args[2], process.args[3], process.args[4]
assert(
	basePath and dumpPath and outPath and seleneVersion,
	"Aufruf: selene-std <base.yml> <dump.json> <out.yml> <version>"
)

local std = serde.decode("yaml", fs.readFile(basePath))
local api = serde.decode("json", fs.readFile(dumpPath))

std.globals = std.globals or {}
std.structs = std.structs or {}

local classes = {}
for _, class in api.Classes do
	classes[class.Name] = class
end

local function hasTag(tags: { any }?, name: string): boolean
	for _, tag in tags or {} do
		if tag == name then
			return true
		end
	end
	return false
end

local CUSTOM_METHOD_TYPES =
	{ CFrame = true, UDim = true, UDim2 = true, Vector2 = true, Vector3 = true }

local writeClassStruct

local function writeClassMembers(tbl, className: string)
	local class = classes[className]
	for _, member in class.Members do
		local field
		local kind = member.MemberType
		if kind == "Callback" then
			field = { property = "override-fields" }
		elseif kind == "Event" then
			field = { struct = "Event" }
		elseif kind == "Function" then
			local args = {}
			for _ in member.Parameters do
				table.insert(args, { required = false, type = "any" })
			end
			field = { args = args, method = true }
		elseif kind == "Property" then
			local sec = member.Security
			local default = if type(sec) == "string"
				then sec == "None"
				else sec.Read == "None" and sec.Write == "None"
			if default then
				field = {
					property = if hasTag(member.Tags, "ReadOnly")
						then "read-only"
						else "override-fields",
				}
				local vt = member.ValueType
				if vt.Category == "Class" then
					writeClassStruct(vt.Name)
					field = { struct = vt.Name }
				elseif vt.Category == "DataType" and CUSTOM_METHOD_TYPES[vt.Name] then
					field = { any = true }
				end
			end
		end
		if field then
			if hasTag(member.Tags, "Deprecated") then
				field.deprecated = { message = "this property is deprecated.", replace = {} }
			end
			tbl[member.Name] = field
		end
	end
	if class.Superclass ~= "<<<ROOT>>>" then
		writeClassMembers(tbl, class.Superclass)
	end
end

function writeClassStruct(className: string)
	if std.structs[className] then
		return
	end
	std.structs[className] = {}
	local tbl = { ["*"] = { struct = "Instance" } }
	writeClassMembers(tbl, className)
	std.structs[className] = tbl
end

local function writeClass(globalName: string, className: string)
	writeClassStruct(className)
	std.globals[globalName] = { struct = className }
end

writeClass("game", "DataModel")
writeClass("plugin", "Plugin")
writeClass("script", "Script")
writeClass("workspace", "Workspace")

for _, enum in api.Enums do
	std.globals[`Enum.{enum.Name}.GetEnumItems`] = { args = {}, method = true, must_use = true }
	for _, item in enum.Items do
		std.globals[`Enum.{enum.Name}.{item.Name}`] = { struct = "EnumItem" }
		for _, legacy in item.LegacyNames or {} do
			std.globals[`Enum.{enum.Name}.{legacy}`] = {
				struct = "EnumItem",
				deprecated = {
					message = `Enum.{enum.Name}.{legacy} was replaced with Enum.{enum.Name}.{item.Name}`,
					replace = { `Enum.{enum.Name}.{item.Name}` },
				},
			}
		end
	end
end

local creatable, services = {}, {}
for _, class in api.Classes do
	if not hasTag(class.Tags, "NotCreatable") then
		table.insert(creatable, class.Name)
	end
	if hasTag(class.Tags, "Service") then
		table.insert(services, class.Name)
	end
end

std.globals["Instance.new"] = {
	args = {
		{ type = creatable },
		{
			required = false,
			type = { display = "Instance" },
			deprecated = { message = "set the instance's parent separately", replace = {} },
		},
	},
	must_use = true,
}
std.structs.DataModel.GetService =
	{ args = { { type = services } }, method = true, must_use = true }

std.roblox_classes = {}
for _, class in api.Classes do
	local events, properties = {}, {}
	for _, member in class.Members do
		if member.MemberType == "Event" then
			table.insert(events, member.Name)
		elseif member.MemberType == "Property" then
			table.insert(properties, member.Name)
		end
	end
	std.roblox_classes[class.Name] =
		{ superclass = class.Superclass, events = events, properties = properties }
end

std.last_updated = os.time()
std.last_selene_version = seleneVersion

-- JSON ist gültiges YAML. Leere Luau-Tabellen kodiert serde als {}, selene erwartet dort Listen.
local json = serde.encode("json", std)
for _, key in { "args", "replace", "events", "properties" } do
	json = json:gsub('"' .. key .. '":{}', '"' .. key .. '":[]')
end
fs.writeFile(outPath, json)
print(`selene-Std geschrieben: {outPath}`)
