--!strict
-- Snapshot of skill levels, skill blooms, Star Net and materials (Net.Progress).
-- The windows only read from here and send requests to the server; validation happens there (Systems/Progress).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)

local ProgressController = {}

local data: Progression.Data = Progression.fresh()
local materials: Progression.Materials = Progression.freshMaterials()

local changed = Instance.new("BindableEvent")
ProgressController.changed = changed.Event

function ProgressController.data(): Progression.Data
	return data
end

function ProgressController.materials(): Progression.Materials
	return materials
end

function ProgressController.start()
	Net.Progress.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		-- Same sanitizing as on load: the UI relies on valid fields
		data = Progression.reconcile(payload.progress)
		materials = Progression.reconcileMaterials(payload.materials)
		changed:Fire()
	end)
end

return ProgressController
