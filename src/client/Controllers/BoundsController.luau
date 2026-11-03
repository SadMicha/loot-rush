--!strict
-- Keeps the own character inside the map it is on. The client owns its character's physics, so a
-- fast sprint, a dash or a steep slope could in theory carry it past the invisible walls before the
-- server notices. Every frame, after physics, this puts it straight back to the nearest edge of
-- the closest map rectangle (the "Bounds" folders the server tags, Shared/Util/Bounds).
-- Server/Systems/FallGuard does the same check on the server as a backup.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)

local BoundsController = {}

local player = Players.LocalPlayer
local rects: { [Instance]: Bounds.Rect? } = {}
local list: { Bounds.Rect } = {} -- reused every frame

local function track(folder: Instance)
	local function refresh()
		rects[folder] = if CollectionService:HasTag(folder, Bounds.TAG)
			then Bounds.read(folder)
			else nil
	end
	refresh()
	folder.AttributeChanged:Connect(refresh)
end

local function step()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	table.clear(list)
	for _, r in rects do
		if r then
			table.insert(list, r)
		end
	end
	local pos = root.Position
	local back = Bounds.pushBack(pos, list)
	if not back then
		return
	end
	local v = root.AssemblyLinearVelocity
	root.CFrame = CFrame.new(back) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
end

function BoundsController.init() end

function BoundsController.start()
	CollectionService:GetInstanceAddedSignal(Bounds.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Bounds.TAG):Connect(function(folder: Instance)
		rects[folder] = nil
	end)
	for _, folder in CollectionService:GetTagged(Bounds.TAG) do
		track(folder)
	end
	RunService.Heartbeat:Connect(step)
end

return BoundsController
