--!strict
-- Keeps the own character inside the map it is on. The client owns its character's physics, so a
-- fast sprint, a dash or a steep slope could in theory carry it past the invisible walls before the
-- server notices. Every frame, after physics, this puts it straight back to the nearest edge of
-- the closest map rectangle (the "Bounds" folders the server tags, Shared/Util/Bounds). A body that
-- got further out than a push reaches (a frame hitch carried a sprint or dash through the wall) goes
-- back to where it last stood inside. Server/Systems/FallGuard is the authoritative check.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)
local Config = require(ReplicatedStorage.Shared.Config)

local BoundsController = {}

local player = Players.LocalPlayer
local rects: { [Instance]: Bounds.Rect? } = {}
local list: { Bounds.Rect } = {} -- reused every frame
local lastRoot: BasePart? = nil
local lastInside: Vector3? = nil -- last position of lastRoot inside a map rectangle

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
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) or humanoid.Health <= 0 then
		return -- dead bodies stay where they fall until the respawn (like FallGuard)
	end
	table.clear(list)
	for _, r in rects do
		if r then
			table.insert(list, r)
		end
	end
	if root ~= lastRoot then
		lastRoot = root
		lastInside = nil -- new body (respawn): no old spot
	end
	local pos = root.Position
	for _, r in list do
		if Bounds.outside(pos, r) <= 0 then
			lastInside = pos
			return
		end
	end
	local target: Vector3
	local back = Bounds.pushBack(pos, list)
	if back then
		target = back
	else
		-- Too far out for a push: back to the last spot inside, unless that is far away (a server
		-- teleport between maps or a rescue) or the body fell (FallGuard handles falls)
		local last = lastInside
		if
			not last
			or (pos - last).Magnitude > Config.BOUNDS_SNAP
			or pos.Y < last.Y - Config.BOUNDS_DROP
		then
			return
		end
		target = last
	end
	local v = root.AssemblyLinearVelocity
	root.CFrame = CFrame.new(target) * root.CFrame.Rotation
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
