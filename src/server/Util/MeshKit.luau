--!strict
-- Meshy world kit loader (ids: Shared/WorldMeshes, prompts: docs/specs/WORLD-MESHES.md).
-- MeshKit.preload() loads every uploaded Model asset once (InsertService, parallel, with a
-- timeout); MeshKit.swap(model, zone) then dresses a freshly built part model with a clone of
-- the mesh. The part model keeps its name, pivot and attributes, so placement code and other
-- systems see the same model as before:
--  * the mesh is scaled to the part model's height (WorldMeshes.fit) and stands bottom-centred
--    on the part model's footprint, in a child Model "Mesh" (no collision, no queries);
--  * parts that collide, are queried, or hold lights/particles/prompts stay as invisible
--    stand-ins, so movement, dash probes and effects work exactly as with the part look;
--  * Neon parts stay visible when the entry has glow = true (crystal cores, lamps);
--  * every other part is removed.
-- An id of 0, a failed load or an unknown name returns the part model untouched.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldMeshes = require(ReplicatedStorage.Shared.WorldMeshes)

local MeshKit = {}

MeshKit.LOAD_TIMEOUT = 15 -- seconds preload waits for all assets before building without them
MeshKit.MESH = "Mesh" -- name of the child Model that holds the mesh

type Template = { parts: { BasePart }, size: Vector3, entry: WorldMeshes.Entry }

local templates: { [string]: Template } = {}
local state: "idle" | "loading" | "done" = "idle"

-- Bounding box of `parts` in the frame `frame`: (min, max)
local function bounds(parts: { BasePart }, frame: CFrame): (Vector3, Vector3)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, p in parts do
		local cf = frame:ToObjectSpace(p.CFrame)
		local h = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
					lo = lo:Min(c)
					hi = hi:Max(c)
				end
			end
		end
	end
	return lo, hi
end

local function partsOf(root: Instance): { BasePart }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- Turns a loaded asset into a template: loose parts, bottom centre at the origin, turned by yaw
local function prepare(asset: Instance, entry: WorldMeshes.Entry): Template?
	local parts = partsOf(asset)
	if #parts == 0 then
		return nil
	end
	local lo, hi = bounds(parts, CFrame.identity)
	local base = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local turn = CFrame.Angles(0, math.rad(entry.yaw or 0), 0)
	for _, p in parts do
		p.Parent = nil
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = turn * (p.CFrame - base)
		p:SetAttribute("NoStuds", true) -- keeps its painted texture (Studs.keeps)
		if entry.texture and entry.texture > 0 and p:IsA("MeshPart") and p.TextureID == "" then
			p.TextureID = "rbxassetid://" .. entry.texture
		end
	end
	local tlo, thi = bounds(parts, CFrame.identity)
	return { parts = parts, size = thi - tlo, entry = entry }
end

local function load(key: string, entry: WorldMeshes.Entry)
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(entry.model)
	end)
	if not ok or not asset then
		warn("[MeshKit] could not load " .. key .. " (" .. entry.model .. "): " .. tostring(asset))
		return
	end
	local t = prepare(asset, entry)
	asset:Destroy()
	if t then
		templates[key] = t
	else
		warn("[MeshKit] " .. key .. " has no parts")
	end
end

-- Loads every uploaded mesh once; later calls wait for the first one. Yields only when ids exist.
function MeshKit.preload()
	if state == "done" then
		return
	end
	local started = os.clock()
	if state == "loading" then
		while state == "loading" and os.clock() - started < MeshKit.LOAD_TIMEOUT do
			task.wait(0.05)
		end
		return
	end
	state = "loading"
	local pending = 0
	for key, entry in WorldMeshes.uploaded() do
		pending += 1
		task.spawn(function()
			load(key, entry)
			pending -= 1
		end)
	end
	while pending > 0 and os.clock() - started < MeshKit.LOAD_TIMEOUT do
		task.wait(0.05)
	end
	if pending > 0 then
		warn("[MeshKit] " .. pending .. " meshes still loading after the timeout; parts used")
	end
	state = "done"
end

-- For tests: register a template as if it were loaded (`asset` = model holding the mesh parts)
function MeshKit.setTemplate(key: string, asset: Instance, entry: WorldMeshes.Entry)
	local t = prepare(asset, entry)
	templates[key] = t :: any
	state = "done"
end

function MeshKit.clear()
	table.clear(templates)
	state = "idle"
end

local function keeps(p: BasePart, glow: boolean): boolean
	if p.CanCollide or p.CanQuery then
		return true
	end
	if glow and p.Material == Enum.Material.Neon and p.Transparency < 1 then
		return true
	end
	for _, d in p:GetDescendants() do
		if
			d:IsA("Light")
			or d:IsA("ParticleEmitter")
			or d:IsA("ProximityPrompt")
			or d:IsA("Attachment")
		then
			return true
		end
	end
	return false
end

-- Dresses `model` (a part model, not yet parented, pivot = its base) with the mesh for its name
-- in `zone`. Returns the same model; without a loaded mesh it is left as it is.
function MeshKit.swap(model: Model, zone: string?): Model
	local key = WorldMeshes.key(model.Name, zone, function(k: string): boolean
		return templates[k] ~= nil
	end)
	local t = key and templates[key]
	if not key or not t then
		return model
	end
	local entry = t.entry
	local pivot = model:GetPivot()
	local own = partsOf(model)
	if #own == 0 then
		return model
	end
	local lo, hi = bounds(own, pivot)
	local s = WorldMeshes.fit(hi - lo, t.size) * (entry.scale or 1)
	local base = pivot * CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)

	local glow = entry.glow == true
	for _, p in own do
		if keeps(p, glow) then
			if not (glow and p.Material == Enum.Material.Neon) then
				p.Transparency = 1
				p.CastShadow = false
			end
		else
			p:Destroy()
		end
	end

	local mesh = Instance.new("Model")
	mesh.Name = MeshKit.MESH
	for _, src in t.parts do
		local p = src:Clone()
		p.Size = src.Size * s
		p.CFrame = base * CFrame.new(src.CFrame.Position * s) * src.CFrame.Rotation
		p.Parent = mesh
	end
	mesh.Parent = model
	model:SetAttribute("MeshKey", key)
	return model
end

-- Loaded keys (for the debug check and tests)
function MeshKit.loaded(): { string }
	local out = {}
	for k in templates do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

return MeshKit
