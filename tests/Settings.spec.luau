-- Settings window rules (Shared/Settings), the account save field and the server remote.
local Profile = require("ReplicatedStorage.Shared.Profile")
local Settings = require("ReplicatedStorage.Shared.Settings")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
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

describe("Settings rules", function()
	it("has a valid default for every setting", function()
		for key, def in Settings.Defs do
			expect(Settings.validate(key, def.default)).toBe(def.default)
		end
	end)

	it("clamps and snaps numbers, rejects NaN and wrong types", function()
		expect(Settings.validate("music", 0.33)).toBe(0.35)
		expect(Settings.validate("music", 7)).toBe(1)
		expect(Settings.validate("music", -1)).toBe(0)
		expect(Settings.validate("music", 0 / 0)).toBeNil()
		expect(Settings.validate("music", math.huge)).toBeNil()
		expect(Settings.validate("music", "loud")).toBeNil()
		expect(Settings.validate("shake", 0.7)).toBe(0.5)
		expect(Settings.validate("hudScale", 1.14)).toBe(1.1)
		expect(Settings.validate("hudScale", 3)).toBe(1.2)
		expect(Settings.validate("camera", 0.1)).toBe(0.5)
	end)

	it("accepts only known options and booleans", function()
		expect(Settings.validate("quality", "low")).toBe("low")
		expect(Settings.validate("quality", "ultra")).toBeNil()
		expect(Settings.validate("damageNumbers", false)).toBe(false)
		expect(Settings.validate("damageNumbers", 0)).toBeNil()
		expect(Settings.validate("nope", 1)).toBeNil()
		expect(Settings.validate(5, 1)).toBeNil()
	end)

	it("resolves auto effects quality per device", function()
		expect(Settings.effectLevel("auto", false, 0)).toBe("high")
		expect(Settings.effectLevel("auto", true, 0)).toBe("medium")
		expect(Settings.effectLevel("auto", false, 2)).toBe("low")
		expect(Settings.effectLevel("high", true, 1)).toBe("high")
	end)
end)

describe("Settings in the save", function()
	it("new accounts get the defaults", function()
		local account = Profile.freshAccount()
		expect(account.settings.music).toBe(Settings.Defs.music.default)
		expect(account.settings.quality).toBe("auto")
	end)

	it("older saves without settings load with defaults, junk is repaired", function()
		local r = Profile.migrate({ v = Profile.VERSION, data = { characters = {} } })
		expect(r.data.settings.minimap).toBe(true)
		local bad = Profile.reconcileAccount({
			settings = { music = 0 / 0, shake = 0, quality = "ultra", evil = string.rep("x", 999) },
		})
		expect(bad.settings.music).toBe(Settings.Defs.music.default)
		expect(bad.settings.shake).toBe(0)
		expect(bad.settings.quality).toBe("auto")
		expect(bad.settings.evil).toBeNil()
	end)
end)

describe("Settings remote", function()
	it("sends the saved settings and stores valid changes only", function()
		sim:boot({ seconds = 2 })
		-- finish the first-join hero setup (its screen would sit over every window)
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Tester Hero", "mage")
		end)
		sim:run(1)
		expect(#sent("Settings")).toBeGreaterThan(0)
		sim:runAs("client", function(req)
			local Net = req("ReplicatedStorage.Shared.Net")
			Net.Setting:FireServer("music", 0.2)
			Net.Setting:FireServer("shake", 0)
			Net.Setting:FireServer("quality", "ultra")
			Net.Setting:FireServer("hudScale", 0 / 0)
			Net.Setting:FireServer({}, true)
		end)
		sim:run(0.5)
		local music, shake, quality, hud = server(function(req, player)
			local s = req("ServerScriptService.Server.Systems.Data").account(player).settings
			return s.music, s.shake, s.quality, s.hudScale
		end)
		expect(music).toBe(0.2)
		expect(shake).toBe(0)
		expect(quality).toBe("auto")
		expect(hud).toBe(1)
	end)

	it("the window changes settings live and saves them", function()
		local gui = sim.player.PlayerGui
		local function find(root: Instance, name: string): any
			for _, d in root:GetDescendants() do
				if d:IsA("GuiButton") and d.Name == name then
					return d
				end
			end
			return nil
		end
		local hudScale = gui.LootRushHUD.Root.UIScale
		local before = hudScale.Scale
		sim:click(find(gui.LootRushHUD, "Gear"))
		sim:run(0.5)
		expect(gui.LootRushSettings.Enabled).toBe(true)
		sim:click(find(gui.LootRushSettings, "Option_s120"))
		sim:run(0.5)
		expect(hudScale.Scale).toBeGreaterThan(before * 1.1)
		sim:click(find(gui.LootRushSettings, "Option_off"))
		sim:run(0.5)
		local saved, shake = server(function(req, player)
			local s = req("ServerScriptService.Server.Systems.Data").account(player).settings
			return s.hudScale, s.shake
		end)
		expect(saved).toBe(1.2)
		expect(shake).toBe(0)
		sim:click(find(gui.LootRushSettings, "Reset"))
		sim:run(0.5)
		expect(math.abs(hudScale.Scale - before)).toBeLessThan(1e-6)
		local resetHud, resetShake = server(function(req, player)
			local st = req("ServerScriptService.Server.Systems.Data").account(player).settings
			return st.hudScale, st.shake
		end)
		expect(resetHud).toBe(1)
		expect(resetShake).toBe(1)
	end)
end)
