--!strict
-- Test commands for playtests (debug menu on the "Dbg" button): gold, level, materials, skill levels,
-- items, unlock all regions and defeat all enemies (play through a Rift quickly). Only in Studio or for UserIds in DEV_USERS.
-- The check lives here on the server - the menu on the client is only a convenience.
-- Every command goes through the same paths as the game (Inventory, Progress, Combat), never around the profile.
-- The server tells the client it is allowed via the player attribute "DebugTools".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RebirthRules = require(ReplicatedStorage.Shared.Rebirth)
local Skills = require(ReplicatedStorage.Shared.Skills)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Pets = require(script.Parent.Pets)
local Progress = require(script.Parent.Progress)
local Rebirth = require(script.Parent.Rebirth)
local Rift = require(script.Parent.Rift)
local Shop = require(script.Parent.Shop)

local Debug = {}

-- Roblox UserIds that may use the test commands in the published game too
local DEV_USERS: { [number]: true } = {}

local MAX_LEVEL = 200
local REGION_SPAN = 5 -- depths per region (starting depths 1, 6, 11 …)

local rng = Random.new()
local allow = RateLimit.new(4, 8)

function Debug.allowed(player: Player): boolean
	return RunService:IsStudio() or DEV_USERS[player.UserId] == true
end

local function whole(value: any, min: number, max: number): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	return if value >= min and value <= max then value else nil
end

local function setLevel(player: Player, level: number)
	local profile = Data.get(player)
	if not profile then
		return
	end
	Combat.setLevel(player, level, 0)
	Progress.sync(player) -- star points depend on the level
end

local function addSkillLevels(player: Player, n: number)
	local profile = Data.get(player)
	if not profile then
		return
	end
	for _, skill in Skills.bar do
		local sp = Progression.skillMut(profile.progress, skill.id)
		for _ = 1, n do
			Progression.addSkillXp(sp, Progression.skillXpFor(sp.level) - sp.xp)
		end
	end
	Progress.sync(player)
end

local function unlockAtlas(player: Player, atLeast: number?)
	local profile = Data.get(player)
	if not profile then
		return
	end
	-- Unlocking checks the best result in the predecessor, and successors can start deeper
	-- (Fire Desert 16 → Altered World 26): so enter the deepest starting depth everywhere.
	local deepest = 0
	for _, region in Atlas.Regions do
		deepest = math.max(deepest, region.depth + REGION_SPAN - 1)
	end
	deepest = math.max(deepest, atLeast or 0)
	for _, region in Atlas.Regions do
		local depth = math.max(profile.atlas[region.id] or 0, deepest)
		profile.atlas[region.id] = depth
	end
	Rift.publishBest(player)
end

local function addItems(player: Player, n: number)
	local ilvl = (player:GetAttribute("Level") or 1) :: number
	for _ = 1, n do
		if not Inventory.add(player, Items.roll(ilvl, rng)) then
			break
		end
	end
end

-- Command → (value check, execution)
local COMMANDS: { [string]: { range: { number }?, run: (Player, number) -> () } } = {
	gold = {
		range = { -1e9, 1e9 },
		run = function(player, n)
			Inventory.addGold(player, n)
		end,
	},
	level = { range = { 1, MAX_LEVEL }, run = setLevel },
	materials = {
		range = { 1, 10000 },
		run = function(player, n)
			Progress.addMaterials(player, { candy = n, shards = n, dust = n })
			Progress.sync(player)
		end,
	},
	soulstars = {
		range = { -1e9, 1e9 },
		run = function(player, n)
			Shop.grant(player, "soulstars", n)
		end,
	},
	skills = { range = { 1, 20 }, run = addSkillLevels },
	items = { range = { 1, 20 }, run = addItems },
	atlas = {
		run = function(player)
			unlockAtlas(player)
		end,
	},
	pet = {
		run = function(player)
			Shop.grant(player, "soulstars", 75)
			local ok, text = Pets.hatch(player, "sternen_ei")
			Net.PetResult:FireClient(player, { ok = ok, text = text })
		end,
	},
	rebirth = {
		run = function(player)
			-- Nicht mitten im Lauf, und tief genug für die nächste Wiedergeburt (Wand wandert mit)
			if Rift.isRunning(player) then
				Net.RebirthResult:FireClient(
					player,
					{ ok = false, text = "Erst das Rift verlassen" }
				)
				return
			end
			unlockAtlas(player, RebirthRules.required(Rift.rebirthsOf(player)))
			local ok, text = Rebirth.perform(player)
			Net.RebirthResult:FireClient(player, { ok = ok, text = text })
		end,
	},
	slay = {
		run = function(player)
			for _, enemy in CollectionService:GetTagged("Enemy") do
				if enemy:IsA("Model") then
					Combat.slay(player, enemy)
				end
			end
		end,
	},
}

local function onCommand(player: Player, command: any, value: any)
	-- Without a loaded save every command would silently do nothing
	if not Debug.allowed(player) or not allow(player) or not Data.get(player) then
		return
	end
	local entry = if typeof(command) == "string" then COMMANDS[command] else nil
	if not entry then
		return
	end
	local n = 0
	if entry.range then
		local checked = whole(value, entry.range[1], entry.range[2])
		if not checked then
			return
		end
		n = checked
	end
	entry.run(player, n)
	print(string.format("[Debug] %s: %s %s", player.Name, command, tostring(value or "")))
end

-- Only enable the menu once the save is loaded
local function onPlayer(player: Player)
	if Debug.allowed(player) and Data.waitFor(player) then
		player:SetAttribute("DebugTools", true)
	end
end

function Debug.init()
	Net.Debug.OnServerEvent:Connect(onCommand)
end

function Debug.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Debug
