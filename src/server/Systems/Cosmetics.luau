--!strict
-- Cosmetics on the server (rules: Shared/Cosmetics). Owned cosmetics are account-wide
-- (account.cosmetics), worn ones per slot (account.wear). Robux packs grant them via
-- Systems/Monetization → Cosmetics.give. The effect (trail, aura) is built on the character here,
-- so everyone in the server sees it. The client only asks to wear (Net.Wear) and gets the state
-- (Net.Store).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Cosmetics)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)

local Cosmetics = {}

local allow = RateLimit.new(3, 6)

local TRAIL = "CosmeticTrail"
local AURA = "CosmeticAura"
local ATTACH_A = "CosmeticA"
local ATTACH_B = "CosmeticB"

local function sequence(colors: { Color3 }): ColorSequence
	if #colors >= 2 then
		return ColorSequence.new(colors[1], colors[#colors])
	end
	return ColorSequence.new(colors[1] or Color3.new(1, 1, 1))
end

local function clearFx(root: BasePart)
	for _, name in { TRAIL, AURA, ATTACH_A, ATTACH_B } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

-- Builds the worn effects on the character (again after every change or respawn)
function Cosmetics.apply(player: Player)
	local account = Data.account(player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not account or not root or not root:IsA("BasePart") then
		return
	end
	clearFx(root)

	local trail = Rules.ById[account.wear.trail or ""]
	if trail then
		local half = Rules.TRAIL_WIDTH / 2
		local a = Instance.new("Attachment")
		a.Name = ATTACH_A
		a.Position = Vector3.new(0, half, 0.6)
		a.Parent = root
		local b = Instance.new("Attachment")
		b.Name = ATTACH_B
		b.Position = Vector3.new(0, -half, 0.6)
		b.Parent = root
		local t = Instance.new("Trail")
		t.Name = TRAIL
		t.Attachment0 = a
		t.Attachment1 = b
		t.Color = sequence(trail.colors)
		t.LightEmission = trail.light
		t.Lifetime = Rules.TRAIL_LIFETIME
		t.FaceCamera = true
		t.Transparency = NumberSequence.new(0.15, 1)
		t.WidthScale = NumberSequence.new(1, 0.2)
		t.Parent = root
	end

	local aura = Rules.ById[account.wear.aura or ""]
	if aura then
		local p = Instance.new("ParticleEmitter")
		p.Name = AURA
		p.Color = sequence(aura.colors)
		p.LightEmission = aura.light
		p.Rate = Rules.AURA_RATE
		p.Lifetime = NumberRange.new(Rules.AURA_LIFETIME * 0.7, Rules.AURA_LIFETIME)
		p.Speed = NumberRange.new(1.5, 3)
		p.SpreadAngle = Vector2.new(25, 25)
		p.EmissionDirection = Enum.NormalId.Top
		p.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, Rules.AURA_SIZE),
			NumberSequenceKeypoint.new(1, 0),
		})
		p.Transparency = NumberSequence.new(0.1, 1)
		p.LightInfluence = 0
		p.Shape = Enum.ParticleEmitterShape.Cylinder
		p.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		p.Parent = root
	end
end

-- Robux shop state for the client
function Cosmetics.sync(player: Player)
	local account = Data.account(player)
	if not account then
		return
	end
	local owned, bought = {}, {}
	for id in account.cosmetics do
		table.insert(owned, id)
	end
	for key in account.bought do
		table.insert(bought, key)
	end
	Net.Store:FireClient(player, {
		cosmetics = owned,
		wear = table.clone(account.wear),
		bought = bought,
	})
end

function Cosmetics.owns(player: Player, id: string): boolean
	local account = Data.account(player)
	return account ~= nil and account.cosmetics[id] == true
end

-- Grants a cosmetic. false = already owned (or unknown): the caller refunds.
-- A cosmetic for an empty slot is worn right away.
function Cosmetics.give(player: Player, id: string): boolean
	local account = Data.account(player)
	local c = Rules.ById[id]
	if not account or not c or account.cosmetics[id] then
		return false
	end
	account.cosmetics[id] = true
	if (account.wear[c.slot] or "") == "" then
		account.wear[c.slot] = id
		Cosmetics.apply(player)
	end
	return true
end

local function onWear(player: Player, slot: any, id: any)
	if not allow(player) or typeof(slot) ~= "string" or typeof(id) ~= "string" then
		return
	end
	local account = Data.account(player)
	if not account or not Rules.fits(slot, id) then
		return
	end
	if id ~= "" and not account.cosmetics[id] then
		return
	end
	account.wear[slot] = id
	Cosmetics.apply(player)
	Cosmetics.sync(player)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		local character = player.Character
		if character then
			character:WaitForChild("HumanoidRootPart", 10)
		end
		Cosmetics.apply(player)
	end)
	local account = Data.waitForAccount(player)
	if account and player.Parent then
		Cosmetics.apply(player)
		Cosmetics.sync(player)
	end
end

function Cosmetics.init()
	Net.Wear.OnServerEvent:Connect(onWear)
end

function Cosmetics.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Cosmetics
