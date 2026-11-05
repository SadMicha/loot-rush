--!strict
-- Saves the settings window (Shared/Settings) in the account, so every hero shares them.
-- The client applies a change live and reports it here (Net.Setting key, value); the server only
-- validates and stores it. After loading, the saved settings go to the client once (Net.Settings).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Settings)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)
local Gear = require(script.Parent.Gear)

local Settings = {}

-- Sliders report on release only, toggles per tap: a few per second is plenty
local allow = RateLimit.new(8, 16)

-- Stores one setting; false when the request was ignored (no save, rate limit, invalid)
function Settings.set(player: Player, key: any, value: any): boolean
	local account = Data.account(player)
	if not account or not allow(player) then
		return false
	end
	if key == Rules.RESET then
		account.settings = Rules.fresh()
		task.defer(Gear.apply, player)
		return true
	end
	local v = Rules.validate(key, value)
	if v == nil then
		return false
	end
	account.settings[key :: string] = v
	if key == "hideHelmet" then
		task.defer(Gear.apply, player) -- the look on the body follows at once
	end
	return true
end

local function onPlayer(player: Player)
	local account = Data.waitForAccount(player)
	if not account or not player.Parent then
		return
	end
	Net.Settings:FireClient(player, table.clone(account.settings))
end

function Settings.init()
	Net.Setting.OnServerEvent:Connect(function(player: Player, key: any, value: any)
		Settings.set(player, key, value)
	end)
end

function Settings.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Settings
