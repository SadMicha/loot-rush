--!strict
-- Visible gear on the hero (looks: Shared/Gear). Builds the worn armor and jewelry from studded
-- parts into the model "WornGear" in the character, welded to the body parts. Built on the
-- server, so it replicates to everyone; the inventory preview clones the character and shows it.
-- Rebuilt only when the worn look changes (Gear.signature), after a respawn and when the avatar
-- swaps its body parts. While a helmet is worn, hat and hair accessories are hidden; the setting
-- "Hide helmet" (account.settings.hideHelmet) leaves the helmet off the body (stats stay).
-- Cost: no per-frame work, at most Gear.MAX_PIECES massless, non-colliding parts per slot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Gear = require(ReplicatedStorage.Shared.Gear)
local Items = require(ReplicatedStorage.Shared.Items)
local Kit = require(ReplicatedStorage.Shared.Models.Kit)
local Data = require(script.Parent.Data)

local GearSystem = {}

local HIDDEN = "GearHidden" -- attribute on a hidden accessory handle: its own transparency
local APPEARANCE_WAIT = 5 -- seconds to wait for the avatar's body parts before building anyway

local built: { [Model]: string } = {} -- character → signature of what is built
local watched: { [Model]: boolean } = {}

local HAIR_TYPES = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
}

-- Gear skins per slot (cosmetic looks, docs/specs/GEAR-COSMETICS.md). Not saved yet: every
-- slot shows the hero's class look until the skins land in the save.
local function skins(_player: Player): { [string]: string }
	return {}
end

-- Worn items that show on the body (only gear the hero can wear right now, like Systems/Stats)
local function worn(player: Player): (string, { [string]: Items.Item })
	local profile = Data.get(player)
	local class = Classes.valid(profile and profile.class or player:GetAttribute("Class"))
	local out: { [string]: Items.Item } = {}
	if profile then
		local level = player:GetAttribute("Level")
		local lvl = if typeof(level) == "number" then level else profile.level
		local account = Data.account(player)
		local hideHelmet = account ~= nil and account.settings.hideHelmet == true
		for _, slot in Gear.Slots do
			local item = profile.equipped[slot]
			if slot == "helmet" and hideHelmet then
				continue -- settings "Hide helmet": hair and hats show instead
			end
			if item and Items.canWear(item, lvl, profile.class) then
				out[slot] = item
			end
		end
	end
	return class, out
end

local function makePart(model: Model, piece: Gear.Piece, size: Vector3, color: Color3): BasePart
	local material = if piece.role == "gem" then Enum.Material.Glass else nil
	local p: BasePart
	if piece.shape == "wedge" then
		p = Kit.wedge(model, size, CFrame.new(), color, material)
	elseif piece.shape == "ball" then
		p = Kit.ball(model, size.X, Vector3.zero, color, material)
	elseif piece.shape == "disc" then
		p = Kit.cylinder(model, size, CFrame.new(), color, material)
	else
		p = Kit.block(model, size, CFrame.new(), color, material)
	end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

-- Hat and hair accessories vanish under a helmet and come back without one
local function hideHair(character: Model, hide: boolean)
	for _, acc in character:GetChildren() do
		if not acc:IsA("Accessory") or not HAIR_TYPES[acc.AccessoryType] then
			continue
		end
		local handle = acc:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then
			continue
		end
		local own = handle:GetAttribute(HIDDEN)
		if hide and own == nil then
			handle:SetAttribute(HIDDEN, handle.Transparency)
			handle.Transparency = 1
		elseif not hide and typeof(own) == "number" then
			handle.Transparency = own
			handle:SetAttribute(HIDDEN, nil)
		end
	end
end

local function build(
	character: Model,
	class: string,
	items: { [string]: Items.Item },
	skin: { [string]: string }
)
	local old = character:FindFirstChild(Gear.MODEL)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = Gear.MODEL
	for _, slot in Gear.Slots do
		local item = items[slot]
		local style = item and Gear.style(class, slot, skin[slot])
		if not item or not style then
			continue
		end
		local neon = Items.rank(item.rarity) >= Gear.GEM_NEON_RANK
		for _, piece in Gear.pieces(style, slot) do
			local body = character:FindFirstChild(piece.part)
			if not body or not body:IsA("BasePart") then
				continue -- R6 or a custom rig without this part: skip the piece
			end
			local size, offset = Gear.place(piece, body.Size)
			local p = makePart(model, piece, size, Gear.color(style, piece.role, item.rarity))
			if piece.role == "gem" and neon then
				p.Material = Enum.Material.Neon
			end
			p.Name = slot
			p.CFrame = body.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0 = body
			weld.Part1 = p
			weld.C0 = offset
			weld.Parent = p
		end
	end
	model.Parent = character
	hideHair(character, items.helmet ~= nil)
end

function GearSystem.apply(player: Player, force: boolean?)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local class, items = worn(player)
	local skin = skins(player)
	local sig = Gear.signature(class, items, skin)
	if not force and built[character] == sig and character:FindFirstChild(Gear.MODEL) then
		return
	end
	built[character] = sig
	build(character, class, items, skin)
end

local function waitForAppearance(player: Player)
	local t0 = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - t0 < APPEARANCE_WAIT do
		task.wait(0.1)
	end
end

-- Rebuild when the avatar replaces body parts or adds hats (welds on old parts would fall off)
local function watch(player: Player, character: Model)
	if watched[character] then
		return
	end
	watched[character] = true
	local pending = false
	local function later()
		if pending then
			return
		end
		pending = true
		task.delay(0.2, function()
			pending = false
			if player.Character == character and character.Parent then
				GearSystem.apply(player, true)
			end
		end)
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") or child:IsA("Accessory") then
			later()
		end
	end)
	character.Destroying:Connect(function()
		watched[character] = nil
		built[character] = nil
	end)
	player.CharacterRemoving:Once(function(c)
		watched[c] = nil
		built[c] = nil
	end)
end

local function onCharacter(player: Player, character: Model)
	waitForAppearance(player)
	if player.Character ~= character then
		return
	end
	GearSystem.apply(player, true)
	watch(player, character)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, player, character)
	end)
	Data.waitFor(player)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

function GearSystem.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return GearSystem
