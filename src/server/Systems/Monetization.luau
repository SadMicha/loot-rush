--!strict
-- Robux auf dem Server (IDs: Shared/Monetization).
--  • Developer Products: ProcessReceipt schreibt die Ware über Shop.grant gut. Ein Kauf gilt erst
--    als verbucht, wenn er gespeichert ist (Data.saveNow) – sonst NotProcessedYet, Roblox fragt
--    später erneut. Die PurchaseId landet in profile.receipts, damit nichts doppelt kommt.
--  • Gamepässe: Besitz beim Beitritt (UserOwnsGamePassAsync mit Wiederholung) und nach Kauf im
--    Spiel (PromptGamePassPurchaseFinished). Fällt die Abfrage aus, gilt der zuletzt gespeicherte
--    Besitz (profile.passes). Ergebnis: Attribut Pass_<key> = true, Pass.attr, Boni über Boosts.
-- Den Kaufdialog öffnet der Client selbst (MarketplaceService:PromptProductPurchase /
-- PromptGamePassPurchase) – der Server vertraut nur den Roblox-Callbacks.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Rules = require(ReplicatedStorage.Shared.Monetization)
local ShopRules = require(ReplicatedStorage.Shared.Shop)
local Boosts = require(script.Parent.Boosts)
local Data = require(script.Parent.Data)
local Shop = require(script.Parent.Shop)

local Monetization = {}

local OWN_TRIES = 3

local owned: { [Player]: { [string]: boolean } } = {}

function Monetization.owns(player: Player, key: string): boolean
	local o = owned[player]
	return o ~= nil and o[key] == true
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
	local profile = Data.get(player)
	if profile then
		profile.passes[pass.key] = true
	end
	Boosts.refresh(player)
end

-- Fragt Roblox; nil = Abfrage fehlgeschlagen
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

local function loadPasses(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	owned[player] = owned[player] or {}
	for _, pass in Rules.Passes do
		local has: boolean? = nil
		if pass.id > 0 then
			has = askOwns(player, pass.id)
		end
		if has == nil then
			has = profile.passes[pass.key] == true -- Ausfall: letzter bekannter Stand
		elseif has == false then
			profile.passes[pass.key] = nil
		end
		if has and player.Parent then
			setOwned(player, pass)
		end
	end
	Boosts.refresh(player)
end

-- ------------------------------------------------------------------ Developer Products
function Monetization.processReceipt(info: any): Enum.ProductPurchaseDecision
	local product =
		ShopRules.productById(if typeof(info.ProductId) == "number" then info.ProductId else 0)
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
		Net.ShopResult:FireClient(player, {
			ok = true,
			text = string.format("+%d %s", product.amount, ShopRules.KindName[product.give]),
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
				Net.ShopResult:FireClient(
					player,
					{ ok = true, text = pass.name .. " freigeschaltet!" }
				)
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
