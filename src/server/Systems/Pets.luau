--!strict
-- Pets on the server (rules: Shared/Pets). The client only sends requests via Net.Pet:
--   "hatch", eggId  → deduct the price, roll a pet, raise the level or give shards
--   "equip", petId / "unequip", petId → take/free a slot
-- State goes to the client as Net.Pets, feedback as Net.PetResult. Equipped pets
-- are listed comma-separated in the attribute "Pets" (for all clients, PetController makes them follow),
-- the slot count in "PetSlots". Bonuses run via Systems/Boosts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Balance)
local Net = require(ReplicatedStorage.Shared.Net)
local Rebirth = require(ReplicatedStorage.Shared.Rebirth)
local Rules = require(ReplicatedStorage.Shared.Pets)
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

-- Price of an egg for this player (gold grows with the best depth, like in the shop)
function Pets.eggPrice(egg: Rules.Egg, bestDepth: number): number
	if egg.price.kind ~= "gold" then
		return egg.price.amount
	end
	return math.floor(egg.price.amount * Balance.shopFactor(bestDepth) + 0.5)
end

-- More equipped than there are slots (game pass gone)? Drop the extras - only on a
-- player action, not on load (game pass ownership may arrive later)
local function trim(player: Player, profile: Data.Profile)
	local list = profile.pets.equipped
	while #list > Pets.slots(player) do
		table.remove(list)
	end
end

function Pets.sync(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local slots = Pets.slots(player)
	local shown = {}
	for i, id in profile.pets.equipped do
		if i <= slots then
			table.insert(shown, id)
		end
	end
	player:SetAttribute("PetSlots", slots)
	player:SetAttribute("Pets", table.concat(shown, ","))
	Net.Pets:FireClient(player, {
		owned = Rules.knownOwned(profile.pets), -- unknown ones (newer server) are not shown
		equipped = profile.pets.equipped,
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
	local egg = Rules.EggById[eggId]
	if not profile or not egg then
		return false, "Unknown egg", nil
	end
	local price = Pets.eggPrice(egg, Rebirth.bestDepth(profile.atlas))
	local have = if egg.price.kind == "gold" then profile.gold else profile.soulstars
	if have < price then
		return false, "Not enough " .. Shop.nameOf(egg.price.kind), nil
	end
	Shop.grant(player, egg.price.kind, -price)
	local pet = Rules.roll(egg, rng)
	local level, shards = Rules.hatchResult(profile.pets, pet.id)
	local fresh = profile.pets.owned[pet.id] == nil
	profile.pets.owned[pet.id] = level
	if shards > 0 then
		Shop.grant(player, "shards", shards)
	end
	-- equip the first pet right away if a slot is free
	if fresh and #profile.pets.equipped < Pets.slots(player) then
		table.insert(profile.pets.equipped, pet.id)
	end
	Boosts.refresh(player)
	Pets.sync(player)
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
	local profile = Data.get(player)
	local pet = Rules.ById[petId]
	if not profile or not pet or not profile.pets.owned[petId] then
		return false, "Pet missing"
	end
	trim(player, profile)
	local list = profile.pets.equipped
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
	local profile = Data.get(player)
	local index = if profile then table.find(profile.pets.equipped, petId) else nil
	if not profile or not index then
		return false, "Not equipped"
	end
	table.remove(profile.pets.equipped, index)
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
		local profile = Data.get(player)
		reply(player, ok, text, {
			pet = petId,
			level = if petId and profile then profile.pets.owned[petId] else nil,
		})
	elseif action == "equip" then
		local ok, text = Pets.equip(player, id)
		reply(player, ok, text, { pet = id })
	elseif action == "unequip" then
		local ok, text = Pets.unequip(player, id)
		reply(player, ok, text, { pet = id })
	end
end

function Pets.init()
	Net.Pet.OnServerEvent:Connect(onPet)
	Boosts.source("pets", function(player, profile)
		return Rules.total(profile.pets, Pets.slots(player))
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
