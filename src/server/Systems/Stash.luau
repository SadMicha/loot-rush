--!strict
-- Hub stash (Shared/Stash): account-wide item storage shared by all heroes of the account.
-- Net.Stash (C→S): "open" | "put", itemId, tab | "take", itemId | "all", tab.
-- Every move is checked here: the player must stand at the stash station in the hub (not in a
-- Rift), the item must exist on the source side, and the target needs room. The item moves in
-- one step between two lists of the same save (Data.account), so nothing can be duplicated.
-- After a move the client gets both snapshots: Net.StashData and the bag (Inventory.sync).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Stash)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)

local Stash = {}

local STATION = "Station_Stash" -- Systems/Hub builds it (window "Stash")

-- Same budget as the bag actions: one tap = one request
local allow = RateLimit.new(8, 16)

local station: BasePart? = nil

local function stationPart(): BasePart?
	if station and station.Parent ~= nil then
		return station
	end
	local hub = workspace:FindFirstChild("Lumenhaven")
	local part = hub and hub:FindFirstChild(STATION, true)
	station = if part and part:IsA("BasePart") then part else nil
	return station
end

-- Standing at the stash: in the hub (no Rift) and within Config.STASH_RANGE of the station
function Stash.near(player: Player): boolean
	if player:GetAttribute("RiftRegion") ~= nil then
		return false
	end
	local part = stationPart()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not part or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= Config.STASH_RANGE
end

local function send(player: Player, text: string?)
	local account = Data.account(player)
	if not account then
		return
	end
	Net.StashData:FireClient(player, {
		tabs = account.stash.tabs,
		slots = Rules.TAB_SLOTS,
		text = text,
	})
end

Stash.sync = send

local function validId(id: any): boolean
	return typeof(id) == "string" and #id > 0 and #id <= Rules.MAX_ID
end

local function onStash(player: Player, action: any, a: any, b: any)
	if not allow(player) or typeof(action) ~= "string" then
		return
	end
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile then
		return
	end
	if not Stash.near(player) then
		send(player, Rules.Text.far)
		return
	end
	local result: Rules.Reason
	if action == "open" then
		send(player)
		return
	elseif action == "put" then
		if not validId(a) or not Rules.validTab(b) then
			return
		end
		result = Rules.deposit(account.stash, profile.inventory, a, b)
	elseif action == "take" then
		if not validId(a) then
			return
		end
		result = Rules.withdraw(account.stash, profile.inventory, a, Items.BAG_MAX)
	elseif action == "all" then
		if not Rules.validTab(a) then
			return
		end
		local moved = Rules.depositAll(account.stash, profile.inventory, a)
		result = if moved > 0 or #profile.inventory == 0 then "ok" else "full"
	else
		return
	end
	send(player, if result == "ok" then nil else Rules.Text[result])
	if result == "ok" then
		Inventory.sync(player)
	end
end

function Stash.init()
	Net.Stash.OnServerEvent:Connect(onStash)
end

return Stash
