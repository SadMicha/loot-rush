--!strict
-- Loot: enemies drop gold and sometimes items. Drops lie with a ground label (name in rarity color)
-- and belong to the killer; whoever gets close enough picks them up automatically.
-- Look: items as a gift box in rarity color (Rare+ bigger, with a light pillar), gold as a coin
-- (Shared/Models/Loot). Pickup tells the client when the item beats the worn one ("upgrade").
-- Amount and quality depend on the enemy's Rift depth (Shared/Balance, table) and the bonuses
-- of the region (Atlas.bonus): deeper = higher item power, more gold, rare items more often.
-- Gold per kill is carried by the enemy itself (attribute Gold, Systems/Enemies).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Balance = require(ReplicatedStorage.Shared.Balance)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local LootModels = require(ReplicatedStorage.Shared.Models.Loot)
local Net = require(ReplicatedStorage.Shared.Net)
local Upgrade = require(ReplicatedStorage.Shared.Upgrade)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Analytics = require(script.Parent.Analytics)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)
local Stats = require(script.Parent.Stats)

type Drop = {
	model: Model,
	part: BasePart, -- anchored core of the box/coin
	owner: Player,
	gold: number,
	item: Items.Item?,
	expires: number,
}

local Loot = {
	-- (player, gold: number, item: Items.Item?) after every pickup, for Systems/Rift
	Picked = Instance.new("BindableEvent"),
	-- seconds after the boss dies before the leftovers fly to the player: the whole loot burst
	-- (Config.LOOT_BURST_SPAN) has landed and bounced by then
	VACUUM_DELAY = Config.LOOT_BURST_SPAN + 0.75,
}

local PICKUP_RADIUS = 6
local GOLD_PICKUP_RADIUS = 14 -- coins come from further away (fewer detours for small change)
local LIFETIME = 60

local drops: { Drop } = {}
local folder: Folder
local rng = Random.new()

-- at = exact landing spot (boss burst); otherwise a random spot within 3 studs of pos
local function makeDrop(pos: Vector3, owner: Player, gold: number, item: Items.Item?, at: Vector3?)
	local text: string
	local color: Color3
	local model: Model
	if item then
		color = Theme.Rarity[item.rarity] or Theme.Rarity.normal
		text = item.name
		local glow = LootModels.Glow[item.rarity]
		model = LootModels.giftBox(color, item.rarity ~= "normal", if glow then glow.box else nil)
	else
		color = Theme.Color.Gold
		text = Format.currency(gold) .. " Gold"
		model = LootModels.coin()
	end
	local part = model.PrimaryPart :: BasePart

	local target = if at
		then Vector3.new(at.X, 0.2, at.Z)
		else Vector3.new(pos.X + rng:NextNumber(-3, 3), 0.2, pos.Z + rng:NextNumber(-3, 3))
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	model:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)) * yaw)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- label and box arrive together
	model.Parent = folder
	TweenService:Create(
		part,
		TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(target) * yaw * part.PivotOffset:Inverse() }
	):Play()

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 24)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	-- The client declutters by these (FxController): rarity for items, a flag for coins
	if item then
		gui:SetAttribute("Rarity", item.rarity)
	else
		gui:SetAttribute("Gold", true)
	end
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextSize = if item and item.rarity ~= "normal" then 16 else 14
	label.TextColor3 = color
	label.FontFace = Theme.Font.UI
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Theme.Color.Bg0
	label.Parent = gui

	-- Rare and better: light pillar, glow and ground ring (Models/Loot.Glow), plus one ring pulse
	-- for the owner when it lands, so a great drop is the loudest thing on screen
	local pillar = if item then LootModels.pillar(color, item.rarity) else nil
	if pillar and item then
		pillar:PivotTo(CFrame.new(target))
		pillar.Parent = model
		local glow = LootModels.Glow[item.rarity]
		task.delay(0.45, function()
			if owner.Parent and model.Parent then
				Net.Fx:FireClient(owner, "nova", {
					pos = target + Vector3.new(0, 0.3, 0),
					radius = glow.ring * 2.5,
					color = color,
				})
			end
		end)
	end

	table.insert(drops, {
		model = model,
		part = part,
		owner = owner,
		gold = gold,
		item = item,
		expires = os.clock() + LIFETIME,
	})
end

-- Loot burst (boss kills, bonus items): the drops fountain out of `pos` one after another and land
-- on a ring around it, the best item last. The server only sends one Net.Fx "lootburst" with the
-- flight paths (the client draws the glowing arcs, FxController) and creates each real drop
-- when its arc arrives, so nothing tweens over the network.
type Planned = { gold: number, item: Items.Item?, owner: Player?, landed: boolean? }

-- Burst drops still in the air: Loot.collect (run end, death, leave) takes them too, so nothing
-- in flight is lost; `landed` stops the drop from also appearing afterwards
local flying: { Planned } = {}

-- Landing spots and start delays for `n` drops (pure, for tests): evenly spread angles with a
-- little jitter, coins on the outer ring, items closer in; the delays fit in Config.LOOT_BURST_SPAN
function Loot.burstPlan(
	pos: Vector3,
	n: number,
	items: number,
	r: Random
): { { at: Vector3, delay: number } }
	local out = {}
	local flight = Config.LOOT_BURST_FLIGHT
	local stagger = if n > 1
		then math.min(Config.LOOT_BURST_STAGGER, (Config.LOOT_BURST_SPAN - flight) / (n - 1))
		else 0
	local turn = r:NextNumber(0, math.pi * 2)
	local minR, maxR = Config.LOOT_BURST_RADIUS_MIN, Config.LOOT_BURST_RADIUS_MAX
	for i = 1, n do
		local isItem = i > n - items
		local a = turn + (i - 1) / n * math.pi * 2 * 1.618 + r:NextNumber(-0.2, 0.2) -- golden spread
		local dist = if isItem
			then r:NextNumber(minR, (minR + maxR) / 2)
			else r:NextNumber((minR + maxR) / 2, maxR)
		out[i] = {
			at = Vector3.new(pos.X + math.cos(a) * dist, 0.2, pos.Z + math.sin(a) * dist),
			delay = (i - 1) * stagger,
		}
	end
	return out
end

local function burst(pos: Vector3, owner: Player, list: { Planned })
	-- Coins first, then items from worst to best: the best one lands last
	table.sort(list, function(a, b)
		local ra = if a.item then Items.rank(a.item.rarity) else 0
		local rb = if b.item then Items.rank(b.item.rarity) else 0
		return ra < rb
	end)
	local items = 0
	for _, d in list do
		if d.item then
			items += 1
		end
	end
	local plan = Loot.burstPlan(pos, #list, items, rng)
	local arcs = {}
	for i, d in list do
		local item = d.item
		arcs[i] = {
			to = plan[i].at,
			delay = plan[i].delay,
			color = if item
				then Theme.Rarity[item.rarity] or Theme.Rarity.normal
				else Theme.Color.Gold,
			big = if item and Items.rank(item.rarity) >= Items.rank("rare") then true else nil,
		}
	end
	Net.Fx:FireClient(owner, "lootburst", {
		pos = pos,
		flight = Config.LOOT_BURST_FLIGHT,
		arcs = arcs,
	})
	for i, d in list do
		d.owner = owner
		table.insert(flying, d)
		task.delay(plan[i].delay + Config.LOOT_BURST_FLIGHT, function()
			local at = table.find(flying, d)
			if at then
				table.remove(flying, at)
			end
			if not d.landed and owner.Parent then
				d.landed = true
				makeDrop(pos, owner, d.gold, d.item, plan[i].at)
			end
		end)
	end
end

-- What an enemy drops at this depth in this region (pure, for tests)
-- tier = World Tier of the run (Shared/WorldTiers): higher item level and rarity shift
function Loot.forDepth(depth: number, regionId: string?, boss: boolean, tier: number?)
	local region = if regionId then Atlas.ById[regionId] else nil
	local bonus: Atlas.Bonus = if region then region.bonus else {}
	local d = math.max(1, math.floor(depth))
	local t = WorldTiers.get(tier)
	local ilvl = Items.levelForDepth(d) + t.ilvl
	return {
		ilvl = if boss then ilvl + Config.LOOT_BOSS_ILVL else ilvl,
		goldMult = 1 + (bonus.gold or 0),
		itemChance = math.min(
			1,
			(if d <= Balance.EARLY_DROP_DEPTH then Balance.P.drop_early else Balance.P.drop_normal)
				* (1 + (bonus.items or 0))
		),
		bossItems = Balance.P.drops_boss,
		eliteItems = Balance.P.drops_elite,
		shift = Balance.rarityShift(d) + t.shift,
		-- lowest rarity of a random drop: no Normal items from Balance.MAGIC_FROM (LOOT.md P5)
		min = if d >= Balance.MAGIC_FROM then "magic" else nil,
		-- bosses may drop their uniques: from UNIQUE_FROM, or from Veteran on (docs/GAMEPLAY.md "World Tiers")
		uniques = d >= Balance.UNIQUE_FROM or (tier or 1) >= 2,
		tier = t.id,
		-- the boss of this depth (Altered World rotates, Atlas.bossFor): its uniques drop
		bossKind = if region then (Atlas.bossFor(region, d)) else nil,
	}
end

-- Chance that a boss kill drops one of the boss's uniques (Balance.UniqueDrops), pure
function Loot.uniqueChance(tier: number?, pity: number?): number
	local u = Balance.UniqueDrops
	local t = math.max(1, math.floor(tier or 1))
	return math.clamp(u.base + u.perTier * (t - 1) + u.pity * math.max(0, pity or 0), 0, 1)
end

-- Rolls the unique of one boss kill and books the luck (pity, Veteran firsts), pure apart from
-- changing `luck`. `allowed` = this depth/tier may drop uniques and the boss kind owns some.
-- Returns true when a unique drops.
function Loot.rollBossUnique(
	luck: Profile.Luck,
	kind: string,
	tier: number?,
	allowed: boolean,
	r: number
): boolean
	if not allowed then
		return false
	end
	local t = math.max(1, math.floor(tier or 1))
	if Balance.UniqueDrops.veteranFirst and t >= 2 and not luck.firsts[kind] then
		luck.firsts[kind] = true
		luck.pity[kind] = 0
		return true
	end
	if r < Loot.uniqueChance(t, luck.pity[kind]) then
		luck.pity[kind] = 0
		return true
	end
	luck.pity[kind] = (luck.pity[kind] or 0) + 1
	return false
end

-- Does this boss kill (the n-th of the hero) bring the guaranteed Epic? Pure.
function Loot.epicDue(bossKills: number): boolean
	local every = Balance.UniqueDrops.epicEvery
	return every > 0 and bossKills > 0 and bossKills % every == 0
end

-- Roll options of a guaranteed first drop (Balance.FirstDrops), nil once all were given (pure)
-- given = drops this character already got from normal kills while the guarantee ran
-- Roll options for a drop of this hero: its class (Item.class, class base names)
local function forHero(owner: Player, opts: Items.RollOpts): Items.RollOpts
	local profile = Data.get(owner)
	local out = table.clone(opts)
	out.class = if profile then profile.class else nil
	return out
end

function Loot.starter(given: number, shift: number): Items.RollOpts?
	local rule = Balance.FirstDrops
	if given >= rule.kills then
		return nil
	end
	if given == 0 then
		return { shift = shift, min = rule.firstMin, slot = rule.firstSlot }
	end
	return { shift = shift }
end

-- Bonus of the depth a player's rift is in (Path Card reward and affixes, Systems/Rift):
-- items/gold = extra shares (0.3 = +30 %), rolls = extra item rolls per normal kill (Big Builds)
export type RunBonus = { items: number, gold: number, rolls: number }
local runBonus: { [Player]: RunBonus } = {}

function Loot.setRunBonus(player: Player, bonus: RunBonus?)
	runBonus[player] = bonus :: any -- nil clears
end

function Loot.runBonus(player: Player): RunBonus?
	return runBonus[player]
end

local function onKilled(
	player: any,
	pos: any,
	_level: any,
	boss: any,
	_skill: any,
	_xp: any,
	depth: any,
	region: any,
	gold: any,
	elite: any
)
	if typeof(player) ~= "Instance" or typeof(pos) ~= "Vector3" then
		return
	end
	local owner = player :: Player
	local t = Loot.forDepth(
		if typeof(depth) == "number" then depth else 1,
		if typeof(region) == "string" then region else nil,
		boss == true,
		owner:GetAttribute("WorldTier") :: number?
	)
	-- Random rounding: small amounts (1.1 gold) still pay out the region bonus on average
	local function coin(amount: number): number
		return math.max(1, math.floor(amount + rng:NextNumber()))
	end
	local function bonus(attr: string): number
		local v = owner:GetAttribute(attr)
		return 1 + (if typeof(v) == "number" then v else 0) / 100
	end
	local rb = runBonus[owner]
	local total = (if typeof(gold) == "number" then math.max(0, gold) else 0)
		* t.goldMult
		* bonus("BonusGold") -- pet, passes … (Systems/Boosts)
		* (1 + (if rb then rb.gold else 0))
	local itemChance =
		math.min(1, t.itemChance * bonus("BonusItems") * (1 + (if rb then rb.items else 0)))
	if boss == true then
		local list: { Planned } = {}
		local coins = Config.LOOT_BOSS_GOLD_DROPS
		for _ = 1, coins do
			table.insert(list, { gold = coin(total / coins) })
		end
		-- Table: boss loot at least 1× Rare+ (random rolls never give uniques, see below)
		for i = 1, t.bossItems do
			local opts = { shift = t.shift, min = if i == 1 then "rare" else t.min }
			table.insert(
				list,
				{ gold = 0, item = Items.roll(t.ilvl, rng, nil, forHero(owner, opts)) }
			)
		end
		local profile = Data.get(owner)
		if profile then
			local luck = profile.luck
			luck.bosses += 1
			if Loot.epicDue(luck.bosses) then
				local opts = forHero(owner, { shift = t.shift, min = "epic" })
				table.insert(list, { gold = 0, item = Items.roll(t.ilvl, rng, nil, opts) })
			end
			-- Targeted uniques (LOOT.md P4): each boss kind drops its own, with pity
			local kind = t.bossKind
			local pool = if kind then Items.uniquesFrom(kind) else {}
			if
				kind
				and Loot.rollBossUnique(
					luck,
					kind,
					t.tier,
					t.uniques and #pool > 0,
					rng:NextNumber()
				)
			then
				local u = pool[rng:NextInteger(1, #pool)]
				table.insert(
					list,
					{ gold = 0, item = Items.makeUnique(u, t.ilvl, rng, profile.class) }
				)
				Analytics.custom(owner, "unique_found", t.tier)
			end
		end
		burst(pos, owner, list)
		return
	end
	if total > 0 then
		makeDrop(pos, owner, coin(total), nil)
	end
	-- Big Builds: extra item rolls per kill, elites included (never a starter drop)
	for _ = 1, if rb then rb.rolls else 0 do
		if rng:NextNumber() < itemChance then
			makeDrop(
				pos,
				owner,
				0,
				Items.roll(t.ilvl, rng, nil, forHero(owner, { shift = t.shift, min = t.min }))
			)
		end
	end
	if elite == true then
		-- Table: elites drop a fixed number of items (at least Magic)
		for _ = 1, t.eliteItems do
			makeDrop(
				pos,
				owner,
				0,
				Items.roll(t.ilvl, rng, nil, forHero(owner, { shift = t.shift, min = "magic" }))
			)
		end
		return
	end
	-- A new character's first kills always drop (Balance.FirstDrops); a random drop counts too
	local profile = Data.get(owner)
	local starter = if profile then Loot.starter(profile.starters, t.shift) else nil
	if starter or rng:NextNumber() < itemChance then
		makeDrop(
			pos,
			owner,
			0,
			Items.roll(
				t.ilvl,
				rng,
				nil,
				forHero(owner, starter or { shift = t.shift, min = t.min })
			)
		)
		if profile and starter then
			profile.starters += 1
		end
	end
end

-- Bonus items (rift affix "Against the Clock", Path Card caches, champions): `count` items of
-- Rare or better at `pos`
function Loot.bonus(owner: Player, pos: Vector3, depth: number, regionId: string?, count: number)
	local t = Loot.forDepth(depth, regionId, true, owner:GetAttribute("WorldTier") :: number?)
	local list: { Planned } = {}
	for _ = 1, count do
		local opts = forHero(owner, { shift = t.shift, min = "rare" })
		table.insert(list, { gold = 0, item = Items.roll(t.ilvl, rng, nil, opts) })
	end
	burst(pos, owner, list)
end

-- "Bag full" popup for an upgrade that stays on the ground: at most once per BAG_WARN seconds
local BAG_WARN = 4
local warned: { [Player]: number } = {}

local function warnFull(player: Player, item: Items.Item, at: Vector3)
	local now = os.clock()
	if now - (warned[player] or -math.huge) < BAG_WARN then
		return
	end
	warned[player] = now
	Net.Fx:FireClient(player, "dmg", {
		pos = at + Vector3.new(0, 4, 0),
		text = "Bag full! Make room for " .. item.name,
		color = Theme.Color.Danger,
	})
end

-- Picks up a drop for its owner. false = bag full and the item is an upgrade: it stays on the
-- ground (anything else is salvaged when the bag is full, Inventory.add).
-- at = position for the text popup; without at silent and without the Picked signal (Loot.collect).
local function pickup(d: Drop, at: Vector3?): boolean
	local item = d.item
	local text: string
	local color: Color3
	local upgrade = false
	if item then
		local stored, salvaged, full, worn = Inventory.add(d.owner, item, true)
		if not stored then
			if at then
				warnFull(d.owner, item, at)
			end
			return false
		end
		text = if full
			then "Bag full - Salvaged " .. item.name
			elseif salvaged then "Salvaged " .. item.name
			elseif worn then "Equipped " .. item.name
			else item.name
		color = Theme.Rarity[item.rarity] or Theme.Rarity.normal
		-- Beats the worn piece of its slot (or the slot is empty): the client adds the "UPGRADE" tag
		local hero = if salvaged or worn then nil else Stats.hero(d.owner)
		upgrade = hero ~= nil
			and Items.canWear(item, hero.level, hero.class)
			and Upgrade.isUpgrade(hero, item)
	else
		Inventory.addGold(d.owner, d.gold)
		text = "+" .. Format.currency(d.gold) .. " Gold"
		color = Theme.Color.Gold
	end
	if at then
		Net.Fx:FireClient(d.owner, "dmg", {
			pos = at + Vector3.new(0, 4, 0),
			text = text,
			color = color,
			pickup = if item then item.rarity else "gold", -- pickup sound (SoundController)
			upgrade = if upgrade then true else nil,
		})
		Loot.Picked:Fire(d.owner, if item then 0 else d.gold, item)
	end
	return true
end

-- Rift end: collect everything on the ground that still belongs to the player, right away.
-- Returns what actually arrived. An upgrade that does not fit is salvaged rather than lost
-- with the arena (gold + materials; it does not count as an item of the run).
function Loot.collect(player: Player): (number, { Items.Item })
	local gold, items = 0, {}
	for i = #drops, 1, -1 do
		local d = drops[i]
		if d.owner == player then
			if pickup(d, nil) then
				if d.item then
					table.insert(items, d.item)
				else
					gold += d.gold
				end
			elseif d.item then
				Inventory.salvageLoot(player, d.item)
			end
			d.model:Destroy()
			table.remove(drops, i)
		end
	end
	-- Still flying out of a boss: handed over the same way, and they will not land any more
	for i = #flying, 1, -1 do
		local f = flying[i]
		if f.owner == player then
			table.remove(flying, i)
			f.landed = true
			local d: Drop = {
				model = nil :: any, -- not used by a silent pickup
				part = nil :: any,
				owner = player,
				gold = f.gold,
				item = f.item,
				expires = 0,
			}
			if pickup(d, nil) then
				if f.item then
					table.insert(items, f.item)
				else
					gold += f.gold
				end
			elseif f.item then
				Inventory.salvageLoot(player, f.item)
			end
		end
	end
	return gold, items
end

-- Depth cleared: everything still lying around for the player is picked up (with popups and the
-- Picked signal, like walking over it), so nobody has to run circles before choosing "Deeper".
-- Items that do not fit stay on the ground. Systems/Rift waits Loot.VACUUM_DELAY before calling it.
function Loot.vacuum(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then root.Position else nil
	for i = #drops, 1, -1 do
		local d = drops[i]
		if d.owner == player and d.model.Parent then
			if pickup(d, at or d.part.Position) then
				d.model:Destroy()
				table.remove(drops, i)
			end
		end
	end
end

local function sweep()
	local now = os.clock()
	for i = #drops, 1, -1 do
		local d = drops[i]
		if not d.model.Parent or now > d.expires or not d.owner.Parent then
			d.model:Destroy()
			table.remove(drops, i)
			continue
		end
		local root = d.owner.Character and d.owner.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local delta = root.Position - d.part.Position
		local magnet = d.owner:GetAttribute("BonusMagnet") -- pet (Systems/Boosts)
		local radius = (if d.item then PICKUP_RADIUS else GOLD_PICKUP_RADIUS)
			+ (if typeof(magnet) == "number" then magnet else 0)
		if Vector3.new(delta.X, 0, delta.Z).Magnitude > radius then
			continue
		end
		if pickup(d, root.Position) then
			d.model:Destroy()
			table.remove(drops, i)
		end
	end
end

function Loot.init()
	folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = workspace
	Combat.EnemyKilled.Event:Connect(onKilled)
	Players.PlayerRemoving:Connect(function(player: Player)
		warned[player] = nil
		runBonus[player] = nil
	end)
end

function Loot.start()
	while true do
		task.wait(0.1)
		sweep()
	end
end

return Loot
