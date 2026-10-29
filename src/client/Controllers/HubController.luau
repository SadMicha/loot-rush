--!strict
-- Stationen im Hub „Lumenhafen“: Der Server setzt ProximityPrompts mit dem Attribut „Fenster“
-- (Rift-Tor → Atlas, Schmiede, Markt → Shop, Stash → Inventar, Haustier-Stall → Pets).
-- Hier wird das Fenster geöffnet. Stationen ohne eigenes Fenster in OPEN (z. B. „Pets“, „Rebirth“)
-- feuern HubController.Requested(name) – daran hängt sich ein neues Fenster an.

local ProximityPromptService = game:GetService("ProximityPromptService")

local AtlasController = require(script.Parent.AtlasController)
local ForgeController = require(script.Parent.ForgeController)
local InventoryController = require(script.Parent.InventoryController)
local ShopController = require(script.Parent.ShopController)

local HubController = {
	-- (window: string) für Stationen, die (noch) kein Fenster in OPEN haben
	Requested = Instance.new("BindableEvent"),
}

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
		elseif typeof(window) == "string" then
			HubController.Requested:Fire(window)
		end
	end)
end

return HubController
