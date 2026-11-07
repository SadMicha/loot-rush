--!strict
-- Meshy world kit (docs/specs/WORLD-MESHES.md): uploaded Model asset ids for the props, trees,
-- rocks and landmarks that the part builders under Shared/Models make. The server
-- (Util/MeshKit) loads every id above 0 once and swaps the matching part model for the mesh;
-- an id of 0 (not uploaded yet) or a failed load keeps today's studded parts, never an error.
--
-- Keys are model names as the part builders set them (`Props.tree` → "Tree"). A zone key
-- "<zone>/<Name>" (Atlas region id or "hub") wins over the plain name, so one zone can get its
-- own look (blue cave rock, red desert rock) while the plain name covers every zone.
-- Bulk ground, walls and cliffs stay parts (mobile performance), and so do functional models
-- (portal, pylon, chest, waypoint shrines), tiny ground details and the horizon backdrop.
--
-- Entry fields: model = Model asset id (Meshy FBX uploaded through "Upload UI assets"),
-- texture = optional colour texture id for MeshParts without one, yaw = turn in degrees if the
-- import faces the wrong way, scale = extra size factor (1 = fit the part model's height),
-- glow = keep the part model's small Neon accents visible on top of the mesh (cores, lamp glass).

local WorldMeshes = {}

export type Entry = {
	model: number,
	texture: number?,
	yaw: number?,
	scale: number?,
	glow: boolean?,
}

-- Zones a key may name (Atlas region ids + the hub)
WorldMeshes.ZONES = table.freeze({
	green_plains = true,
	crystal_caves = true,
	mushroom_swamp = true,
	fire_desert = true,
	sky_islands = true,
	altered_world = true,
	hub = true,
})

-- Models that carry gameplay parts (named children other systems look up) and must stay parts
WorldMeshes.FUNCTIONAL = table.freeze({
	CrystalPylon = true, -- "Core" (pylon beams)
	RiftPortal = true, -- "Field"
	Chest = true, -- "Lid"
	Stash = true,
	Forge = true,
	FloatingIsland = true, -- horizon backdrop
})

-- How much wider than the part model a mesh may be (as a share of the larger footprint side)
-- before it is shrunk to fit; keeps a wide Meshy tree from swallowing the trail.
WorldMeshes.FOOTPRINT_SLACK = 1.25

type Extra = { texture: number?, yaw: number?, scale: number?, glow: boolean? }

local function e(model: number, extra: Extra?): Entry
	local x: Extra = extra or {} :: Extra
	return table.freeze({
		model = model,
		texture = x.texture,
		yaw = x.yaw,
		scale = x.scale,
		glow = x.glow,
	})
end

-- Paste the ids from assets/ui-asset-ids.csv here (keys match docs/specs/WORLD-MESHES.md).
WorldMeshes.ids = table.freeze({
	-- Shared pieces (every zone that uses the builder)
	Tree = e(0),
	Pine = e(0),
	DeadTree = e(0),
	Rock = e(0),
	RuinPillar = e(0),
	Arch = e(0),
	BrokenColumn = e(0),
	WallColumn = e(0),
	CrystalCluster = e(0, { glow = true }),
	Lantern = e(0, { glow = true }),
	Banner = e(0),
	Barrel = e(0),
	Crate = e(0),
	Bench = e(0),
	FlowerBox = e(0),
	Well = e(0),
	Signpost = e(0),
	HayBale = e(0),
	Campfire = e(0, { glow = true }),
	Fence = e(0),
	-- Green Plains
	["green_plains/Hedge"] = e(0),
	["green_plains/RuinWall"] = e(0),
	["green_plains/StandingStones"] = e(0),
	["green_plains/Windmill"] = e(0),
	-- Crystal Caves
	["crystal_caves/Rock"] = e(0),
	["crystal_caves/Stalagmite"] = e(0, { glow = true }),
	["crystal_caves/CrystalGrowth"] = e(0, { glow = true }),
	["crystal_caves/GlowShrooms"] = e(0, { glow = true }),
	["crystal_caves/SupportFrame"] = e(0),
	["crystal_caves/MineCart"] = e(0),
	-- Mushroom Swamp
	["mushroom_swamp/GiantMushroom"] = e(0),
	["mushroom_swamp/Willow"] = e(0),
	["mushroom_swamp/DeadTree"] = e(0),
	["mushroom_swamp/Reeds"] = e(0),
	["mushroom_swamp/StiltHut"] = e(0),
	["mushroom_swamp/SunkenLog"] = e(0),
	["mushroom_swamp/VineCurtain"] = e(0),
	-- Fire Desert
	["fire_desert/Rock"] = e(0),
	["fire_desert/OvenChimney"] = e(0, { glow = true }),
	["fire_desert/Cactus"] = e(0),
	["fire_desert/BreadLoaf"] = e(0),
	["fire_desert/RollingPin"] = e(0),
	["fire_desert/Cookie"] = e(0),
	["fire_desert/Bones"] = e(0),
	["fire_desert/ScorchedStones"] = e(0, { glow = true }),
	["fire_desert/RibArch"] = e(0),
	["fire_desert/CrystalCluster"] = e(0, { glow = true }),
	-- Sky Islands
	["sky_islands/GuardianStatue"] = e(0),
	["sky_islands/WindBanner"] = e(0),
	["sky_islands/CastleTower"] = e(0),
	["sky_islands/HoverRock"] = e(0),
	["sky_islands/Railing"] = e(0),
	["sky_islands/Cloud"] = e(0),
	-- Altered World
	["altered_world/RiftShard"] = e(0, { glow = true }),
	["altered_world/EyeMonolith"] = e(0, { glow = true }),
	["altered_world/BrokenStairs"] = e(0),
	["altered_world/InvertedTree"] = e(0, { glow = true }),
	["altered_world/GlitchCubes"] = e(0, { glow = true }),
	["altered_world/DriftShards"] = e(0, { glow = true }),
	["altered_world/Rock"] = e(0),
	-- Hub (Lumenhaven)
	["hub/Tree"] = e(0),
	["hub/Pine"] = e(0),
	["hub/Rock"] = e(0),
	["hub/CastleTower"] = e(0),
	["hub/Windmill"] = e(0),
	["hub/WindBanner"] = e(0),
} :: { [string]: Entry })

-- The key that decides the look of `name` in `zone`: the zone key if it is available, else the
-- plain name if it is, else nil (keep the parts). Available = has an uploaded id, or what
-- `has` says (the server passes "is loaded").
function WorldMeshes.key(name: string, zone: string?, has: ((key: string) -> boolean)?): string?
	if WorldMeshes.FUNCTIONAL[name] then
		return nil
	end
	local ok = has
		or function(k: string): boolean
			local entry = WorldMeshes.ids[k]
			return entry ~= nil and entry.model > 0
		end
	if zone and ok(zone .. "/" .. name) then
		return zone .. "/" .. name
	end
	if ok(name) then
		return name
	end
	return nil
end

-- Uniform scale that gives a mesh of size `mesh` the height of the part model (`parts`), shrunk
-- further if its footprint would get wider than FOOTPRINT_SLACK × the part model's.
function WorldMeshes.fit(parts: Vector3, mesh: Vector3): number
	if mesh.Y <= 0 or parts.Y <= 0 then
		return 1
	end
	local s = parts.Y / mesh.Y
	local wide = math.max(mesh.X, mesh.Z) * s
	local room = math.max(parts.X, parts.Z) * WorldMeshes.FOOTPRINT_SLACK
	if wide > room and wide > 0 then
		s *= room / wide
	end
	return s
end

-- With glow = true a Neon part stays visible only if it is a small accent: its longest side is at
-- most this share of the prop's height. Neon bodies (crystal spikes, glowing caps) are hidden,
-- else they would draw through the mesh.
WorldMeshes.GLOW_MAX_SHARE = 0.3

function WorldMeshes.glows(partSize: Vector3, height: number): boolean
	return height > 0
		and math.max(partSize.X, partSize.Y, partSize.Z) <= height * WorldMeshes.GLOW_MAX_SHARE
end

-- Entries with an uploaded id (what the server loads)
function WorldMeshes.uploaded(ids: { [string]: Entry }?): { [string]: Entry }
	local out = {}
	for k, v in ids or WorldMeshes.ids do
		if v.model > 0 then
			out[k] = v
		end
	end
	return out
end

return table.freeze(WorldMeshes)
