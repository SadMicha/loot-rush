--!strict
-- Inventar & Ausrüstung: Items aufnehmen, anlegen, ablegen, verkaufen.
-- Rechnet Ausrüstungswerte in Player-Attribute um (StatDamage/StatLife/StatCrit/StatSpeed),
-- die Systems/Combat und PlayerSetup lesen. Der Client bekommt nur Schnappschüsse (Net.Inv).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)

local Inventory = {}

local MAX_ITEMS = 40

local function snapshot(player: Player)
	local profile = Data.get(player)
	if profile then
		Net.Inv:FireClient(player, { items = profile.inventory, equipped = profile.equipped })
	end
end

local function recompute(player: Player, fill: boolean)
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
	player:SetAttribute("StatDamage", sum.damage)
	player:SetAttribute("StatLife", sum.life)
	player:SetAttribute("StatCrit", sum.crit)
	player:SetAttribute("StatSpeed", sum.speed)

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.WALK_SPEED * (1 + sum.speed / 100)
	end
	Combat.refreshStats(player, fill)
end

local function findIndex(list: { Items.Item }, id: string): number?
	for i, item in list do
		if item.id == id then
			return i
		end
	end
	return nil
end

function Inventory.add(player: Player, item: Items.Item): boolean
	local profile = Data.get(player)
	if not profile or #profile.inventory >= MAX_ITEMS then
		return false
	end
	table.insert(profile.inventory, item)
	snapshot(player)
	return true
end

function Inventory.addGold(player: Player, amount: number)
	local profile = Data.get(player)
	if profile then
		profile.gold += amount
		player:SetAttribute("Gold", profile.gold)
	end
end

local function onEquip(player: Player, id: any)
	local profile = Data.get(player)
	if not profile or typeof(id) ~= "string" then
		return
	end
	local index = findIndex(profile.inventory, id)
	if not index then
		return
	end
	local item = table.remove(profile.inventory, index) :: Items.Item
	if not Items.SlotName[item.slot] then
		table.insert(profile.inventory, item)
		return
	end
	local old = profile.equipped[item.slot]
	profile.equipped[item.slot] = item
	if old then
		table.insert(profile.inventory, old)
	end
	recompute(player, false)
	snapshot(player)
end

local function onUnequip(player: Player, slot: any)
	local profile = Data.get(player)
	if not profile or typeof(slot) ~= "string" then
		return
	end
	local item = profile.equipped[slot]
	if not item or #profile.inventory >= MAX_ITEMS then
		return
	end
	profile.equipped[slot] = nil
	table.insert(profile.inventory, item)
	recompute(player, false)
	snapshot(player)
end

local function onSell(player: Player, id: any)
	local profile = Data.get(player)
	if not profile or typeof(id) ~= "string" then
		return
	end
	local index = findIndex(profile.inventory, id)
	if not index then
		return
	end
	local item = table.remove(profile.inventory, index) :: Items.Item
	Inventory.addGold(player, Items.sellValue(item))
	snapshot(player)
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	player:SetAttribute("Gold", profile.gold)
	recompute(player, true)
	snapshot(player)
end

function Inventory.init()
	Net.Equip.OnServerEvent:Connect(onEquip)
	Net.Unequip.OnServerEvent:Connect(onUnequip)
	Net.Sell.OnServerEvent:Connect(onSell)
end

function Inventory.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Inventory
