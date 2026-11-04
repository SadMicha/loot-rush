-- Preload list (Shared/Preload): every registered asset id is in it, once, never empty
local Assets = require("ReplicatedStorage.Shared.UI.Assets")
local Preload = require("ReplicatedStorage.Shared.Preload")
local Sounds = require("ReplicatedStorage.Shared.Sounds")
local Weapons = require("ReplicatedStorage.Shared.Weapons")

describe("Preload", function()
	local entries = Preload.collect()
	local byId = {}
	for _, e in entries do
		byId[e.id] = e
	end

	it("has only valid, unique ids", function()
		local seen = {}
		for _, e in entries do
			expect(Preload.valid(e.id)).toBe(true)
			expect(seen[e.id]).toBeNil()
			seen[e.id] = true
		end
		expect(#entries).toBeGreaterThan(100)
	end)

	it("includes every registered image", function()
		local groups = {
			Assets.Hud,
			Assets.Fixed,
			Assets.Slice,
			Assets.IconImage,
			Assets.Icon,
			Assets.Class,
			Assets.Art,
		}
		for _, group in groups do
			for _, def in group do
				if def.id ~= "" then
					expect(byId[def.id] ~= nil).toBe(true)
				end
			end
		end
		for _, w in Assets.Weapon do
			if w.texture ~= "" then
				expect(byId[w.texture] ~= nil).toBe(true)
			end
		end
		for _, id in Assets.Vfx do
			expect(byId[id] ~= nil).toBe(true)
		end
	end)

	it("includes every sound and animation", function()
		for _, group in { Sounds.Hooks, Sounds.Ambience, Sounds.Music } do
			for _, def in group do
				expect(byId[def.id] ~= nil).toBe(true)
			end
		end
		for _, id in Weapons.HOLD_ANIM do
			expect(byId[id].kind).toBe("animation")
		end
	end)

	it("orders images, then sounds, then animations", function()
		local rank = { image = 1, sound = 2, animation = 3 }
		local last = 0
		for _, e in entries do
			expect(rank[e.kind] >= last).toBe(true)
			last = rank[e.kind]
		end
	end)

	it("splits into batches that keep order and never mix kinds", function()
		local batches = Preload.batches(entries, 10)
		local count = 0
		for _, batch in batches do
			expect(#batch <= 10).toBe(true)
			for _, e in batch do
				expect(e.kind).toBe(batch[1].kind)
				count += 1
				expect(entries[count].id).toBe(e.id)
			end
		end
		expect(count).toBe(#entries)
		expect(#Preload.batches({}, 5)).toBe(0)
	end)

	it("turns entries into content instances, never strings", function()
		local batch = {
			{ id = "rbxassetid://1", kind = "image" },
			{ id = "rbxassetid://2", kind = "sound" },
			{ id = "rbxassetid://3", kind = "animation" },
		}
		local objects = Preload.instances(batch)
		expect(#objects).toBe(3)
		expect(typeof(objects[1])).toBe("Instance")
		expect(objects[1].ClassName).toBe("ImageLabel")
		expect(objects[1].Image).toBe("rbxassetid://1")
		expect(objects[2].ClassName).toBe("Sound")
		expect(objects[3].ClassName).toBe("Animation")
	end)
end)
