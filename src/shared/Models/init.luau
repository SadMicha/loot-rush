--!strict
-- Part models built in code (Rojo-friendly, versionable, no .rbxm needed). Every part gets the
-- classic stud look through Kit/Studs, so new builders get studs automatically.
-- Preview in Studio (edit mode, Rojo connected) via the command bar:
--   require(game.ReplicatedStorage.Shared.Models).showcase()
-- puts all models in a row into workspace.ModelPreview. If you like a model,
-- you can touch it up there by hand and save it as a package/.rbxm.

local Biomes = require(script.Biomes)
local Buildings = require(script.Buildings)
local Creatures = require(script.Creatures)
local Kit = require(script.Kit)
local Loot = require(script.Loot)
local Props = require(script.Props)
local Studs = require(script.Studs)

local Models = {
	Biomes = Biomes,
	Buildings = Buildings,
	Creatures = Creatures,
	Kit = Kit,
	Loot = Loot,
	Props = Props,
	Studs = Studs,
}

function Models.showcase(origin: Vector3?): Model
	local old = workspace:FindFirstChild("ModelPreview")
	if old then
		old:Destroy()
	end
	local row = Instance.new("Model")
	row.Name = "ModelPreview"
	local list: { Model } = {
		Props.tree(1.3),
		Props.pillar(1.4),
		Props.pylon(),
		Props.crystalCluster(1, 1),
		Props.crystalCluster(1.4, 2, Kit.C.magic),
		Props.chest(),
		Props.fence(),
		Props.portal(),
		Props.pine(1),
		Props.lantern(),
		Props.banner(),
		Props.flowerBox(),
		Props.barrel(),
		Props.crate(),
		Props.well(),
		Props.bench(),
		Props.scaffold(8),
		Buildings.stall(Kit.C.roof, Kit.C.cream, 8, 5),
		Buildings.stash(Props.chest()),
		Biomes.windmill(1),
		Biomes.hayBale(),
		Biomes.campfire(),
		Biomes.signpost(),
		Biomes.ruinWall(1),
		Biomes.rails(12),
		Biomes.mineCart(),
		Biomes.supportFrame(),
		Biomes.glowShrooms(1, Kit.C.crystal),
		Biomes.stiltHut(1),
		Biomes.lilyPad(1),
		Biomes.willow(1, 1),
		Biomes.log(1),
		Biomes.breadLoaf(1),
		Biomes.rollingPin(1),
		Biomes.cookie(1),
		Biomes.cactus(1),
		Biomes.bones(1),
		Biomes.statue(1, Kit.C.stoneLight),
		Biomes.brokenColumn(1, Kit.C.stoneLight),
		Biomes.windBanner(Kit.C.crystalDeep),
		Biomes.hoverRock(1, 4),
		Biomes.invertedTree(1, Kit.C.magic),
		Biomes.glitchCubes(1, Kit.C.magic),
		Biomes.eyeMonolith(1, Kit.C.magic),
		Biomes.brokenStairs(1, Kit.C.stoneDark),
		Props.island(0.5, true),
		Buildings.forge(1),
		Buildings.forge(2),
		Buildings.forge(3),
		Buildings.house(1),
		Buildings.house(2),
		Buildings.house(3),
		Creatures.slime(1, Color3.fromHex("#49D8D8"), Kit.C.crystal),
		Creatures.beetle(1),
		Creatures.crab(1),
		Creatures.lantern(1),
		Creatures.worm(1),
		Creatures.frog(1),
		Creatures.snail(1),
		Creatures.mushroom(1),
		Creatures.golem(1),
		Creatures.imp(1),
		Creatures.wisp(1),
		Creatures.statue(1),
		Creatures.crown(Creatures.golem(1.5), 1.5, 3.1),
		Loot.giftBox(Color3.fromHex("#A9AFC8"), false),
		Loot.giftBox(Color3.fromHex("#5FA8FF"), true),
		Loot.giftBox(Color3.fromHex("#E8C04A"), true),
		Loot.giftBox(Color3.fromHex("#B98CFF"), true),
		Loot.coin(),
		Loot.shard(),
		Loot.runeCandy(),
	}
	local x = 0
	local base = origin or Vector3.new(0, 0, 80)
	for _, m in list do
		local size = m:GetExtentsSize()
		x += size.X / 2
		-- The island has its pivot on top of the grass: lift it so it visibly floats above the ground.
		-- Enemies have their pivot in the body center.
		local lift = if m.Name == "FloatingIsland"
			then size.Y
			elseif m.PrimaryPart and m.PrimaryPart.Name == "Body" then Creatures.BODY_Y
			else 0
		m:PivotTo(CFrame.new(base + Vector3.new(x, lift, 0)))
		m.Parent = row
		x += size.X / 2 + 4
	end
	row.Parent = workspace
	return row
end

return Models
