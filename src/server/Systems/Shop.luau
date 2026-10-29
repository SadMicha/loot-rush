--!strict
-- Shop auf dem Server: prüft Ingame-Käufe (Shared.Shop.check), bucht Preis ab und schreibt die Ware gut.
-- Der Client schickt nur die Angebots-ID (Net.Buy) und bekommt eine Rückmeldung (Net.ShopResult).
-- Bestände, die kein anderes System zeigt, stehen als Player-Attribute bereit: "Potions", "Soulstars".
--
-- Robux: Developer Products aus Shared.Shop.Products. Solange alle IDs 0 sind, wird ProcessReceipt
-- gar nicht gesetzt. Ein Kauf gilt erst als verbucht, wenn er gespeichert ist (Data.saveNow);
-- die PurchaseId landet in profile.receipts, damit ein wiederholter Callback nichts doppelt gibt.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Rebirth = require(ReplicatedStorage.Shared.Rebirth)
local Rules = require(ReplicatedStorage.Shared.Shop)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)

local Shop = {}

local allow = RateLimit.new(4, 8)

local MATERIAL: { [string]: boolean } = { candy = true, shards = true, dust = true }

local function reply(player: Player, ok: boolean, text: string, offerId: string?)
	Net.ShopResult:FireClient(player, { ok = ok, text = text, offerId = offerId })
end

-- Bestände für Shared.Shop.check
function Shop.wallet(player: Player): Rules.Wallet?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	return {
		gold = profile.gold,
		soulstars = profile.soulstars,
		potions = profile.potions,
		candy = profile.materials.candy,
		shards = profile.materials.shards,
		dust = profile.materials.dust,
	}
end

-- Bestand ändern (negativ = abbuchen, nie unter 0) und dem Client zeigen
function Shop.grant(player: Player, kind: string, amount: number)
	local profile = Data.get(player)
	if not profile then
		return
	end
	if kind == "gold" then
		Inventory.addGold(player, math.max(amount, -profile.gold))
	elseif MATERIAL[kind] then
		Progress.addMaterials(player, { [kind] = amount })
		Progress.sync(player)
	elseif kind == "potions" then
		local max = Rules.Max.potions
		profile.potions = math.clamp(profile.potions + math.floor(amount), 0, max)
		player:SetAttribute("Potions", profile.potions)
	elseif kind == "soulstars" then
		profile.soulstars = math.max(0, profile.soulstars + math.floor(amount))
		player:SetAttribute("Soulstars", profile.soulstars)
	end
end

local function onBuy(player: Player, offerId: any)
	if not allow(player) or typeof(offerId) ~= "string" then
		return
	end
	local offer = Rules.ById[offerId]
	local wallet = Shop.wallet(player)
	if not offer or not wallet then
		return
	end
	local profile = Data.get(player)
	local best = if profile then Rebirth.bestDepth(profile.atlas) else 1
	local ok, why = Rules.check(offer, wallet, best)
	local price = Rules.price(offer, best)
	if not ok or not price then
		reply(player, false, why or "Geht nicht", offerId)
		return
	end
	local amount = Rules.amount(offer, best)
	Shop.grant(player, price.kind, -price.amount)
	Shop.grant(player, offer.give, amount)
	reply(player, true, string.format("+%d %s", amount, Rules.KindName[offer.give]), offerId)
end

-- ------------------------------------------------------------------ Robux
local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local product = Rules.productById(info.ProductId)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local profile = if player then Data.get(player) else nil
	if not product or not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox fragt beim nächsten Beitritt erneut
	end
	local purchase = tostring(info.PurchaseId)
	if not table.find(profile.receipts, purchase) then
		Shop.grant(player, product.give, product.amount)
		table.insert(profile.receipts, purchase)
		while #profile.receipts > Profile.MAX_RECEIPTS do
			table.remove(profile.receipts, 1)
		end
		reply(player, true, string.format("+%d %s", product.amount, Rules.KindName[product.give]))
	end
	if not Data.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if profile then
		player:SetAttribute("Potions", profile.potions)
		player:SetAttribute("Soulstars", profile.soulstars)
	end
end

function Shop.init()
	Net.Buy.OnServerEvent:Connect(onBuy)
	if Rules.hasLiveProducts() then
		MarketplaceService.ProcessReceipt = processReceipt
	end
end

function Shop.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Shop
