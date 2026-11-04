--!strict
-- Shows every hero's worn cosmetics in 3D, purely local (looks: Shared/CosmeticFx, parts:
-- Client/Fx/CosmeticRig). What someone wears comes from the player attributes WearAura and
-- WearTrail (Systems/Cosmetics); the server itself only builds the trail ribbon.
--   aura   layered rig at the feet (sigil, rings, orbiting shards, motes, light pillar, sprites)
--   trail  extras on top of the server ribbon: sparks while running, a bright core ribbon (legend)
--   equip  a shock ring (+ light column) when someone puts a cosmetic on; sound for the own hero
-- Budget for 12 players: own hero full detail, the nearest others full up to a cap by the
-- Effects quality setting, the rest "lite" (sigil + 2 shards), far ones nothing; sprite particles
-- only on the nearest few. Everything is removed on swap, respawn and leave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Fx = require(ReplicatedStorage.Shared.CosmeticFx)
local Kit = require(ReplicatedStorage.Shared.Models.Kit)
local Prefs = require(script.Parent.Parent.Prefs)
local Rig = require(script.Parent.Parent.Fx.CosmeticRig)
local SoundController = require(script.Parent.SoundController)

local AuraController = {}

local SPARK_AT = "CosmeticSparkAt"
local SPARKS = "CosmeticSparks"
local CORE = "CosmeticCore"
local CORE_A = "CosmeticCoreA"
local CORE_B = "CosmeticCoreB"

type Entry = {
	player: Player,
	aura: string,
	trail: string,
	detail: Fx.Detail,
	rig: Rig.Rig?,
	sparks: ParticleEmitter?,
	trailFx: { Instance },
	connections: { RBXScriptConnection },
}

local folder: Folder
local entries: { [Player]: Entry } = {}
local me = Players.LocalPlayer
local lodAt = 0
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, humanoid
end

local function feet(root: BasePart, humanoid: Humanoid?): CFrame
	local r15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
	local drop = Fx.feetDrop(r15, if humanoid then humanoid.HipHeight else 2, root.Size.Y)
	return CFrame.new(root.Position - Vector3.new(0, drop, 0))
end

local function level(): string
	return Prefs.effectLevel()
end

-- ------------------------------------------------------------------ Aura
local function dropRig(e: Entry)
	local rig = e.rig
	if rig then
		Rig.destroy(rig)
	end
	e.rig = nil
end

local function buildRig(e: Entry)
	dropRig(e)
	local c = Cosmetics.ById[e.aura]
	if not c or c.slot ~= "aura" or e.detail == "off" then
		return
	end
	local root = rootOf(e.player)
	if not root then
		return
	end
	e.rig = Rig.aura(c, Fx.plan(c, e.detail), folder, { world = true })
end

-- ------------------------------------------------------------------ Trail extras
local function dropTrail(e: Entry)
	for _, inst in e.trailFx do
		inst:Destroy()
	end
	table.clear(e.trailFx)
	e.sparks = nil
end

local function buildTrail(e: Entry)
	dropTrail(e)
	local c = Cosmetics.ById[e.trail]
	local root = rootOf(e.player)
	if not c or c.slot ~= "trail" or not root or e.detail == "off" then
		return
	end
	local tier = Fx.trailTier(c.rarity)
	local style = Fx.style(c)
	if tier.sparks > 0 then
		local at = Instance.new("Attachment")
		at.Name = SPARK_AT
		at.Position = Vector3.new(0, -0.6, 0.5)
		local p = Instance.new("ParticleEmitter")
		p.Name = SPARKS
		p.Rate = 0
		p.Lifetime = NumberRange.new(0.4, 0.8)
		p.Speed = NumberRange.new(0.5, 2)
		p.SpreadAngle = Vector2.new(60, 60)
		p.Acceleration = Vector3.new(0, -6, 0)
		p.Color = ColorSequence.new(style.core, style.deep)
		p.LightEmission = c.light
		p.LightInfluence = 0
		p.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		p.Transparency = NumberSequence.new(0.1, 1)
		p.RotSpeed = NumberRange.new(-120, 120)
		Kit.vfx(p, "mote_stud")
		p.Parent = at
		at.Parent = root
		e.sparks = p
		table.insert(e.trailFx, at)
	end
	if tier.core and e.detail == "full" then
		local a = Instance.new("Attachment")
		a.Name = CORE_A
		a.Position = Vector3.new(0, 0.25, 0.55)
		local b = Instance.new("Attachment")
		b.Name = CORE_B
		b.Position = Vector3.new(0, -0.25, 0.55)
		local t = Instance.new("Trail")
		t.Name = CORE
		t.Attachment0 = a
		t.Attachment1 = b
		t.Color = ColorSequence.new(Color3.new(1, 1, 1), style.core)
		t.LightEmission = 1
		t.LightInfluence = 0
		t.FaceCamera = true
		t.Lifetime = tier.lifetime * 0.75
		t.Transparency = NumberSequence.new(0.05, 1)
		t.WidthScale = NumberSequence.new(1, 0)
		a.Parent = root
		b.Parent = root
		t.Parent = root
		table.insert(e.trailFx, a)
		table.insert(e.trailFx, b)
		table.insert(e.trailFx, t)
	end
end

-- ------------------------------------------------------------------ Equip moment
local function celebrate(e: Entry, id: string)
	local c = Cosmetics.ById[id]
	local root, humanoid = rootOf(e.player)
	if not c or not root then
		return
	end
	local own = e.player == me
	if not own and e.detail ~= "full" then
		return
	end
	local big = c.slot == "aura"
	Rig.burst(folder, feet(root, humanoid), Fx.style(c).core, Fx.BURST_RADIUS, big)
	if own then
		SoundController.play(
			if c.rarity == "legend" then "cosmetic_equip_legend" else "cosmetic_equip"
		)
	end
end

-- ------------------------------------------------------------------ Players
local function read(player: Player, slot: string): string
	local v = player:GetAttribute(Fx.ATTR[slot])
	return if typeof(v) == "string" then v else ""
end

local function rebuild(e: Entry)
	buildRig(e)
	buildTrail(e)
end

local function forget(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	dropRig(e)
	dropTrail(e)
	for _, conn in e.connections do
		conn:Disconnect()
	end
	entries[player] = nil
end

local function watch(player: Player)
	if entries[player] then
		return
	end
	local e: Entry = {
		player = player,
		aura = read(player, "aura"),
		trail = read(player, "trail"),
		detail = if player == me then Fx.detail(true, 0, 0, level()) else "off",
		rig = nil,
		sparks = nil,
		trailFx = {},
		connections = {},
	}
	entries[player] = e
	for _, slot in Cosmetics.Slots do
		table.insert(
			e.connections,
			player:GetAttributeChangedSignal(Fx.ATTR[slot]):Connect(function()
				local id = read(player, slot)
				if slot == "aura" then
					e.aura = id
					buildRig(e)
				else
					e.trail = id
					buildTrail(e)
				end
				if id ~= "" then
					celebrate(e, id)
				end
			end)
		)
	end
	table.insert(
		e.connections,
		player.CharacterAdded:Connect(function(character: Model)
			dropRig(e)
			dropTrail(e)
			character:WaitForChild("HumanoidRootPart", 10)
			if entries[player] == e then
				rebuild(e)
			end
		end)
	)
	table.insert(
		e.connections,
		player.CharacterRemoving:Connect(function()
			dropRig(e)
			dropTrail(e)
		end)
	)
	rebuild(e)
end

-- ------------------------------------------------------------------ LOD
type Ranked = { e: Entry, d: number }

local function lod()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local others: { Ranked } = {}
	for player, e in entries do
		local root = rootOf(player)
		local d = if root then (root.Position - eye).Magnitude else math.huge
		if player ~= me then
			table.insert(others, { e = e, d = d })
		end
	end
	table.sort(others, function(a: Ranked, b: Ranked): boolean
		return a.d < b.d
	end)
	local lvl = level()
	local function set(e: Entry, detail: Fx.Detail)
		if e.detail ~= detail then
			e.detail = detail
			rebuild(e)
		end
	end
	local own = entries[me]
	if own then
		set(own, Fx.detail(true, 0, 0, lvl))
	end
	for rank, r in others do
		set(r.e, Fx.detail(false, r.d, rank, lvl))
	end
	-- Sprite particles only on the nearest few auras (own first)
	local sprites = 0
	local function spriteBudget(e: Entry)
		local rig = e.rig
		local emitter = rig and rig.emitter
		if emitter then
			sprites += 1
			emitter.Enabled = sprites <= Fx.SPRITE_LIMIT
		end
	end
	if own then
		spriteBudget(own)
	end
	for _, r in others do
		spriteBudget(r.e)
	end
	-- Trail sparks follow the running speed
	for player, e in entries do
		local sparks = e.sparks
		local root = rootOf(player)
		local c = Cosmetics.ById[e.trail]
		if sparks and root and c then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			sparks.Rate = Fx.trailTier(c.rarity).sparks
				* math.clamp(speed / Fx.TRAIL_SPARK_SPEED, 0, 1)
		end
	end
end

local function frame()
	local now = os.clock()
	if now >= lodAt then
		lodAt = now + Fx.LOD_EVERY
		lod()
	end
	table.clear(moveParts)
	table.clear(moveCFrames)
	for player, e in entries do
		local rig = e.rig
		if rig then
			local root, humanoid = rootOf(player)
			if root then
				local origin = feet(root, humanoid)
				Rig.step(rig, origin, now, moveParts, moveCFrames)
				if rig.plan.pulse > 0 then
					Rig.pulse(rig, origin, now, folder)
				end
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Parts all aura rigs use right now (debug / tests)
function AuraController.partCount(): number
	local n = 0
	for _, e in entries do
		local rig = e.rig
		if rig then
			n += #rig.parts
		end
	end
	return n
end

function AuraController.init()
	folder = Instance.new("Folder")
	folder.Name = "CosmeticFx"
	folder.Parent = Workspace
end

function AuraController.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(forget)
	Prefs.changed:Connect(function(key: string)
		if key == "quality" then
			lodAt = 0
		end
	end)
	RunService:BindToRenderStep("CosmeticFx", Enum.RenderPriority.Camera.Value + 2, frame) -- after the camera
end

return AuraController
