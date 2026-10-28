-- Gebiete im Atlas: Freischalt-Regel, Gegner-Mix je Gebiet und Rift-Start über das Remote.
local Atlas = require("ReplicatedStorage.Shared.Atlas")

local function bests(t: { [string]: number }): (string) -> number
	return function(id)
		return t[id] or 0
	end
end

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function enter(id: string?)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", id)
	end)
	sim:run(0.5)
end

local function leave()
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
	end)
	sim:run(0.5)
end

describe("Atlas-Regeln", function()
	it("öffnet Gebiete erst nach der Tiefe davor im Vorgänger", function()
		expect(Atlas.isOpen("gruene_ebenen", bests({}))).toBe(true)
		expect(Atlas.isOpen("kristallhoehlen", bests({}))).toBe(false)
		expect(Atlas.isOpen("kristallhoehlen", bests({ gruene_ebenen = 4 }))).toBe(false)
		expect(Atlas.isOpen("kristallhoehlen", bests({ gruene_ebenen = 5 }))).toBe(true)
		expect(Atlas.isOpen("pilzsumpf", bests({ gruene_ebenen = 5 }))).toBe(false)
		expect(Atlas.isOpen("pilzsumpf", bests({ gruene_ebenen = 10 }))).toBe(true)
		-- Feuerwüste hat zwei Wege
		expect(Atlas.isOpen("feuerwueste", bests({ pilzsumpf = 15 }))).toBe(true)
		expect(Atlas.isOpen("feuerwueste", bests({ kristallhoehlen = 15 }))).toBe(true)
		expect(Atlas.isOpen("feuerwueste", bests({ gruene_ebenen = 99 }))).toBe(false)
		expect(Atlas.isOpen("gibtsnicht", bests({}))).toBe(false)
	end)

	it("hat lückenlose Start-Tiefen entlang der Pfade", function()
		for _, r in Atlas.Regions do
			for _, id in r.next do
				expect(Atlas.ById[id]).never.toBeNil()
				expect(Atlas.ById[id].depth).toBeGreaterThan(r.depth)
			end
		end
	end)
end)

describe("Gebiete im Spiel", function()
	it("kennt alle Gegner und Bosse der Gebiete", function()
		sim:boot({ seconds = 2 })
		local missing = server(function(req)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local out = {}
			for _, r in Atlas.Regions do
				for _, k in r.enemies do
					if not Enemies.has(k) then
						table.insert(out, k)
					end
				end
				if not Enemies.has(r.bossKind) then
					table.insert(out, r.bossKind)
				end
			end
			return out
		end)
		expect(#missing).toBe(0)
	end)

	it("lehnt gesperrte Gebiete ab", function()
		enter("kristallhoehlen")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		enter("quatsch")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
	end)

	it("startet ein freigeschaltetes Gebiet auf seiner Tiefe mit seinem Gegner-Mix", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Data").get(player).atlas.gruene_ebenen = 5
		end)
		enter("kristallhoehlen")
		expect(sim.player:GetAttribute("RiftRegion")).toBe("kristallhoehlen")
		expect(sim.player:GetAttribute("RiftDepth")).toBe(6)
		local names = server(function()
			local out = {}
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				out[e.Name] = true
			end
			return out
		end)
		local allowed = { Kristallschleim = true, Kristallkrabbe = true, ["Fledermaus-Lampion"] = true }
		local count = 0
		for name in names do
			count += 1
			expect(allowed[name]).toBe(true)
		end
		expect(count).toBeGreaterThan(0)
		sim:run(4) -- KI greift an (Telegraph, Geschosse)
		leave()
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
	end)

	it("lässt jeden Gegnertyp ohne Fehler kämpfen", function()
		server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local at = if root then root.Position else Vector3.zero
			for i, name in Enemies.kindNames() do
				local a = i / 8 * math.pi * 2
				Enemies.spawn(name, at + Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10), 3)
			end
		end)
		sim:run(8)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear()
		end)
		sim:run(0.2)
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
