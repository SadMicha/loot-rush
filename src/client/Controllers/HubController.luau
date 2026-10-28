--!strict
-- Stationen im Hub „Lumenhafen“: Der Server setzt ProximityPrompts mit dem Attribut „Fenster“
-- (Rift-Tor → Atlas, Schmiede, Markt → Shop, Stash → Inventar). Hier wird das Fenster geöffnet.

local ProximityPromptService = game:GetService("ProximityPromptService")

local AtlasController = require(script.Parent.AtlasController)
local ForgeController = require(script.Parent.ForgeController)
local InventoryController = require(script.Parent.InventoryController)
local ShopController = require(script.Parent.ShopController)

local HubController = {}

local OPEN: { [string]: () -> () } = {
	Atlas = AtlasController.toggle,
	Forge = ForgeController.toggle,
	Inventory = InventoryController.toggle,
	Shop = function()
		ShopController.open()
	end,
}

function HubController.init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local window = prompt:GetAttribute("Fenster")
		local fn = if typeof(window) == "string" then OPEN[window] else nil
		if fn then
			fn()
		end
	end)
end

return HubController
