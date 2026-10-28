--!nocheck
-- Headless-Roblox: lädt das per Rojo gebaute Spiel (.rbxl) in Lune und führt Server- und
-- Client-Skripte aus, ohne Roblox Studio. Instanzen sind Proxys um Lunes Instanzen; was Lune
-- nicht kann (Events, Services, AbsoluteSize, Tweens, Remotes …), ergänzt diese Datei.
--
-- Alles, was schiefgeht, landet in sandbox.issues:
--   error  – Laufzeitfehler im Spielcode (mit Stacktrace), ungültige Properties, Kick …
--   warn   – warn()-Ausgaben, hängende WaitForChild-Aufrufe
--   info   – Roblox-Funktionen, die die Sandbox nur als leeren Platzhalter kennt

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Layout = require("./Layout")
local Scheduler = require("./Scheduler")
local Signal = require("./Signal")

local RInstance = roblox.Instance
local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Sandbox = {}
Sandbox.__index = Sandbox

local realTypeof = typeof

-------------------------------------------------------------------------------
-- Hilfen

local function isNative(v)
	return realTypeof(v) == "Instance"
end

local function tidy(line: string): string
	return (line:gsub('%[string "([^"]+)"%]', "%1"))
end

local function shortTrace(trace: string): string
	local out = {}
	for line in trace:gmatch("[^\n]+") do
		if
			not line:find("tools/lune/")
			and not line:find("%[C%]")
			and not line:find("__mlua")
			and not line:find("^stack traceback")
			and not line:find("^%s*in %?$")
		then
			table.insert(out, tidy(line))
		end
	end
	return table.concat(out, "\n")
end

-- Fehlermeldung ohne mitgeschleppten Stacktrace
local function errorText(err: any): string
	local text = tostring(err)
	text = text:gsub("^runtime error: ", "")
	text = text:match("^(.-)\nstack traceback") or text
	return tidy(text)
end

-- Mini-PRNG (Park–Miller), damit Random reproduzierbar und ohne Roblox läuft
local RandomClass = {}
RandomClass.__index = RandomClass
RandomClass.__type = "Random"
local function newRandom(seed: number?)
	local s = math.floor(math.abs(seed or 1234567)) % 2147483646 + 1
	local r = setmetatable({ _s = s }, RandomClass)
	-- Aufwärmen: sonst liefern kleine Nachbar-Seeds (1, 2, 3 …) fast gleiche erste Zahlen
	for _ = 1, 4 do
		r:_next()
	end
	return r
end
function RandomClass:_next(): number
	self._s = (self._s * 48271) % 2147483647
	return self._s / 2147483647
end
function RandomClass:NextNumber(a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + (hi - lo) * self:_next()
end
function RandomClass:NextInteger(a: number, b: number): number
	if a > b then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	return a + math.floor(self:_next() * (b - a + 1))
end
function RandomClass:NextUnitVector()
	local v = Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
	return if v.Magnitude > 0 then v.Unit else Vector3.new(1, 0, 0)
end
function RandomClass:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomClass:Clone()
	return setmetatable({ _s = self._s }, RandomClass)
end

local function tweenInfo(time, style, dir, repeatCount, reverses, delayTime)
	return setmetatable({
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = dir or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}, { __type = "TweenInfo" })
end

local function paramsObject(typeName: string)
	return function()
		return setmetatable({
			FilterDescendantsInstances = {},
			FilterType = Enum.RaycastFilterType.Exclude,
			IgnoreWater = false,
			CollisionGroup = "Default",
			RespectCanCollide = false,
			MaxParts = 0,
			BruteForceAllSlow = false,
			AddToFilter = function(self, v)
				table.insert(self.FilterDescendantsInstances, v)
			end,
		}, { __type = typeName })
	end
end

-- Werte, die Lune-Instanzen nicht von selbst haben ("missing default value")
local DEFAULTS = {
	Humanoid = {
		Health = 100,
		MaxHealth = 100,
		WalkSpeed = 16,
		JumpPower = 50,
		JumpHeight = 7.2,
		HipHeight = 2,
		MoveDirection = Vector3.zero,
		RootPart = false,
		FloorMaterial = Enum.Material.Plastic,
		DisplayName = "",
		AutoRotate = true,
	},
	Player = {
		UserId = 1,
		DisplayName = "Tester",
		AccountAge = 100,
		MembershipType = Enum.MembershipType.None,
	},
	Camera = { FieldOfView = 70, CameraType = Enum.CameraType.Custom },
	UserInputService = {
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
		AccelerometerEnabled = false,
		VREnabled = false,
		MouseBehavior = Enum.MouseBehavior.Default,
		MouseIconEnabled = true,
		MouseDeltaSensitivity = 1,
		PreferredInput = Enum.PreferredInput.KeyboardAndMouse,
	},
	GuiService = { MenuIsOpen = false, TopbarInset = false },
}

local VALUE_DEFAULTS = {
	bool = false,
	int = 0,
	int64 = 0,
	float = 0,
	double = 0,
	string = "",
	Vector3 = Vector3.zero,
	Vector2 = Vector2.zero,
	CFrame = CFrame.identity,
}

-------------------------------------------------------------------------------
-- Aufbau

export type Options = {
	placePath: string,
	dumpPath: string?,
	viewport: Vector2?,
	touch: boolean?,
	quiet: boolean?,
	sourceFiles: { [string]: string }?,
}

function Sandbox.new(opts: Options)
	local self = setmetatable({}, Sandbox)
	self.issues = {}
	self.logs = {}
	self.netLog = {}
	self.stubbed = {}
	self.quiet = opts.quiet
	self.viewport = opts.viewport or Vector2.new(1920, 1080)
	self.touch = opts.touch or false

	self.sched = Scheduler.new(function(err, trace, side)
		self:issue("error", "runtime", errorText(err), shortTrace(trace), side)
	end)

	self.native = setmetatable({}, { __mode = "k" }) -- proxy -> native
	self.proxies = {} -- debugId -> proxy
	self.side = {} -- proxy -> { [key]: value } (Werte, die Lune nicht speichern kann)
	self.signals = {} -- proxy -> { [name]: Signal }
	self.watchers = {} -- Poller für Property-/Attribut-/Kind-Änderungen
	self.tagSignals = { added = {}, removed = {} }
	self.modules = { server = {}, client = {} }
	self.loading = {}
	self.globals = { server = {}, client = {} }
	self.datastores = {}
	self.actions = {}
	self.renderSteps = {}
	self.layout = Layout.new(self.viewport, 58)
	self.sourceFiles = opts.sourceFiles or {}

	self:loadApiDump(opts.dumpPath)
	self:installCustom()

	local place = roblox.deserializePlace(fs.readFile(opts.placePath))
	self.game = self:wrap(place)
	self.workspace = self.game:GetService("Workspace")

	local camera = self:wrap(RInstance.new("Camera"))
	camera.Name = "Camera"
	camera.Parent = self.workspace
	self.workspace.CurrentCamera = camera
	self.camera = camera

	self.sched.onFrame = function(dt)
		self.layout:invalidate()
		self:poll()
		local rs = self.game:GetService("RunService")
		for _, step in self.renderSteps do
			self.sched:spawnAs(step.side, step.fn, dt)
		end
		for _, name in
			{
				"PreRender",
				"RenderStepped",
				"PreAnimation",
				"Stepped",
				"PreSimulation",
				"PostSimulation",
				"Heartbeat",
			}
		do
			local sig = self:signalIfExists(rs, name)
			if sig then
				if name == "Stepped" then
					sig:Fire(self.sched.now, dt)
				else
					sig:Fire(dt)
				end
			end
		end
	end
	return self
end

function Sandbox:issue(level: string, kind: string, message: string, trace: string?, side: string?)
	for _, i in self.issues do
		if i.kind == kind and i.message == message then
			i.count += 1
			return
		end
	end
	table.insert(
		self.issues,
		{
			level = level,
			kind = kind,
			message = message,
			trace = trace,
			side = side,
			count = 1,
			time = self.sched.now,
		}
	)
end

function Sandbox:loadApiDump(path: string?)
	self.api = nil
	if not path or not fs.isFile(path) then
		return
	end
	local dump = serde.decode("json", fs.readFile(path))
	local classes = {}
	for _, class in dump.Classes do
		local members = {}
		for _, m in class.Members do
			members[m.Name] = m
		end
		classes[class.Name] = { superclass = class.Superclass, members = members }
	end
	self.api = classes
end

-- Mitglied im API-Dump suchen (inkl. Oberklassen)
function Sandbox:apiMember(className: string, key: string)
	local api = self.api
	if not api then
		return nil
	end
	local c = api[className]
	while c do
		local m = c.members[key]
		if m then
			return m
		end
		c = api[c.superclass]
	end
	return nil
end

-------------------------------------------------------------------------------
-- Proxys

local ProxyMT = {}

function Sandbox:wrap(v)
	if not isNative(v) then
		return v
	end
	local key = v:GetDebugId()
	local p = self.proxies[key]
	if p then
		return p
	end
	p = setmetatable({}, ProxyMT)
	rawset(p, "__sb", self)
	self.native[p] = v
	self.proxies[key] = p
	return p
end

function Sandbox:unwrap(v)
	if type(v) == "table" then
		local n = self.native[v]
		if n then
			return n
		end
	end
	return v
end

function Sandbox:isProxy(v): boolean
	return type(v) == "table" and self.native[v] ~= nil
end

local function wrapResults(self, ...)
	local n = select("#", ...)
	local out = table.pack(...)
	for i = 1, n do
		local v = out[i]
		if isNative(v) then
			out[i] = self:wrap(v)
		elseif type(v) == "table" and #v > 0 and isNative(v[1]) then
			local list = table.create(#v)
			for j, item in v do
				list[j] = self:wrap(item)
			end
			out[i] = list
		end
	end
	return table.unpack(out, 1, n)
end

local function unwrapArgs(self, ...)
	local n = select("#", ...)
	local out = table.pack(...)
	for i = 1, n do
		out[i] = self:unwrap(out[i])
	end
	return table.unpack(out, 1, n)
end

function Sandbox:signal(p, name: string)
	local list = self.signals[p]
	if not list then
		list = {}
		self.signals[p] = list
	end
	local sig = list[name]
	if not sig then
		sig = Signal.new(self.sched, name)
		list[name] = sig
	end
	return sig
end

function Sandbox:signalIfExists(p, name: string)
	local list = self.signals[p]
	return list and list[name]
end

function Sandbox:sideGet(p, key)
	local t = self.side[p]
	return t and t[key]
end

function Sandbox:sideSet(p, key, value)
	local t = self.side[p]
	if not t then
		t = {}
		self.side[p] = t
	end
	t[key] = value
end

-- Eigene Mitglieder pro Klasse: { get = fn(p) } für Properties, { set = fn(p, v) }, { method = fn(p, ...) }
function Sandbox:custom(className: string, key: string, def)
	self.customs[className] = self.customs[className] or {}
	self.customs[className][key] = def
end

local function classChain(native)
	return native.ClassName
end

function Sandbox:findCustom(native, key: string)
	local cache = self.customCache
	local className = classChain(native)
	local ck = className .. "." .. key
	local hit = cache[ck]
	if hit ~= nil then
		return hit or nil
	end
	local db = roblox.getReflectionDatabase()
	local name = className
	local found = false
	while name do
		local c = self.customs[name]
		if c and c[key] then
			found = c[key]
			break
		end
		local info = db:GetClass(name)
		local nextName = info and info.Superclass
		if not info and self.api and self.api[name] then
			nextName = self.api[name].superclass
		end
		name = if nextName == "<<<ROOT>>>" then nil else nextName
	end
	cache[ck] = found
	return found or nil
end

local function stubReturn(member)
	local rt = member.ReturnType
	if not rt then
		return nil
	end
	if
		rt.Name == "Array"
		or rt.Name == "Objects"
		or rt.Name == "Dictionary"
		or rt.Name == "Instances"
	then
		return {}
	end
	return VALUE_DEFAULTS[rt.Name]
end

function Sandbox:index(p, key)
	local native = self.native[p]
	local custom = self:findCustom(native, key)
	if custom then
		if custom.get then
			return custom.get(p)
		elseif custom.method then
			return custom.method
		end
	end

	local stored = self.side[p]
	if stored and stored[key] ~= nil then
		return stored[key]
	end

	local ok, v = pcall(function()
		return native[key]
	end)
	if ok then
		if type(v) == "function" then
			return function(selfArg, ...)
				local target = self.native[selfArg] or selfArg
				return wrapResults(self, v(target, unwrapArgs(self, ...)))
			end
		end
		return wrapResults(self, v)
	end

	local err = tostring(v)
	if err:find("has been destroyed") then
		return nil
	end
	local className = native.ClassName
	if err:find("missing default value") then
		local d = DEFAULTS[className] and DEFAULTS[className][key]
		if d ~= nil then
			return if d == false then nil else d
		end
		local member = self:apiMember(className, key)
		if member and member.ValueType then
			return VALUE_DEFAULTS[member.ValueType.Name]
		end
		return nil
	end

	local member = self:apiMember(className, key)
	if member then
		local t = member.MemberType
		if t == "Event" then
			return self:signal(p, key)
		elseif t == "Function" then
			return function(...)
				local where = className .. ":" .. key .. "()"
				if not self.stubbed[where] then
					self.stubbed[where] = true
					self:issue("info", "stub", where .. " ist in der Sandbox nur ein Platzhalter")
				end
				return stubReturn(member)
			end
		elseif t == "Property" then
			local d = DEFAULTS[className] and DEFAULTS[className][key]
			if d ~= nil then
				return if d == false then nil else d
			end
			return VALUE_DEFAULTS[member.ValueType and member.ValueType.Name or ""]
		elseif t == "Callback" then
			return nil
		end
	end
	error(
		string.format(
			'%s is not a valid member of %s "%s"',
			tostring(key),
			className,
			native:GetFullName()
		),
		3
	)
end

function Sandbox:newindex(p, key, value)
	local native = self.native[p]
	local custom = self:findCustom(native, key)
	if custom and custom.set then
		custom.set(p, value)
		return
	end
	local raw = self:unwrap(value)
	local ok, err = pcall(function()
		native[key] = raw
	end)
	if ok then
		local stored = self.side[p]
		if stored then
			stored[key] = nil
		end
		return
	end
	err = tostring(err)
	if err:find("has been destroyed") then
		-- Roblox erlaubt Properties auf zerstörten Instanzen (z. B. auslaufende Tweens)
		self:sideSet(p, key, value)
		return
	end
	local className = native.ClassName
	local member = self:apiMember(className, key)
	if member and (member.MemberType == "Property" or member.MemberType == "Callback") then
		-- Lune kennt die Property nicht (neuer als die eingebaute Datenbank) – trotzdem merken
		if err:find("not a valid member") or err:find("missing default") or err:find("unknown") then
			self:sideSet(p, key, value)
			return
		end
	end
	if err:find("not a valid member") then
		error(
			string.format(
				'%s is not a valid member of %s "%s"',
				tostring(key),
				className,
				native:GetFullName()
			),
			3
		)
	end
	error(
		string.format(
			"Setzen von %s.%s fehlgeschlagen: %s",
			className,
			tostring(key),
			err:match("^[^\n]+") or err
		),
		3
	)
end

ProxyMT.__index = function(p, key)
	return rawget(p, "__sb"):index(p, key)
end
ProxyMT.__newindex = function(p, key, value)
	rawget(p, "__sb"):newindex(p, key, value)
end
ProxyMT.__tostring = function(p)
	local sb = rawget(p, "__sb")
	return sb.native[p].Name
end
ProxyMT.__metatable = "The metatable is locked"

-------------------------------------------------------------------------------
-- Änderungen beobachten (Lune feuert keine Events, darum wird jeden Frame verglichen)

function Sandbox:watch(kind: string, p, name: string?, fire: (any) -> ())
	for _, w in self.watchers do
		if w.kind == kind and w.p == p and w.name == name then
			return
		end
	end
	local w = { kind = kind, p = p, name = name, fire = fire }
	w.last = self:snapshot(w)
	table.insert(self.watchers, w)
end

function Sandbox:snapshot(w)
	local native = self.native[w.p]
	if w.kind == "prop" then
		local ok, v = pcall(function()
			return w.p[w.name]
		end)
		return if ok then v else nil
	elseif w.kind == "attr" then
		return native:GetAttribute(w.name)
	elseif w.kind == "attrs" then
		return native:GetAttributes()
	elseif w.kind == "children" or w.kind == "descendants" then
		local set = {}
		local list = if w.kind == "children" then native:GetChildren() else native:GetDescendants()
		for _, c in list do
			set[c:GetDebugId()] = c
		end
		return set
	end
	return nil
end

function Sandbox:poll()
	for _, w in table.clone(self.watchers) do
		local native = self.native[w.p]
		if native and (native.Parent ~= nil or native.ClassName == "DataModel") then
			local now = self:snapshot(w)
			if w.kind == "children" or w.kind == "descendants" then
				for id, c in now do
					if not w.last[id] then
						w.fire("added", self:wrap(c))
					end
				end
				for id, c in w.last do
					if not now[id] then
						w.fire("removed", self:wrap(c))
					end
				end
			elseif w.kind == "attrs" then
				for k, v in now do
					if w.last[k] ~= v then
						w.fire(k)
					end
				end
				for k in w.last do
					if now[k] == nil then
						w.fire(k)
					end
				end
			elseif now ~= w.last then
				w.fire(now, w.last)
			end
			w.last = now
		end
	end
end

-------------------------------------------------------------------------------
-- Ereignisse, Services und Methoden, die Lune fehlen

function Sandbox:installCustom()
	self.customs = {}
	self.customCache = {}
	local sched = self.sched

	local function fireTag(which: string, tag: string, inst)
		local sig = self.tagSignals[which][tag]
		if sig then
			sig:Fire(inst)
		end
	end

	-- Instance -------------------------------------------------------------
	self:custom("Instance", "WaitForChild", {
		method = function(p, name, timeout)
			local native = self.native[p]
			local start = sched.now
			local warned = false
			while true do
				local c = native:FindFirstChild(name)
				if c then
					return self:wrap(c)
				end
				if timeout and sched.now - start >= timeout then
					return nil
				end
				if not warned and sched.now - start >= 5 then
					warned = true
					self:issue(
						"warn",
						"yield",
						string.format(
							'Infinite yield possible on %s:WaitForChild("%s")',
							native:GetFullName(),
							name
						),
						shortTrace(debug.traceback()),
						sched.side
					)
				end
				sched:wait(0)
			end
		end,
	})
	self:custom("Instance", "GetPropertyChangedSignal", {
		method = function(p, prop)
			local native = self.native[p]
			local ok, err = pcall(function()
				return p[prop]
			end)
			if not ok and tostring(err):find("not a valid member") then
				error(string.format("%s is not a valid property name.", tostring(prop)), 2)
			end
			local sig = self:signal(p, "Changed:" .. prop)
			self:watch("prop", p, prop, function()
				sig:Fire()
			end)
			local _ = native
			return sig
		end,
	})
	self:custom("Instance", "GetAttributeChangedSignal", {
		method = function(p, attr)
			local sig = self:signal(p, "Attr:" .. attr)
			self:watch("attr", p, attr, function()
				sig:Fire()
			end)
			return sig
		end,
	})
	self:custom("Instance", "AttributeChanged", {
		get = function(p)
			local sig = self:signal(p, "AttributeChanged")
			self:watch("attrs", p, nil, function(name)
				sig:Fire(name)
			end)
			return sig
		end,
	})
	for _, pair in
		{
			{ "ChildAdded", "children", "added" },
			{ "ChildRemoved", "children", "removed" },
			{ "DescendantAdded", "descendants", "added" },
			{ "DescendantRemoving", "descendants", "removed" },
		}
	do
		self:custom("Instance", pair[1], {
			get = function(p)
				local sig = self:signal(p, pair[1])
				self:watch(pair[2], p, pair[1], function(what, child)
					if what == pair[3] then
						sig:Fire(child)
					end
				end)
				return sig
			end,
		})
	end
	self:custom("Instance", "Destroy", {
		method = function(p)
			local native = self.native[p]
			local sig = self:signalIfExists(p, "Destroying")
			if sig then
				sig:Fire()
			end
			for _, d in native:GetDescendants() do
				local dp = self.proxies[d:GetDebugId()]
				local ds = dp and self:signalIfExists(dp, "Destroying")
				if ds then
					ds:Fire()
				end
			end
			native:Destroy()
		end,
	})
	self:custom("Instance", "AddTag", {
		method = function(p, tag)
			local native = self.native[p]
			if not native:HasTag(tag) then
				native:AddTag(tag)
				fireTag("added", tag, p)
			end
		end,
	})
	self:custom("Instance", "RemoveTag", {
		method = function(p, tag)
			local native = self.native[p]
			if native:HasTag(tag) then
				native:RemoveTag(tag)
				fireTag("removed", tag, p)
			end
		end,
	})
	self:custom("Instance", "GetActor", {
		method = function()
			return nil
		end,
	})

	-- GUI -----------------------------------------------------------------
	local function rect(p)
		return self.layout:rect(self.native[p])
	end
	self:custom("GuiBase2d", "AbsoluteSize", {
		get = function(p)
			local r = rect(p)
			return if r then Vector2.new(r.w, r.h) else Vector2.zero
		end,
	})
	self:custom("GuiBase2d", "AbsolutePosition", {
		get = function(p)
			local r = rect(p)
			return if r then Vector2.new(r.x, r.y) else Vector2.zero
		end,
	})
	self:custom("GuiBase2d", "AbsoluteRotation", {
		get = function()
			return 0
		end,
	})
	self:custom("TextLabel", "TextBounds", {
		get = function(p)
			local native = self.native[p]
			local r = rect(p)
			local size = native.TextSize * (r and r.s or 1)
			return Layout.textBounds(
				native.Text,
				size,
				Layout.isBold(native),
				if native.TextWrapped and r then r.w else nil
			)
		end,
	})
	self.customs.TextButton = { TextBounds = self.customs.TextLabel.TextBounds }
	self.customs.TextBox = {
		TextBounds = self.customs.TextLabel.TextBounds,
		CaptureFocus = {
			method = function(p)
				self:signal(p, "Focused"):Fire()
			end,
		},
		ReleaseFocus = {
			method = function(p, submitted)
				self:signal(p, "FocusLost"):Fire(submitted or false)
			end,
		},
		IsFocused = {
			method = function()
				return false
			end,
		},
	}
	self:custom("GuiObject", "TweenPosition", {
		method = function(p, pos)
			p.Position = pos
			return true
		end,
	})
	self:custom("GuiObject", "TweenSize", {
		method = function(p, size)
			p.Size = size
			return true
		end,
	})
	self:custom("GuiObject", "TweenSizeAndPosition", {
		method = function(p, size, pos)
			p.Size = size
			p.Position = pos
			return true
		end,
	})

	-- DataModel / Services --------------------------------------------------
	self:custom("DataModel", "GetService", {
		method = function(p, name)
			local native = self.native[p]
			local ok, svc = pcall(function()
				return native:GetService(name)
			end)
			if not ok then
				error(string.format("'%s' is not a valid Service name", tostring(name)), 2)
			end
			return self:wrap(svc)
		end,
	})
	self.customs.DataModel.FindService = self.customs.DataModel.GetService
	self:custom("DataModel", "BindToClose", {
		method = function(_, fn)
			self.onClose = self.onClose or {}
			table.insert(self.onClose, fn)
		end,
	})
	self:custom("DataModel", "IsLoaded", {
		method = function()
			return true
		end,
	})
	self:custom("DataModel", "PlaceId", {
		get = function()
			return 0
		end,
	})
	self:custom("DataModel", "GameId", {
		get = function()
			return 0
		end,
	})
	self:custom("DataModel", "JobId", {
		get = function()
			return "sandbox"
		end,
	})

	self:custom("RunService", "IsServer", {
		method = function()
			return sched.side == "server"
		end,
	})
	self:custom("RunService", "IsClient", {
		method = function()
			return sched.side == "client"
		end,
	})
	self:custom("RunService", "IsStudio", {
		method = function()
			return self.studio ~= false -- Tests setzen sim.studio = false für „veröffentlichtes Spiel“
		end,
	})
	self:custom("RunService", "IsRunning", {
		method = function()
			return true
		end,
	})
	self:custom("RunService", "IsRunMode", {
		method = function()
			return false
		end,
	})
	self:custom("RunService", "IsEdit", {
		method = function()
			return false
		end,
	})
	self:custom("RunService", "BindToRenderStep", {
		method = function(_, name, _prio, fn)
			self.renderSteps[name] = { fn = fn, side = sched.side }
		end,
	})
	self:custom("RunService", "UnbindFromRenderStep", {
		method = function(_, name)
			self.renderSteps[name] = nil
		end,
	})

	self:custom("Players", "LocalPlayer", {
		get = function()
			return if sched.side == "client" then self.player else nil
		end,
	})
	self:custom("Players", "GetPlayers", {
		method = function()
			return if self.player and self.player.Parent then { self.player } else {}
		end,
	})
	self:custom("Players", "GetPlayerFromCharacter", {
		method = function(_, model)
			if self.player and model ~= nil and self.player.Character == model then
				return self.player
			end
			return nil
		end,
	})
	self:custom("Players", "GetPlayerByUserId", {
		method = function(_, id)
			if self.player and id == self.player.UserId then
				return self.player
			end
			return nil
		end,
	})
	self:custom("Players", "GetNameFromUserIdAsync", {
		method = function()
			return "Tester"
		end,
	})
	self:custom("Player", "Kick", {
		method = function(p, msg)
			self:issue(
				"error",
				"kick",
				"Spieler gekickt: " .. tostring(msg or ""),
				shortTrace(debug.traceback()),
				sched.side
			)
			p.Parent = nil
		end,
	})
	self:custom("Player", "GetMouse", {
		method = function()
			if not self.mouse then
				self.mouse = {
					Hit = CFrame.new(0, 0, -10),
					Origin = CFrame.identity,
					Target = nil,
					X = self.viewport.X / 2,
					Y = self.viewport.Y / 2,
					Icon = "",
					TargetFilter = nil,
					UnitRay = roblox.Ray.new(Vector3.zero, Vector3.new(0, 0, -1)),
					Move = Signal.new(sched, "Move"),
					Button1Down = Signal.new(sched, "Button1Down"),
					Button1Up = Signal.new(sched, "Button1Up"),
					Button2Down = Signal.new(sched, "Button2Down"),
					Button2Up = Signal.new(sched, "Button2Up"),
					WheelForward = Signal.new(sched, "WheelForward"),
					WheelBackward = Signal.new(sched, "WheelBackward"),
				}
			end
			return self.mouse
		end,
	})
	self:custom("Player", "LoadCharacter", {
		method = function()
			self:spawnCharacter()
		end,
	})
	self:custom("Player", "GetNetworkPing", {
		method = function()
			return 0.05
		end,
	})
	self:custom("Player", "HasAppearanceLoaded", {
		method = function()
			return true
		end,
	})
	self:custom("Player", "DistanceFromCharacter", {
		method = function(p, pos)
			local c = p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart")
			return if root then (root.Position - pos).Magnitude else 0
		end,
	})

	self:custom("Workspace", "Raycast", {
		method = function()
			return nil
		end,
	})
	for _, name in { "Blockcast", "Spherecast", "Shapecast" } do
		self:custom("Workspace", name, {
			method = function()
				return nil
			end,
		})
	end
	for _, name in { "GetPartBoundsInRadius", "GetPartBoundsInBox", "GetPartsInPart" } do
		self:custom("Workspace", name, {
			method = function()
				return {}
			end,
		})
	end
	self:custom("Workspace", "GetServerTimeNow", {
		method = function()
			return 1.7e9 + sched.now
		end,
	})

	self:custom("Camera", "ViewportSize", {
		get = function()
			return self.viewport
		end,
	})
	for _, name in { "WorldToViewportPoint", "WorldToScreenPoint" } do
		self:custom("Camera", name, {
			method = function()
				return Vector3.new(self.viewport.X / 2, self.viewport.Y / 2, 10), true
			end,
		})
	end
	for _, name in { "ViewportPointToRay", "ScreenPointToRay" } do
		self:custom("Camera", name, {
			method = function(p)
				local cf = p.CFrame
				return roblox.Ray.new(cf.Position, cf.LookVector)
			end,
		})
	end

	self:custom("GuiService", "GetGuiInset", {
		method = function()
			return Vector2.new(0, 58), Vector2.zero
		end,
	})
	-- Freier Platz in der Topbar: links davon Roblox-Menü/Chat (gleiche Maße wie Checks.TOPBAR)
	self:custom("GuiService", "TopbarInset", {
		get = function()
			return roblox.Rect.new(180, 0, self.viewport.X - 60, 58)
		end,
	})
	self:custom("UserInputService", "TouchEnabled", {
		get = function()
			return self.touch
		end,
	})
	self:custom("UserInputService", "KeyboardEnabled", {
		get = function()
			return not self.touch
		end,
	})
	self:custom("UserInputService", "MouseEnabled", {
		get = function()
			return not self.touch
		end,
	})
	self:custom("UserInputService", "GetMouseLocation", {
		method = function()
			return self.viewport / 2
		end,
	})
	for _, name in { "IsKeyDown", "IsMouseButtonPressed", "IsGamepadButtonDown" } do
		self:custom("UserInputService", name, {
			method = function()
				return false
			end,
		})
	end
	self:custom("UserInputService", "GetLastInputType", {
		method = function()
			return if self.touch then Enum.UserInputType.Touch else Enum.UserInputType.Keyboard
		end,
	})
	self:custom("UserInputService", "GetFocusedTextBox", {
		method = function()
			return nil
		end,
	})
	self:custom("UserInputService", "GetConnectedGamepads", {
		method = function()
			return {}
		end,
	})
	self:custom("UserInputService", "GetKeysPressed", {
		method = function()
			return {}
		end,
	})

	self:custom("ContextActionService", "BindAction", {
		method = function(_, name, fn, touch, ...)
			self.actions[name] = { fn = fn, touch = touch, inputs = { ... }, side = sched.side }
		end,
	})
	self:custom("ContextActionService", "BindActionAtPriority", {
		method = function(_, name, fn, touch, _prio, ...)
			self.actions[name] = { fn = fn, touch = touch, inputs = { ... }, side = sched.side }
		end,
	})
	self:custom("ContextActionService", "UnbindAction", {
		method = function(_, name)
			self.actions[name] = nil
		end,
	})
	self:custom("ContextActionService", "GetButton", {
		method = function()
			return nil
		end,
	})

	self:custom("TweenService", "Create", {
		method = function(_, target, info, goals)
			if not self:isProxy(target) then
				error("TweenService:Create: Argument 1 muss eine Instance sein", 2)
			end
			for prop, goal in goals do
				local ok, current = pcall(function()
					return target[prop]
				end)
				if not ok then
					error(
						string.format(
							"No property named '%s' for object '%s'",
							tostring(prop),
							tostring(target)
						),
						2
					)
				end
				if current ~= nil and realTypeof(current) ~= realTypeof(goal) then
					error(
						string.format(
							"TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')",
							prop,
							realTypeof(current),
							realTypeof(goal)
						),
						2
					)
				end
			end
			return self:newTween(target, info, goals)
		end,
	})
	self:custom("TweenService", "GetValue", {
		method = function(_, alpha)
			return alpha
		end,
	})

	self:custom("Debris", "AddItem", {
		method = function(_, item, t)
			sched:delay(t or 10, function()
				if item.Parent then
					item:Destroy()
				end
			end)
		end,
	})

	self:custom("CollectionService", "GetTagged", {
		method = function(_, tag)
			local out = {}
			for _, d in self.native[self.game]:GetDescendants() do
				if d:HasTag(tag) then
					table.insert(out, self:wrap(d))
				end
			end
			return out
		end,
	})
	self:custom("CollectionService", "AddTag", {
		method = function(_, inst, tag)
			inst:AddTag(tag)
		end,
	})
	self:custom("CollectionService", "RemoveTag", {
		method = function(_, inst, tag)
			inst:RemoveTag(tag)
		end,
	})
	self:custom("CollectionService", "HasTag", {
		method = function(_, inst, tag)
			return self.native[inst]:HasTag(tag)
		end,
	})
	self:custom("CollectionService", "GetTags", {
		method = function(_, inst)
			return self.native[inst]:GetTags()
		end,
	})
	self:custom("CollectionService", "GetInstanceAddedSignal", {
		method = function(_, tag)
			self.tagSignals.added[tag] = self.tagSignals.added[tag]
				or Signal.new(sched, "Added:" .. tag)
			return self.tagSignals.added[tag]
		end,
	})
	self:custom("CollectionService", "GetInstanceRemovedSignal", {
		method = function(_, tag)
			self.tagSignals.removed[tag] = self.tagSignals.removed[tag]
				or Signal.new(sched, "Removed:" .. tag)
			return self.tagSignals.removed[tag]
		end,
	})

	local guidRng = newRandom(42)
	self:custom("HttpService", "GenerateGUID", {
		method = function(_, braces)
			local hex = ""
			for i = 1, 32 do
				hex ..= string.format("%x", guidRng:NextInteger(0, 15))
				if i == 8 or i == 12 or i == 16 or i == 20 then
					hex ..= "-"
				end
			end
			hex = hex:upper()
			return if braces == false then hex else "{" .. hex .. "}"
		end,
	})
	self:custom("HttpService", "JSONEncode", {
		method = function(_, v)
			return serde.encode("json", v)
		end,
	})
	self:custom("HttpService", "JSONDecode", {
		method = function(_, s)
			return serde.decode("json", s)
		end,
	})
	self:custom("HttpService", "UrlEncode", {
		method = function(_, s)
			return (
				s:gsub("[^%w%-_%.~]", function(c)
					return string.format("%%%02X", string.byte(c))
				end)
			)
		end,
	})

	self:custom("TextService", "GetTextSize", {
		method = function(_, text, size, font, frame)
			local bold = tostring(font):find("Bold") ~= nil
			local b = Layout.textBounds(text, size, bold, frame and frame.X)
			return b
		end,
	})

	self:custom("DataStoreService", "GetDataStore", {
		method = function(_, name, scope)
			return self:dataStore((name or "") .. "/" .. (scope or "global"))
		end,
	})
	self.customs.DataStoreService.GetOrderedDataStore = self.customs.DataStoreService.GetDataStore
	self:custom("DataStoreService", "GetRequestBudgetForRequestType", {
		method = function()
			return 100
		end,
	})

	self:custom("Stats", "GetTotalMemoryUsageMb", {
		method = function()
			return 400
		end,
	})
	self:custom("Stats", "GetMemoryUsageMbForTag", {
		method = function()
			return 10
		end,
	})

	self:custom("StarterGui", "SetCoreGuiEnabled", { method = function() end })
	self:custom("StarterGui", "GetCoreGuiEnabled", {
		method = function()
			return true
		end,
	})
	self:custom("StarterGui", "SetCore", { method = function() end })
	self:custom("StarterGui", "GetCore", {
		method = function()
			return nil
		end,
	})

	-- Figuren ----------------------------------------------------------------
	local function animTrack()
		return {
			IsPlaying = false,
			Length = 1,
			Speed = 1,
			TimePosition = 0,
			WeightCurrent = 1,
			Looped = false,
			Priority = Enum.AnimationPriority.Action,
			Stopped = Signal.new(sched, "Stopped"),
			Ended = Signal.new(sched, "Ended"),
			DidLoop = Signal.new(sched, "DidLoop"),
			Play = function(t)
				t.IsPlaying = true
			end,
			Stop = function(t)
				t.IsPlaying = false
				t.Stopped:Fire()
			end,
			AdjustSpeed = function(t, s)
				t.Speed = s
			end,
			AdjustWeight = function() end,
			GetMarkerReachedSignal = function()
				return Signal.new(sched, "Marker")
			end,
			Destroy = function() end,
		}
	end
	self:custom("Humanoid", "LoadAnimation", {
		method = function()
			return animTrack()
		end,
	})
	self:custom("Animator", "LoadAnimation", {
		method = function()
			return animTrack()
		end,
	})
	self:custom("Humanoid", "TakeDamage", {
		method = function(p, amount)
			if not p:FindFirstChildOfClass("ForceField") then
				p.Health = math.max(0, p.Health - amount)
			end
		end,
	})
	self:custom("Humanoid", "MoveTo", {
		method = function(p, pos)
			local root = p.Parent and p.Parent:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = CFrame.new(pos)
			end
			sched:delay(0.5, function()
				self:signal(p, "MoveToFinished"):Fire(true)
			end)
		end,
	})
	self:custom("Humanoid", "GetState", {
		method = function()
			return Enum.HumanoidStateType.Running
		end,
	})
	for _, name in { "HealthChanged", "Died" } do
		self:custom("Humanoid", name, {
			get = function(p)
				local sig = self:signal(p, name)
				self:watch("prop", p, "Health", function(now, before)
					local hc = self:signalIfExists(p, "HealthChanged")
					if hc then
						hc:Fire(now)
					end
					local died = self:signalIfExists(p, "Died")
					if died and now <= 0 and (before or 1) > 0 then
						died:Fire()
					end
				end)
				return sig
			end,
		})
	end

	local function pivotOf(p)
		local native = self.native[p]
		if native:IsA("BasePart") then
			return native.CFrame
		end
		local primary = native.PrimaryPart or native:FindFirstChildWhichIsA("BasePart", true)
		return if primary then primary.CFrame else CFrame.identity
	end
	self:custom("PVInstance", "GetPivot", { method = pivotOf })
	self:custom("PVInstance", "PivotTo", {
		method = function(p, cf)
			local native = self.native[p]
			if native:IsA("BasePart") then
				native.CFrame = cf
				return
			end
			local old = pivotOf(p)
			for _, d in native:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = cf * old:ToObjectSpace(d.CFrame)
				end
			end
		end,
	})
	self:custom("Model", "SetPrimaryPartCFrame", {
		method = function(p, cf)
			p:PivotTo(cf)
		end,
	})
	self:custom("Model", "GetBoundingBox", {
		method = function(p)
			return pivotOf(p), Vector3.new(4, 5, 4)
		end,
	})
	self:custom("Model", "GetExtentsSize", {
		method = function()
			return Vector3.new(4, 5, 4)
		end,
	})
	self:custom("Model", "MoveTo", {
		method = function(p, pos)
			p:PivotTo(CFrame.new(pos))
		end,
	})
	self:custom("Model", "GetScale", {
		method = function()
			return 1
		end,
	})
	self:custom("Model", "ScaleTo", { method = function() end })
	self:custom("BasePart", "GetMass", {
		method = function(p)
			local s = self.native[p].Size
			return s.X * s.Y * s.Z * 0.7
		end,
	})
	self:custom("BasePart", "GetVelocityAtPosition", {
		method = function()
			return Vector3.zero
		end,
	})
	self:custom("BasePart", "GetNetworkOwner", {
		method = function()
			return nil
		end,
	})
	self:custom("BasePart", "CanSetNetworkOwnership", {
		method = function()
			return true
		end,
	})
	self:custom("BasePart", "GetTouchingParts", {
		method = function()
			return {}
		end,
	})

	-- Netzwerk -------------------------------------------------------------
	local function copyArgs(where, ...)
		local n = select("#", ...)
		local out = table.pack(...)
		local function copy(v, depth)
			local t = realTypeof(v)
			if t == "function" or t == "thread" then
				error(where .. ": Funktionen können nicht über das Netz geschickt werden", 4)
			end
			if t == "table" and not self:isProxy(v) and getmetatable(v) == nil then
				if depth > 30 then
					error(where .. ": Tabelle zu tief verschachtelt", 4)
				end
				local c = {}
				for k, x in v do
					c[k] = copy(x, depth + 1)
				end
				return c
			end
			return v
		end
		for i = 1, n do
			out[i] = copy(out[i], 0)
		end
		return out
	end
	local function logNet(dir, remote, args)
		table.insert(self.netLog, { dir = dir, name = remote.Name, args = args, t = sched.now })
	end
	self:custom("RemoteEvent", "FireServer", {
		method = function(p, ...)
			if sched.side ~= "client" then
				error("FireServer can only be called from the client", 2)
			end
			local args = copyArgs(p.Name .. ":FireServer", ...)
			logNet("C→S", p, args)
			local sig = self:signal(p, "OnServerEvent")
			sched:defer(function()
				sig:Fire(self.player, table.unpack(args, 1, args.n))
			end)
		end,
	})
	local function toClient(p, ...)
		local args = copyArgs(p.Name .. ":FireClient", ...)
		logNet("S→C", p, args)
		local sig = self:signal(p, "OnClientEvent")
		sched:defer(function()
			sig:Fire(table.unpack(args, 1, args.n))
		end)
	end
	self:custom("RemoteEvent", "FireClient", {
		method = function(p, player, ...)
			if sched.side ~= "server" then
				error("FireClient can only be called from the server", 2)
			end
			if player ~= self.player then
				error("FireClient: player argument must be a Player", 2)
			end
			toClient(p, ...)
		end,
	})
	self:custom("RemoteEvent", "FireAllClients", {
		method = function(p, ...)
			if sched.side ~= "server" then
				error("FireAllClients can only be called from the server", 2)
			end
			if self.player then
				toClient(p, ...)
			end
		end,
	})
	self:custom("UnreliableRemoteEvent", "FireServer", self.customs.RemoteEvent.FireServer)
	self:custom("UnreliableRemoteEvent", "FireClient", self.customs.RemoteEvent.FireClient)
	self:custom("UnreliableRemoteEvent", "FireAllClients", self.customs.RemoteEvent.FireAllClients)
	self:custom("RemoteFunction", "InvokeServer", {
		method = function(p, ...)
			local args = copyArgs(p.Name .. ":InvokeServer", ...)
			logNet("C→S", p, args)
			local cb = self:sideGet(p, "OnServerInvoke")
			if not cb then
				return nil
			end
			return cb(self.player, table.unpack(args, 1, args.n))
		end,
	})
	self:custom("RemoteFunction", "InvokeClient", {
		method = function(p, _player, ...)
			local args = copyArgs(p.Name .. ":InvokeClient", ...)
			logNet("S→C", p, args)
			local cb = self:sideGet(p, "OnClientInvoke")
			return if cb then cb(table.unpack(args, 1, args.n)) else nil
		end,
	})
	self:custom("BindableEvent", "Fire", {
		method = function(p, ...)
			local args = copyArgs(p.Name .. ":Fire", ...)
			self:signal(p, "Event"):Fire(table.unpack(args, 1, args.n))
		end,
	})
	self:custom("BindableFunction", "Invoke", {
		method = function(p, ...)
			local cb = self:sideGet(p, "OnInvoke")
			return if cb then cb(...) else nil
		end,
	})
end

function Sandbox:newTween(target, info, goals)
	local sched = self.sched
	info = info or tweenInfo()
	local tween
	tween = setmetatable({
		Instance = target,
		TweenInfo = info,
		PlaybackState = Enum.PlaybackState.Begin,
		Completed = Signal.new(sched, "Completed"),
		Name = "Tween",
		ClassName = "Tween",
		_thread = nil,
		Play = function(t)
			if t._thread then
				sched:cancel(t._thread)
			end
			t.PlaybackState = Enum.PlaybackState.Playing
			t._thread = sched:delay((info.DelayTime or 0) + (info.Time or 0), function()
				t._thread = nil
				for k, v in goals do
					target[k] = v
				end
				if (info.RepeatCount or 0) >= 0 then
					t.PlaybackState = Enum.PlaybackState.Completed
					t.Completed:Fire(Enum.PlaybackState.Completed)
				end
			end)
		end,
		Cancel = function(t)
			if t._thread then
				sched:cancel(t._thread)
				t._thread = nil
			end
			t.PlaybackState = Enum.PlaybackState.Cancelled
			t.Completed:Fire(Enum.PlaybackState.Cancelled)
		end,
		Pause = function(t)
			if t._thread then
				sched:cancel(t._thread)
				t._thread = nil
			end
			t.PlaybackState = Enum.PlaybackState.Paused
		end,
		Destroy = function(t)
			if t._thread then
				sched:cancel(t._thread)
			end
		end,
		IsA = function(_, c)
			return c == "Tween" or c == "TweenBase" or c == "Instance"
		end,
	}, { __type = "Instance" })
	return tween
end

function Sandbox:dataStore(key: string)
	local data = self.datastores[key]
	if not data then
		data = {}
		self.datastores[key] = data
	end
	local sched = self.sched
	local store = {}
	function store:GetAsync(k)
		sched:wait(0)
		return data[k]
	end
	function store:SetAsync(k, v)
		sched:wait(0)
		data[k] = v
	end
	function store:UpdateAsync(k, fn)
		sched:wait(0)
		local new = fn(data[k])
		if new ~= nil then
			data[k] = new
		end
		return data[k]
	end
	function store:IncrementAsync(k, delta)
		data[k] = (data[k] or 0) + (delta or 1)
		return data[k]
	end
	function store:RemoveAsync(k)
		local old = data[k]
		data[k] = nil
		return old
	end
	function store:GetSortedAsync()
		return {
			IsFinished = true,
			GetCurrentPage = function()
				return {}
			end,
			AdvanceToNextPageAsync = function() end,
		}
	end
	return store
end

-------------------------------------------------------------------------------
-- Skripte ausführen

function Sandbox:typeof(v): string
	if self:isProxy(v) then
		return "Instance"
	end
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return mt.__type
		end
	end
	return realTypeof(v)
end

function Sandbox:makeEnv(scriptProxy, side: string)
	local sched = self.sched
	local sb = self
	local G = self.globals[side]
	local function print_(...)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		local line = table.concat(parts, " ", 1, parts.n)
		table.insert(sb.logs, { side = side, kind = "print", text = line, t = sched.now })
		if not sb.quiet then
			print(string.format("  [%s] %s", side, line))
		end
	end
	local function warn_(...)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		local line = table.concat(parts, " ", 1, parts.n)
		table.insert(sb.logs, { side = side, kind = "warn", text = line, t = sched.now })
		sb:issue("warn", "warn", line, nil, side)
	end
	local taskLib = table.freeze({
		spawn = function(f, ...)
			return sched:spawn(f, ...)
		end,
		defer = function(f, ...)
			return sched:defer(f, ...)
		end,
		delay = function(t, f, ...)
			return sched:delay(t, f, ...)
		end,
		wait = function(t)
			return sched:wait(t)
		end,
		cancel = function(co)
			sched:cancel(co)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	})
	local osLib = setmetatable({
		clock = function()
			return sched.now
		end,
		time = function(t)
			if t then
				return os.time(t)
			end
			return 1700000000 + math.floor(sched.now)
		end,
	}, { __index = os })

	local env = {
		game = self.game,
		Game = self.game,
		workspace = self.workspace,
		Workspace = self.workspace,
		script = scriptProxy,
		plugin = nil,
		shared = G,
		_G = G,
		print = print_,
		warn = warn_,
		typeof = function(v)
			return sb:typeof(v)
		end,
		require = function(m)
			return sb:require(m, side)
		end,
		task = taskLib,
		wait = function(t)
			local dt = sched:wait(t)
			return dt, sched.now
		end,
		delay = function(t, f)
			sched:delay(t, f)
		end,
		spawn = function(f)
			sched:defer(f)
		end,
		tick = function()
			return 1700000000 + sched.now
		end,
		time = function()
			return sched.now
		end,
		elapsedTime = function()
			return sched.now
		end,
		os = osLib,
		settings = function()
			return {
				Rendering = { QualityLevel = Enum.QualityLevel.Automatic },
				Physics = {},
				Network = {},
			}
		end,
		UserSettings = function()
			return {
				GetService = function()
					return {
						SavedQualityLevel = Enum.SavedQualitySetting.Automatic,
						GetUserGameSettings = function() end,
					}
				end,
			}
		end,
		Instance = table.freeze({
			new = function(className, parent)
				local ok, n = pcall(RInstance.new, className)
				if not ok then
					error(
						string.format(
							'Unable to create an Instance of type "%s"',
							tostring(className)
						),
						2
					)
				end
				local p = sb:wrap(n)
				if parent then
					p.Parent = parent
				end
				return p
			end,
			fromExisting = function(p)
				return sb:wrap(sb.native[p]:Clone())
			end,
		}),
		Random = { new = newRandom },
		TweenInfo = { new = tweenInfo },
		RaycastParams = { new = paramsObject("RaycastParams") },
		OverlapParams = { new = paramsObject("OverlapParams") },
		DateTime = {
			now = function()
				return {
					UnixTimestamp = 1700000000 + math.floor(sched.now),
					UnixTimestampMillis = (1700000000 + sched.now) * 1000,
				}
			end,
		},
		Enum = Enum,
	}
	for _, name in
		{
			"Axes",
			"BrickColor",
			"CFrame",
			"Color3",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"Content",
			"Faces",
			"Font",
			"NumberRange",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"PhysicalProperties",
			"Ray",
			"Rect",
			"Region3",
			"Region3int16",
			"UDim",
			"UDim2",
			"Vector2",
			"Vector2int16",
			"Vector3",
			"Vector3int16",
		}
	do
		env[name] = (roblox :: any)[name]
	end
	return env
end

function Sandbox:runSource(p, side: string, isModule: boolean)
	local native = self.native[p]
	local source = native.Source
	local chunkName = self:sourceFile(native)
	local ok, fn =
		pcall(luau.load, source, { debugName = chunkName, environment = self:makeEnv(p, side) })
	if not ok then
		error(string.format("Syntaxfehler in %s: %s", chunkName, tostring(fn)), 0)
	end
	if isModule then
		return fn
	end
	return fn
end

-- Instanz → Quelldatei (aus `rojo sourcemap`), damit Fehler auf src/…luau:Zeile zeigen.
-- Kopien in PlayerScripts/PlayerGui werden auf ihr Original in StarterPlayer/StarterGui abgebildet.
function Sandbox:sourceFile(native): string
	local full = native:GetFullName()
	local mapped = full
		:gsub("^Players%.[^%.]+%.PlayerScripts%.", "StarterPlayer.StarterPlayerScripts.")
		:gsub("^Players%.[^%.]+%.PlayerGui%.", "StarterGui.")
	return self.sourceFiles[mapped] or full
end

function Sandbox:require(m, side: string)
	if not self:isProxy(m) then
		if type(m) == "number" then
			error("require(assetId) wird in der Sandbox nicht unterstützt", 2)
		end
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local native = self.native[m]
	if native.ClassName ~= "ModuleScript" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local key = native:GetDebugId()
	local cache = self.modules[side]
	local entry = cache[key]
	if entry then
		return entry.value
	end
	local loadKey = side .. key
	if self.loading[loadKey] then
		error("Requested module was required recursively: " .. native:GetFullName(), 2)
	end
	self.loading[loadKey] = true
	local fn = self:runSource(m, side, true)
	local results = table.pack(pcall(fn))
	self.loading[loadKey] = nil
	if not results[1] then
		error(
			string.format(
				"%s\nRequested module experienced an error while loading: %s",
				tostring(results[2]),
				native:GetFullName()
			),
			0
		)
	end
	if results.n ~= 2 then
		error("Module code did not return exactly one value: " .. native:GetFullName(), 2)
	end
	cache[key] = { value = results[2] }
	return results[2]
end

-- Skript als eigenen Thread starten (wie Roblox es tut)
function Sandbox:startScript(p, side: string)
	local ok, fn = pcall(function()
		return self:runSource(p, side, false)
	end)
	if not ok then
		self:issue("error", "syntax", tostring(fn), nil, side)
		return
	end
	self.sched:spawnAs(side, fn)
end

local function scriptSide(native): string?
	if native.ClassName == "LocalScript" then
		return "client"
	end
	if native.ClassName == "Script" then
		local ok, ctx = pcall(function()
			return native.RunContext
		end)
		if ok and ctx == Enum.RunContext.Client then
			return "client"
		end
		return "server"
	end
	return nil
end

local function isDisabled(native): boolean
	local ok, v = pcall(function()
		return native.Disabled
	end)
	if ok and v then
		return true
	end
	ok, v = pcall(function()
		return native.Enabled
	end)
	return ok and v == false
end

function Sandbox:serverScripts()
	local out = {}
	for _, svcName in { "ServerScriptService", "Workspace" } do
		local svc = self.native[self.game]:GetService(svcName)
		for _, d in svc:GetDescendants() do
			if scriptSide(d) == "server" and not isDisabled(d) then
				table.insert(out, self:wrap(d))
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------
-- Spielablauf

function Sandbox:startServer()
	for _, s in self:serverScripts() do
		self:startScript(s, "server")
	end
	self.sched:flushDeferred()
end

function Sandbox:spawnCharacter()
	local player = self.player
	local old = player.Character
	if old then
		old:Destroy()
	end
	local sched = self.sched
	local prev = sched.side
	sched.side = "server"
	local model = self:wrap(RInstance.new("Model"))
	model.Name = player.Name
	local root = self:wrap(RInstance.new("Part"))
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	local head = self:wrap(RInstance.new("Part"))
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = CFrame.new(0, 4.5, 0)
	head.Parent = model
	local torso = self:wrap(RInstance.new("Part"))
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = CFrame.new(0, 3, 0)
	torso.Parent = model
	local humanoid = self:wrap(RInstance.new("Humanoid"))
	for k, v in DEFAULTS.Humanoid do
		if v ~= false then
			pcall(function()
				humanoid[k] = v
			end)
		end
	end
	humanoid.Parent = model
	local animator = self:wrap(RInstance.new("Animator"))
	animator.Parent = humanoid
	model.PrimaryPart = root
	model.Parent = self.workspace
	player.Character = model
	sched.side = prev
	self:signal(player, "CharacterAdded"):Fire(model)
	return model
end

function Sandbox:joinPlayer(name: string?)
	local players = self.game:GetService("Players")
	local player = self:wrap(RInstance.new("Player"))
	player.Name = name or "Tester"
	for k, v in DEFAULTS.Player do
		pcall(function()
			player[k] = v
		end)
	end
	self:wrap(RInstance.new("PlayerGui")).Parent = player
	self:wrap(RInstance.new("Backpack")).Parent = player
	local scripts = self:wrap(RInstance.new("PlayerScripts"))
	scripts.Parent = player
	player.Parent = players
	self.player = player
	self:signal(players, "PlayerAdded"):Fire(player)
	self.sched:flushDeferred()

	-- StarterGui → PlayerGui, StarterPlayerScripts → PlayerScripts
	local starterGui = self.native[self.game]:GetService("StarterGui")
	for _, c in starterGui:GetChildren() do
		if c:IsA("LayerCollector") then
			c:Clone().Parent = self.native[player.PlayerGui]
		end
	end
	local starterPlayer = self.native[self.game]:GetService("StarterPlayer")
	local sps = starterPlayer:FindFirstChild("StarterPlayerScripts")
	local clientScripts = {}
	if sps then
		for _, c in sps:GetChildren() do
			local copy = c:Clone()
			copy.Parent = self.native[scripts]
			table.insert(clientScripts, copy)
		end
	end
	local replicatedFirst = self.native[self.game]:GetService("ReplicatedFirst")
	for _, d in replicatedFirst:GetDescendants() do
		if scriptSide(d) == "client" and not isDisabled(d) then
			self:startScript(self:wrap(d), "client")
		end
	end
	for _, c in clientScripts do
		for _, d in { c, table.unpack(c:GetDescendants()) } do
			if scriptSide(d) == "client" and not isDisabled(d) then
				self:startScript(self:wrap(d), "client")
			end
		end
	end
	self.sched:flushDeferred()
	return player
end

function Sandbox:boot(opts: { seconds: number?, character: boolean? }?)
	local o = opts or {}
	self:startServer()
	self:joinPlayer()
	if o.character ~= false then
		self.sched:run(0.1)
		self:spawnCharacter()
	end
	self.sched:run(o.seconds or 3)
end

function Sandbox:run(seconds: number)
	self.sched:run(seconds)
end

function Sandbox:setViewport(v: Vector2, touch: boolean?)
	self.viewport = v
	if touch ~= nil then
		self.touch = touch
	end
	self.layout = Layout.new(v, 58)
	self.sched:step(1 / 30)
end

-- Knopf „drücken“: alle passenden Ereignisse in Roblox-Reihenfolge feuern
function Sandbox:click(p)
	local sched = self.sched
	local input = {
		UserInputType = Enum.UserInputType.MouseButton1,
		UserInputState = Enum.UserInputState.Begin,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.zero,
		Delta = Vector3.zero,
	}
	for _, name in { "MouseEnter", "InputBegan", "MouseButton1Down" } do
		local sig = self:signalIfExists(p, name)
		if sig then
			sig:Fire(if name == "InputBegan" then input else 0, 0)
		end
	end
	sched:flushDeferred()
	input.UserInputState = Enum.UserInputState.End
	for _, name in
		{ "MouseButton1Up", "InputEnded", "MouseButton1Click", "Activated", "MouseLeave" }
	do
		local sig = self:signalIfExists(p, name)
		if sig then
			sig:Fire(
				if name == "InputEnded" or name == "Activated" then input else 0,
				if name == "Activated" then 1 else 0
			)
		end
	end
	sched:flushDeferred()
end

function Sandbox:hasHandlers(p): boolean
	for _, name in
		{ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "InputBegan" }
	do
		local sig = self:signalIfExists(p, name)
		if sig and sig:hasListeners() then
			return true
		end
	end
	return false
end

function Sandbox:pressKey(keyCode, processed: boolean?)
	local uis = self.game:GetService("UserInputService")
	local input = {
		UserInputType = Enum.UserInputType.Keyboard,
		UserInputState = Enum.UserInputState.Begin,
		KeyCode = keyCode,
		Position = Vector3.zero,
		Delta = Vector3.zero,
	}
	local began = self:signalIfExists(uis, "InputBegan")
	if began then
		began:Fire(input, processed or false)
	end
	for name, a in self.actions do
		for _, k in a.inputs do
			if k == keyCode then
				self.sched:spawnAs(a.side, a.fn, name, Enum.UserInputState.Begin, input)
			end
		end
	end
	self.sched:flushDeferred()
	input.UserInputState = Enum.UserInputState.End
	local ended = self:signalIfExists(uis, "InputEnded")
	if ended then
		ended:Fire(input, processed or false)
	end
	self.sched:flushDeferred()
end

-- Instanz per Pfad ("ServerScriptService.Server.Systems.Inventory")
function Sandbox:find(path: string)
	local node = self.native[self.game]
	for part in path:gmatch("[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node and self:wrap(node)
end

-- Code auf der Server- oder Client-Seite ausführen (dieselben Modul-Instanzen wie das laufende Spiel)
function Sandbox:runAs(side: string, fn: (require: (string) -> any) -> ())
	self.sched:spawnAs(side, function()
		fn(function(path)
			local m = self:find(path)
			assert(m, "Modul nicht gefunden: " .. path)
			return self:require(m, side)
		end)
	end)
	self.sched:flushDeferred()
end

Sandbox.Random = { new = newRandom }

function Sandbox:playerGui()
	return self.player and self.player:FindFirstChild("PlayerGui")
end

function Sandbox:nativeOf(p)
	return self.native[p]
end

function Sandbox:counts()
	local c = { error = 0, warn = 0, info = 0 }
	for _, i in self.issues do
		c[i.level] += 1
	end
	return c
end

return Sandbox
