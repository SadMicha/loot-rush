--!strict
-- Player stats from gear and Star Web → player attributes read by Combat, PlayerSetup and the UI.
--   StatDamage/StatLife/StatCrit/StatSpeed: gear + stars (as before)
--   StatLifePct, StatCritDamage, StatAttackSpeed, StatDouble, StatLowLife, StatDash,
--   StatArmor, StatBlock, StatCritShard, StatArcaneShield: stars only
--   StatWeapon: weapon base damage of the worn weapon as a factor (1 = IP 10 or no weapon)
-- Skill-related stars (skill damage, cooldown …) are applied directly by Progression.effectiveSkill.
-- No stat is capped; StatCrit above 100% overcrits (Shared/Crit).
-- Call Stats.refresh after every change to gear or stars (it also updates the visible gear,
-- Systems/Gear).
-- Worn gear above the hero's level (Items.canWear; an older save, or a stash twink worn before
-- the rule) gives nothing until the hero reaches its level; a level change refreshes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Balance)
local Items = require(ReplicatedStorage.Shared.Items)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Gear = require(script.Parent.Gear)

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
	armor = "StatArmor",
	block = "StatBlock",
	critShard = "StatCritShard",
	arcaneShield = "StatArcaneShield",
}

function Stats.refresh(player: Player, fill: boolean)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local sum: { [string]: number } = { damage = 0, life = 0, crit = 0, speed = 0 }
	local level = Stats.level(player)
	for _, item in profile.equipped do
		if not Items.canWear(item, level, profile.class) then
			continue
		end
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
	local worn: Items.Item? = profile.equipped.weapon
	local weapon = if worn and Items.canWear(worn, level, profile.class) then worn else nil
	player:SetAttribute(
		"StatWeapon",
		Balance.weaponFactor(if weapon then Items.itemPower(weapon) else Balance.P.ip_per_depth)
	)
	Combat.refreshStats(player, fill)
	Gear.apply(player) -- worn look on the body (rebuilds only when it changed)
end

-- Hero level for gear requirements: the live attribute (set first on a level-up), else the save
function Stats.level(player: Player): number
	local attr = player:GetAttribute("Level")
	if typeof(attr) == "number" then
		return attr
	end
	local profile = Data.get(player)
	return if profile then profile.level else 1
end

-- A level change can wake worn gear that was above the hero's level
local function watch(player: Player)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local profile = Data.get(player)
		if not profile then
			return
		end
		for _, item in profile.equipped do
			if Items.requiredLevel(item) > 1 then
				Stats.refresh(player, false)
				return
			end
		end
	end)
end

function Stats.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return Stats
