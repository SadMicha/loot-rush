--!strict
-- Stud Rush (docs/STUD-RUSH.md): the server counts the Rush meter from the kills it already
-- knows (no client stud claims) and owns the Rush state.
--   RushMeter (number 0..Rush.METER), RushUntil (server time, workspace:GetServerTimeNow()),
--   Rushing (bool) are player attributes; Net.Rush("start") triggers a Rush with a full meter.
-- During a Rush: more move speed (Combat.applySpeed), faster basic attacks (Combat basic loop),
-- kills add a little time (chain, capped), a glow on the character everyone sees.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RushRules = require(ReplicatedStorage.Shared.Rush)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)

local Rush = {}

local allow = RateLimit.new(2, 4)
local GLOW = Color3.fromRGB(255, 214, 90)

type State = { meter: number, startedAt: number, untilT: number }
local states: { [Player]: State } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function state(player: Player): State
	local st = states[player]
	if not st then
		st = { meter = 0, startedAt = 0, untilT = 0 }
		states[player] = st
	end
	return st
end

local function glow(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("RushGlow")
	if on and not old then
		local h = Instance.new("Highlight")
		h.Name = "RushGlow"
		h.FillColor = GLOW
		h.FillTransparency = 0.8
		h.OutlineColor = GLOW
		h.OutlineTransparency = 0.1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
	elseif not on and old then
		old:Destroy()
	end
end

function Rush.isRushing(player: Player): boolean
	return now() < state(player).untilT
end

function Rush.meter(player: Player): number
	return state(player).meter
end

-- Adds meter (kills); during a Rush the kill extends it instead (chain, capped)
function Rush.add(player: Player, amount: number)
	local st = state(player)
	if Rush.isRushing(player) then
		st.untilT = math.min(st.untilT + RushRules.CHAIN, st.startedAt + RushRules.MAX_DURATION)
		player:SetAttribute("RushUntil", st.untilT)
		return
	end
	st.meter = math.min(RushRules.METER, st.meter + amount)
	player:SetAttribute("RushMeter", st.meter)
end

local function stop(player: Player)
	local st = states[player]
	if st then
		st.untilT = 0
	end
	if player:GetAttribute("Rushing") then
		player:SetAttribute("Rushing", false)
		glow(player, false)
		Combat.speedChanged(player)
	end
end

-- Starts a Rush if the meter is full; false otherwise
function Rush.trigger(player: Player): boolean
	local st = state(player)
	if Rush.isRushing(player) or st.meter < RushRules.METER then
		return false
	end
	st.meter = 0
	st.startedAt = now()
	st.untilT = st.startedAt + RushRules.DURATION
	player:SetAttribute("RushMeter", 0)
	player:SetAttribute("RushUntil", st.untilT)
	player:SetAttribute("Rushing", true)
	glow(player, true)
	Combat.speedChanged(player)
	Net.Fx:FireAllClients("rush", { who = player.UserId })
	return true
end

local function onPlayer(player: Player)
	state(player)
	player:SetAttribute("RushMeter", 0)
	player:SetAttribute("RushUntil", 0)
	player:SetAttribute("Rushing", false)
	player.CharacterAdded:Connect(function()
		stop(player) -- a new character (death, hub) ends the Rush; the meter stays
	end)
end

function Rush.init()
	Net.Rush.OnServerEvent:Connect(function(player: Player, action: any)
		if allow(player) and action == "start" then
			Rush.trigger(player)
		end
	end)
	Combat.EnemyDied.Event:Connect(function(enemy: Model, _pos: Vector3, killer: Player?)
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") or not killer.Parent then
			return
		end
		Rush.add(
			killer,
			RushRules.gain(enemy:GetAttribute("Elite") == true, enemy:GetAttribute("Boss") == true)
		)
	end)
end

function Rush.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	-- Ends Rushes on time
	task.spawn(function()
		while true do
			task.wait(0.1)
			local t = now()
			for player, st in states do
				if st.untilT > 0 and t >= st.untilT then
					stop(player)
				end
			end
		end
	end)
end

return Rush
