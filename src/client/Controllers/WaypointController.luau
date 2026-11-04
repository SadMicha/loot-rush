--!strict
-- Quest waypoint (docs/ROADMAP.md O1): in the hub a gold beam runs from the player's feet to
-- the station of the active quest (Shared/Quests.Waypoints: Rift Gate, Forge, Stash, Pet Stable),
-- and the minimap shows a marker there (HudController reads WaypointController.target()).
-- Both hide in a Rift, near the station (Config.WAYPOINT_HIDE) and for quests without a station.
-- Purely client-side; the station parts can stream out and back in, so they are looked up again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Quests)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local QuestController = require(script.Parent.QuestController)

local WaypointController = {}

local TICK = 0.25
local HUB = "Lumenhaven"

local player = Players.LocalPlayer
local C = Theme.Color

-- Beam + its two attachments, rebuilt when the character or the station part is new (a respawn or a
-- stream-out destroys them with their parent)
type Rig = { from: Attachment, to: Attachment, beam: Beam, root: BasePart, part: BasePart }
local rig: Rig? = nil
local station: BasePart? = nil
local stationWindow = ""
local target: Vector3? = nil

-- Position of the active quest's station while the waypoint shows, nil otherwise
function WaypointController.target(): Vector3?
	return target
end

-- Station part for a window name (cached while it stays streamed in)
local function find(window: string): BasePart?
	if
		station
		and stationWindow == window
		and station.Parent ~= nil
		and station:IsDescendantOf(workspace)
	then
		return station
	end
	station, stationWindow = nil, window
	local hub = workspace:FindFirstChild(HUB)
	local part = hub and hub:FindFirstChild("Station_" .. window, true)
	if part and part:IsA("BasePart") then
		station = part
	end
	return station
end

-- A respawn or stream-out destroys the attachments with their parent: forget such a rig. Only
-- properties are read here (a destroyed instance has Parent nil and takes no method calls).
local function alive(r: Rig): boolean
	return r.from.Parent == r.root
		and r.to.Parent == r.part
		and r.root.Parent ~= nil
		and r.part.Parent ~= nil
end

local function drop()
	local r = rig
	rig = nil
	if r then
		-- an attachment whose parent is gone was destroyed with it (Parent nil, locked);
		-- detach the rest
		for _, a in { r.from, r.to } do
			if a.Parent ~= nil then
				a.Parent = nil
			end
		end
	end
end

local function hide()
	target = nil
	local r = rig
	if r and not alive(r) then
		rig = nil
	elseif r then
		r.beam.Enabled = false
	end
end

local function build(root: BasePart, part: BasePart): Rig
	drop()
	local from = Instance.new("Attachment")
	from.Name = "WaypointFrom"
	from.Position = Vector3.new(0, -2.6, 0) -- at the feet
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "WaypointTo"
	to.Position = Vector3.new(0, -1.6, 0) -- near the station's floor
	to.Parent = part
	local beam = Instance.new("Beam")
	beam.Name = "QuestWaypoint"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(C.GoldHi, C.Gold)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 0.5
	beam.Width1 = 0.9
	beam.Segments = 1
	beam.Parent = from
	return { from = from, to = to, beam = beam, root = root, part = part }
end

local function update()
	local window = Rules.waypoint(QuestController.state().step)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not window
		or player:GetAttribute("RiftRegion") ~= nil
		or not (root and root:IsA("BasePart"))
	then
		return hide()
	end
	local part = find(window)
	if not part then
		return hide()
	end
	local flat = part.Position - root.Position
	if Vector3.new(flat.X, 0, flat.Z).Magnitude < Config.WAYPOINT_HIDE then
		return hide()
	end
	target = part.Position
	local r: Rig? = rig
	if not r or r.root ~= root or r.part ~= part or not alive(r) then
		r = build(root, part)
	end
	local live = r :: Rig
	rig = live
	live.beam.Enabled = true
end

function WaypointController.start()
	task.spawn(function()
		while true do
			update()
			task.wait(TICK)
		end
	end)
end

return WaypointController
