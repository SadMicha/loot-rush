--!strict
-- Inventar & Ausrüstung: Items aufnehmen, anlegen, ablegen, verkaufen (= verwerten: Gold + Material).
-- Werte rechnet Systems/Stats in Player-Attribute um. Der Client bekommt nur Schnappschüsse (Net.Inv).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Stats = require(script.Parent.Stats)

local Inventory = {}

local MAX_ITEMS = 40

-- Jede Aktion schickt den ganzen Inventar-Schnappschuss zurück: Spam drosseln
local allow = RateLimit.new(8, 16)

local function snapshot(player: Player)
	local profile = Data.get(player)
	if profile then
		Net.Inv:FireClient(player, { items = profile.inventory, equipped = profile.equipped })
	end
end

Inventory.sync = snapshot

local function recompute(player: Player, fill: boolean)
	Stats.refresh(player, fill)
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
	if not profile or not allow(player) or typeof(id) ~= "string" or #id > 64 then
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
	if not profile or not allow(player) or typeof(slot) ~= "string" or #slot > 64 then
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
	if not profile or not allow(player) or typeof(id) ~= "string" or #id > 64 then
		return
	end
	local index = findIndex(profile.inventory, id)
	if not index then
		return
	end
	local item = table.remove(profile.inventory, index) :: Items.Item
	Inventory.addGold(player, Items.sellValue(item))
	Progress.salvage(player, item)
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
