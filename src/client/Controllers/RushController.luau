--!strict
-- Stud Rush on the client (docs/STUD-RUSH.md): own kills pop studs that are vacuumed to the
-- character (BrickController.stud, purely visual), key G or the HUD Rush button asks the server
-- to start a Rush. Meter and state come from the attributes RushMeter / RushUntil / Rushing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Rush = require(ReplicatedStorage.Shared.Rush)
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

function RushController.ready(): boolean
	return RushController.meter() >= 1 and RushController.remaining() <= 0
end

function RushController.trigger()
	if RushController.ready() then
		Net.Rush:FireServer("start")
	end
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
			QuestController.toast("RUSH!", Color3.fromRGB(255, 214, 90))
			FeelController.shake(0.4)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.G then
			RushController.trigger()
		end
	end)
end

return RushController
