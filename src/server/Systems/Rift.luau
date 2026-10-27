--!strict
-- Rift-Ablauf: Betreten → Wellen → Boss → Wahl „tiefer“ oder „zurück ins Dorf“.
-- Ein Rift gleichzeitig pro Server; der Starter ist der Besitzer. Zustand liegt als Attribute am
-- Besitzer (siehe Types.luau), der Client liest nur. Tod, Verlassen oder Abbruch beenden den Lauf.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Combat = require(script.Parent.Combat)
local CombatState = require(script.Parent.CombatState)
local Metrics = require(script.Parent.Metrics)
local Enemies = require(script.Parent.Enemies)

type Run = {
	owner: Player,
	depth: number,
	wave: number,
}

local Rift = {}

local FAILED_SHOWN = 4 -- Sekunden, die „gescheitert“ im HUD steht
local POLL = 0.3

local run: Run? = nil
local rng = Random.new()

local function character(player: Player): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid then
		return model, root, humanoid
	end
	return nil, nil, nil
end

local function alive(r: Run): boolean
	if run ~= r or not r.owner.Parent then
		return false
	end
	local _, _, humanoid = character(r.owner)
	return humanoid ~= nil and humanoid.Health > 0
end

local function publish(r: Run, phase: string)
	r.owner:SetAttribute("RiftDepth", r.depth)
	r.owner:SetAttribute("RiftWave", r.wave)
	r.owner:SetAttribute("RiftWaves", Config.RIFT_WAVES)
	r.owner:SetAttribute("RiftPhase", phase)
end

local function enemiesLeft(): number
	return #CollectionService:GetTagged("Enemy")
end

local function spawnPoint(): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0, Config.ENEMY_ZONE_RADIUS)
	return Config.ENEMY_ZONE + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Wartet, bis alle Gegner tot sind. false = Lauf wurde abgebrochen.
local function waitClear(r: Run): boolean
	while alive(r) do
		local left = enemiesLeft()
		if r.owner:GetAttribute("RiftLeft") ~= left then
			r.owner:SetAttribute("RiftLeft", left)
		end
		if left == 0 then
			return true
		end
		task.wait(POLL)
	end
	return false
end

local function returnToHub(player: Player)
	local model = character(player)
	if model then
		model:PivotTo(CFrame.new(Config.HUB_POS))
		Combat.refreshStats(player, true)
		CombatState.reset(player)
	end
end

-- Beendet den Lauf. failed = Besitzer gestorben; sonst freiwillig verlassen.
local function finish(r: Run, failed: boolean)
	if run ~= r then
		return
	end
	run = nil
	Metrics.report(
		string.format("Tiefe %d %s", r.depth, if failed then "gescheitert" else "verlassen")
	)
	Enemies.clear()
	local owner = r.owner
	if not owner.Parent then
		return
	end
	owner:SetAttribute("RiftLeft", 0)
	if failed then
		owner:SetAttribute("RiftPhase", "failed") -- Respawn bringt den Spieler selbst zum Hub
		task.delay(FAILED_SHOWN, function()
			if owner.Parent and owner:GetAttribute("RiftPhase") == "failed" then
				owner:SetAttribute("RiftPhase", "")
			end
		end)
	else
		owner:SetAttribute("RiftPhase", "")
		returnToHub(owner)
	end
end

local function play(r: Run)
	Metrics.begin(r.owner)
	for wave = 1, Config.RIFT_WAVES do
		r.wave = wave
		publish(r, "wave")
		local count = math.min(
			Config.RIFT_WAVE_BASE + Config.RIFT_WAVE_STEP * ((wave - 1) + (r.depth - 1)),
			Config.RIFT_WAVE_MAX
		)
		for _ = 1, count do
			Enemies.spawn("slime", spawnPoint(), r.depth)
		end
		if not waitClear(r) then
			return finish(r, true)
		end
		task.wait(Config.RIFT_WAVE_PAUSE)
		if not alive(r) then
			return finish(r, true)
		end
	end

	publish(r, "boss")
	Enemies.spawn("boss", Config.ENEMY_ZONE, r.depth)
	if not waitClear(r) then
		return finish(r, true)
	end
	Metrics.report(string.format("Tiefe %d geschafft", r.depth))
	publish(r, "clear")
end

local function begin(player: Player)
	local model, _, humanoid = character(player)
	if run or not model or not humanoid or humanoid.Health <= 0 then
		return
	end
	local r: Run = { owner = player, depth = 1, wave = 0 }
	run = r
	model:PivotTo(CFrame.new(Config.RIFT_START))
	task.spawn(play, r)
end

local function deeper(player: Player)
	local r = run
	if not r or r.owner ~= player or player:GetAttribute("RiftPhase") ~= "clear" then
		return
	end
	r.depth += 1
	r.wave = 0
	Combat.refreshStats(player, true)
	task.spawn(play, r)
end

local function onAction(player: Player, action: any)
	if action == "enter" then
		begin(player)
	elseif action == "deeper" then
		deeper(player)
	elseif action == "leave" then
		local r = run
		if r and r.owner == player then
			finish(r, false)
		end
	end
end

function Rift.init()
	Net.Rift.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player: Player)
		local r = run
		if r and r.owner == player then
			finish(r, false)
		end
	end)
end

return Rift
