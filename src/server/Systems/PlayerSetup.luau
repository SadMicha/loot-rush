--!strict
-- Sets base values for every character: walk speed, no jumping (space = dash), strips the avatar
-- shirt and pants, and switches off Roblox's own name/health overlay (the client draws Gilded Ink
-- nameplates, Shared/Nameplate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerSetup = {}

-- Flat shirt/pants/T-shirt textures of the player's own avatar show through the gaps between the
-- armor plates and fight the studded look, so they are removed (and again when the avatar loader
-- adds them after the spawn). Accessories and hair stay.
local function isAvatarClothing(child: Instance): boolean
	return child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic")
end

local function stripClothing(character: Model)
	for _, child in character:GetChildren() do
		if isAvatarClothing(child) then
			child:Destroy()
		end
	end
	character.ChildAdded:Connect(function(child: Instance)
		if isAvatarClothing(child) then
			-- deferred: the engine is still parenting the child while this event fires
			task.defer(child.Destroy, child)
		end
	end)
end

local function onCharacter(character: Model)
	stripClothing(character)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local player = Players:GetPlayerFromCharacter(character)
	local speed = if player then (player:GetAttribute("StatSpeed") or 0) :: number else 0
	humanoid.WalkSpeed = Config.WALK_SPEED * (1 + speed / 100)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
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
