--!strict
-- The classic Roblox stud look for everything the game builds (map, buildings, props, enemies,
-- pets, loot). One place decides how a part gets its studs, so every builder under
-- Shared/Models and every map system (World, Hub) looks the same.
--
-- How the studs are made:
--  * Blocks, wedges, corner wedges: Material Plastic with TopSurface = Studs and
--    BottomSurface = Inlet (the native Roblox surfaces, no extra instances, no upload).
--  * Balls and cylinders (surfaces do not render there): the MaterialVariant "LootStuds" in
--    MaterialService (Plastic + stud ColorMap/NormalMap from assets/world, StudsPerTile 1).
--    Scripts cannot set texture maps, so it is created once in Studio (docs/TECH.md "World from parts");
--    without it these shapes stay plain Plastic.
--  * Glow and see-through parts (Neon, Glass, ForceField) and invisible parts keep their
--    look: studs on light or water look wrong. A part with the attribute NoStuds = true is
--    left alone as well (e.g. a part that must keep a special material).

local MaterialService = game:GetService("MaterialService")
local Studs = {}

Studs.VARIANT = "LootStuds"

-- Materials that keep their look (glow, water, shields), by enum name
Studs.KEEP = table.freeze({
	Neon = true,
	Glass = true,
	ForceField = true,
})

-- The MaterialVariant can only be made in Studio or by Rojo (its texture maps are
-- plugin-only properties), so the code just uses it when it is there.
local function variantReady(): boolean
	return MaterialService:FindFirstChild(Studs.VARIANT) ~= nil
end

-- Does this part keep its own look (glow, glass, invisible, opted out)?
function Studs.keeps(part: BasePart): boolean
	return Studs.KEEP[part.Material.Name] == true
		or part.Transparency >= 1
		or part:GetAttribute("NoStuds") == true
end

local function curved(part: BasePart): boolean
	if part:IsA("Part") then
		return part.Shape == Enum.PartType.Ball or part.Shape == Enum.PartType.Cylinder
	end
	return false
end

-- Gives one part the stud look. Safe to call several times (and after Shape changes).
function Studs.apply(part: BasePart)
	if Studs.keeps(part) then
		return
	end
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Inlet
	if curved(part) and variantReady() then
		part.MaterialVariant = Studs.VARIANT
	else
		part.MaterialVariant = ""
	end
end

-- Stud look for worn gear (armor on the hero's body, shop and inventory previews). Blocks and
-- wedges get the native classic studs on every face except the bottom (Inlet): high contrast,
-- they render in ViewportFrames and need no MaterialVariant or upload. Balls and discs (where
-- surfaces do not render) use the LootStuds variant when it is there, else plain Plastic.
-- (The variant's soft 1-stud tiling was too faint to read on small armor plates.)
function Studs.applyAllFaces(part: BasePart)
	if Studs.keeps(part) then
		return
	end
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Inlet
	part.MaterialVariant = if curved(part) and variantReady() then Studs.VARIANT else ""
end

-- Gives every part under `root` (and root itself) the stud look. Returns how many parts got it.
function Studs.applyTree(root: Instance): number
	local n = 0
	if root:IsA("BasePart") and not Studs.keeps(root) then
		Studs.apply(root)
		n += 1
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not Studs.keeps(d) then
			Studs.apply(d)
			n += 1
		end
	end
	return n
end

-- Has this part the stud look (or does it rightly keep its own)? For tests and the debug check.
function Studs.styled(part: BasePart): boolean
	if Studs.keeps(part) then
		return true
	end
	if part.Material == Enum.Material.Plastic and part.MaterialVariant == Studs.VARIANT then
		return true -- curved part with the variant
	end
	return part.Material == Enum.Material.Plastic
		and part.TopSurface == Enum.SurfaceType.Studs
		and part.BottomSurface == Enum.SurfaceType.Inlet
end

return Studs
