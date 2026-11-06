-- Endless surroundings (docs/specs/WORLD-MAPS.md §2): the Hub and every arena get a horizon of
-- pure scenery around them that never blocks, collides or casts shadows.
local Atlas = require("ReplicatedStorage.Shared.Atlas")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req))
	end)
	return table.unpack(out, 1, out.n)
end

-- Horizon parts in a map: count, and how many of them could block or cast shadows
local function audit(folder: Instance): (number, number)
	local n, bad = 0, 0
	for _, f in folder:GetChildren() do
		if f:IsA("Folder") and f:GetAttribute("Horizon") then
			for _, d in f:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
					if d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow then
						bad += 1
					end
				end
			end
		end
	end
	return n, bad
end

local PART_BUDGET = 450 -- ~+5% over the old maximum of 430 parts per horizon

describe("Horizon", function()
	it("surrounds the Hub and every arena with scenery that never blocks", function()
		sim:boot({ seconds = 1 })
		local n, bad = server(function()
			return audit(workspace.Lumenhaven)
		end)
		expect(n).toBeGreaterThan(50)
		expect(bad).toBe(0)
		for _, region in Atlas.Regions do
			local rn, rb = server(function(req)
				local World = req("ServerScriptService.Server.Systems.World")
				World.build(Atlas.ById[region.id], 2)
				local a, b = audit(workspace.Arena:FindFirstChild("Region_" .. region.id .. "_2"))
				World.release(2)
				return a, b
			end)
			expect(rn).toBeGreaterThan(20)
			expect(rn).toBeLessThan(PART_BUDGET) -- phone budget: before the redesign the max was 430
			expect(rb).toBe(0)
		end
	end)

	it(
		"gives each region its own horizon kind (only the Rifts that share a look may repeat)",
		function()
			local kinds = server(function(req)
				local World = req("ServerScriptService.Server.Systems.World")
				local seen = {}
				local distinct = 0
				for _, region in Atlas.Regions do
					local kind = World.Looks[region.id].horizon.kind or "mountains"
					if not seen[kind] then
						seen[kind] = true
						distinct += 1
					end
				end
				return distinct
			end)
			expect(kinds).toBe(#Atlas.Regions)
		end
	)
end)
