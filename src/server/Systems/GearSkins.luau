--!strict
-- Gear skins on the server (rules: Shared/GearSkins, looks: Shared/Gear, rotation:
-- Shared/ShopRotation). Owned skins are account-wide (account.gearSkins), worn ones per slot
-- (account.gearWear); Systems/Gear builds them on the body. Looks only, never stats.
--   • Buying (Net.Skin "buy"): Soulstars only. A paid non-season skin, set or trail/aura must be in
--     today's or this week's rotation (computed here from os.time()); a season skin or set only
--     while its season is live. Price, ownership and wallet are checked here, never trusted.
--   • Robux sets: Systems/Monetization (ProcessReceipt) → GearSkins.give; owned pieces are
--     refunded at their Soulstar price.
--   • Free skins: GearSkins.check grants every earned one (Shared/GearSkins.earned: facts of any
--     hero, daily claims, Great Build total, season track, playing in the season). Runs on join and
--     after Journey/Season/Great Build rewards, daily claims and fact changes (Journey.touch).
--   • Wearing (Net.Skin "wear"): an owned skin of that slot, "" = back to the class look.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticRules = require(ReplicatedStorage.Shared.Cosmetics)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Gear = require(ReplicatedStorage.Shared.Gear)
local Net = require(ReplicatedStorage.Shared.Net)
local Rotation = require(ReplicatedStorage.Shared.ShopRotation)
local Rules = require(ReplicatedStorage.Shared.GearSkins)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Cosmetics = require(script.Parent.Cosmetics)
local Data = require(script.Parent.Data)
local GearSystem = require(script.Parent.Gear)
local Shop = require(script.Parent.Shop)

local GearSkins = {}

local allow = RateLimit.new(4, 8)

-- Clock of every purchase and season check (tests move it)
GearSkins.now = os.time

type Result = { ok: boolean, text: string, kind: string?, id: string? }

function GearSkins.owns(player: Player, id: string): boolean
	local account = Data.account(player)
	return account ~= nil and account.gearSkins[id] == true
end

function GearSkins.sync(player: Player, unlocked: { string }?, result: Result?)
	local account = Data.account(player)
	if not account then
		return
	end
	local owned = {}
	for id in account.gearSkins do
		table.insert(owned, id)
	end
	table.sort(owned)
	Net.SkinState:FireClient(player, {
		owned = owned,
		wear = table.clone(account.gearWear),
		unlocked = unlocked,
		result = result,
	})
end

-- Grants a skin. false = unknown or already owned (the caller refunds a paid one).
-- A skin for a slot showing the class look is worn right away.
function GearSkins.give(player: Player, id: string): boolean
	local account = Data.account(player)
	local skin = Rules.ById[id]
	if not account or not skin or account.gearSkins[id] then
		return false
	end
	account.gearSkins[id] = true
	if account.gearWear[skin.slot] == nil then
		local class = player:GetAttribute("Class")
		if Rules.fits(skin.slot, id, if typeof(class) == "string" then class else nil) then
			account.gearWear[skin.slot] = id
			GearSystem.apply(player)
		end
	end
	return true
end

-- Grants every free skin the account has earned (idempotent); returns the new ids
function GearSkins.check(player: Player): { string }
	local account = Data.account(player)
	if not account then
		return {}
	end
	local new = {}
	for _, id in Rules.newlyEarned(account.gearSkins, Rules.context(account, GearSkins.now())) do
		if GearSkins.give(player, id) then
			table.insert(new, id)
		end
	end
	if #new > 0 then
		GearSkins.sync(player, new)
	end
	return new
end

-- Soulstar price of an offer for this player right now; nil + why when it cannot be bought
function GearSkins.quote(player: Player, kind: string, id: string): (number?, string?)
	local account = Data.account(player)
	if not account then
		return nil, "Not loaded yet"
	end
	local now = GearSkins.now()
	local season: string? = nil
	local price = 0
	if kind == "skin" then
		local skin = Rules.ById[id]
		if not skin or not skin.price then
			return nil, "Not for sale"
		end
		if account.gearSkins[id] then
			return nil, "Already owned"
		end
		season, price = skin.season, skin.price
	elseif kind == "set" then
		local set = Rules.SetById[id]
		if not set then
			return nil, "Not for sale"
		end
		price = Rules.setPrice(set, function(piece)
			return account.gearSkins[piece] == true
		end)
		if price <= 0 then
			return nil, "Already owned"
		end
		season = set.season
	elseif kind == "cosmetic" then
		local c = CosmeticRules.ById[id]
		if not c or not c.soulstars or c.season then
			return nil, "Not for sale"
		end
		if account.cosmetics[id] then
			return nil, "Already owned"
		end
		price = c.soulstars
	else
		return nil, "Not for sale"
	end
	if season then
		if not Rules.available(season, now) then
			return nil, "The season is over"
		end
	elseif not Rotation.offered(kind, id, now) then
		return nil, "No longer in the shop"
	end
	if account.soulstars < price then
		return nil, "Not enough Soulstars"
	end
	return price, nil
end

local function nameOf(kind: string, id: string): string
	if kind == "skin" then
		return Rules.ById[id].name
	elseif kind == "set" then
		return Rules.SetById[id].name
	end
	return CosmeticRules.ById[id].name
end

-- Books a Soulstar purchase; returns the result sent to the client
function GearSkins.buy(player: Player, kind: string, id: string): Result
	local price, why = GearSkins.quote(player, kind, id)
	if not price then
		return { ok = false, text = why or "Not possible", kind = kind, id = id }
	end
	Shop.grant(player, "soulstars", -price, "Shop", kind .. ":" .. id)
	if kind == "skin" then
		GearSkins.give(player, id)
	elseif kind == "set" then
		for _, piece in Rules.SetById[id].pieces do
			GearSkins.give(player, piece)
		end
	else
		Cosmetics.give(player, id)
		Cosmetics.sync(player)
	end
	return {
		ok = true,
		text = `{nameOf(kind, id)} unlocked! -{Format.currency(price)} Soulstars`,
		kind = kind,
		id = id,
	}
end

-- Wears an owned skin in its slot ("" = class look); false when refused
function GearSkins.wear(player: Player, slot: string, id: string): boolean
	local account = Data.account(player)
	if not account or not table.find(Gear.Slots, slot) then
		return false
	end
	if id == "" then
		account.gearWear[slot] = nil
	elseif account.gearSkins[id] and Rules.fits(slot, id) then
		account.gearWear[slot] = id
	else
		return false
	end
	GearSystem.apply(player)
	return true
end

local function onSkin(player: Player, action: any, a: any, b: any)
	if not allow(player) then
		return
	end
	if action == "buy" and typeof(a) == "string" and typeof(b) == "string" then
		if #a > 16 or #b > 64 then
			return
		end
		GearSkins.sync(player, nil, GearSkins.buy(player, a, b))
	elseif action == "wear" and typeof(a) == "string" and typeof(b) == "string" then
		if #a > 16 or #b > 64 then
			return
		end
		GearSkins.wear(player, a, b)
		GearSkins.sync(player)
	elseif action == "sync" then
		GearSkins.sync(player)
	end
end

local function onPlayer(player: Player)
	local account = Data.waitForAccount(player)
	if not account or not player.Parent then
		return
	end
	GearSkins.check(player)
	GearSkins.sync(player)
end

function GearSkins.init()
	Net.Skin.OnServerEvent:Connect(onSkin)
end

function GearSkins.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return GearSkins
