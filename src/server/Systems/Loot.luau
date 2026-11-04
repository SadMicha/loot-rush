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
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Combat = require(script.Parent.Combat)
local Data = require(script.Parent.Data)
local Inventory = require(script.Parent.Inventory)

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
	VACUUM_DELAY = 1.2, -- seconds after the boss dies before the leftovers fly to the player
}

local PICKUP_RADIUS = 6
local GOLD_PICKUP_RADIUS = 14 -- coins come from further away (fewer detours for small change)
local LIFETIME = 60

local drops: { Drop } = {}
local folder: Folder
local rng = Random.new()

local function makeDrop(pos: Vector3, owner: Player, gold: number, item: Items.Item?)
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

	local target = Vector3.new(pos.X + rng:NextNumber(-3, 3), 0.2, pos.Z + rng:NextNumber(-3, 3))
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
		itemChance = math.min(1, Balance.P.drop_normal * (1 + (bonus.items or 0))),
		bossItems = Balance.P.drops_boss,
		eliteItems = Balance.P.drops_elite,
		shift = Balance.rarityShift(d) + t.shift,
		uniques = d >= Balance.UNIQUE_FROM or (tier or 1) >= 2, -- uniques from Veteran on (docs/GAMEPLAY.md "World Tiers")
	}
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
	local total = (if typeof(gold) == "number" then math.max(0, gold) else 0)
		* t.goldMult
		* bonus("BonusGold") -- pet, passes … (Systems/Boosts)
	local itemChance = math.min(1, t.itemChance * bonus("BonusItems"))
	if boss == true then
		local coins = Config.LOOT_BOSS_GOLD_DROPS
		for _ = 1, coins do
			makeDrop(pos, owner, coin(total / coins), nil)
		end
		-- Table: boss loot at least 1× Rare+
		for i = 1, t.bossItems do
			local opts =
				{ shift = t.shift, min = if i == 1 then "rare" else nil, uniques = t.uniques }
			makeDrop(pos, owner, 0, Items.roll(t.ilvl, rng, nil, forHero(owner, opts)))
		end
		return
	end
	if total > 0 then
		makeDrop(pos, owner, coin(total), nil)
	end
	if elite == true then
		-- Table: elites drop a fixed number of items (at least Magic)
		for _ = 1, t.eliteItems do
			makeDrop(
				pos,
				owner,
				0,
				Items.roll(
					t.ilvl,
					rng,
					nil,
					forHero(owner, { shift = t.shift, min = "magic", uniques = t.uniques })
				)
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
				forHero(owner, starter or { shift = t.shift, uniques = t.uniques })
			)
		)
		if profile and starter then
			profile.starters += 1
		end
	end
end

-- Bonus items (rift variant "Against the Clock"): `count` items of Rare or better at `pos`
function Loot.bonus(owner: Player, pos: Vector3, depth: number, regionId: string?, count: number)
	local t = Loot.forDepth(depth, regionId, true, owner:GetAttribute("WorldTier") :: number?)
	for _ = 1, count do
		makeDrop(
			pos,
			owner,
			0,
			Items.roll(
				t.ilvl,
				rng,
				nil,
				forHero(owner, { shift = t.shift, min = "rare", uniques = t.uniques })
			)
		)
	end
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
		local stored, salvaged, full = Inventory.add(d.owner, item, true)
		if not stored then
			if at then
				warnFull(d.owner, item, at)
			end
			return false
		end
		text = if full
			then "Bag full - Salvaged " .. item.name
			elseif salvaged then "Salvaged " .. item.name
			else item.name
		color = Theme.Rarity[item.rarity] or Theme.Rarity.normal
		-- Beats the worn piece of its slot (or the slot is empty): the client adds the "UPGRADE" tag
		local profile = Data.get(d.owner)
		upgrade = not salvaged
			and profile ~= nil
			and Items.canWear(item, profile.level, profile.class)
			and Items.isUpgrade(item, profile.equipped[item.slot])
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
	end)
end

function Loot.start()
	while true do
		task.wait(0.1)
		sweep()
	end
end

return Loot
