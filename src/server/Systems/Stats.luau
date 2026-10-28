--!strict
-- Spielerwerte aus Ausrüstung und Sternennetz → Player-Attribute, die Combat, PlayerSetup und das UI lesen.
--   StatDamage/StatLife/StatCrit/StatSpeed: Ausrüstung + Sterne (wie bisher)
--   StatLifePct, StatCritDamage, StatAttackSpeed, StatDouble, StatLowLife, StatDash: nur Sterne
-- Skill-bezogene Sterne (Skill-Schaden, Abklingzeit …) verrechnet Progression.effectiveSkill direkt.
-- Nach jeder Änderung an Ausrüstung oder Sternen Stats.refresh aufrufen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)

local Stats = {}

local EQUIP_ATTR: { [string]: string } = {
	damage = "StatDamage",
	life = "StatLife",
	crit = "StatCrit",
	speed = "StatSpeed",
}
local STAR_ATTR: { [string]: string } = {
	lifePct = "StatLifePct",
	critDamage = "StatCritDamage",
	attackSpeed = "StatAttackSpeed",
	double = "StatDouble",
	lowLifeDamage = "StatLowLife",
	dash = "StatDash",
}

function Stats.refresh(player: Player, fill: boolean)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local sum: { [string]: number } = { damage = 0, life = 0, crit = 0, speed = 0 }
	for _, item in profile.equipped do
		for _, a in item.affixes do
			if sum[a.stat] then
				sum[a.stat] += a.value
			end
		end
	end
	local mods = Progression.starMods(profile.progress)
	for stat, attr in EQUIP_ATTR do
		player:SetAttribute(attr, sum[stat] + (mods[stat] or 0))
	end
	for stat, attr in STAR_ATTR do
		player:SetAttribute(attr, mods[stat] or 0)
	end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.WALK_SPEED * (1 + (sum.speed + (mods.speed or 0)) / 100)
	end
	Combat.refreshStats(player, fill)
end

return Stats
