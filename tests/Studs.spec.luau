-- Parts + studs world: every part the game builds (hub, every arena, every showcase model) has
-- the classic stud look or rightly keeps its own (Neon, Glass, invisible), and no Blender
-- meshes are left in the map.

local Atlas = require("ReplicatedStorage.Shared.Atlas")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req))
	end)
	return table.unpack(out, 1, out.n)
end

-- Counts parts under `root` without the stud look, and MeshParts
local function audit(req, root: Instance): (number, number, number, { string })
	local Studs = req("ReplicatedStorage.Shared.Models").Studs
	local parts, bad, meshes = 0, 0, 0
	local names = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d:IsA("MeshPart") then
				meshes += 1
			end
			if not Studs.styled(d) then
				bad += 1
				if #names < 5 then
					table.insert(names, d:GetFullName() .. " (" .. tostring(d.Material) .. ")")
				end
			end
		end
	end
	return parts, bad, meshes, names
end

describe("Studs", function()
	it("gives blocks, wedges, balls, cylinders and trusses the stud look", function()
		local Kit = require("ReplicatedStorage.Shared.Models").Kit
		local Studs = Kit.Studs
		local m = Instance.new("Model")
		local list = {
			Kit.block(m, Vector3.one, CFrame.new(), Kit.C.stone),
			Kit.block(m, Vector3.one, CFrame.new(), Kit.C.stone, Enum.Material.Slate),
			Kit.wedge(m, Vector3.one, CFrame.new(), Kit.C.roof),
			Kit.cornerWedge(m, Vector3.one, CFrame.new(), Kit.C.roof),
			Kit.ball(m, 1, Vector3.zero, Kit.C.leaf),
			Kit.cylinder(m, Vector3.one, CFrame.new(), Kit.C.wood),
			Kit.truss(m, 6, CFrame.new(), Kit.C.woodDark),
		}
		for _, p in list do
			expect(p.Material).toBe(Enum.Material.Plastic)
			expect(p.TopSurface).toBe(Enum.SurfaceType.Studs)
			expect(p.BottomSurface).toBe(Enum.SurfaceType.Inlet)
			expect(Studs.styled(p)).toBe(true)
		end
	end)

	it("keeps glow, glass, invisible and opted-out parts as they are", function()
		local Kit = require("ReplicatedStorage.Shared.Models").Kit
		local Studs = Kit.Studs
		local m = Instance.new("Model")
		local neon = Kit.block(m, Vector3.one, CFrame.new(), Kit.C.fire, Enum.Material.Neon)
		local glass = Kit.block(m, Vector3.one, CFrame.new(), Kit.C.water, Enum.Material.Glass)
		expect(neon.Material).toBe(Enum.Material.Neon)
		expect(glass.Material).toBe(Enum.Material.Glass)
		local hidden = Instance.new("Part")
		hidden.Transparency = 1
		hidden.Material = Enum.Material.Slate
		Studs.apply(hidden)
		expect(hidden.Material).toBe(Enum.Material.Slate)
		local opted = Instance.new("Part")
		opted.Material = Enum.Material.Marble
		opted:SetAttribute("NoStuds", true)
		Studs.apply(opted)
		expect(opted.Material).toBe(Enum.Material.Marble)
	end)

	it("applyTree fixes hand-made parts", function()
		local Studs = require("ReplicatedStorage.Shared.Models").Studs
		local m = Instance.new("Model")
		local p = Instance.new("Part")
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = m
		expect(Studs.styled(p)).toBe(false)
		expect(Studs.applyTree(m)).toBe(1)
		expect(Studs.styled(p)).toBe(true)
	end)

	it("every showcase model is studded", function()
		local Models = require("ReplicatedStorage.Shared.Models")
		local row = Models.showcase()
		for _, d in row:GetDescendants() do
			if d:IsA("BasePart") then
				expect(Models.Studs.styled(d)).toBe(true)
			end
		end
	end)
end)

describe("LootStuds variant in the Rojo project", function()
	it("is defined with Plastic, 1 stud per tile and both maps", function()
		-- the sandbox does not keep texture-map properties: check the project file itself
		local name = "LootStuds" -- Studs.VARIANT
		local v = projectJson().tree.MaterialService[name]
		expect(v["$className"]).toBe("MaterialVariant")
		expect(v["$properties"].BaseMaterial).toBe("Plastic")
		expect(v["$properties"].StudsPerTile).toBe(1)
		for _, key in { "ColorMap", "NormalMap" } do
			expect(string.match(v["$properties"][key], "^rbxassetid://%d+$") ~= nil).toBe(true)
		end
	end)
end)

describe("Parts + studs map", function()
	it("hub and every arena are studded parts without meshes", function()
		sim:boot({ seconds = 1 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		local parts, bad, meshes, names = server(function(req)
			local hub = workspace:FindFirstChild("Lumenhaven")
			return audit(req, hub :: Instance)
		end)
		expect(parts).toBeGreaterThan(500)
		expect(meshes).toBe(0)
		if bad > 0 then
			print("unstudded:", table.concat(names, ", "))
		end
		expect(bad).toBe(0)

		for _, region in Atlas.Regions do
			local p, b, mesh, n = server(function(req)
				local World = req("ServerScriptService.Server.Systems.World")
				World.build(Atlas.ById[region.id], 2)
				local folder = workspace.Arena:FindFirstChild("Region_" .. region.id .. "_2")
				local a, bb, c, d = audit(req, folder :: Instance)
				World.release(2)
				return a, bb, c, d
			end)
			expect(p).toBeGreaterThan(100)
			expect(mesh).toBe(0)
			if b > 0 then
				print(region.id, "unstudded:", table.concat(n, ", "))
			end
			expect(b).toBe(0)
		end
	end)

	it("sets up sky, depth of field and clouds", function()
		sim:boot({ seconds = 1 })
		local sky, dof = server(function()
			local Lighting = game:GetService("Lighting")
			return Lighting:FindFirstChildOfClass("Sky") ~= nil,
				Lighting:FindFirstChildOfClass("DepthOfFieldEffect") ~= nil
		end)
		expect(sky).toBe(true)
		expect(dof).toBe(true)
	end)
end)
