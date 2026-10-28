--!strict
-- Beute: Gegner lassen Gold und manchmal Items fallen. Drops liegen mit Boden-Label (Name in Seltenheitsfarbe)
-- und gehören dem Töter; wer nah genug herangeht, hebt sie automatisch auf.
-- Optik: Items als Geschenkbox in Seltenheitsfarbe, Gold als Münze (Shared/Models/Loot).
-- Menge und Güte richten sich nach der Rift-Tiefe des Gegners (Config.LOOT_*) und den Boni des
-- Gebiets (Atlas.bonus): tiefer = höhere Gegenstandsstufe, mehr Gold, öfter seltene Items.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local LootModels = require(ReplicatedStorage.Shared.Models.Loot)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Combat = require(script.Parent.Combat)
local Inventory = require(script.Parent.Inventory)

type Drop = {
	model: Model,
	part: BasePart, -- verankerter Kern der Box/Münze
	owner: Player,
	gold: number,
	item: Items.Item?,
	expires: number,
}

local Loot = {}

local PICKUP_RADIUS = 6
local LIFETIME = 60
local BOSS_GOLD_DROPS = 5
local BOSS_ITEM_DROPS = 3

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
		model = LootModels.giftBox(color, item.rarity ~= "normal")
	else
		color = Theme.Color.Gold
		text = tostring(gold) .. " Gold"
		model = LootModels.coin()
	end
	local part = model.PrimaryPart :: BasePart

	local target = Vector3.new(pos.X + rng:NextNumber(-3, 3), 0.2, pos.Z + rng:NextNumber(-3, 3))
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	model:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)) * yaw)
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

	if item and (item.rarity == "rare" or item.rarity == "epic") then
		local beam = Instance.new("Part")
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.4
		beam.Size = Vector3.new(0.35, 16, 0.35)
		beam.Position = target + Vector3.new(0, 8, 0)
		beam.Parent = part
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

-- Was ein Gegner auf dieser Tiefe in diesem Gebiet fallen lässt (rein, für Tests)
function Loot.forDepth(depth: number, regionId: string?, boss: boolean)
	local region = if regionId then Atlas.ById[regionId] else nil
	local bonus: Atlas.Bonus = if region then region.bonus else {}
	local d = math.max(1, math.floor(depth))
	local ilvl = Items.levelForDepth(d, Config.LOOT_ILVL_PER_DEPTH)
	return {
		ilvl = if boss then ilvl + Config.LOOT_BOSS_ILVL else ilvl,
		gold = d * Config.LOOT_GOLD_PER_DEPTH * (if boss then 2 else 1),
		goldMult = 1 + (bonus.gold or 0),
		itemChance = math.min(1, Config.LOOT_ITEM_CHANCE * (1 + (bonus.items or 0))),
		find = Config.LOOT_FIND_PER_DEPTH * (d - 1) + (if boss then Config.LOOT_BOSS_FIND else 0),
	}
end

local function onKilled(
	player: any,
	pos: any,
	_level: any,
	boss: any,
	_skill: any,
	_xp: any,
	depth: any,
	region: any
)
	if typeof(player) ~= "Instance" or typeof(pos) ~= "Vector3" then
		return
	end
	local owner = player :: Player
	local t = Loot.forDepth(
		if typeof(depth) == "number" then depth else 1,
		if typeof(region) == "string" then region else nil,
		boss == true
	)
	local function gold(lo: number, hi: number): number
		return math.floor((rng:NextInteger(lo, hi) + t.gold) * t.goldMult + 0.5)
	end
	if boss == true then
		for _ = 1, BOSS_GOLD_DROPS do
			makeDrop(pos, owner, gold(8, 12), nil)
		end
		for _ = 1, BOSS_ITEM_DROPS do
			makeDrop(pos, owner, 0, Items.roll(t.ilvl, rng, t.find))
		end
		return
	end
	makeDrop(pos, owner, gold(2, 4), nil)
	if rng:NextNumber() < t.itemChance then
		makeDrop(pos, owner, 0, Items.roll(t.ilvl, rng, t.find))
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
		if Vector3.new(delta.X, 0, delta.Z).Magnitude > PICKUP_RADIUS then
			continue
		end

		local item = d.item
		local text: string
		local color: Color3
		if item then
			if not Inventory.add(d.owner, item) then
				continue -- Inventar voll: Item bleibt liegen
			end
			text = item.name
			color = Theme.Rarity[item.rarity] or Theme.Rarity.normal
		else
			Inventory.addGold(d.owner, d.gold)
			text = "+" .. tostring(d.gold) .. " Gold"
			color = Theme.Color.Gold
		end
		Net.Fx:FireClient(
			d.owner,
			"dmg",
			{ pos = root.Position + Vector3.new(0, 4, 0), text = text, color = color }
		)
		d.model:Destroy()
		table.remove(drops, i)
	end
end

function Loot.init()
	folder = Instance.new("Folder")
	folder.Name = "Beute"
	folder.Parent = workspace
	Combat.EnemyKilled.Event:Connect(onKilled)
end

function Loot.start()
	while true do
		task.wait(0.1)
		sweep()
	end
end

return Loot
