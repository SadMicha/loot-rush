--!strict
-- Entscheidet serverseitig, ob ein Spieler „im Kampf“ ist.
-- Kampf = ein Gegner (Tag "Enemy") im Radius ODER der Spieler hat gerade Schaden bekommen.
-- Ergebnis: Player-Attribut "InCombat" (repliziert automatisch, der Client liest es nur).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CombatState = {}

local lastCombat: { [Player]: number } = {}
local lastHealth: { [Player]: number } = {}

local function enemyNear(position: Vector3): boolean
	local r2 = Config.COMBAT_RADIUS * Config.COMBAT_RADIUS
	for _, enemy in CollectionService:GetTagged("Enemy") do
		local pos: Vector3? = nil
		if enemy:IsA("BasePart") then
			pos = enemy.Position
		elseif enemy:IsA("Model") then
			pos = enemy:GetPivot().Position
		end
		if pos then
			local d = pos - position
			if d.X * d.X + d.Z * d.Z <= r2 then
				return true
			end
		end
	end
	return false
end

local function update(player: Player, now: number)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return
	end

	local hurt = false
	local prev = lastHealth[player]
	if prev and humanoid.Health < prev then
		hurt = true
	end
	lastHealth[player] = humanoid.Health

	if hurt or enemyNear(root.Position) then
		lastCombat[player] = now
	end

	local inCombat = now - (lastCombat[player] or -math.huge) < Config.CALM_DELAY
	if player:GetAttribute("InCombat") ~= inCombat then
		player:SetAttribute("InCombat", inCombat)
	end
end

-- Kampf sofort beenden (z. B. Rückkehr in den Hub), ohne die Ruhe-Verzögerung abzuwarten
function CombatState.reset(player: Player)
	lastCombat[player] = nil
	lastHealth[player] = nil
	player:SetAttribute("InCombat", false)
end

function CombatState.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCombat[player] = nil
		lastHealth[player] = nil
	end)
end

function CombatState.start()
	while true do
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			update(player, now)
		end
		task.wait(Config.COMBAT_TICK)
	end
end

return CombatState
