--!strict
-- Skill levels, Skill Blooms, Star Web and Forge materials (rules in Shared.Progression).
--   • Skills gain XP when they land the killing blow (the enemy's XP)
--   • Bloom Points (1 per skill level) and star points (1 per level) are only allocated by the server
--   • Materials: salvage (Inventory → Progress.salvage) and boss kills
-- The client gets snapshots via Net.Progress (throttled, at most once per second
-- on XP gain, immediately after its own actions).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skills = require(ReplicatedStorage.Shared.Skills)
local SpellStones = require(ReplicatedStorage.Shared.SpellStones)
local StarNet = require(ReplicatedStorage.Shared.StarNet)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Stats = require(script.Parent.Stats)

local Progress = {
	-- (player, delta: { [string]: number }) materials from fights (not salvage), for Systems/Rift
	Looted = Instance.new("BindableEvent"),
}

local FLUSH = 1 -- seconds between batched snapshots
local BOSS_CANDY = 1 -- Rune Candy per boss (until there are candy drops)
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

-- Salvage: shards fixed, candy by expected value, Glitter Dust by chance
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

-- ------------------------------------------------------------------ Skill XP
local function onKilled(
	player: any,
	_pos: any,
	_level: any,
	boss: any,
	skillId: any,
	xp: any,
	_depth: any,
	_region: any,
	_gold: any,
	elite: any
)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local profile = Data.get(player)
	if not profile then
		return
	end
	if typeof(skillId) == "string" and Skills.ById[skillId] and typeof(xp) == "number" then
		local sp = Progression.skillMut(profile.progress, skillId)
		if Progression.addSkillXp(sp, xp) > 0 then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				Net.Fx:FireClient(player, "dmg", {
					pos = root.Position + Vector3.new(0, 5, 0),
					text = string.format("%s level %d", Skills.ById[skillId].name, sp.level),
				})
			end
		end
		dirty[player] = true
	end
	-- Spell stones (Shared/SpellStones) from bosses and elites
	local chance = if boss == true
		then SpellStones.BOSS_CHANCE
		elseif elite == true then SpellStones.ELITE_CHANCE
		else 0
	if chance > 0 and rng:NextNumber() < chance then
		local id = SpellStones.roll(rng)
		profile.progress.stones[id] = (profile.progress.stones[id] or 0) + 1
		dirty[player] = true
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			Net.Fx:FireClient(player, "dmg", {
				pos = root.Position + Vector3.new(0, 6, 0),
				text = SpellStones.ById[id].name .. "!",
				color = SpellStones.ById[id].color,
			})
		end
	end
	if boss == true then
		local delta = {
			candy = BOSS_CANDY,
			dust = if rng:NextNumber() < BOSS_DUST_CHANCE then 1 else 0,
		}
		Progress.addMaterials(player, delta)
		Progress.Looted:Fire(player, delta)
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

-- Bar loadout (Skills window)
local function onLoadout(player: Player, action: any, a: any, b: any)
	if not allow(player) or typeof(action) ~= "string" then
		return
	end
	local profile = Data.get(player)
	if not profile then
		return
	end
	local progress = profile.progress
	if action == "equip" then
		if typeof(a) ~= "number" or typeof(b) ~= "string" then
			return
		end
		local level = (player:GetAttribute("Level") or 1) :: number
		if not Progression.equip(progress, a, b, level, profile.class) then
			return
		end
	elseif action == "socket" then
		-- a = skill id, b = { index, stoneId } ("" empties the socket)
		if typeof(a) ~= "string" or typeof(b) ~= "table" then
			return
		end
		local index, stoneId = b[1], b[2]
		if typeof(index) ~= "number" or typeof(stoneId) ~= "string" or #stoneId > 32 then
			return
		end
		if not Progression.socket(progress, a, index, stoneId) then
			return
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
			if not Progression.canAllocate(profile.progress, starId, level, profile.class) then
				return
			end
			stars[starId] = true
			Actions.fire(player, "star")
		else
			if not Progression.canRemove(profile.progress, starId, profile.class) then
				return
			end
			stars[starId] = nil
		end
	elseif action == "reset" then
		table.clear(stars)
		Progression.fitStars(profile.progress, profile.class) -- the own start point stays
	else
		return
	end
	Stats.refresh(player, false)
	send(player)
end

-- ------------------------------------------------------------------ Lifecycle
local function onPlayer(player: Player)
	local profile = Data.waitFor(player)
	if profile then
		Progression.fitBar(profile.progress, profile.class)
		if Progression.fitStars(profile.progress, profile.class) then
			Stats.refresh(player, false)
		end
		send(player)
	end
end

-- After the class was set (Systems/Characters setup): bar to the class, stats, snapshot
function Progress.classChanged(player: Player)
	local profile = Data.get(player)
	if profile then
		Progression.fitBar(profile.progress, profile.class)
		Progression.fitStars(profile.progress, profile.class)
		Stats.refresh(player, false)
		send(player)
	end
end

function Progress.init()
	Net.Bloom.OnServerEvent:Connect(onBloom)
	Net.Star.OnServerEvent:Connect(onStar)
	Net.Loadout.OnServerEvent:Connect(onLoadout)
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
