--!strict
-- Test-Befehle für Playtests (Debug-Menü am „Dbg“-Knopf): Gold, Level, Material, Skill-Stufen,
-- Gegenstände, alle Gebiete freischalten und alle Gegner besiegen (Rift schnell durchspielen). Nur in Studio oder für UserIds in DEV_USERS.
-- Die Prüfung sitzt hier im Server – das Menü im Client ist nur Bequemlichkeit.
-- Jeder Befehl geht über dieselben Wege wie das Spiel (Inventory, Progress, Combat), nicht am Profil vorbei.
-- Freigabe zeigt der Server dem Client über das Player-Attribut „DebugTools“.

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

-- Roblox-UserIds, die die Test-Befehle auch im veröffentlichten Spiel benutzen dürfen
local DEV_USERS: { [number]: true } = {}

local MAX_LEVEL = 200
local REGION_SPAN = 5 -- Tiefen je Gebiet (Start-Tiefen 1, 6, 11 …)

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
	Progress.sync(player) -- Sternpunkte hängen am Level
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
	-- Freischalten prüft die Bestleistung im Vorgänger, und Nachfolger können tiefer starten
	-- (Feuerwüste 16 → Veränderte Welt 26): darum überall die tiefste Start-Tiefe eintragen.
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

-- Befehl → (Prüfung des Werts, Ausführung)
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
	potions = {
		range = { -100, 100 },
		run = function(player, n)
			Shop.grant(player, "potions", n)
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
	-- Ohne geladenen Spielstand würde jeder Befehl still ins Leere laufen
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

-- Menü erst freigeben, wenn der Spielstand geladen ist
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
