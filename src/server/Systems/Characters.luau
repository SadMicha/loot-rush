--!strict
-- Characters (docs/CLASSES.md, docs/specs/SEASONS.md §6): an account holds up to 12 characters,
-- each with its own name, class, level, gear and progress. The class belongs to the character and
-- is locked once the character is set up; another class means another character.
--  • First join: the account has one character that still needs its setup (attribute
--    SetupDone = false opens the setup screen): name + class. Until then it plays as the default.
--  • Profile screen: list of the account's characters, "New character" (name + class) and
--    "Play" to switch. Switching saves and rejoins the game into the other character (all systems
--    load it fresh); in Studio, where teleports fail, the player is kicked with a rejoin hint.
-- Remote Net.Character (C→S): "list" | "setup", name, classId | "create", name, classId | "play", id
-- Remote Net.Characters (S→C): { active, max, list = { { id, name, class, level, league } } }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")

local Classes = require(ReplicatedStorage.Shared.Classes)
local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(ReplicatedStorage.Shared.Profile)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Rift = require(script.Parent.Rift)
local Weapons = require(script.Parent.Weapons)

local Characters = {}

local allow = RateLimit.new(2, 4)
local allowList = RateLimit.new(2, 4) -- own budget: a refresh never blocks a real action
local switching: { [Player]: boolean } = {}
-- One setup/create/play at a time per player: the name filter yields, a second request must not
-- pass the same checks meanwhile (double tap → two heroes)
local busy: { [Player]: boolean } = {}

local function exclusive(player: Player, fn: () -> (boolean, string?)): (boolean, string?)
	if busy[player] then
		return false, "One moment …"
	end
	busy[player] = true
	local ok, a, b = pcall(fn)
	busy[player] = nil
	if not ok then
		warn("[Characters] request failed:", a)
		return false, "Not possible right now"
	end
	return a, b
end

-- Roblox text filter for a name others may see. Refuses on a filter error, except in Studio
-- (no filter service there / in the test sandbox), where the checked name is used as is.
local function filterName(player: Player, name: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(result) == "string" then
		return if result == name then name else nil -- hashed (####) = not allowed
	end
	return if RunService:IsStudio() then name else nil
end

-- Character list for the client
function Characters.sync(player: Player)
	local account = Data.account(player)
	if not account then
		return
	end
	local list = {}
	for _, c in account.characters do
		table.insert(list, {
			id = c.id,
			name = c.name,
			class = c.class,
			level = c.level,
			league = c.league,
		})
	end
	Net.Characters:FireClient(player, {
		active = account.active,
		max = Profile.MAX_CHARACTERS,
		list = list,
	})
end

-- Applies the active character's class everywhere (bar, stars, stats, weapon)
local function applyClass(player: Player)
	player:SetAttribute("Class", (assert(Data.get(player))).class)
	Progress.classChanged(player)
	Combat.refreshStats(player, false)
	Weapons.equip(player)
end

-- First-join setup of the active character: name + class. Returns (ok, reason).
function Characters.setup(player: Player, name: any, classId: any): (boolean, string?)
	local profile = Data.get(player)
	if not profile or profile.setupDone then
		return false, "Already set up"
	end
	if typeof(classId) ~= "string" or not Classes.ById[classId] then
		return false, "Unknown class"
	end
	local valid = Profile.validName(name)
	if not valid then
		return false, "Name: 3-16 letters or digits"
	end
	if Rift.isRunning(player) then
		return false, "Leave the rift first"
	end
	local clean = filterName(player, valid)
	if not clean or Data.get(player) ~= profile or profile.setupDone then
		return false, if clean then "Already set up" else "Please pick another name"
	end
	profile.name = clean
	profile.class = classId
	profile.setupDone = true
	player:SetAttribute("CharacterName", clean)
	player:SetAttribute("SetupDone", true)
	applyClass(player)
	Characters.sync(player)
	return true, nil
end

-- Rejoins the game into the account's active character
local function rejoin(player: Player, name: string)
	switching[player] = true
	Data.saveNow(player)
	if not player.Parent then
		return
	end
	local ok = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		task.wait(1) -- a teleport may still fail later: no kick while it might go through
	end
	if player.Parent and not ok then
		player:Kick("Switched to " .. name .. ". Please rejoin to play.")
	end
end

-- Makes another character active and rejoins. Returns (ok, reason).
function Characters.play(player: Player, id: any): (boolean, string?)
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile or typeof(id) ~= "string" or #id > Profile.MAX_KEY_LEN then
		return false, "Unknown character"
	end
	local target = Profile.character(account, id)
	if not target then
		return false, "Unknown character"
	end
	if target == profile or switching[player] then
		return false, "Already playing"
	end
	if Rift.isRunning(player) then
		return false, "Leave the rift first"
	end
	if not profile.setupDone then
		return false, "Finish your hero first"
	end
	account.active = target.id
	switching[player] = true -- set before anything yields: no second switch or create
	task.spawn(rejoin, player, if target.name ~= "" then target.name else "your hero")
	return true, nil
end

-- New character (name + class) and switch to it. Returns (ok, reason).
function Characters.create(player: Player, name: any, classId: any): (boolean, string?)
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile then
		return false, "Not loaded"
	end
	if not profile.setupDone then
		return false, "Finish your hero first"
	end
	if typeof(classId) ~= "string" or not Classes.ById[classId] then
		return false, "Unknown class"
	end
	local valid = Profile.validName(name)
	if not valid then
		return false, "Name: 3-16 letters or digits"
	end
	if #account.characters >= Profile.MAX_CHARACTERS then
		return false, "All character slots are used"
	end
	if Rift.isRunning(player) or switching[player] then
		return false, "Leave the rift first"
	end
	local clean = filterName(player, valid)
	if not clean then
		return false, "Please pick another name"
	end
	if switching[player] or Data.account(player) ~= account then
		return false, "Already switching"
	end
	local char = Profile.newCharacter(account, clean, classId, os.time())
	if not char then
		return false, "All character slots are used"
	end
	Characters.sync(player)
	return Characters.play(player, char.id)
end

local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if not profile then
		return
	end
	player:SetAttribute("CharacterName", profile.name)
	player:SetAttribute("SetupDone", profile.setupDone)
	Characters.sync(player)
end

function Characters.init()
	Net.Character.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
		if action == "list" then
			if allowList(player) then
				Characters.sync(player)
			end
			return
		end
		if action ~= "setup" and action ~= "create" and action ~= "play" then
			return
		end
		if not allow(player) then
			-- always answer, so the client's buttons unlock again
			Net.CharacterResult:FireClient(
				player,
				{ ok = false, text = "Too fast, try again", action = action }
			)
			return
		end
		local ok, why
		if action == "setup" then
			ok, why = exclusive(player, function()
				return Characters.setup(player, a, b)
			end)
		elseif action == "create" then
			ok, why = exclusive(player, function()
				return Characters.create(player, a, b)
			end)
		elseif action == "play" then
			ok, why = exclusive(player, function()
				return Characters.play(player, a)
			end)
		else
			return
		end
		Net.CharacterResult:FireClient(player, { ok = ok, text = why or "", action = action })
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		switching[player] = nil
		busy[player] = nil
	end)
end

function Characters.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
end

return Characters
