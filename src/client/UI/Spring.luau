--!strict
-- Damped springs for UI properties (hover, press, selection, sliding tab marker, bars, window pop).
-- One RenderStepped connection drives every running spring and disconnects when all have settled.
--   Spring.target(frame, { Position = UDim2.fromOffset(10, 0) }, "Bouncy")
--   Spring.snap(frame, { Size = ... }) -- jump without motion (first layout)
-- Supported value types: number, UDim, UDim2, Vector2, Color3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local Spring = {}

export type Preset = "Snappy" | "Soft" | "Bouncy"

type Kind = "number" | "UDim" | "UDim2" | "Vector2" | "Color3"
type State = {
	inst: Instance,
	prop: string,
	kind: Kind,
	pos: { number },
	vel: { number },
	goal: { number },
	speed: number,
	damping: number,
}

local EPSILON = 1e-3
local MAX_DT = 1 / 20
local STEP = 1 / 240

local active: { [string]: State } = {}
local conn: RBXScriptConnection? = nil
local ids: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local nextId = 0

local function keyOf(inst: Instance, prop: string): string
	local id = ids[inst]
	if not id then
		nextId += 1
		id = tostring(nextId)
		ids[inst] = id
	end
	return id .. "." .. prop
end

local function pack(v: any): (Kind?, { number })
	local t = typeof(v)
	if t == "number" then
		return "number", { v }
	elseif t == "UDim" then
		return "UDim", { v.Scale, v.Offset }
	elseif t == "UDim2" then
		return "UDim2", { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "Vector2" then
		return "Vector2", { v.X, v.Y }
	elseif t == "Color3" then
		return "Color3", { v.R, v.G, v.B }
	end
	return nil, {}
end

local function unpackValue(kind: Kind, p: { number }): any
	if kind == "number" then
		return p[1]
	elseif kind == "UDim" then
		return UDim.new(p[1], p[2])
	elseif kind == "UDim2" then
		return UDim2.new(p[1], p[2], p[3], p[4])
	elseif kind == "Vector2" then
		return Vector2.new(p[1], p[2])
	end
	return Color3.new(math.clamp(p[1], 0, 1), math.clamp(p[2], 0, 1), math.clamp(p[3], 0, 1))
end

-- Settled = close to the goal and nearly still (scaled to the size of the values: pixels vs. 0..1)
local function settled(s: State): boolean
	for i, g in s.goal do
		local scale = math.max(1, math.abs(g)) * EPSILON
		if math.abs(s.pos[i] - g) > scale or math.abs(s.vel[i]) > scale * 10 then
			return false
		end
	end
	return true
end

local function step(dt: number)
	dt = math.min(dt, MAX_DT)
	for key, s in active do
		if not s.inst.Parent then
			active[key] = nil
			continue
		end
		-- Semi-implicit Euler in small sub-steps (stable for stiff springs and frame drops)
		local w, z = s.speed, s.damping
		local left = dt
		while left > 0 do
			local h = math.min(STEP, left)
			left -= h
			for i, g in s.goal do
				local a = w * w * (g - s.pos[i]) - 2 * z * w * s.vel[i]
				s.vel[i] += a * h
				s.pos[i] += s.vel[i] * h
			end
		end
		if settled(s) then
			for i, g in s.goal do
				s.pos[i] = g
			end
			active[key] = nil
		end
		local inst: any = s.inst
		inst[s.prop] = unpackValue(s.kind, s.pos)
	end
	if next(active) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function ensureRunning()
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

-- Spring the properties toward their goals (keeps the current velocity when retargeted)
function Spring.target(inst: Instance, goals: { [string]: any }, preset: Preset?)
	local p = Theme.Flat.Spring[preset or "Snappy"]
	for prop, goal in goals do
		local kind, g = pack(goal)
		if not kind then
			continue
		end
		local key = keyOf(inst, prop)
		local s = active[key]
		if s and s.kind == kind then
			s.goal = g
			s.speed = p.speed
			s.damping = p.damping
		else
			local any: any = inst
			local _, current = pack(any[prop])
			local vel = table.create(#g, 0)
			local state: State = {
				inst = inst,
				prop = prop,
				kind = kind :: Kind,
				pos = if #current == #g then current else table.clone(g),
				vel = vel,
				goal = g,
				speed = p.speed,
				damping = p.damping,
			}
			active[key] = state
		end
	end
	ensureRunning()
end

-- Set the properties at once and stop any spring on them
function Spring.snap(inst: Instance, values: { [string]: any })
	local any: any = inst
	for prop, value in values do
		active[keyOf(inst, prop)] = nil
		any[prop] = value
	end
end

-- Push a running spring (e.g. a "pop" when an item is selected): adds velocity to a number property
function Spring.impulse(inst: Instance, prop: string, velocity: number, preset: Preset?)
	local any: any = inst
	local current = any[prop]
	if typeof(current) ~= "number" then
		return
	end
	local key = keyOf(inst, prop)
	local s = active[key]
	if not s then
		Spring.target(inst, { [prop] = current }, preset)
		s = active[key]
	end
	if s then
		s.vel[1] += velocity
		ensureRunning()
	end
end

return Spring
