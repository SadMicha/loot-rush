--!strict
-- Robux on the server (IDs: Shared/Monetization).
--  • Developer Products: ProcessReceipt credits the goods (Soulstars/gold via Shop.grant,
--    cosmetics via Cosmetics.give - an already owned cosmetic is refunded in Soulstars). A purchase only counts
--    as booked once it is saved (Data.saveNow) - otherwise NotProcessedYet, Roblox asks
--    again later. The PurchaseId goes into account.receipts so nothing is credited twice.
--  • Game passes: ownership on join (UserOwnsGamePassAsync with retries) and after a purchase in
--    game (PromptGamePassPurchaseFinished). If the query fails, the last saved
--    ownership (account.passes) applies. Result: attribute Pass_<key> = true, Pass.attr, bonuses via Boosts.
-- The client opens the purchase dialog itself (MarketplaceService:PromptProductPurchase /
-- PromptGamePassPurchase) - the server only trusts the Roblox callbacks.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local CosmeticRules = require(ReplicatedStorage.Shared.Cosmetics)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Rules = require(ReplicatedStorage.Shared.Monetization)
local Store = require(ReplicatedStorage.Shared.Store)
local Boosts = require(script.Parent.Boosts)
local Cosmetics = require(script.Parent.Cosmetics)
local Data = require(script.Parent.Data)
local Shop = require(script.Parent.Shop)

local Monetization = {}

local OWN_TRIES = 3

local owned: { [Player]: { [string]: boolean } } = {}

function Monetization.owns(player: Player, key: string): boolean
	local o = owned[player]
	return o ~= nil and o[key] == true
end

-- Is there still an ownership entry for this player? (for tests: must be gone after leaving)
function Monetization.isTracked(player: Player): boolean
	return owned[player] ~= nil
end

local function setOwned(player: Player, pass: Rules.Pass)
	local o = owned[player]
	if not o then
		o = {}
		owned[player] = o
	end
	o[pass.key] = true
	player:SetAttribute(Rules.passAttr(pass.key), true)
	if pass.attr then
		player:SetAttribute(pass.attr, true)
	end
	local account = Data.account(player)
	if account then
		account.passes[pass.key] = true
	end
	Boosts.refresh(player)
end

-- Asks Roblox; nil = query failed
local function askOwns(player: Player, id: number): boolean?
	for attempt = 1, OWN_TRIES do
		local ok, result =
			pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		if ok then
			return result == true
		end
		if attempt < OWN_TRIES then
			task.wait(attempt)
		end
	end
	return nil
end

-- passes: defaults to Rules.Passes (tests pass a list with a real id to force the ownership query)
local function loadPasses(player: Player, passes: { Rules.Pass }?)
	local account = Data.waitForAccount(player)
	-- The player may have left while the save loaded: PlayerRemoving already cleared owned[player]
	-- and writing it again would leak the entry (same check after every yielding query below)
	if not account or not player.Parent then
		return
	end
	owned[player] = owned[player] or {}
	for _, pass in passes or Rules.Passes do
		local has: boolean? = nil
		if pass.id > 0 then
			has = askOwns(player, pass.id)
			if not player.Parent then
				owned[player] = nil
				return
			end
		end
		if has == nil then
			has = account.passes[pass.key] == true -- outage: last known state
		elseif has == false then
			account.passes[pass.key] = nil
		end
		if has and player.Parent then
			setOwned(player, pass)
		end
	end
	Boosts.refresh(player)
end
Monetization.loadPasses = loadPasses

-- ------------------------------------------------------------------ Developer Products
-- Credits one product (no checks: ProcessReceipt already matched the purchase). Returns the
-- feedback text ("+550 Soulstars · Ember Trail").
local function grant(player: Player, account: Profile.Account, product: Rules.Product): string
	local parts = {}
	local refund = 0
	if product.soulstars then
		Shop.grant(player, "soulstars", product.soulstars)
		table.insert(parts, "+" .. Format.int(product.soulstars) .. " Soulstars")
	end
	if product.gold then
		local profile = Data.get(player)
		local best = if profile then Atlas.bestDepth(profile.atlas) else 1
		local gold = Store.goldFor(product, best)
		Shop.grant(player, "gold", gold)
		table.insert(parts, "+" .. Format.int(gold) .. " Gold")
	end
	local cosmetics: { string } = product.cosmetics or {}
	for _, id in cosmetics do
		if Cosmetics.give(player, id) then
			local c = CosmeticRules.ById[id]
			table.insert(parts, if c then c.name else id)
		else
			refund += product.refund or 0
		end
	end
	if refund > 0 then
		Shop.grant(player, "soulstars", refund)
		table.insert(parts, "+" .. Format.int(refund) .. " Soulstars (already owned)")
	end
	if product.once then
		account.bought[product.key] = true
	end
	Cosmetics.sync(player)
	return table.concat(parts, " · ")
end

function Monetization.processReceipt(info: any): Enum.ProductPurchaseDecision
	local product =
		Rules.productById(if typeof(info.ProductId) == "number" then info.ProductId else 0)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	-- Receipts are account-wide: a purchase is booked once, whichever character is played
	local account = if player then Data.account(player) else nil
	if not product or not player or not account then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox asks again on the next join
	end
	local purchase = tostring(info.PurchaseId)
	if not table.find(account.receipts, purchase) then
		local text = grant(player, account, product)
		table.insert(account.receipts, purchase)
		while #account.receipts > Profile.MAX_RECEIPTS do
			table.remove(account.receipts, 1)
		end
		Net.ShopResult:FireClient(player, {
			ok = true,
			text = text,
			offerId = product.key,
			robux = true,
		})
	end
	if not Data.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.init()
	MarketplaceService.ProcessReceipt = Monetization.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, id: number, purchased: boolean)
			local pass = if purchased then Rules.passById(id) else nil
			if pass and player.Parent then
				setOwned(player, pass)
				Net.ShopResult:FireClient(player, {
					ok = true,
					text = pass.name .. " unlocked forever!",
					offerId = pass.key,
					robux = true,
				})
			end
		end
	)
	Boosts.source("passes", function(player)
		return Rules.bonus(function(key)
			return Monetization.owns(player, key)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
	end)
end

function Monetization.start()
	for _, player in Players:GetPlayers() do
		task.spawn(loadPasses, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(loadPasses, player)
	end)
end

return Monetization
