--!strict
-- Class choice (docs/CLASSES.md): the first join asks for a class (attribute ClassChosen = false
-- opens the picker on the client); later the class can be changed in the hub, never in a rift.
-- Changing keeps skill levels and blooms (they are per skill), swaps the bar to the new class's
-- skills and the held weapon to the class weapon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Rift = require(script.Parent.Rift)
local Weapons = require(script.Parent.Weapons)

local ClassChoice = {}

local allow = RateLimit.new(1, 3)

-- Sets the class; false if not allowed right now (unknown id, in a rift, no save)
function ClassChoice.choose(player: Player, classId: any): boolean
	if typeof(classId) ~= "string" or not Classes.ById[classId] then
		return false
	end
	local profile = Data.get(player)
	if not profile or Rift.isRunning(player) then
		return false
	end
	local changed = profile.class ~= classId
	profile.class = classId
	profile.classChosen = true
	player:SetAttribute("ClassChosen", true)
	if changed then
		player:SetAttribute("Class", classId)
		Progress.classChanged(player)
		Combat.refreshStats(player, false)
		Weapons.equip(player)
	end
	return true
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if profile then
		player:SetAttribute("ClassChosen", profile.classChosen)
	end
end

function ClassChoice.init()
	Net.Class.OnServerEvent:Connect(function(player: Player, action: any, classId: any)
		if allow(player) and action == "choose" then
			ClassChoice.choose(player, classId)
		end
	end)
end

function ClassChoice.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return ClassChoice
