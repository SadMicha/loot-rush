-- The Smoothing: studless grey enemies, arenas that get their studs back as the player clears
-- depths, a boss intro line per region.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local Smoothing = require("ReplicatedStorage.Shared.Smoothing")

describe("Smoothing rules", function()
	it("restores a region over its depths", function()
		expect(Smoothing.restored(6, 0)).toBe(0)
		expect(Smoothing.restored(6, 6)).toBe(1 / Smoothing.SPAN)
		expect(Smoothing.restored(6, 40)).toBe(1)
		expect(Smoothing.arenaShare(1)).toBe(0)
		expect(Smoothing.arenaShare(0)).toBe(Smoothing.ARENA_MAX)
		expect(Smoothing.enemyChance(0) > Smoothing.enemyChance(1)).toBe(true)
	end)

	it("has a boss intro line for every region", function()
		for _, region in Atlas.Regions do
			expect(Smoothing.BossIntro[region.id]).never.toBeNil()
		end
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

describe("Smoothing in game", function()
	it("builds smoothed enemies without studs, tougher than normal ones", function()
		sim:boot({ seconds = 2 })
		local normal, smooth, name, studless = server(function(req)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local Studs = req("ReplicatedStorage.Shared.Models.Studs")
			local a = Enemies.spawn("slime", Vector3.new(0, 0, -40), 5, { run = 33 })
			local b =
				Enemies.spawn("slime", Vector3.new(6, 0, -40), 5, { run = 33, smoothed = true })
			local plain, n = true, 0
			for _, d in b:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("NoStuds") then
					n += 1
					plain = plain
						and d.Material == Enum.Material.SmoothPlastic
						and d.TopSurface ~= Enum.SurfaceType.Studs
						and Studs.styled(d) -- opted out, so the stud audit stays clean
				end
			end
			plain = plain and n > 0
			local out = { a:GetAttribute("MaxHealth"), b:GetAttribute("MaxHealth"), b.Name, plain }
			Enemies.clear(33)
			return table.unpack(out)
		end)
		expect(smooth > normal).toBe(true)
		expect(string.sub(name, 1, 7)).toBe("Smooth ")
		expect(studless).toBe(true)
	end)

	it("smooths part of an untouched arena and restores it again", function()
		local smoothed, back = server(function(req)
			local World = req("ServerScriptService.Server.Systems.World")
			World.build(Atlas.ById.crystal_caves, 2)
			local function count(): number
				local n = 0
				for _, d in
					workspace.Arena:FindFirstChild("Region_crystal_caves_2"):GetDescendants()
				do
					if d:IsA("BasePart") and d:GetAttribute("Smoothed") then
						n += 1
					end
				end
				return n
			end
			World.smooth(2, Smoothing.arenaShare(0))
			local a = count()
			World.smooth(2, Smoothing.arenaShare(1))
			local b = count()
			World.release(2)
			return a, b
		end)
		expect(smoothed > 0).toBe(true)
		expect(back).toBe(0)
	end)

	it("runs without runtime errors", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
