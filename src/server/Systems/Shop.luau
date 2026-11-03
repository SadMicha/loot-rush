--!strict
-- Shop on the server: checks in-game purchases (Shared.Shop.check), deducts the price and credits the goods.
-- The client only sends the offer ID (Net.Buy) and gets feedback (Net.ShopResult).
-- Stocks no other system shows are available as player attributes: "Soulstars".
--
-- Robux purchases (ProcessReceipt, game passes) are booked by Systems/Monetization via Shop.grant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)

local Net = require(ReplicatedStorage.Shared.Net)
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

-- Display name of a stock kind ("gold" → "Gold")
function Shop.nameOf(kind: string): string
	return Rules.KindName[kind] or kind
end

-- Stocks for Shared.Shop.check
function Shop.wallet(player: Player): Rules.Wallet?
	local profile = Data.get(player)
	local account = Data.account(player)
	if not profile or not account then
		return nil
	end
	return {
		gold = profile.gold,
		soulstars = account.soulstars, -- account-wide
		candy = profile.materials.candy,
		shards = profile.materials.shards,
		dust = profile.materials.dust,
	}
end

-- Change stock (negative = deduct, never below 0) and show it to the client
function Shop.grant(player: Player, kind: string, amount: number)
	local profile = Data.get(player)
	local account = Data.account(player)
	if not profile or not account then
		return
	end
	if kind == "gold" then
		Inventory.addGold(player, math.max(amount, -profile.gold))
	elseif MATERIAL[kind] then
		Progress.addMaterials(player, { [kind] = amount })
		Progress.sync(player)
	elseif kind == "soulstars" then
		account.soulstars = math.max(0, account.soulstars + math.floor(amount))
		player:SetAttribute("Soulstars", account.soulstars)
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
	local best = if profile then Atlas.bestDepth(profile.atlas) else 1
	local ok, why = Rules.check(offer, wallet, best)
	local price = Rules.price(offer, best)
	if not ok or not price then
		reply(player, false, why or "Not possible", offerId)
		return
	end
	local amount = Rules.amount(offer, best)
	Shop.grant(player, price.kind, -price.amount)
	Shop.grant(player, offer.give, amount)
	reply(player, true, string.format("+%d %s", amount, Rules.KindName[offer.give]), offerId)
end

local function onPlayer(player: Player)
	local account = Data.waitForAccount(player)
	if account then
		player:SetAttribute("Soulstars", account.soulstars)
	end
end

function Shop.init()
	Net.Buy.OnServerEvent:Connect(onBuy)
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
