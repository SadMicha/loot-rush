--!strict
-- Glitzer-Schmiede auf dem Server: prüft die Anfrage, würfelt (Shared.Forge.apply), bucht Material ab
-- und ersetzt den Gegenstand im Inventar oder in der Ausrüstung. Der Client schickt nur
-- Aktion + Item-ID + Affix-Nummer und bekommt Inventar, Material und eine Rückmeldung zurück.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Forge)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)
local Stats = require(script.Parent.Stats)

local Forge = {}

local rng = Random.new()
local allow = RateLimit.new(4, 6)

local DONE: { [string]: string } = {
	add = "Neues Affix",
	tier = "Tier verbessert",
	reroll = "Neu gewürfelt",
	seal = "Versiegelt",
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

	-- Gegenstand suchen: erst Tasche, dann Ausrüstung
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

	local result = Rules.apply(actionId, item, affix :: number?, profile.materials, rng)
	if not result.ok or not result.item or not result.material or not result.cost then
		reply(player, false, result.reason or "Geht nicht", itemId)
		return
	end
	Progress.addMaterials(player, { [result.material] = -result.cost })
	if bagIndex then
		profile.inventory[bagIndex] = result.item
	elseif slot then
		profile.equipped[slot] = result.item
		Stats.refresh(player, false)
	end
	Inventory.sync(player)
	Progress.sync(player)
	local used = result.used or 0
	local text = DONE[actionId] or "Fertig"
	if Rules.ById[actionId].usesCharges then
		text ..= if used == 0
			then " · keine Ladung verbraucht!"
			else string.format(" · −%d Ladung%s", used, if used == 1 then "" else "en")
	end
	reply(player, true, text, itemId, used)
end

function Forge.init()
	Net.ForgeAct.OnServerEvent:Connect(onAct)
end

return Forge
