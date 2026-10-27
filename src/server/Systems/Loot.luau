--!strict
-- Beute: Gegner lassen Gold und manchmal Items fallen. Drops liegen mit Boden-Label (Name in Seltenheitsfarbe)
-- und gehören dem Töter; wer nah genug herangeht, hebt sie automatisch auf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Combat = require(script.Parent.Combat)
local Inventory = require(script.Parent.Inventory)

type Drop = {
	part: Part,
	owner: Player,
	gold: number,
	item: Items.Item?,
	expires: number,
}

local Loot = {}

local PICKUP_RADIUS = 6
local LIFETIME = 60
local ITEM_CHANCE = 0.35
local BOSS_GOLD_DROPS = 5
local BOSS_ITEM_DROPS = 3

local drops: { Drop } = {}
local folder: Folder
local rng = Random.new()

local function makeDrop(pos: Vector3, owner: Player, gold: number, item: Items.Item?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon

	local text: string
	local color: Color3
	if item then
		color = Theme.Rarity[item.rarity] or Theme.Rarity.normal
		text = item.name
		part.Size = Vector3.one * 1.4
		if item.rarity == "normal" then
			part.Material = Enum.Material.SmoothPlastic
		end
	else
		color = Theme.Color.Gold
		text = tostring(gold) .. " Gold"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * 1.2
	end
	part.Color = color

	local target = Vector3.new(pos.X + rng:NextNumber(-3, 3), 1.2, pos.Z + rng:NextNumber(-3, 3))
	part.Position = target + Vector3.new(0, 3, 0)
	part.Parent = folder
	TweenService:Create(
		part,
		TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ Position = target }
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

	table.insert(
		drops,
		{ part = part, owner = owner, gold = gold, item = item, expires = os.clock() + LIFETIME }
	)
end

local function onKilled(player: any, pos: any, level: any, boss: any)
	if typeof(player) ~= "Instance" or typeof(pos) ~= "Vector3" or typeof(level) ~= "number" then
		return
	end
	local owner = player :: Player
	if boss == true then
		for _ = 1, BOSS_GOLD_DROPS do
			makeDrop(pos, owner, rng:NextInteger(8, 12) + level * 4, nil)
		end
		for _ = 1, BOSS_ITEM_DROPS do
			makeDrop(pos, owner, 0, Items.roll(level + 2, rng))
		end
		return
	end
	makeDrop(pos, owner, rng:NextInteger(2, 4) + level * 2, nil)
	if rng:NextNumber() < ITEM_CHANCE then
		makeDrop(pos, owner, 0, Items.roll(level, rng))
	end
end

local function sweep()
	local now = os.clock()
	for i = #drops, 1, -1 do
		local d = drops[i]
		if not d.part.Parent or now > d.expires or not d.owner.Parent then
			d.part:Destroy()
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
		d.part:Destroy()
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
