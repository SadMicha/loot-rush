-- Debug-Menü: Test-Befehle wirken nur in Studio (bzw. für DEV_USERS) und prüfen ihre Werte.
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
	sim:run(1)
end

local function state()
	return server(function(req, player)
		local p = req("ServerScriptService.Server.Systems.Data").get(player)
		local skill = p.progress.skills.funkenball
		return {
			gold = p.gold,
			level = player:GetAttribute("Level"),
			candy = p.materials.candy,
			skill = if skill then skill.level else 1,
			items = #p.inventory,
			atlas = player:GetAttribute("AtlasBest_himmelsinseln"),
			tools = player:GetAttribute("DebugTools"),
		}
	end)
end

describe("Debug-Menü", function()
	it("ignoriert Befehle außerhalb von Studio", function()
		sim:boot({ seconds = 2 })
		local before = state()
		expect(before.tools).toBe(true)
		sim.studio = false
		client(function(_, Net)
			Net.Debug:FireServer("gold", 5000)
			Net.Debug:FireServer("atlas")
		end)
		sim.studio = true
		local after = state()
		expect(after.gold).toBe(before.gold)
		expect(after.atlas).toBeNil()
	end)

	it("setzt Gold, Level, Material, Skills, Items und Gebiete", function()
		local before = state()
		client(function(_, Net)
			Net.Debug:FireServer("gold", 5000)
			Net.Debug:FireServer("level", 12)
			Net.Debug:FireServer("materials", 50)
			Net.Debug:FireServer("skills", 2)
			Net.Debug:FireServer("items", 3)
			Net.Debug:FireServer("atlas")
		end)
		local after = state()
		expect(after.gold).toBe(before.gold + 5000)
		expect(after.level).toBe(12)
		expect(after.candy).toBe(before.candy + 50)
		expect(after.skill).toBe(before.skill + 2)
		expect(after.items).toBe(before.items + 3)
		expect(after.atlas).toBeGreaterThanOrEqual(21) -- Start-Tiefe der Himmelsinseln
	end)

	it("lehnt unsinnige Werte ab", function()
		local before = state()
		client(function(_, Net)
			Net.Debug:FireServer("gold", 0 / 0)
			Net.Debug:FireServer("gold", 1.5)
			Net.Debug:FireServer("level", 9999)
			Net.Debug:FireServer("level", "10")
			Net.Debug:FireServer("quatsch", 1)
			Net.Debug:FireServer({ "gold" }, 1)
		end)
		local after = state()
		expect(after.gold).toBe(before.gold)
		expect(after.level).toBe(before.level)
	end)

	it("Knopf im Menü schickt den Befehl", function()
		local gui = sim.player.PlayerGui:FindFirstChild("LootRushDebug")
		expect(gui).never.toBeNil()
		local button = nil
		for _, d in gui:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "gold" then
				button = d
			end
		end
		expect(button).never.toBeNil()
		local before = state()
		sim:click(button)
		sim:run(1)
		expect(state().gold).toBe(before.gold + 10000)
	end)
end)
