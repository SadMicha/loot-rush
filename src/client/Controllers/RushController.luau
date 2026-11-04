--!strict
-- Stud Rush on the client (docs/GAMEPLAY.md "Stud Rush"): own kills pop studs that are vacuumed to the
-- character (BrickController.stud, purely visual). The server starts the Rush on its own when the
-- meter is full; the HUD shows the meter bar and the Rush in the buff bar (HudController).
-- Meter and state come from the attributes RushMeter / RushUntil / Rushing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rush = require(ReplicatedStorage.Shared.Rush)
local Status = require(ReplicatedStorage.Shared.Status)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local BrickController = require(script.Parent.BrickController)
local FeelController = require(script.Parent.FeelController)
local QuestController = require(script.Parent.QuestController)

local RushController = {}

local player = Players.LocalPlayer

-- Meter fill 0..1
function RushController.meter(): number
	local m = player:GetAttribute("RushMeter")
	return if typeof(m) == "number" then math.clamp(m / Rush.METER, 0, 1) else 0
end

-- Seconds left of the running Rush (0 = none)
function RushController.remaining(): number
	local untilT = player:GetAttribute("RushUntil")
	if player:GetAttribute("Rushing") ~= true or typeof(untilT) ~= "number" then
		return 0
	end
	return math.max(0, untilT - workspace:GetServerTimeNow())
end

function RushController.start()
	Net.Fx.OnClientEvent:Connect(function(kind: string, d: any)
		if typeof(d) ~= "table" then
			return
		end
		if kind == "death" and d.by == player.UserId and typeof(d.pos) == "Vector3" then
			local color = if typeof(d.color) == "Color3" then d.color else Color3.new(1, 0.85, 0.3)
			local boss = d.boss == true
			for _ = 1, Rush.studs(d.big == true and not boss, boss) do
				BrickController.stud(d.pos, color)
			end
		elseif kind == "rush" and d.who == player.UserId then
			-- What the Rush gives, so the player knows why everything got faster
			QuestController.toast("STUD RUSH! " .. Status.Defs.rush.text, Theme.Color.GoldHi)
			FeelController.shake(0.4)
		end
	end)
end

return RushController
