--!strict
-- "Bag full" notice (audit #7, docs/CRITERIA-AUDIT.md): when the bag reaches its capacity
-- (snapshot field `capacity`, Shared/Bag), one toast says what happens now (Systems/Inventory:
-- loot that is no upgrade gets salvaged, upgrades wait on the ground). It fires again only after
-- the bag had room in between.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bag = require(ReplicatedStorage.Shared.Bag)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local QuestController = require(script.Parent.QuestController)

local BagController = {}

local full: boolean? = nil -- nil until the first snapshot (no toast on join)

function BagController.start()
	Net.Inv.OnClientEvent:Connect(function(snap: any)
		if typeof(snap) ~= "table" or typeof(snap.items) ~= "table" then
			return
		end
		local now = #snap.items >= Bag.fromAttribute(snap.capacity)
		if now and full == false then
			QuestController.toast(
				"Bag full! New loot gets salvaged. Make room in the Inventory",
				Theme.Color.Danger
			)
		end
		full = now
	end)
end

return BagController
