-- Server-Systeme hinter den Fenstern: Sternennetz, Skill-Blüte und Schmiede über echte Remotes.
local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function client(fn)
	sim:runAs("client", function(req)
		fn(req, req("ReplicatedStorage.Shared.Net"))
	end)
	sim:run(0.5)
end

local function sent(name: string): { any }
	local list = {}
	for _, n in sim.netLog do
		if n.name == name and n.dir == "S→C" then
			table.insert(list, n.args)
		end
	end
	return list
end

describe("Systeme", function()
	it("startet und schickt den Fortschritt", function()
		sim:boot({ seconds = 3 })
		expect(#sent("Progress")).toBeGreaterThan(0)
	end)

	it("weist Sterne nur nach den Regeln zu und wendet sie an", function()
		server(function(_, player)
			player:SetAttribute("Level", 4) -- 3 Punkte
		end)
		client(function(_, Net)
			Net.Star:FireServer("alloc", "eisenhaut") -- nicht verbunden
			Net.Star:FireServer("alloc", "k1")
			Net.Star:FireServer("alloc", "k2")
			Net.Star:FireServer("alloc", "k4")
			Net.Star:FireServer("alloc", "g1") -- keine Punkte mehr
			Net.Star:FireServer("alloc", { "quatsch" })
			Net.Star:FireServer(42)
		end)
		local stars, damage = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			return p.progress.stars, player:GetAttribute("StatDamage")
		end)
		expect(stars.k1).toBe(true)
		expect(stars.k2).toBe(true)
		expect(stars.k4).toBe(true)
		expect(stars.eisenhaut).toBeNil()
		expect(stars.g1).toBeNil()
		expect(damage).toBeGreaterThanOrEqual(6)

		client(function(_, Net)
			Net.Star:FireServer("remove", "k1") -- k2/k4 hängen dran
			Net.Star:FireServer("reset")
		end)
		local after = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).progress.stars
		end)
		expect(next(after)).toBeNil()
	end)

	it("vergibt Blüten-Punkte nur mit Skill-Stufen", function()
		client(function(_, Net)
			Net.Bloom:FireServer("spend", "funkenball", "trunk1")
		end)
		local before = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			local sp = p.progress.skills.funkenball
			local pts = if sp then sp.bloom.trunk1 else nil
			-- Stufe 3 geben: 2 Punkte
			req("ReplicatedStorage.Shared.Progression").skillMut(p.progress, "funkenball").level = 3
			return pts
		end)
		expect(before).toBeNil()
		client(function(_, Net)
			Net.Bloom:FireServer("spend", "funkenball", "trunk1")
			Net.Bloom:FireServer("spend", "funkenball", "left1") -- kommt bald
			Net.Bloom:FireServer("spend", "funkenball", "trunk1")
			Net.Bloom:FireServer("spend", "funkenball", "trunk1") -- keine Punkte mehr
		end)
		local bloom = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).progress.skills.funkenball.bloom
		end)
		expect(bloom.trunk1).toBe(2)
		expect(bloom.left1).toBeNil()
	end)

	it("schmiedet mit Material und lehnt Unsinn ab", function()
		local id = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			p.materials.candy = 1
			table.insert(p.inventory, {
				id = "schmiede-test",
				slot = "waffe",
				rarity = "magic",
				name = "Teststab",
				ilvl = 5,
				affixes = { { stat = "damage", value = 4, implicit = true } },
			})
			return "schmiede-test"
		end)
		client(function(_, Net)
			Net.ForgeAct:FireServer("add", id, nil)
			Net.ForgeAct:FireServer("add", id, nil) -- kein Bonbon mehr
			Net.ForgeAct:FireServer("tier", id, 0 / 0)
			Net.ForgeAct:FireServer("tier", "gibtsnicht", 1)
		end)
		local item, candy = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			for _, it in p.inventory do
				if it.id == id then
					return it, p.materials.candy
				end
			end
			return nil, p.materials.candy
		end)
		expect(#item.affixes).toBe(2)
		expect(candy).toBe(0)
		local results = sent("ForgeResult")
		expect(#results).toBe(2)
		expect(results[1][1].ok).toBe(true)
		expect(results[2][1].ok).toBe(false)
	end)

	it("läuft ohne Laufzeitfehler", function()
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
