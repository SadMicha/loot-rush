--!strict
-- Wiedergeburt auf dem Server (Regeln: Shared/Rebirth). Der Client schickt nur Net.Rebirth,
-- der Server prüft Bedingung und Zustand (kein laufendes Rift), setzt zurück, gibt Seelensterne,
-- speichert sofort und antwortet über Net.RebirthResult.
-- Für das UI: Player-Attribute "Rebirths", "RebirthNeed" (nötige beste Tiefe), "BestDepth" (Rift)
-- und die Bonus-Attribute aus Systems/Boosts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Rebirth)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Boosts = require(script.Parent.Boosts)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)
local Rift = require(script.Parent.Rift)
local Shop = require(script.Parent.Shop)
local Stats = require(script.Parent.Stats)

local Rebirth = {}

local allow = RateLimit.new(0.5, 2)

local function publish(player: Player, rebirths: number)
	player:SetAttribute("Rebirths", rebirths)
	player:SetAttribute("RebirthNeed", Rules.required(rebirths))
end

local function reply(player: Player, ok: boolean, text: string, rebirths: number?)
	Net.RebirthResult:FireClient(player, { ok = ok, text = text, rebirths = rebirths })
end

-- Führt die Wiedergeburt aus. true = geklappt (auch für Tests)
function Rebirth.perform(player: Player): (boolean, string)
	local profile = Data.get(player)
	if not profile then
		return false, "Spielstand nicht geladen"
	end
	if Rift.isRunning(player) or player:GetAttribute("RiftRegion") ~= nil then
		return false, "Erst das Rift verlassen"
	end
	local ok, why = Rules.check(profile.rebirths, Rules.bestDepth(profile.atlas))
	if not ok then
		return false, why or "Geht noch nicht"
	end
	local n = profile.rebirths + 1
	profile.rebirths = n
	profile.atlas = {}
	profile.progress.stars = {} -- Sternpunkte kommen aus dem Level
	Inventory.addGold(player, -profile.gold)
	Combat.setLevel(player, 1, 0)
	Shop.grant(player, "soulstars", Rules.reward(n))
	publish(player, n)
	Rift.publishBest(player)
	Stats.refresh(player, true)
	Boosts.refresh(player)
	Progress.sync(player)
	Data.saveNow(player)
	return true, string.format("Wiedergeburt %d! +%d Seelensterne", n, Rules.reward(n))
end

local function onRebirth(player: Player)
	if not allow(player) then
		return
	end
	local ok, text = Rebirth.perform(player)
	local profile = Data.get(player)
	reply(player, ok, text, if profile then profile.rebirths else nil)
end

function Rebirth.init()
	Net.Rebirth.OnServerEvent:Connect(onRebirth)
	Boosts.source("rebirth", function(_player, profile)
		return Rules.bonus(profile.rebirths)
	end)
end

function Rebirth.start()
	local function onPlayer(player: Player)
		local profile = Data.waitFor(player)
		if profile then
			publish(player, profile.rebirths)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Rebirth
