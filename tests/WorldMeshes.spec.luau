-- Meshy world kit (docs/specs/WORLD-MESHES.md): id table rules, mesh fit, and the part fallback.
-- Without uploaded ids every prop keeps its studded parts; a loaded mesh dresses the prop,
-- keeps its name and pivot, and leaves invisible stand-ins only where something collides.
local Atlas = require("ReplicatedStorage.Shared.Atlas")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req))
	end)
	return table.unpack(out, 1, out.n)
end

-- Height (min Y, max Y) of the parts under `root`, from part centres and sizes (unrotated props)
local function span(root: Instance, skip: Instance?): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not (skip and d:IsDescendantOf(skip)) then
			lo = math.min(lo, d.Position.Y - d.Size.Y / 2)
			hi = math.max(hi, d.Position.Y + d.Size.Y / 2)
		end
	end
	return lo, hi
end

-- A stand-in for a loaded asset: one tall thin part away from the origin
local function fakeAsset(): Model
	local m = Instance.new("Model")
	local p = Instance.new("Part")
	p.Size = Vector3.new(2, 8, 2)
	p.CFrame = CFrame.new(5, 10, 5)
	p.Parent = m
	return m
end

describe("WorldMeshes", function()
	it("uses valid zones, whole non-negative ids and never names a functional model", function()
		local WorldMeshes = require("ReplicatedStorage.Shared.WorldMeshes")
		local n = 0
		for key, entry in WorldMeshes.ids do
			n += 1
			local zone, name = string.match(key, "^([%w_]+)/(%w+)$")
			if zone then
				expect(WorldMeshes.ZONES[zone]).toBe(true)
			else
				name = key
			end
			expect(WorldMeshes.FUNCTIONAL[name :: string]).toBe(nil)
			expect(entry.model >= 0 and entry.model % 1 == 0).toBe(true)
		end
		expect(n).toBeGreaterThanOrEqual(40)
	end)

	it("prefers the zone key, falls back to the plain name, else keeps parts", function()
		local WorldMeshes = require("ReplicatedStorage.Shared.WorldMeshes")
		local have = { Rock = true, ["crystal_caves/Rock"] = true }
		local function has(k: string): boolean
			return have[k] == true
		end
		expect(WorldMeshes.key("Rock", "crystal_caves", has)).toBe("crystal_caves/Rock")
		expect(WorldMeshes.key("Rock", "fire_desert", has)).toBe("Rock")
		expect(WorldMeshes.key("Rock", nil, has)).toBe("Rock")
		expect(WorldMeshes.key("Tree", "hub", has)).toBe(nil)
		have.RiftPortal = true
		expect(WorldMeshes.key("RiftPortal", nil, has)).toBe(nil)
	end)

	it("keeps only small Neon accents visible with glow", function()
		local WorldMeshes = require("ReplicatedStorage.Shared.WorldMeshes")
		expect(WorldMeshes.glows(Vector3.new(0.7, 0.9, 0.7), 6)).toBe(true) -- lamp glass
		expect(WorldMeshes.glows(Vector3.new(1.1, 4.2, 1.1), 5)).toBe(false) -- crystal spike
		expect(WorldMeshes.glows(Vector3.new(1, 1, 1), 0)).toBe(false)
	end)

	it("fits the mesh to the part height and caps its footprint", function()
		local WorldMeshes = require("ReplicatedStorage.Shared.WorldMeshes")
		expect(WorldMeshes.fit(Vector3.new(4, 10, 4), Vector3.new(1, 5, 1))).toBe(2)
		-- a wide mesh: height would give 20 studs width, room is 4 * 1.25 = 5
		local s = WorldMeshes.fit(Vector3.new(4, 10, 4), Vector3.new(4, 2, 4))
		expect(math.abs(s * 4 - 4 * WorldMeshes.FOOTPRINT_SLACK) < 1e-6).toBe(true)
		expect(WorldMeshes.fit(Vector3.new(4, 10, 4), Vector3.new(1, 0, 1))).toBe(1)
	end)
end)

describe("MeshKit", function()
	it("leaves props untouched when no mesh is loaded", function()
		local count, mesh = server(function(req)
			local MeshKit = req("ServerScriptService.Server.Util.MeshKit")
			local Models = req("ReplicatedStorage.Shared.Models")
			MeshKit.clear()
			local tree = Models.Props.tree(1)
			local before = #tree:GetDescendants()
			MeshKit.swap(tree, "green_plains")
			return #tree:GetDescendants() - before, tree:FindFirstChild(MeshKit.MESH)
		end)
		expect(count).toBe(0)
		expect(mesh).toBe(nil)
	end)

	it("dresses a prop with the mesh at the part height and hides colliding parts", function()
		local ok, height, meshHeight, visible, name, drop = server(function(req)
			local MeshKit = req("ServerScriptService.Server.Util.MeshKit")
			local Models = req("ReplicatedStorage.Shared.Models")
			MeshKit.clear()
			MeshKit.setTemplate("Tree", fakeAsset(), { model = 0 })
			local tree = Models.Props.tree(1.5)
			local lo, hi = span(tree)
			MeshKit.swap(tree, "green_plains")
			local mesh = tree:FindFirstChild(MeshKit.MESH)
			local mlo, mhi = span(mesh :: Instance)
			local shown = 0
			for _, d in tree:GetDescendants() do
				if d:IsA("BasePart") and not d:IsDescendantOf(mesh :: Instance) then
					if d.Transparency < 1 then
						shown += 1
					end
				end
			end
			MeshKit.clear()
			return mesh ~= nil, hi - lo, mhi - mlo, shown, tree.Name, mlo - lo
		end)
		expect(ok).toBe(true)
		expect(math.abs(height - meshHeight) < 1e-3).toBe(true)
		expect(visible).toBe(0)
		expect(name).toBe("Tree")
		expect(math.abs(drop) < 1e-3).toBe(true) -- the mesh stands where the parts stood
	end)

	it("hides Neon bodies under the mesh even with glow", function()
		local shown = server(function(req)
			local MeshKit = req("ServerScriptService.Server.Util.MeshKit")
			local Models = req("ReplicatedStorage.Shared.Models")
			MeshKit.clear()
			MeshKit.setTemplate("CrystalCluster", fakeAsset(), { model = 0, glow = true })
			local m = Models.Props.crystalCluster(1, 3)
			MeshKit.swap(m, nil)
			local mesh = m:FindFirstChild(MeshKit.MESH) :: Instance
			local n = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and not d:IsDescendantOf(mesh) and d.Transparency < 1 then
					n += 1
				end
			end
			MeshKit.clear()
			return n
		end)
		expect(shown).toBe(0)
	end)

	it("dresses arena props from a zone template", function()
		sim:boot({ seconds = 1 })
		local meshes, keys = server(function(req)
			local MeshKit = req("ServerScriptService.Server.Util.MeshKit")
			local World = req("ServerScriptService.Server.Systems.World")
			MeshKit.clear()
			MeshKit.setTemplate("crystal_caves/Rock", fakeAsset(), { model = 0 })
			World.build(Atlas.ById.crystal_caves, 2)
			local folder = workspace.Arena:FindFirstChild("Region_crystal_caves_2")
			local n, k = 0, {}
			for _, d in (folder :: Instance):GetDescendants() do
				if d:IsA("Model") and d:GetAttribute("MeshKey") then
					n += 1
					k[d:GetAttribute("MeshKey")] = true
				end
			end
			World.release(2)
			MeshKit.clear()
			return n, k
		end)
		expect(meshes).toBeGreaterThan(0)
		expect(keys["crystal_caves/Rock"]).toBe(true)
	end)
end)
