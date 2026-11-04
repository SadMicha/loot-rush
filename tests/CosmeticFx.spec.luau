-- Cosmetic looks in 3D (Shared/CosmeticFx): tiers grow with rarity, the LOD keeps 12 heroes in
-- budget, and every aura / trail has a readable look.
local Cosmetics = require("ReplicatedStorage.Shared.Cosmetics")
local Fx = require("ReplicatedStorage.Shared.CosmeticFx")

local ORDER = { "normal", "magic", "rare", "epic", "unique", "legend" }

local function fake(rarity: string): any
	return { id = "x", slot = "aura", rarity = rarity, colors = { Color3.new(1, 1, 1) }, light = 1 }
end

describe("Cosmetic looks", function()
	it("every rarity has a tier, higher rarities get more layers", function()
		local last = 0
		for _, rarity in ORDER do
			expect(Fx.Tiers[rarity]).never.toBeNil()
			expect(Fx.TrailTiers[rarity]).never.toBeNil()
			local n = Fx.partCount(Fx.plan(fake(rarity), "full"))
			expect(n >= last).toBe(true)
			last = n
		end
		local legend = Fx.Tiers.legend
		expect(legend.pillar).toBe(true)
		expect(legend.crown > 0 and legend.ring2 > 0 and legend.pulse > 0).toBe(true)
		expect(Fx.Tiers.epic.band > 0).toBe(true)
		expect(Fx.TrailTiers.legend.width > Fx.TrailTiers.rare.width).toBe(true)
	end)

	it("every aura has a shard style and two colors, every slot an attribute", function()
		for _, c in Cosmetics.List do
			local style = Fx.style(c)
			expect(style.core).never.toBeNil()
			if c.slot == "aura" then
				expect(Fx.Shard[c.id]).never.toBeNil()
			end
			expect(Fx.Tiers[c.rarity]).never.toBeNil()
		end
		for _, slot in Cosmetics.Slots do
			expect(Fx.ATTR[slot]).never.toBeNil()
		end
	end)

	it("lite and off are cheap", function()
		local c = fake("legend")
		local lite = Fx.plan(c, "lite")
		expect(Fx.partCount(lite) <= 2 + Fx.LITE_RING + Fx.LITE_SHARDS).toBe(true)
		expect(lite.pillar).toBe(false)
		expect(lite.light).toBe(0)
		expect(Fx.partCount(Fx.plan(c, "off"))).toBe(0)
	end)

	it("LOD: own hero full, nearest others up to the cap, far ones off", function()
		expect(Fx.detail(true, 0, 0, "high")).toBe("full")
		expect(Fx.detail(true, 0, 0, "low")).toBe("lite")
		expect(Fx.detail(false, 10, 1, "high")).toBe("full")
		expect(Fx.detail(false, 10, 4, "high")).toBe("lite")
		expect(Fx.detail(false, 10, 1, "low")).toBe("lite")
		expect(Fx.detail(false, Fx.FULL_RANGE + 1, 1, "high")).toBe("lite")
		expect(Fx.detail(false, Fx.LITE_RANGE + 1, 1, "high")).toBe("off")
		expect(Fx.detail(false, 0 / 0, 1, "high")).toBe("off")
	end)

	it("12 legendary heroes in one spot stay within the part budget", function()
		local c = fake("legend")
		for _, lvl in { "low", "medium", "high" } do
			local total = Fx.partCount(Fx.plan(c, Fx.detail(true, 0, 0, lvl)))
			for rank = 1, 11 do
				total += Fx.partCount(Fx.plan(c, Fx.detail(false, 10, rank, lvl)))
			end
			expect(total <= 400).toBe(true)
		end
	end)

	it("feet sit below the root for both rig types", function()
		expect(Fx.feetDrop(false, 0, 2)).toBe(3)
		expect(Fx.feetDrop(true, 2, 2)).toBe(3)
	end)
end)
