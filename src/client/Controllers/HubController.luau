--!strict
-- Stations in the "Lumenhaven" Hub: the server sets ProximityPrompts with the attribute "Window"
-- (Rift Gate -> Atlas, Forge, Market -> Market window (attribute "Shop"), Stash -> Stash window, Pet Stable -> Pets).
-- The window is opened here. Stations without their own window in OPEN (e.g. "Pets")
-- fire HubController.Requested(name) - a new window hooks in there.

local ProximityPromptService = game:GetService("ProximityPromptService")

local AtlasController = require(script.Parent.AtlasController)
local ForgeController = require(script.Parent.ForgeController)
local InventoryController = require(script.Parent.InventoryController)
local LeaderboardController = require(script.Parent.LeaderboardController)
local MarketController = require(script.Parent.MarketController)
local QuestController = require(script.Parent.QuestController)
local StashController = require(script.Parent.StashController)

local HubController = {
	-- (window: string) for stations that have no window in OPEN (yet)
	Requested = Instance.new("BindableEvent"),
}

local OPEN: { [string]: () -> () } = {
	Atlas = AtlasController.toggle,
	Forge = function()
		local hint = QuestController.lockHint("forge")
		if hint then
			QuestController.toast("Locked - " .. hint)
		else
			ForgeController.toggle()
		end
	end,
	Inventory = InventoryController.toggle,
	Leaderboard = LeaderboardController.open,
	Shop = function() -- the Market station (stable attribute name)
		MarketController.open()
	end,
	Stash = StashController.open,
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
