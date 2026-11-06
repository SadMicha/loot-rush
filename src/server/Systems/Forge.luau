--!strict
-- Forge on the server: checks the request, rolls (Shared.Forge.apply), deducts materials
-- and replaces the item in the inventory or in the gear. The client only sends
-- action + item ID + affix number and gets inventory, materials and feedback back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Forge)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)
local Stats = require(script.Parent.Stats)

local Forge = {}

local rng = Random.new()
local allow = RateLimit.new(4, 6)

local DONE: { [string]: string } = {
	add = "New affix",
	tier = "Tier upgraded",
	reroll = "Rerolled",
	seal = "Sealed",
	fuse = "Fused",
	attune = "Attuned",
}

local function reply(player: Player, ok: boolean, text: string, itemId: string?, used: number?)
	Net.ForgeResult:FireClient(player, { ok = ok, text = text, itemId = itemId, used = used })
end

local function onAct(player: Player, actionId: any, itemId: any, affix: any)
	if not allow(player) then
		return
	end
	if typeof(actionId) ~= "string" or typeof(itemId) ~= "string" or #itemId > 64 then
		return
	end
	if
		affix ~= nil and (typeof(affix) ~= "number" or affix % 1 ~= 0 or affix < 1 or affix > 16)
	then
		return
	end
	local profile = Data.get(player)
	if not profile or not Rules.ById[actionId] then
		return
	end

	-- Find the item: bag first, then gear
	local bagIndex: number? = nil
	local slot: string? = nil
	local item: Items.Item? = nil
	for i, it in profile.inventory do
		if it.id == itemId then
			bagIndex, item = i, it
			break
		end
	end
	if not item then
		for s, it in profile.equipped do
			if it.id == itemId then
				slot, item = s, it
				break
			end
		end
	end
	if not item then
		return
	end

	-- Fuse looks for a duplicate in the bag, Attune raises to the best loot level (Shared/Forge)
	local ctx: Rules.Context = {
		bag = profile.inventory,
		attune = Rules.attuneLevel(
			Atlas.bestDepth(profile.atlas),
			profile.tier.unlocked,
			Stats.level(player)
		),
	}
	local result = Rules.apply(actionId, item, affix :: number?, profile.materials, rng, ctx)
	if not result.ok or not result.item or not result.material or not result.cost then
		reply(player, false, result.reason or "Not possible", itemId)
		return
	end
	-- The player's lock stays on the forged item (Shared/Salvage)
	if item.locked then
		result.item.locked = true
	end
	if result.cost > 0 then
		Progress.addMaterials(player, { [result.material] = -result.cost }, "Gameplay", "forge")
	end
	if bagIndex then
		profile.inventory[bagIndex] = result.item
	elseif slot then
		profile.equipped[slot] = result.item
	end
	-- Fuse used up the duplicate: take it out of the bag (never the forged item itself)
	local consumed = result.consumed
	if consumed and consumed ~= item.id then
		for i, it in profile.inventory do
			if it.id == consumed then
				table.remove(profile.inventory, i)
				break
			end
		end
	end
	if slot then
		Stats.refresh(player, false)
	end
	Inventory.sync(player)
	Progress.sync(player)
	local used = result.used or 0
	local text = DONE[actionId] or "Done"
	if Rules.ById[actionId].usesCharges then
		text ..= if used == 0
			then " - no charge used!"
			else string.format(" - %d charge%s used", used, if used == 1 then "" else "s")
	end
	if actionId == "fuse" then
		text = string.format("Fused - Rank %s", Rules.rankName(Items.rankOf(result.item)))
	end
	reply(player, true, text, itemId, used)
	Actions.fire(player, "forge")
end

function Forge.init()
	Net.ForgeAct.OnServerEvent:Connect(onAct)
end

return Forge
