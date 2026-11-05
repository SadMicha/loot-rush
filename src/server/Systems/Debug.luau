--!strict
-- Test commands for playtests (debug menu on the "Dbg" button): gold, level, materials, skill levels,
-- items, all shop cosmetics, unlock all regions and defeat all enemies of the own Rift (play through a Rift quickly),
-- and "reset" (whole account back to a first-join save, then a kick). Only in Studio, for the
-- owner of the place (user-owned experience) or for UserIds in DEV_USERS.
-- The check lives here on the server - the menu on the client is only a convenience.
-- Every command goes through the same paths as the game (Inventory, Progress, Combat), never around the profile.
-- The server tells the client it is allowed via the player attribute "DebugTools".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local CosmeticRules = require(ReplicatedStorage.Shared.Cosmetics)
local SkinRules = require(ReplicatedStorage.Shared.GearSkins)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RushRules = require(ReplicatedStorage.Shared.Rush)
local Skills = require(ReplicatedStorage.Shared.Skills)
local SpellStones = require(ReplicatedStorage.Shared.SpellStones)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Analytics = require(script.Parent.Analytics)
local Combat = require(script.Parent.Combat)
local Cosmetics = require(script.Parent.Cosmetics)
local Daily = require(script.Parent.Daily)
local Data = require(script.Parent.Data)
local GearSkins = require(script.Parent.GearSkins)
local GreatBuild = require(script.Parent.GreatBuild)
local Leaderboard = require(script.Parent.Leaderboard)
local Inventory = require(script.Parent.Inventory)
local Pets = require(script.Parent.Pets)
local Progress = require(script.Parent.Progress)
local Rift = require(script.Parent.Rift)
local Rush = require(script.Parent.Rush)
local Seasons = require(script.Parent.Seasons)
local Shop = require(script.Parent.Shop)
local Weapons = require(script.Parent.Weapons)
local WeaponList = require(ReplicatedStorage.Shared.Weapons).List

local Debug = {}

-- Roblox UserIds that may use the test commands in the published game too
local DEV_USERS: { [number]: true } = {}

-- The account that owns the experience may always use them (0 for group games or outside Roblox)
local OWNER_ID: number = (function(): number
	local ok, id = pcall(function(): number
		return if game.CreatorType == Enum.CreatorType.User then game.CreatorId else 0
	end)
	return if ok and typeof(id) == "number" then id else 0
end)()

local MAX_LEVEL = 200
local REGION_SPAN = 5 -- depths per region (starting depths 1, 6, 11 …)

local rng = Random.new()
local allow = RateLimit.new(4, 8)
local allowReset = RateLimit.new(1 / 30, 1) -- the kick ends the session anyway; no repeated saves

Debug.RESET_MESSAGE = "Account reset - rejoin to start over."

function Debug.allowed(player: Player): boolean
	return RunService:IsStudio()
		or DEV_USERS[player.UserId] == true
		or (OWNER_ID > 0 and player.UserId == OWNER_ID)
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
	for _, skill in Skills.list do
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
	local profile = Data.get(player)
	local opts: Items.RollOpts = { class = if profile then profile.class else nil }
	for _ = 1, n do
		if not Inventory.add(player, Items.roll(ilvl, rng, nil, opts)) then
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
			local ok, text, petId = Pets.hatch(player, "star_egg")
			Net.PetResult:FireClient(player, { ok = ok, text = text, kind = "hatch", pet = petId })
		end,
	},
	tier = {
		-- Unlocks the next World Tier (Shared/WorldTiers) and selects it
		run = function(player)
			local profile = Data.get(player)
			if not profile or Rift.isRunning(player) then
				return
			end
			profile.tier.unlocked = math.min(profile.tier.unlocked + 1, WorldTiers.MAX)
			profile.tier.selected = profile.tier.unlocked
			Rift.publishBest(player)
		end,
	},
	stones = {
		-- One of every spell stone (Shared/SpellStones)
		run = function(player)
			local profile = Data.get(player)
			if not profile then
				return
			end
			for _, stone in SpellStones.List do
				profile.progress.stones[stone.id] = (profile.progress.stones[stone.id] or 0) + 1
			end
			Progress.sync(player)
		end,
	},
	cosmetics = {
		-- Every shop cosmetic (Shared/Cosmetics: trails, auras from all packs) into the account save,
		-- through the same path a Robux pack uses. Already owned ones are skipped.
		run = function(player)
			for _, c in CosmeticRules.List do
				Cosmetics.give(player, c.id)
			end
			Cosmetics.sync(player)
			for _, skin in SkinRules.List do -- every gear skin too (season ones included)
				GearSkins.give(player, skin.id)
			end
			GearSkins.sync(player)
		end,
	},
	stance = {
		-- Preview the holding stances (Shared/Anim STANCE): puts the next weapon of the list into the
		-- hand (player attribute "StanceWeapon"), after the last one back to the class weapon
		run = function(player)
			local now = player:GetAttribute("StanceWeapon")
			local index = 0
			for i, w in WeaponList do
				if w.id == now then
					index = i
				end
			end
			local nextWeapon = WeaponList[index + 1]
			player:SetAttribute("StanceWeapon", nextWeapon and nextWeapon.id)
			task.spawn(Weapons.equip, player)
		end,
	},
	rush = {
		-- Fills the Stud Rush meter (Systems/Rush)
		run = function(player)
			Rush.add(player, RushRules.METER)
		end,
	},
	day = {
		-- Daily reward: pretend the last claim was yesterday (claim again)
		run = function(player)
			Daily.rewind(player)
		end,
	},
	season = {
		-- Season Journey: finishes the next unfinished challenge (Systems/Seasons)
		run = function(player)
			Seasons.completeNext(player)
		end,
	},
	buildstage = {
		-- Great Build: adds what the current stage still needs (to every server!) and flushes
		run = function()
			GreatBuild.finishStage()
		end,
	},
	buildshards = {
		-- Great Build: shards to donate
		run = function(player)
			Progress.addMaterials(player, { shards = 1000 })
			Progress.sync(player)
		end,
	},
	slay = {
		-- Only the caller's own run: other players' Rifts run on the same server
		run = function(player)
			local run = Rift.runOf(player)
			if not run then
				return
			end
			for _, enemy in CollectionService:GetTagged("Enemy") do
				if enemy:IsA("Model") and enemy:GetAttribute("Run") == run then
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
	if command == "reset" then
		-- Replay the start (tutorial, quests, first drops, hero creation): the whole account goes
		-- back to a first-join save and the player is kicked (the menu asks twice before sending).
		-- A running Rift ends on the kick ("gone"); its depths never reach a leaderboard.
		if allowReset(player) then
			print(string.format("[Debug] %s: reset account", player.Name))
			Leaderboard.taint(player)
			Analytics.flush(player) -- pooled economy flows of the old save go out first
			Data.reset(player, Debug.RESET_MESSAGE)
		end
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
	-- A hero touched by a test command never reaches a leaderboard (Systems/Leaderboard).
	-- "day", "cosmetics" and "stance" only change the account or the looks (calendar, cosmetics,
	-- the weapon shown in the hand), "buildstage" only the global Great Build, not the hero's power.
	if
		command ~= "day"
		and command ~= "cosmetics"
		and command ~= "stance"
		and command ~= "buildstage"
	then
		local profile = Data.get(player)
		if profile then
			profile.debugged = true
		end
		Leaderboard.taint(player) -- depths already cleared in this run are dropped too
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
