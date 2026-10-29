--!strict
-- Lässt ausgerüstete Haustiere aller Spieler hinter ihnen herschweben (nur Optik, rein lokal).
-- Welche Haustiere jemand trägt, steht im Player-Attribut "Pets" (kommagetrennt, Systems/Pets).
-- Modell: ReplicatedStorage.Assets.Pet_<id>, wenn Micha eins importiert hat, sonst ein kleiner
-- Platzhalter aus Shared/Models/Creatures (Bauplan Pets.look).
-- Für das Haustier-Fenster: PetController.state (letzter Net.Pets-Stand) und PetController.Changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Pets = require(ReplicatedStorage.Shared.Pets)
local Creatures = require(ReplicatedStorage.Shared.Models.Creatures)

local PetController = {
	-- letzter Stand vom Server: { owned = { [id] = Stufe }, equipped = { id }, slots = number }
	state = { owned = {}, equipped = {}, slots = 1 } :: { [string]: any },
	-- feuert nach jedem neuen Stand (Net.Pets)
	Changed = Instance.new("BindableEvent"),
}

local SCALE = 0.45
local FOLLOW = 8 -- höher = enger hinterher
local OFFSETS = { Vector3.new(3, 2.5, 3.5), Vector3.new(-3, 2.5, 3.5) }

type Follower = { id: string, model: Model, cf: CFrame }

local folder: Folder
local followers: { [Player]: { Follower } } = {}

local function build(id: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local custom = assets and assets:FindFirstChild("Pet_" .. id)
	if custom and custom:IsA("Model") then
		local m = custom:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
		return m
	end
	local pet = Pets.ById[id]
	local maker = pet and (Creatures :: any)[pet.look]
	if typeof(maker) ~= "function" then
		return nil
	end
	local m = maker(SCALE, pet.color, pet.glow) :: Model
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
		end
	end
	return m
end

local function clear(player: Player)
	local list = followers[player]
	if list then
		for _, f in list do
			f.model:Destroy()
		end
	end
	followers[player] = nil
end

local function refresh(player: Player)
	clear(player)
	local raw = player:GetAttribute("Pets")
	if typeof(raw) ~= "string" or raw == "" then
		return
	end
	local list: { Follower } = {}
	for _, id in string.split(raw, ",") do
		if #list >= #OFFSETS then
			break
		end
		local model = build(id)
		if model then
			model.Name = "Haustier_" .. id
			model.Parent = folder
			table.insert(list, { id = id, model = model, cf = model:GetPivot() })
		end
	end
	followers[player] = list
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Pets"):Connect(function()
		refresh(player)
	end)
	refresh(player)
end

local function step(dt: number)
	local t = os.clock()
	local alpha = 1 - math.exp(-FOLLOW * dt)
	for player, list in followers do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		for i, f in list do
			local bob = math.sin(t * 3 + i) * 0.4
			local target = root.CFrame * CFrame.new(OFFSETS[i] + Vector3.new(0, bob, 0))
			-- nicht durch Teleporte (Hub ↔ Rift) schweben
			if (f.cf.Position - target.Position).Magnitude > 60 then
				f.cf = target
			else
				f.cf = f.cf:Lerp(target, alpha)
			end
			f.model:PivotTo(f.cf)
		end
	end
end

function PetController.init()
	folder = Instance.new("Folder")
	folder.Name = "Haustiere"
	folder.Parent = workspace
	Net.Pets.OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" then
			PetController.state = data
			PetController.Changed:Fire(data)
		end
	end)
end

function PetController.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)
	RunService.RenderStepped:Connect(step)
end

return PetController
