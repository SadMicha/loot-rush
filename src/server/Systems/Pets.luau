--!strict
-- Pets on the server (rules: Shared/Pets). The client only sends requests via Net.Pet:
--   "hatch", eggId  → deduct the price, roll a pet, raise the level or give shards
--   "equip", petId / "unequip", petId → take/free a slot
-- State goes to the client as Net.Pets, feedback as Net.PetResult (kind = the action). Equipped pets
-- are listed comma-separated in the attribute "Pets" (for all clients, PetController makes them follow),
-- the slot count in "PetSlots". Bonuses run via Systems/Boosts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Pets)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Boosts = require(script.Parent.Boosts)
local Data = require(script.Parent.Data)
local Shop = require(script.Parent.Shop)

local Pets = {}

local allow = RateLimit.new(3, 6)
local rng = Random.new()

-- Egg odds for display before purchase (fixed, so computed once): { [eggId] = { Odd } }
local eggOdds: { [string]: { Rules.Odd } } = {}
for _, egg in Rules.Eggs do
	eggOdds[egg.id] = Rules.odds(egg)
end

-- Extra slots (game pass) are reported by Systems/Monetization via the attribute "PassPetSlot"
function Pets.slots(player: Player): number
	local extra = if player:GetAttribute("PassPetSlot") == true then 1 else 0
	return math.min(Rules.MAX_SLOTS, Rules.BASE_SLOTS + extra)
end

-- More equipped than there are slots (game pass gone)? Drop the extras - only on a
-- player action, not on load (game pass ownership may arrive later)
local function trim(player: Player, account: Data.Account)
	local list = account.pets.equipped
	while #list > Pets.slots(player) do
		table.remove(list)
	end
end

function Pets.sync(player: Player)
	local account = Data.account(player) -- pets are account-wide (all characters)
	if not account then
		return
	end
	local slots = Pets.slots(player)
	local shown = {}
	for i, id in account.pets.equipped do
		if i <= slots then
			table.insert(shown, id)
		end
	end
	player:SetAttribute("PetSlots", slots)
	player:SetAttribute("Pets", table.concat(shown, ","))
	Net.Pets:FireClient(player, {
		owned = Rules.knownOwned(account.pets), -- unknown ones (newer server) are not shown
		equipped = account.pets.equipped,
		slots = slots,
		odds = eggOdds,
	})
end

local function reply(player: Player, ok: boolean, text: string, extra: { [string]: any }?)
	local msg: { [string]: any } = { ok = ok, text = text }
	if extra then
		for k, v in extra do
			msg[k] = v
		end
	end
	Net.PetResult:FireClient(player, msg)
end

-- Hatch an egg. Returns (ok, text, pet ID?) (also for tests)
function Pets.hatch(player: Player, eggId: string): (boolean, string, string?)
	local profile = Data.get(player)
	local account = Data.account(player)
	local egg = Rules.EggById[eggId]
	if not profile or not account or not egg then
		return false, "Unknown egg", nil
	end
	local price =
		Rules.eggPrice(egg, Atlas.bestDepth(profile.atlas), Rules.ownedCount(account.pets))
	local have = if egg.price.kind == "gold" then profile.gold else account.soulstars
	if have < price then
		return false, "Not enough " .. Shop.nameOf(egg.price.kind), nil
	end
	if price > 0 then
		Shop.grant(player, egg.price.kind, -price)
	end
	local pet = Rules.roll(egg, rng)
	local level, shards = Rules.hatchResult(account.pets, pet.id)
	local fresh = account.pets.owned[pet.id] == nil
	account.pets.owned[pet.id] = level
	if shards > 0 then
		Shop.grant(player, "shards", shards)
	end
	-- equip the first pet right away if a slot is free
	if fresh and #account.pets.equipped < Pets.slots(player) then
		table.insert(account.pets.equipped, pet.id)
	end
	Boosts.refresh(player)
	Pets.sync(player)
	Actions.fire(player, "hatch")
	local text = if fresh
		then pet.name .. " hatched!"
		elseif shards > 0 then string.format(
			"%s is already max level: +%d shards",
			pet.name,
			shards
		)
		else string.format("%s rises to level %d!", pet.name, level)
	return true, text, pet.id
end

function Pets.equip(player: Player, petId: string): (boolean, string)
	local account = Data.account(player)
	local pet = Rules.ById[petId]
	if not account or not pet or not account.pets.owned[petId] then
		return false, "Pet missing"
	end
	trim(player, account)
	local list = account.pets.equipped
	if table.find(list, petId) then
		return false, "Already equipped"
	end
	if #list >= Pets.slots(player) then
		table.remove(list, 1) -- replace the oldest
	end
	table.insert(list, petId)
	Boosts.refresh(player)
	Pets.sync(player)
	return true, pet.name .. " joins you"
end

function Pets.unequip(player: Player, petId: string): (boolean, string)
	local account = Data.account(player)
	local index = if account then table.find(account.pets.equipped, petId) else nil
	if not account or not index then
		return false, "Not equipped"
	end
	table.remove(account.pets.equipped, index)
	Boosts.refresh(player)
	Pets.sync(player)
	local pet = Rules.ById[petId]
	return true, (if pet then pet.name else "Pet") .. " takes a rest"
end

local function onPet(player: Player, action: any, id: any)
	if not allow(player) or typeof(id) ~= "string" or #id > 64 then
		return
	end
	if action == "hatch" then
		local ok, text, petId = Pets.hatch(player, id)
		local account = Data.account(player)
		reply(player, ok, text, {
			kind = "hatch",
			pet = petId,
			level = if petId and account then account.pets.owned[petId] else nil,
		})
	elseif action == "equip" then
		local ok, text = Pets.equip(player, id)
		reply(player, ok, text, { kind = "equip", pet = id })
	elseif action == "unequip" then
		local ok, text = Pets.unequip(player, id)
		reply(player, ok, text, { kind = "unequip", pet = id })
	end
end

function Pets.init()
	Net.Pet.OnServerEvent:Connect(onPet)
	Boosts.source("pets", function(player)
		local account = Data.account(player)
		return if account then Rules.total(account.pets, Pets.slots(player)) else {}
	end)
end

function Pets.start()
	local function onPlayer(player: Player)
		if Data.waitFor(player) then
			Pets.sync(player)
			Boosts.refresh(player)
		end
		-- Game pass may arrive later (purchase in game)
		player:GetAttributeChangedSignal("PassPetSlot"):Connect(function()
			Boosts.refresh(player)
			Pets.sync(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Pets
