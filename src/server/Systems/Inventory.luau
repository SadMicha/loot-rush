--!strict
-- Inventory & gear: pick up, equip, unequip, sell items (= salvage: gold + materials).
-- Systems/Stats turns the values into player attributes. The client only gets snapshots (Net.Inv).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Stats = require(script.Parent.Stats)

local Inventory = {}

local MAX_ITEMS = Items.BAG_MAX

-- Every action sends the whole inventory snapshot back: throttle spam
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

-- Auto-salvage (unlocked at depth 10, Shared/Quests): loot up to this rarity is salvaged on pickup
local function autoSalvages(profile: Data.Profile, item: Items.Item): boolean
	local limit = Items.rank(profile.autoSalvage)
	return limit > 0 and Items.rank(item.rarity) <= limit
end

-- Salvage an item that never reached the bag (gold + materials, counts for the salvage quest)
function Inventory.salvageLoot(player: Player, item: Items.Item)
	Inventory.addGold(player, Items.sellValue(item))
	Progress.salvage(player, item)
	Actions.fire(player, "salvage")
end

function Inventory.isFull(player: Player): boolean
	local profile = Data.get(player)
	return profile ~= nil and #profile.inventory >= MAX_ITEMS
end

-- Puts an item into the bag. fromLoot = picked up in a Rift: the auto-salvage setting applies,
-- and with a full bag loot that is no upgrade is salvaged instead of left behind (audit #7:
-- items used to vanish without a word). An upgrade stays on the ground until there is room.
-- Returns (stored or salvaged, salvaged, bag was full).
function Inventory.add(
	player: Player,
	item: Items.Item,
	fromLoot: boolean?
): (boolean, boolean, boolean)
	local profile = Data.get(player)
	if not profile then
		return false, false, false
	end
	if fromLoot and autoSalvages(profile, item) then
		Inventory.salvageLoot(player, item)
		return true, true, false
	end
	if #profile.inventory >= MAX_ITEMS then
		if fromLoot and not Items.isUpgrade(item, profile.equipped[item.slot]) then
			Inventory.salvageLoot(player, item)
			return true, true, true
		end
		return false, false, true
	end
	table.insert(profile.inventory, item)
	snapshot(player)
	return true, false, false
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
	local item = profile.inventory[index]
	-- unknown slot, above the hero's level (a stash twink, Items.requiredLevel) or another class's
	-- weapon from the shared stash (Items.classLock)
	if not Items.SlotName[item.slot] or not Items.canWear(item, profile.level, profile.class) then
		return
	end
	table.remove(profile.inventory, index)
	local old = profile.equipped[item.slot]
	profile.equipped[item.slot] = item
	if old then
		table.insert(profile.inventory, old)
	end
	recompute(player, false)
	snapshot(player)
	Actions.fire(player, "equip")
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
	Actions.fire(player, "salvage")
end

local allowFilter = RateLimit.new(2, 4)

local function onAutoSalvage(player: Player, rarity: any)
	local profile = Data.get(player)
	if not profile or not allowFilter(player) or typeof(rarity) ~= "string" then
		return
	end
	-- "" = off; never uniques (they are the reason to play)
	if rarity ~= "" and (Items.rank(rarity) == 0 or rarity == "unique") then
		return
	end
	profile.autoSalvage = rarity
	player:SetAttribute("AutoSalvage", rarity)
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	player:SetAttribute("Gold", profile.gold)
	player:SetAttribute("AutoSalvage", profile.autoSalvage)
	recompute(player, true)
	snapshot(player)
end

function Inventory.init()
	Net.Equip.OnServerEvent:Connect(onEquip)
	Net.Unequip.OnServerEvent:Connect(onUnequip)
	Net.Sell.OnServerEvent:Connect(onSell)
	Net.AutoSalvage.OnServerEvent:Connect(onAutoSalvage)
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
