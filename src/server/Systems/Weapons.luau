--!strict
-- Held weapon on the avatar (rules and ids: Shared/Weapons, Assets.Weapon; docs/WEAPONS.md).
-- Sets the player attribute "Class" from the save and welds the class weapon into the right
-- hand after every spawn. With uploaded ids the FBX mesh is loaded once per weapon
-- (InsertService) and cloned; without ids, or if loading fails, a part-built weapon is used.

local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Kit = require(ReplicatedStorage.Shared.Models.Kit)
local Data = require(script.Parent.Data)

local WeaponSystem = {}

local NAME = "HeldWeapon"
local meshCache: { [string]: BasePart } = {}
local tried: { [string]: boolean } = {}
local loading: { [string]: boolean } = {} -- LoadAsset in flight: other callers wait for it

local function assetId(raw: string): number?
	return tonumber(string.match(raw, "%d+$") or "")
end

-- First MeshPart of the uploaded model, scaled to the weapon length, texture applied
local function loadMesh(w: Weapons.Weapon): BasePart?
	while loading[w.id] do
		task.wait(0.1)
	end
	if tried[w.id] then
		return meshCache[w.id]
	end
	tried[w.id] = true
	local ids = Assets.Weapon[w.id]
	local id = ids and assetId(ids.model)
	if not ids or not id then
		return nil
	end
	loading[w.id] = true
	local ok, model = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	loading[w.id] = nil
	if not ok or not model then
		warn("[Weapons] could not load " .. w.id .. ": " .. tostring(model))
		return nil
	end
	local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
	if not mesh then
		model:Destroy()
		return nil
	end
	mesh.Parent = nil
	model:Destroy()
	if ids.texture ~= "" then
		local tex = assetId(ids.texture)
		if tex then
			(mesh :: MeshPart).TextureID = "rbxassetid://" .. tex
		end
	end
	local size = mesh.Size
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		mesh.Size = size * (w.length / longest)
	end
	meshCache[w.id] = mesh
	return mesh
end

-- Part fallback: the weapon's long axis runs along -Y from the grip (y = 0)
local function buildParts(w: Weapons.Weapon, model: Model): BasePart
	local L = w.length
	local handle: BasePart
	if w.id == "warrior_sword" then
		handle = Kit.block(
			model,
			Vector3.new(0.3, 0.9, 0.3),
			CFrame.new(0, 0.45, 0),
			Kit.shade(w.color, -0.4)
		)
		Kit.block(model, Vector3.new(1.2, 0.2, 0.3), CFrame.new(0, 0, 0), w.accent)
		Kit.block(
			model,
			Vector3.new(0.4, L - 1, 0.12),
			CFrame.new(0, -(L - 1) / 2, 0),
			w.color,
			Enum.Material.Metal
		)
	elseif w.id == "ranger_bow" then
		handle = Kit.block(
			model,
			Vector3.new(0.3, 0.6, 0.3),
			CFrame.new(0, 0, 0),
			Kit.shade(w.color, -0.3)
		)
		for _, side in { 1, -1 } do
			Kit.block(
				model,
				Vector3.new(0.25, L / 2, 0.25),
				CFrame.new(0, side * L / 4, -0.35) * CFrame.Angles(math.rad(side * 18), 0, 0),
				w.color
			)
		end
		local cord = Kit.block(
			model,
			Vector3.new(0.05, L * 0.95, 0.05),
			CFrame.new(0, 0, -0.75),
			Color3.new(0.95, 0.95, 0.9)
		)
		cord.Material = Enum.Material.Neon
		Kit.block(
			model,
			Vector3.new(0.12, 0.3, 0.12),
			CFrame.new(0, 0.3, 0),
			w.accent,
			Enum.Material.Neon
		)
	else
		-- staff / scepter: shaft with a glowing head
		handle = Kit.cylinder(
			model,
			Vector3.new(L, 0.3, 0.3),
			CFrame.new(0, -L / 2 + 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			w.color
		)
		local head = if w.id == "druid_scepter" then 1.1 else 0.8
		Kit.ball(model, head, Vector3.new(0, 1 + head / 2, 0), w.accent, Enum.Material.Neon)
		if w.id == "druid_scepter" then
			Kit.cylinder(
				model,
				Vector3.new(0.3, 1.6, 1.6),
				CFrame.new(0, 1 + head, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Kit.shade(w.accent, -0.2)
			)
		end
	end
	return handle
end

local HANDS = { "RightHand", "Right Arm", "UpperTorso", "HumanoidRootPart" }
local APPEARANCE_WAIT = 5 -- seconds to wait for the avatar's body parts before equipping anyway

local function hand(character: Model): BasePart?
	for _, name in HANDS do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- The avatar loads after the spawn and swaps its body parts (RightHand etc.). A weapon welded to
-- the old hand would fall out of the world, so equip only once the appearance has loaded.
local function waitForAppearance(player: Player)
	if player:HasAppearanceLoaded() then
		return
	end
	local done = false
	local conn = player.CharacterAppearanceLoaded:Connect(function()
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < APPEARANCE_WAIT and not player:HasAppearanceLoaded() do
		task.wait(0.1)
	end
	conn:Disconnect()
end

local watched: { [Model]: boolean } = {}
local generation: { [Player]: number } = {} -- newest equip call per player; older ones give up

-- Re-equip when the hand the weapon hangs on is replaced (avatar loading, HumanoidDescription)
local function watch(player: Player, character: Model)
	if watched[character] then
		return
	end
	watched[character] = true
	local pending = false
	local function check()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if player.Character ~= character or not character.Parent then
				return
			end
			local held = character:FindFirstChild(NAME)
			local joint = held and held:FindFirstChild("Grip")
			local part0 = joint and (joint :: Weld).Part0
			if not part0 or part0.Parent ~= character or part0 ~= hand(character) then
				WeaponSystem.equip(player)
			end
		end)
	end
	character.ChildAdded:Connect(function(child)
		if table.find(HANDS, child.Name) then
			check()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if table.find(HANDS, child.Name) then
			check()
		end
	end)
	character.Destroying:Connect(function()
		watched[character] = nil
	end)
	player.CharacterRemoving:Once(function(c)
		watched[c] = nil
	end)
end

function WeaponSystem.equip(player: Player)
	local character = player.Character
	if not character or not hand(character) then
		return
	end
	local w = Weapons.ByClass[Classes.valid(player:GetAttribute("Class"))]
	if not w then
		return
	end
	local gen = (generation[player] or 0) + 1
	generation[player] = gen
	waitForAppearance(player) -- may yield (avatar still loading)
	local mesh = loadMesh(w) -- may yield (first load per server)
	if generation[player] ~= gen then
		return -- a newer equip (class change, respawn) started while this one waited
	end
	if player.Character ~= character or not character.Parent then
		return -- respawned while loading: the new character equips itself
	end
	-- the avatar may have swapped its hand parts during the load: find the grip again
	local grip = hand(character)
	if not grip then
		return
	end
	local old = character:FindFirstChild(NAME)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = NAME
	model:SetAttribute("Weapon", w.id)
	local root: BasePart
	if mesh then
		root = mesh:Clone()
		root.CFrame = CFrame.new()
		root.Parent = model
	else
		root = buildParts(w, model)
	end
	model.PrimaryPart = root
	-- Joints from fixed offsets (not world positions): the weapon sits right even if the server's
	-- copy of the hand moved meanwhile. Root → hand via "Grip", every other part → root.
	local rootCf = root.CFrame
	local place = grip.CFrame * w.grip
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Anchored = false
			if p ~= root then
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = p
				weld.C0 = rootCf:ToObjectSpace(p.CFrame)
				weld.Parent = p
			end
			p.CFrame = place * rootCf:ToObjectSpace(p.CFrame)
		end
	end
	local joint = Instance.new("Weld")
	joint.Name = "Grip"
	joint.Part0 = grip
	joint.Part1 = root
	joint.C0 = w.grip
	joint.Parent = model
	model.Parent = character
	watch(player, character)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(WeaponSystem.equip, player)
	end)
	local profile = Data.waitFor(player)
	player:SetAttribute("Class", Classes.valid(profile and profile.class))
	if player.Character then
		WeaponSystem.equip(player)
	end
end

function WeaponSystem.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		generation[player] = nil
	end)
end

return WeaponSystem
