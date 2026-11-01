--!strict
-- Stations in the "Lumen Harbor" Hub: the server sets ProximityPrompts with the attribute "Window"
-- (Rift Gate -> Atlas, Forge, Market -> Shop, Stash -> Inventory, Pet Stable -> Pets).
-- The window is opened here. Stations without their own window in OPEN (e.g. "Pets", "Rebirth")
-- fire HubController.Requested(name) - a new window hooks in there.

local ProximityPromptService = game:GetService("ProximityPromptService")

local AtlasController = require(script.Parent.AtlasController)
local ForgeController = require(script.Parent.ForgeController)
local InventoryController = require(script.Parent.InventoryController)
local ShopController = require(script.Parent.ShopController)

local HubController = {
	-- (window: string) for stations that have no window in OPEN (yet)
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
		local window = prompt:GetAttribute("Window")
		local fn = if typeof(window) == "string" then OPEN[window] else nil
		if fn then
			fn()
		elseif typeof(window) == "string" then
			HubController.Requested:Fire(window)
		end
	end)
end

return HubController
