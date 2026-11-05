--!strict
-- Inventory & gear: pick up, equip, unequip, sell items (= salvage: gold + materials).
-- Item lock and bulk salvage (Shared/Salvage): Net.ItemLock (id, on) locks a bag or worn item,
-- Net.SalvageMany (ids) salvages the bag's downgrades in one request; locked items and uniques
-- are never salvaged by either path, and auto-salvage keeps upgrades unless the player turns it off.
-- Systems/Stats turns the values into player attributes. The client only gets snapshots (Net.Inv).
-- Bag size (Shared/Bag): account-wide upgrade level in account.season.bag, bought with the hero's
-- gold over Net.Bag; attributes BagLevel / BagMax. A bag over its capacity (new season) keeps
-- every item and only takes new ones once it is below the capacity again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bag = require(ReplicatedStorage.Shared.Bag)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Salvage = require(ReplicatedStorage.Shared.Salvage)
local Upgrade = require(ReplicatedStorage.Shared.Upgrade)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Analytics = require(script.Parent.Analytics)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Stats = require(script.Parent.Stats)

local Inventory = {}

-- Every action sends the whole inventory snapshot back: throttle spam
local allow = RateLimit.new(8, 16)
-- Bag upgrades: a purchase is one tap; a double tap is answered "stale" by Bag.check anyway
local allowBag = RateLimit.new(2, 4)

local function bagLevel(player: Player): number
	local account = Data.account(player)
	return if account then Bag.level(account.season.bag) else 0
end

-- Bag slots of the player (account-wide, this season's upgrade level)
function Inventory.capacity(player: Player): number
	return Bag.capacity(bagLevel(player))
end

local function snapshot(player: Player)
	local profile = Data.get(player)
	if profile then
		local level = bagLevel(player)
		Net.Inv:FireClient(player, {
			items = profile.inventory,
			equipped = profile.equipped,
			capacity = Bag.capacity(level),
			level = level,
		})
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

-- Auto-salvage (unlocked at depth 10, Shared/Quests): loot up to this rarity is salvaged on pickup,
-- except upgrades while "keep upgrades" is on (Shared/Salvage.auto)
local function autoSalvages(player: Player, profile: Data.Profile, item: Items.Item): boolean
	if Items.rank(profile.autoSalvage) <= 0 then
		return false
	end
	local hero = if profile.autoKeep then Stats.hero(player) else nil
	return Salvage.auto(profile.autoSalvage, profile.autoKeep, item, hero)
end

-- Salvage/sell gold: pooled like the salvage shards (one economy event per minute, Systems/Analytics)
local function salvageGold(player: Player, item: Items.Item)
	local gold = Items.sellValue(item)
	Inventory.addGold(player, gold)
	local profile = Data.get(player)
	if profile then
		Analytics.pool(player, "Gold", gold, profile.gold, "Gameplay", "salvage")
	end
end

-- Salvage an item that never reached the bag (gold + materials, counts for the salvage quest)
function Inventory.salvageLoot(player: Player, item: Items.Item)
	salvageGold(player, item)
	Progress.salvage(player, item)
	Actions.fire(player, "salvage")
end

function Inventory.isFull(player: Player): boolean
	local profile = Data.get(player)
	return profile ~= nil and #profile.inventory >= Inventory.capacity(player)
end

local function setBagAttributes(player: Player)
	local level = bagLevel(player)
	player:SetAttribute("BagLevel", level)
	player:SetAttribute("BagMax", Bag.capacity(level))
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
	if fromLoot and autoSalvages(player, profile, item) then
		Inventory.salvageLoot(player, item)
		return true, true, false
	end
	-- A unique from loot always fits, even over capacity (a full bag shows red, as after a season
	-- reset): boss uniques are rare and booked as found (pity, Veteran firsts, Systems/Loot), so
	-- they must never become salvage or vanish with the arena
	local keepUnique = fromLoot == true and item.rarity == "unique"
	if #profile.inventory >= Inventory.capacity(player) and not keepUnique then
		local hero = if fromLoot then Stats.hero(player) else nil
		if hero and not Upgrade.isUpgrade(hero, item) then
			Inventory.salvageLoot(player, item)
			return true, true, true
		end
		return false, false, true
	end
	table.insert(profile.inventory, item)
	snapshot(player)
	return true, false, false
end

-- txn (Analytics transaction type) logs the change as one economy event; loot pickups pass none
-- (Rift logs the run's gold once at its end)
function Inventory.addGold(player: Player, amount: number, txn: string?, sku: string?)
	local profile = Data.get(player)
	if profile then
		profile.gold += amount
		player:SetAttribute("Gold", profile.gold)
		if txn then
			Analytics.economy(player, "Gold", amount, profile.gold, txn, sku)
		end
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
	if not item or #profile.inventory >= Inventory.capacity(player) then
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
	if not Salvage.canSalvage(profile.inventory[index]) then
		snapshot(player) -- the client hid the cell already: bring it back
		return
	end
	local item = table.remove(profile.inventory, index) :: Items.Item
	salvageGold(player, item)
	Progress.salvage(player, item)
	snapshot(player)
	Actions.fire(player, "salvage")
end

-- Net.SalvageMany ids: bulk "Salvage all downgrades". Every id is checked again here: still in the
-- bag, not locked, not unique and still a downgrade for the hero (Salvage.isDowngrade), so a
-- stale or forged list can only salvage what the button would have offered. Returns the count.
function Inventory.salvageMany(player: Player, raw: any): number
	local profile = Data.get(player)
	local ids = Salvage.validIds(raw)
	if not profile or not ids then
		return 0
	end
	local hero = Stats.hero(player)
	if not hero then
		return 0
	end
	local wanted: { [string]: boolean } = {}
	for _, id in ids do
		wanted[id] = true
	end
	local keep: { Items.Item } = {}
	local gone: { Items.Item } = {}
	for _, item in profile.inventory do
		if wanted[item.id] and Salvage.isDowngrade(item, hero) then
			table.insert(gone, item)
		else
			table.insert(keep, item)
		end
	end
	if #gone == 0 then
		snapshot(player)
		return 0
	end
	-- One list swap, no yield: the bag never holds an item that was already paid out
	table.clear(profile.inventory)
	for _, item in keep do
		table.insert(profile.inventory, item)
	end
	for _, item in gone do
		salvageGold(player, item)
		Progress.salvage(player, item)
	end
	snapshot(player)
	Actions.fire(player, "salvage", #gone) -- quests count every item, like single salvages
	return #gone
end

-- Net.ItemLock id, on: locks or unlocks a bag or worn item (saved on the item)
function Inventory.setLock(player: Player, id: any, on: any): boolean
	local profile = Data.get(player)
	if not profile or typeof(id) ~= "string" or #id == 0 or #id > 64 or typeof(on) ~= "boolean" then
		return false
	end
	local item: Items.Item? = nil
	local index = findIndex(profile.inventory, id)
	if index then
		item = profile.inventory[index]
	else
		for _, worn in profile.equipped do
			if worn.id == id then
				item = worn
				break
			end
		end
	end
	if not item then
		return false
	end
	item.locked = if on then true else nil
	snapshot(player)
	return true
end

local function replyBag(player: Player, ok: boolean, text: string, price: number?)
	local level = bagLevel(player)
	Net.BagResult:FireClient(player, {
		ok = ok,
		text = text,
		level = level,
		capacity = Bag.capacity(level),
		price = price,
	})
end

-- Net.Bag "upgrade", level: buys the next bag level with the active hero's gold. Check, level
-- and gold change in one step without yielding, so two requests can never pay or level twice.
local function onBag(player: Player, action: any, target: any)
	if not allowBag(player) or action ~= "upgrade" or not Bag.validTarget(target) then
		return
	end
	local profile = Data.get(player)
	local account = Data.account(player)
	if not profile or not account then
		return
	end
	local level = Bag.level(account.season.bag)
	local reason, price = Bag.check(level, target, profile.gold)
	if reason ~= "ok" then
		replyBag(player, false, Bag.Text[reason])
		return
	end
	account.season.bag = level + 1
	Inventory.addGold(player, -price, "Shop", "bag_upgrade")
	setBagAttributes(player)
	snapshot(player)
	replyBag(player, true, Bag.doneText(level + 1), price)
end

local allowFilter = RateLimit.new(2, 4)

local allowBulk = RateLimit.new(1, 3)

-- rarity ("" = off; never uniques, they are the reason to play), keep: optional boolean
-- (keep upgrades); nil leaves it as it is (older clients send only the rarity)
local function onAutoSalvage(player: Player, rarity: any, keep: any)
	local profile = Data.get(player)
	if not profile or not allowFilter(player) or not Salvage.validLimit(rarity) then
		return
	end
	if keep ~= nil and typeof(keep) ~= "boolean" then
		return
	end
	profile.autoSalvage = rarity
	player:SetAttribute("AutoSalvage", rarity)
	if keep ~= nil then
		profile.autoKeep = keep
		player:SetAttribute("AutoKeep", keep)
	end
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	player:SetAttribute("Gold", profile.gold)
	player:SetAttribute("AutoSalvage", profile.autoSalvage)
	player:SetAttribute("AutoKeep", profile.autoKeep)
	setBagAttributes(player)
	recompute(player, true)
	snapshot(player)
end

function Inventory.init()
	Net.Equip.OnServerEvent:Connect(onEquip)
	Net.Unequip.OnServerEvent:Connect(onUnequip)
	Net.Sell.OnServerEvent:Connect(onSell)
	Net.AutoSalvage.OnServerEvent:Connect(onAutoSalvage)
	Net.ItemLock.OnServerEvent:Connect(function(player: Player, id: any, on: any)
		if allow(player) then
			Inventory.setLock(player, id, on)
		end
	end)
	Net.SalvageMany.OnServerEvent:Connect(function(player: Player, ids: any)
		if allowBulk(player) then
			Inventory.salvageMany(player, ids)
		end
	end)
	Net.Bag.OnServerEvent:Connect(onBag)
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
