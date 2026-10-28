--!strict
-- Skill-Stufen, Skill-Blüten, Sternennetz und Schmiede-Material (Regeln in Shared.Progression).
--   • Skills sammeln XP, wenn sie den tödlichen Treffer landen (XP des Gegners)
--   • Blüten-Punkte (1 je Skill-Stufe) und Sternpunkte (1 je Level) verteilt nur der Server
--   • Material: Verwerten (Inventory → Progress.salvage) und Boss-Kills
-- Der Client bekommt Schnappschüsse über Net.Progress (gedrosselt, höchstens 1× pro Sekunde
-- bei XP-Zuwachs, sofort nach eigenen Aktionen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skills = require(ReplicatedStorage.Shared.Skills)
local StarNet = require(ReplicatedStorage.Shared.StarNet)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Stats = require(script.Parent.Stats)

local Progress = {}

local FLUSH = 1 -- Sekunden zwischen gesammelten Schnappschüssen
local BOSS_CANDY = 1 -- Runen-Bonbons je Boss (bis es Bonbon-Drops gibt)
local BOSS_DUST_CHANCE = 0.25

local rng = Random.new()
local dirty: { [Player]: boolean } = {}
local allow = RateLimit.new(6, 12)

local MAT_ATTR: { [string]: string } = { candy = "Candy", shards = "Shards", dust = "Dust" }

local function send(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	dirty[player] = nil
	for key, attr in MAT_ATTR do
		player:SetAttribute(attr, (profile.materials :: any)[key])
	end
	Net.Progress:FireClient(player, { progress = profile.progress, materials = profile.materials })
end
Progress.sync = send

function Progress.addMaterials(player: Player, delta: { [string]: number })
	local profile = Data.get(player)
	if not profile then
		return
	end
	local m = profile.materials :: any
	for key, n in delta do
		if MAT_ATTR[key] then
			m[key] = math.max(0, m[key] + math.floor(n))
		end
	end
	dirty[player] = true
end

-- Verwerten: Splitter fest, Bonbons nach Erwartungswert, Glitzerstaub per Chance
function Progress.salvage(player: Player, item: Items.Item)
	local profile = Data.get(player)
	local s = Items.Salvage[item.rarity]
	if not profile or not s then
		return
	end
	local find = (Progression.starMods(profile.progress).shardFind or 0) / 100
	local candy = math.floor(s.candy) + (if rng:NextNumber() < s.candy % 1 then 1 else 0)
	local dust = if rng:NextNumber() < s.dust then 1 else 0
	Progress.addMaterials(player, {
		shards = math.floor(s.shards * (1 + find) + 0.5),
		candy = candy,
		dust = dust,
	})
	send(player)
end

-- ------------------------------------------------------------------ Skill-XP
local function onKilled(player: any, _pos: any, _level: any, boss: any, skillId: any, xp: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local profile = Data.get(player)
	if not profile then
		return
	end
	if typeof(skillId) == "string" and Skills.BarIndex[skillId] and typeof(xp) == "number" then
		local sp = Progression.skillMut(profile.progress, skillId)
		if Progression.addSkillXp(sp, xp) > 0 then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				Net.Fx:FireClient(player, "dmg", {
					pos = root.Position + Vector3.new(0, 5, 0),
					text = string.format(
						"%s Stufe %d",
						Skills.bar[Skills.BarIndex[skillId]].name,
						sp.level
					),
				})
			end
		end
		dirty[player] = true
	end
	if boss == true then
		Progress.addMaterials(player, {
			candy = BOSS_CANDY,
			dust = if rng:NextNumber() < BOSS_DUST_CHANCE then 1 else 0,
		})
	end
end

-- ------------------------------------------------------------------ Remotes
local function onBloom(player: Player, action: any, skillId: any, key: any)
	if not allow(player) or typeof(action) ~= "string" or typeof(skillId) ~= "string" then
		return
	end
	local profile = Data.get(player)
	if not profile or not Skills.Blooms[skillId] then
		return
	end
	if action == "spend" then
		if typeof(key) ~= "string" then
			return
		end
		local sp = Progression.skillMut(profile.progress, skillId)
		if Progression.canBloom(sp, skillId, key) then
			sp.bloom[key] = (sp.bloom[key] or 0) + 1
		end
	elseif action == "reset" then
		local sp = profile.progress.skills[skillId]
		if sp then
			table.clear(sp.bloom)
		end
	else
		return
	end
	send(player)
end

local function onStar(player: Player, action: any, starId: any)
	if not allow(player) or typeof(action) ~= "string" then
		return
	end
	local profile = Data.get(player)
	if not profile then
		return
	end
	local stars = profile.progress.stars
	local level = (player:GetAttribute("Level") or 1) :: number
	if action == "alloc" or action == "remove" then
		if typeof(starId) ~= "string" or not StarNet.ById[starId] then
			return
		end
		if action == "alloc" then
			if not Progression.canAllocate(profile.progress, starId, level) then
				return
			end
			stars[starId] = true
		else
			if not Progression.canRemove(profile.progress, starId) then
				return
			end
			stars[starId] = nil
		end
	elseif action == "reset" then
		table.clear(stars)
	else
		return
	end
	Stats.refresh(player, false)
	send(player)
end

-- ------------------------------------------------------------------ Lebenszyklus
local function onPlayer(player: Player)
	if Data.waitFor(player) then
		send(player)
	end
end

function Progress.init()
	Net.Bloom.OnServerEvent:Connect(onBloom)
	Net.Star.OnServerEvent:Connect(onStar)
	Combat.EnemyKilled.Event:Connect(onKilled)
	Players.PlayerRemoving:Connect(function(player: Player)
		dirty[player] = nil
	end)
end

function Progress.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
	while true do
		task.wait(FLUSH)
		for player in dirty do
			send(player)
		end
	end
end

return Progress
