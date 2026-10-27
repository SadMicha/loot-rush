--!strict
-- Setzt Grundwerte für jeden Charakter: Lauftempo, kein Springen (Leertaste = Dash).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerSetup = {}

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local player = Players:GetPlayerFromCharacter(character)
	local speed = if player then (player:GetAttribute("StatSpeed") or 0) :: number else 0
	humanoid.WalkSpeed = Config.WALK_SPEED * (1 + speed / 100)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
end

local function onPlayer(player: Player)
	player:SetAttribute("InCombat", false)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

function PlayerSetup.init() end

function PlayerSetup.start()
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return PlayerSetup
