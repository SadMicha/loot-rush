--!strict
-- Schnappschuss von Skill-Stufen, Skill-Blüten, Sternennetz und Material (Net.Progress).
-- Die Fenster lesen nur hier und schicken Wünsche an den Server; geprüft wird dort (Systems/Progress).

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
		-- Gleiche Säuberung wie beim Laden: das UI verlässt sich auf gültige Felder
		data = Progression.reconcile(payload.progress)
		materials = Progression.reconcileMaterials(payload.materials)
		changed:Fire()
	end)
end

return ProgressController
