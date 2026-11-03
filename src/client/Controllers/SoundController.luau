--!strict
-- Plays the one-shot sound hooks (Shared/Sounds.Hooks) for game moments: own hits, casts, basic
-- attacks, dodge, damage taken, death, enemy telegraphs and loot near the player, level-ups,
-- the Stud Rush, boss moments and shop/forge/pet results. UI sounds go through Shape.sound.
-- Mobile friendly: a small pool of Sound instances per hook (created on first play), a minimum
-- gap per hook so 30 hits in one frame play once, and only sounds near the own character.
-- Ids that fail to load warn once in the Output with their hook name (spot-check in Studio).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Audio = require(script.Parent.Parent.Audio)

local SoundController = {}

local player = Players.LocalPlayer
local pools: { [string]: { Sound } } = {}
local turn: { [string]: number } = {} -- round robin per hook
local lastAt: { [string]: number } = {}
local rng = Random.new()

local HEAR = 150 -- studs: further away belongs to someone else's rift
local NEAR = 70 -- studs: enemy telegraphs and loot drops are only heard this close

-- Plays a hook by name; returns false if it is unknown, silent (no id) or throttled
function SoundController.play(name: string): boolean
	local def = Sounds.Hooks[name]
	if not def or def.id == "" then
		return false
	end
	local now = os.clock()
	if now - (lastAt[name] or -math.huge) < def.gap then
		return false
	end
	lastAt[name] = now
	local pool = pools[name]
	if not pool then
		local group = Audio.group(def.channel)
		local list: { Sound } = {}
		for i = 1, def.voices do
			local snd = Instance.new("Sound")
			snd.Name = name .. i
			snd.SoundId = def.id
			snd.SoundGroup = group
			snd.Parent = group
			list[i] = snd
		end
		pools[name] = list
		pool = list
	end
	local i = (turn[name] or 0) % #pool + 1
	turn[name] = i
	local snd = pool[i]
	snd.Volume = def.volume
	snd.PlaybackSpeed = def.speed * (1 + rng:NextNumber(-def.pitch, def.pitch))
	snd.TimePosition = 0
	snd:Play()
	return true
end

local function rootPos(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function within(pos: any, range: number): boolean
	local at = rootPos()
	return typeof(pos) == "Vector3" and at ~= nil and (at - pos).Magnitude <= range
end

local function onFx(kind: string, d: any)
	if typeof(d) ~= "table" then
		return
	end
	local me = player.UserId
	if kind == "dmg" then
		if d.pickup ~= nil then -- own pickup popup (Systems/Loot sends it to the owner only)
			SoundController.play(if d.pickup == "gold" then "pickup_gold" else "pickup")
		elseif d.hurt then
			if d.who == me then
				SoundController.play("hurt")
			end
		elseif d.amount == nil then
			if d.who == me then -- own "Blocked!" / "Dodged", not loot or skill toasts
				SoundController.play("blocked")
			end
		elseif d.by == me then
			SoundController.play(if d.crit then "crit" else "hit")
		end
	elseif kind == "act" then
		if d.by == me and d.basic == true then -- skills sound through SkillCast
			SoundController.play(if d.kind == "projectile" then "attack_shot" else "attack")
		end
	elseif kind == "death" then
		if d.by == me then
			SoundController.play(if d.big then "kill_big" else "kill")
		end
	elseif kind == "levelup" then
		if d.who == me then
			SoundController.play("level_up")
		end
	elseif kind == "phase" then
		if within(d.pos, HEAR) then -- bosses of other players' rifts stay silent
			SoundController.play("boss_phase")
		end
	elseif kind == "intro" then
		SoundController.play("boss_intro")
	elseif kind == "rush" then
		if d.who == me then
			SoundController.play("rush")
		end
	end
end

-- Enemy telegraphs are flat parts directly in workspace.Enemies (Systems/Enemies circle/line)
local function watchEnemies(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") and within(child.Position, NEAR) then
			SoundController.play("telegraph")
		end
	end)
end

-- Loot drops carry a BillboardGui with a Rarity attribute (items) or Gold (coins), Systems/Loot
local function watchLoot(folder: Instance)
	folder.DescendantAdded:Connect(function(child)
		if not child:IsA("BillboardGui") then
			return
		end
		local part = child.Parent
		if not (part and part:IsA("BasePart")) then
			return
		end
		local rarity = child:GetAttribute("Rarity")
		local gold = child:GetAttribute("Gold") == true
		if (gold or typeof(rarity) == "string") and within(part.Position, NEAR) then
			SoundController.play(
				Sounds.lootHook(if typeof(rarity) == "string" and not gold then rarity else nil)
			)
		end
	end)
end

local function watchFolder(name: string, watch: (Instance) -> ())
	local folder = workspace:FindFirstChild(name)
	if folder then
		watch(folder)
		return
	end
	local conn: RBXScriptConnection
	conn = workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == name and child:IsA("Folder") then
			conn:Disconnect()
			watch(child)
		end
	end)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			SoundController.play("death")
		end)
	end
end

-- Loads every hook once (short clips) so the first hit is not late; reports ids that fail.
-- In Studio the ambience and music loops are checked too (on phones they load when played).
local function preload()
	local names: { [string]: { string } } = {}
	local list: { string } = {}
	local function add(label: string, id: string)
		if id == "" then
			return
		end
		if not names[id] then
			names[id] = {}
			table.insert(list, id)
		end
		table.insert(names[id], label)
	end
	for name, def in Sounds.Hooks do
		add(name, def.id)
	end
	if RunService:IsStudio() then
		for name, def in Sounds.Ambience do
			add("ambience." .. name, def.id)
		end
		for name, def in Sounds.Music do
			add("music." .. name, def.id)
		end
	end
	local failed = 0
	local ok = pcall(function()
		ContentProvider:PreloadAsync(
			list :: { any },
			function(id: string, status: Enum.AssetFetchStatus)
				if status ~= Enum.AssetFetchStatus.Success then
					failed += 1
					warn(
						"[Sound] "
							.. table.concat(names[id] or { "?" }, ", ")
							.. " did not load ("
							.. id
							.. ", "
							.. status.Name
							.. ") - replace it in Shared/Sounds"
					)
				end
			end
		)
	end)
	if ok and RunService:IsStudio() then
		print(("[Sound] %d sound ids checked, %d failed"):format(#list, failed))
	end
end

function SoundController.init()
	Audio.group("sfx")
end

function SoundController.start()
	Net.Fx.OnClientEvent:Connect(onFx)
	Net.SkillCast.OnClientEvent:Connect(function(skillId: any)
		local skill = if typeof(skillId) == "string" then Skills.ById[skillId] else nil
		if skill then
			SoundController.play("cast_" .. skill.kind)
		end
	end)
	Net.RiftResult.OnClientEvent:Connect(function(summary: any)
		if typeof(summary) == "table" and summary.kind == "clear" then
			SoundController.play("rift_clear")
		end
	end)
	Net.ShopResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" and data.ok == true then
			SoundController.play("purchase")
		end
	end)
	Net.ForgeResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" and data.ok == true then
			SoundController.play("forge")
		end
	end)
	Net.PetResult.OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" and data.ok == true and data.kind == "hatch" then
			SoundController.play("hatch")
		end
	end)
	-- Dodge: the dash controller publishes its charges; one fewer = a roll
	local charges = player:GetAttribute("DashCharges")
	player:GetAttributeChangedSignal("DashCharges"):Connect(function()
		local now = player:GetAttribute("DashCharges")
		if typeof(now) == "number" and typeof(charges) == "number" and now < charges then
			SoundController.play("dodge")
		end
		charges = now
	end)
	watchFolder("Enemies", watchEnemies)
	watchFolder("Loot", watchLoot)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	task.spawn(preload)
end

return SoundController
