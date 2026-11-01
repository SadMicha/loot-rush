-- Rift-Lauf von vorne bis hinten: Wellen → Boss → Zwischenstand → zurück ins Dorf, Tod,
-- Abbruch. Prüft die Zusammenfassung (Net.RiftResult), Bestwerte und die Rückkehr in den Hub.
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local RiftRun = require("ReplicatedStorage.Shared.RiftRun")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function rift(action: string, id: string?)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer(action, id)
	end)
	sim:run(0.5)
end

local function results(): { any }
	local list = {}
	for _, n in sim.netLog do
		if n.name == "RiftResult" and n.dir == "S→C" then
			table.insert(list, n.args[1])
		end
	end
	return list
end

local function last(): any
	local list = results()
	return list[#list]
end

local function phase(): string
	return sim.player:GetAttribute("RiftPhase") or ""
end

-- Besiegt alle Gegner (wie der Debug-Befehl „slay“), bis der Boss liegt
local function clearDepth()
	for _ = 1, 40 do
		if phase() == "clear" then
			return
		end
		server(function(req, player)
			local Combat = req("ServerScriptService.Server.Systems.Combat")
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				Combat.slay(player, e)
			end
		end)
		sim:run(1)
	end
end

local function hubDistance(): number
	return server(function(req, player)
		local Config = req("ReplicatedStorage.Shared.Config")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return if root then (root.Position - Config.HUB_POS).Magnitude else math.huge
	end)
end

describe("Lauf-Zusammenfassung (rein)", function()
	it("meldet neu freigeschaltete Gebiete und neue Bestwerte", function()
		local best = { gruene_ebenen = 4 }
		local function get(id)
			return best[id] or 0
		end
		local t = RiftRun.newTally("gruene_ebenen", 1, get, 3, 0)
		t.cleared = 5
		RiftRun.addMaterials(t, { candy = 1, dust = 0, quatsch = 5 })
		best.gruene_ebenen = 5
		local s = RiftRun.summary(t, "end", "left", 5, get, 4, 61.4)
		expect(s.bestBefore).toBe(4)
		expect(s.best).toBe(5)
		expect(s.newBest).toBe(true)
		expect(#s.unlocked).toBe(1)
		expect(s.unlocked[1]).toBe("kristallhoehlen")
		expect(s.materials.candy).toBe(1)
		expect((s.materials :: any).quatsch).toBeNil()
		expect(s.seconds).toBe(61)
		expect(s.levelBefore).toBe(3)
		expect(s.level).toBe(4)
	end)

	it("kennt nur Gebiete aus dem Atlas", function()
		for id in
			RiftRun.openSet(function()
				return 99
			end)
		do
			expect(Atlas.ById[id]).never.toBeNil()
		end
	end)
end)

local goldStart = 0

describe("Rift-Lauf im Spiel", function()
	it("schafft Tiefe 1, schickt den Zwischenstand und speichert den Bestwert", function()
		sim:boot({ seconds = 2 })
		goldStart = sim.player:GetAttribute("Gold") or 0
		rift("enter", "gruene_ebenen")
		expect(phase()).toBe("wave")
		expect(hubDistance()).toBeGreaterThan(100) -- in der Arena
		clearDepth()
		expect(phase()).toBe("clear")
		local s = last()
		expect(s).never.toBeNil()
		expect(s.kind).toBe("clear")
		expect(s.region).toBe("gruene_ebenen")
		expect(s.depth).toBe(1)
		expect(s.cleared).toBe(1)
		expect(s.bestBefore).toBe(0)
		expect(s.best).toBe(1)
		expect(s.newBest).toBe(true)
		expect(s.bosses).toBe(1)
		expect(s.kills).toBeGreaterThan(Atlas.ById.gruene_ebenen.depth) -- Wellen + Boss
		expect(s.xp).toBeGreaterThan(0)
		expect(s.materials.candy).toBeGreaterThan(0) -- Boss-Bonbon
		local saved = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).atlas.gruene_ebenen
		end)
		expect(saved).toBe(1)
		expect(sim.player:GetAttribute(Atlas.attr("gruene_ebenen"))).toBe(1)
	end)

	it("sammelt beim Zurückkehren die Beute ein und bringt den Spieler in den Hub", function()
		rift("leave")
		local s = last()
		expect(s.kind).toBe("end")
		expect(s.reason).toBe("left")
		expect(s.gold).toBeGreaterThan(0)
		expect(sim.player:GetAttribute("Gold") - goldStart).toBe(s.gold) -- alles Gold des Laufs
		expect(phase()).toBe("")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		expect(hubDistance()).toBeLessThan(10)
		local left = server(function()
			return #workspace.Beute:GetChildren()
		end)
		expect(left).toBe(0)
	end)

	it("meldet einen Abbruch mitten in der Tiefe", function()
		rift("enter", "gruene_ebenen")
		expect(phase()).toBe("wave")
		rift("leave")
		local s = last()
		expect(s.reason).toBe("abandoned")
		expect(s.cleared).toBe(0)
		expect(s.best).toBe(1) -- Bestwert bleibt
		expect(s.newBest).toBe(false)
		expect(hubDistance()).toBeLessThan(10)
	end)

	it("beendet den Lauf sofort beim Tod, auch während der Wahl nach dem Boss", function()
		rift("enter", "gruene_ebenen")
		clearDepth()
		expect(phase()).toBe("clear")
		local before = #results()
		server(function(_, player)
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			humanoid.Health = 0
		end)
		sim:run(0.5)
		expect(#results()).toBe(before + 1)
		local s = last()
		expect(s.kind).toBe("end")
		expect(s.reason).toBe("failed")
		expect(s.cleared).toBe(1)
		expect(phase()).toBe("failed")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		local enemies = server(function()
			return #game:GetService("CollectionService"):GetTagged("Enemy")
		end)
		expect(enemies).toBe(0)
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
