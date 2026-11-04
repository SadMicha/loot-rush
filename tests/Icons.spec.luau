-- Icons: every icon key in the catalogs points at a real Assets.Icon entry (no placeholder frames)
local Assets = require("ReplicatedStorage.Shared.UI.Assets")
local Cosmetics = require("ReplicatedStorage.Shared.Cosmetics")
local Pets = require("ReplicatedStorage.Shared.Pets")
local Shop = require("ReplicatedStorage.Shared.Shop")
local SpellStones = require("ReplicatedStorage.Shared.SpellStones")
local Status = require("ReplicatedStorage.Shared.Status")
local Store = require("ReplicatedStorage.Shared.Store")

describe("Icons", function()
	it("library aliases share the atlas cell of their code", function()
		expect(Assets.Icon.trail_gilded).toBe(Assets.Icon.H11)
		expect(Assets.Icon.buff_haste).toBe(Assets.Icon.G23)
		expect(Assets.Icon.leaderboard).toBe(Assets.Icon.F41)
	end)

	it("catalogs only use existing icons", function()
		local function check(where: string, key: string)
			if Assets.Icon[key] == nil and Assets.IconImage[key] == nil then
				error(`{where}: unknown icon "{key}"`)
			end
		end
		for _, c in Cosmetics.List do
			check("cosmetic " .. c.id, c.icon)
		end
		for _, p in Pets.List do
			check("pet " .. p.id, Pets.iconOf(p))
		end
		for _, e in Pets.Eggs do
			check("egg " .. e.id, Pets.eggIconOf(e))
		end
		for _, st in SpellStones.List do
			check("stone " .. st.id, st.icon)
		end
		for _, o in Shop.Offers do
			check("shop " .. o.id, o.icon)
		end
		for _, o in Store.Offers do
			check("store " .. o.id, o.icon)
		end
		for id, d in Status.Defs do
			check("status " .. id, d.icon)
		end
	end)
end)
