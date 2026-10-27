--!strict
-- Part-Modelle, per Code gebaut (Rojo-freundlich, versionierbar, keine .rbxm nötig).
-- Vorschau in Studio (Edit-Modus, Rojo verbunden) über die Command Bar:
--   require(game.ReplicatedStorage.Shared.Models).showcase()
-- legt alle Modelle in einer Reihe in workspace.ModellVorschau ab. Gefällt ein Modell,
-- kann man es dort von Hand nachbessern und als Package/.rbxm speichern.

local Kit = require(script.Kit)
local Props = require(script.Props)

local Models = {
	Kit = Kit,
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
	}
	local x = 0
	local base = origin or Vector3.new(0, 0, 80)
	for _, m in list do
		local size = m:GetExtentsSize()
		x += size.X / 2
		-- Insel hat ihren Pivot oben auf dem Gras: anheben, damit sie sichtbar über dem Boden hängt.
		local lift = if m.Name == "Schwebeinsel" then size.Y else 0
		m:PivotTo(CFrame.new(base + Vector3.new(x, lift, 0)))
		m.Parent = row
		x += size.X / 2 + 4
	end
	row.Parent = workspace
	return row
end

return Models
