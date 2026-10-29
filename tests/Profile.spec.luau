local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Profile.migrate", function()
	it("legt für neue Spieler einen frischen Stand an", function()
		local r = Profile.migrate(nil)
		expect(r.v).toBe(Profile.VERSION)
		expect(r.data.gold).toBe(0)
		expect(r.data.level).toBe(1)
		expect(#r.data.inventory).toBe(0)
	end)

	it("frische Stände teilen keine Tabellen", function()
		local a, b = Profile.fresh(), Profile.fresh()
		table.insert(a.inventory, { id = "x" })
		expect(#b.inventory).toBe(0)
	end)

	it("hebt v1-Stände auf die aktuelle Version", function()
		local item =
			{ id = "a-1", slot = "helm", rarity = "magic", name = "Helm", ilvl = 3, affixes = {} }
		local r = Profile.migrate({
			version = 1,
			gold = 50,
			inventory = { item },
			equipped = { ring = item },
		})
		expect(r.v).toBe(Profile.VERSION)
		expect(r.data.gold).toBe(50)
		expect(r.data.inventory[1].id).toBe("a-1")
		expect(r.data.equipped.ring.id).toBe("a-1")
		expect(r.data.level).toBe(1)
		expect((r.data :: any).version).toBeNil()
	end)

	it(
		"v2 → v3: zieht Item-Stufen auf die neue Beute-Stufe (Tiefe statt Tiefe × 2 − 1)",
		function()
			local function item(ilvl)
				return {
					id = "i" .. ilvl,
					slot = "waffe",
					rarity = "rare",
					name = "W",
					ilvl = ilvl,
					affixes = {},
				}
			end
			local r = Profile.migrate({
				v = 2,
				data = { inventory = { item(1), item(19) }, equipped = { waffe = item(59) } },
				lock = { job = "A", t = 1 },
			})
			expect(r.v).toBe(Profile.VERSION)
			expect(r.data.inventory[1].ilvl).toBe(1)
			expect(r.data.inventory[2].ilvl).toBe(10)
			expect(r.data.equipped.waffe.ilvl).toBe(30)
			expect(r.lock.job).toBe("A")
		end
	)

	it("ergänzt fehlende und falsche Felder, behält unbekannte", function()
		local r = Profile.migrate({ v = Profile.VERSION, data = { gold = "kaputt", extra = 7 } })
		expect(r.data.gold).toBe(0)
		expect(r.data.xp).toBe(0)
		expect((r.data :: any).extra).toBe(7)
	end)

	it("lehnt Stände einer neueren Spielversion ab", function()
		local ok, err = pcall(Profile.migrate, { v = Profile.VERSION + 1, data = {} })
		expect(ok).toBe(false)
		expect(tostring(err)).toMatch("NEWER")
	end)
end)

describe("Profile.lockedByOther", function()
	it("erkennt fremde, eigene und verwaiste Locks", function()
		local rec = { v = 2, data = {}, lock = { job = "A", t = 1000 } }
		expect(Profile.lockedByOther(rec, "B", 1010, 150)).toBe(true)
		expect(Profile.lockedByOther(rec, "A", 1010, 150)).toBe(false)
		expect(Profile.lockedByOther(rec, "B", 1200, 150)).toBe(false)
		expect(Profile.lockedByOther({ v = 2, data = {} }, "B", 1010, 150)).toBe(false)
		expect(Profile.lockedByOther(nil, "B", 1010, 150)).toBe(false)
	end)
end)
