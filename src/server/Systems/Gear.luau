--!strict
-- Visible gear on the hero (looks: Shared/Gear). Builds the worn armor and jewelry from studded
-- parts into the model "WornGear" in the character, welded to the body parts. Built on the
-- server, so it replicates to everyone; the inventory preview clones the character and shows it.
-- Rebuilt only when the worn look changes (Gear.signature), after a respawn and when the avatar
-- swaps its body parts. While a helmet is worn, hat and hair accessories are hidden; the setting
-- "Hide helmet" (account.settings.hideHelmet) leaves the helmet off the body (stats stay).
-- Rarity shows on the body: Gear.pieces(style, slot, rarity) adds trim, gems and Neon edges.
-- Gear skins (Shared/GearSkins, account.gearWear) swap the look of a slot, never the stats.
-- The builder itself is shared (Shared/Models/GearBuild), so the shop preview can try skins on.
-- Cost: no per-frame work, no particles; massless, non-colliding parts within Gear.MAX_PIECES per
-- slot and Gear.MAX_SET per full set.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Gear = require(ReplicatedStorage.Shared.Gear)
local Items = require(ReplicatedStorage.Shared.Items)
local GearBuild = require(ReplicatedStorage.Shared.Models.GearBuild)
local SkinRules = require(ReplicatedStorage.Shared.GearSkins)
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

-- Worn gear skins per slot (account.gearWear, docs/specs/GEAR-COSMETICS.md): only owned skins
-- that fit the slot and the hero's class; every other slot shows the class look
local function skins(player: Player, class: string): { [string]: string }
	local out: { [string]: string } = {}
	local account = Data.account(player)
	if not account then
		return out
	end
	for slot, id in account.gearWear do
		if account.gearSkins[id] and SkinRules.fits(slot, id, class) then
			out[slot] = id
		end
	end
	return out
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
	GearBuild.build(character, class, items, skin)
	hideHair(character, items.helmet ~= nil)
end

function GearSystem.apply(player: Player, force: boolean?)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local class, items = worn(player)
	local skin = skins(player, class)
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
