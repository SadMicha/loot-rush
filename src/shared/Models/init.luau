--!strict
-- Part-Modelle, per Code gebaut (Rojo-freundlich, versionierbar, keine .rbxm nötig).
-- Vorschau in Studio (Edit-Modus, Rojo verbunden) über die Command Bar:
--   require(game.ReplicatedStorage.Shared.Models).showcase()
-- legt alle Modelle in einer Reihe in workspace.ModellVorschau ab. Gefällt ein Modell,
-- kann man es dort von Hand nachbessern und als Package/.rbxm speichern.

local Buildings = require(script.Buildings)
local Creatures = require(script.Creatures)
local Kit = require(script.Kit)
local Loot = require(script.Loot)
local Props = require(script.Props)

local Models = {
	Buildings = Buildings,
	Creatures = Creatures,
	Kit = Kit,
	Loot = Loot,
	Props = Props,
}

function Models.showcase(origin: Vector3?): Model
	local old = workspace:FindFirstChild("ModellVorschau")
	if old then
		old:Destroy()
	end
	local row = Instance.new("Model")
	row.Name = "ModellVorschau"
	local list: { Model } = {
		Props.tree(1.3),
		Props.pillar(1.4),
		Props.pylon(),
		Props.crystalCluster(1, 1),
		Props.crystalCluster(1.4, 2, Kit.C.magic),
		Props.chest(),
		Props.fence(),
		Props.portal(),
		Props.island(0.5, true),
		Buildings.forge(1),
		Buildings.forge(2),
		Buildings.forge(3),
		Buildings.house(1),
		Buildings.house(2),
		Buildings.house(3),
		Creatures.slime(1, Color3.fromHex("#49D8D8"), Kit.C.crystal),
		Creatures.beetle(1),
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
		-- Insel hat ihren Pivot oben auf dem Gras: anheben, damit sie sichtbar über dem Boden hängt.
		-- Gegner haben ihren Pivot in der Körpermitte.
		local lift = if m.Name == "Schwebeinsel"
			then size.Y
			elseif m.PrimaryPart and m.PrimaryPart.Name == "Koerper" then Creatures.BODY_Y
			else 0
		m:PivotTo(CFrame.new(base + Vector3.new(x, lift, 0)))
		m.Parent = row
		x += size.X / 2 + 4
	end
	row.Parent = workspace
	return row
end

return Models
