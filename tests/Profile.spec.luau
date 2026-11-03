local Profile = require("ReplicatedStorage.Shared.Profile")

-- The played character of a migrated record
local function hero(r: any): any
	return Profile.active(r.data)
end

describe("Profile.migrate", function()
	it("creates a fresh save for new players", function()
		local r = Profile.migrate(nil)
		expect(r.v).toBe(Profile.VERSION)
		expect(#r.data.characters).toBe(1)
		expect(hero(r).gold).toBe(0)
		expect(hero(r).level).toBe(1)
		expect(#hero(r).inventory).toBe(0)
		expect(hero(r).setupDone).toBe(false) -- the setup screen asks for name + class
		expect(r.data.active).toBe(hero(r).id)
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
		expect(hero(r).gold).toBe(50)
		expect(hero(r).inventory[1].id).toBe("a-1")
		expect(hero(r).equipped.ring.id).toBe("a-1")
		expect(hero(r).level).toBe(1)
		expect((hero(r) :: any).version).toBeNil()
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
			})
			expect(r.v).toBe(Profile.VERSION)
			expect(hero(r).inventory[1].ilvl).toBe(1)
			expect(hero(r).inventory[2].ilvl).toBe(10)
			expect(hero(r).equipped.weapon.ilvl).toBe(30)
		end
	)

	it("loads a save from before the 9 slots (only the 5 old slots equipped)", function()
		local function item(slot)
			return { id = slot, slot = slot, rarity = "magic", name = slot, ilvl = 4, affixes = {} }
		end
		local equipped = {}
		for _, slot in { "helmet", "armor", "weapon", "amulet", "ring" } do
			equipped[slot] = item(slot)
		end
		local r = Profile.migrate({ v = 3, data = { equipped = equipped } })
		local count = 0
		for slot, it in hero(r).equipped do
			count += 1
			expect(it.slot).toBe(slot)
		end
		expect(count).toBe(5)
		for _, slot in { "boots", "gloves", "belt", "offhand" } do
			expect(hero(r).equipped[slot]).toBeNil()
		end
	end)

	it("fills missing and wrong fields, keeps unknown ones", function()
		local r = Profile.migrate({
			v = Profile.VERSION,
			data = { extra = 7, characters = { { id = "c1", gold = "broken", more = 1 } } },
		})
		expect(hero(r).gold).toBe(0)
		expect(hero(r).xp).toBe(0)
		expect((hero(r) :: any).more).toBe(1)
		expect((r.data :: any).extra).toBe(7)
	end)

	it("rejects saves from a newer game version", function()
		local ok, err = pcall(Profile.migrate, { v = Profile.VERSION + 1, data = {} })
		expect(ok).toBe(false)
		expect(tostring(err)).toMatch("NEWER")
	end)
end)

describe("Account and characters (v4)", function()
	it("v3 → v4: the old save becomes the first character, account values move up", function()
		local r = Profile.migrate({
			v = 3,
			data = {
				gold = 40,
				level = 12,
				class = "ranger",
				classChosen = true,
				soulstars = 30,
				receipts = { "r1" },
				passes = { vip = true },
				pets = { owned = { moss_frog = 2 }, equipped = { "moss_frog" } },
			},
		})
		expect(r.v).toBe(Profile.VERSION)
		expect(r.data.soulstars).toBe(30)
		expect(r.data.receipts[1]).toBe("r1")
		expect(r.data.passes.vip).toBe(true)
		expect(r.data.pets.owned.moss_frog).toBe(2)
		expect(#r.data.characters).toBe(1)
		local c: any = hero(r)
		expect(c.id).toBe("c1")
		expect(c.gold).toBe(40)
		expect(c.level).toBe(12)
		expect(c.class).toBe("ranger")
		expect(c.setupDone).toBe(true)
		expect(c.league).toBe("legacy")
		expect(c.soulstars).toBeNil()
		expect(c.pets).toBeNil()
		expect(c.classChosen).toBeNil()
	end)

	it("v3 saves without a class choice still need the setup", function()
		local r = Profile.migrate({ v = 3, data = { classChosen = false } })
		expect(hero(r).setupDone).toBe(false)
	end)

	it("gives every character a unique id and repairs the active one", function()
		local acc = Profile.reconcileAccount({
			characters = { { id = "c1" }, { id = "c1" }, "junk", {} },
			active = "nope",
		})
		expect(#acc.characters).toBe(3)
		local seen = {}
		for _, c in acc.characters do
			expect(c.id ~= "").toBe(true)
			expect(seen[c.id]).toBeNil()
			seen[c.id] = true
		end
		expect(acc.active).toBe("c1")
		expect(Profile.active(acc)).toBe(acc.characters[1])
	end)

	it("creates new characters up to the cap", function()
		local acc = Profile.freshAccount()
		acc.characters[1].setupDone = true
		for i = 2, Profile.MAX_CHARACTERS do
			local c = Profile.newCharacter(acc, "Hero " .. i, "mage", 100)
			expect(c).never.toBeNil()
			expect((c :: any).setupDone).toBe(true)
			expect((c :: any).class).toBe("mage")
			expect((c :: any).created).toBe(100)
		end
		expect(#acc.characters).toBe(Profile.MAX_CHARACTERS)
		expect(Profile.newCharacter(acc, "One More", "mage", 100)).toBeNil()
		expect(acc.active).toBe("c1") -- creating does not switch
	end)

	it("accepts only clean names", function()
		expect(Profile.validName("  Brix  ")).toBe("Brix")
		expect(Profile.validName("Sir Brix 2")).toBe("Sir Brix 2")
		expect(Profile.validName("ab")).toBeNil()
		expect(Profile.validName(string.rep("a", Profile.NAME_MAX + 1))).toBeNil()
		expect(Profile.validName("Bad__Name")).toBeNil()
		expect(Profile.validName("two  spaces")).toBeNil()
		expect(Profile.validName(42)).toBeNil()
		expect(Profile.reconcile({ name = "x!" }).name).toBe("")
	end)
end)
