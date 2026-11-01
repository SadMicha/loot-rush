local Profile = require("ReplicatedStorage.Shared.Profile")

describe("Profile.migrate", function()
	it("creates a fresh save for new players", function()
		local r = Profile.migrate(nil)
		expect(r.v).toBe(Profile.VERSION)
		expect(r.data.gold).toBe(0)
		expect(r.data.level).toBe(1)
		expect(#r.data.inventory).toBe(0)
	end)

	it("fresh saves share no tables", function()
		local a, b = Profile.fresh(), Profile.fresh()
		table.insert(a.inventory, { id = "x" })
		expect(#b.inventory).toBe(0)
	end)

	it("lifts v1 saves to the current version", function()
		local item =
			{ id = "a-1", slot = "helmet", rarity = "magic", name = "Helm", ilvl = 3, affixes = {} }
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
		"v2 → v3: pulls item levels to the new loot level (depth instead of depth × 2 − 1)",
		function()
			local function item(ilvl)
				return {
					id = "i" .. ilvl,
					slot = "weapon",
					rarity = "rare",
					name = "W",
					ilvl = ilvl,
					affixes = {},
				}
			end
			local r = Profile.migrate({
				v = 2,
				data = { inventory = { item(1), item(19) }, equipped = { weapon = item(59) } },
				lock = { job = "A", t = 1 },
			})
			expect(r.v).toBe(Profile.VERSION)
			expect(r.data.inventory[1].ilvl).toBe(1)
			expect(r.data.inventory[2].ilvl).toBe(10)
			expect(r.data.equipped.weapon.ilvl).toBe(30)
			expect(r.lock.job).toBe("A")
		end
	)

	it("fills missing and wrong fields, keeps unknown ones", function()
		local r = Profile.migrate({ v = Profile.VERSION, data = { gold = "broken", extra = 7 } })
		expect(r.data.gold).toBe(0)
		expect(r.data.xp).toBe(0)
		expect((r.data :: any).extra).toBe(7)
	end)

	it("rejects saves from a newer game version", function()
		local ok, err = pcall(Profile.migrate, { v = Profile.VERSION + 1, data = {} })
		expect(ok).toBe(false)
		expect(tostring(err)).toMatch("NEWER")
	end)
end)

describe("Profile.lockedByOther", function()
	it("detects foreign, own and orphaned locks", function()
		local rec = { v = 2, data = {}, lock = { job = "A", t = 1000 } }
		expect(Profile.lockedByOther(rec, "B", 1010, 150)).toBe(true)
		expect(Profile.lockedByOther(rec, "A", 1010, 150)).toBe(false)
		expect(Profile.lockedByOther(rec, "B", 1200, 150)).toBe(false)
		expect(Profile.lockedByOther({ v = 2, data = {} }, "B", 1010, 150)).toBe(false)
		expect(Profile.lockedByOther(nil, "B", 1010, 150)).toBe(false)
	end)
end)
