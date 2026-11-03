--!strict
-- One-time contextual hints (docs/ROADMAP-1.0.md O4), shown as a toast (QuestController.toast)
-- the first time something happens, then never again on this account:
--   hintSkills  first enemy within Config.HINT_SKILL_RANGE in a Rift  → how to use skills
--   hintDodge   first enemy telegraph within Config.HINT_TELEGRAPH_RANGE → dash out of red zones
--   hintRush    first Stud Rush (attribute Rushing)                     → what the Rush is
-- "Seen" is a hidden account setting (Shared/Settings, saved through Client/Prefs); the Defaults
-- button in the settings window clears them. Nothing shows before the saved settings arrived.
-- Texts follow the input: touch buttons on phones, keys on PC.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Prefs = require(script.Parent.Parent.Prefs)
local QuestController = require(script.Parent.QuestController)

local HintsController = {}

local TICK = 0.5

local player = Players.LocalPlayer

local TEXTS = {
	hintSkills = {
		touch = "Tap a skill button to attack!",
		keys = "Press Q, E, R or F to use your skills!",
	},
	hintDodge = {
		touch = "Red zone! Tap the dash button to dodge.",
		keys = "Red zone! Press Space to dash out.",
	},
	hintRush = {
		touch = "Stud Rush! Kills fill the meter, a full meter makes you faster and stronger.",
		keys = "Stud Rush! Kills fill the meter, a full meter makes you faster and stronger.",
	},
}

-- Shows a hint once (true = shown now)
function HintsController.show(key: string): boolean
	local text = TEXTS[key]
	if not text or not Prefs.loaded() or Prefs.get(key) ~= false then
		return false
	end
	Prefs.set(key, true)
	QuestController.toast(
		if UserInputService.TouchEnabled then text.touch else text.keys,
		Theme.Color.GoldHi
	)
	return true
end

local function root(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function near(pos: Vector3, range: number): boolean
	local r = root()
	return r ~= nil and (pos - r.Position).Magnitude <= range
end

local function checkEnemies()
	if Prefs.get("hintSkills") ~= false or player:GetAttribute("RiftRegion") == nil then
		return
	end
	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy:IsA("Model") and near(enemy:GetPivot().Position, Config.HINT_SKILL_RANGE) then
			HintsController.show("hintSkills")
			return
		end
	end
end

-- Enemy telegraphs are flat parts directly in workspace.Enemies (Systems/Enemies)
local function watchTelegraphs(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		if
			child:IsA("BasePart")
			and Prefs.get("hintDodge") == false
			and near(child.Position, Config.HINT_TELEGRAPH_RANGE)
		then
			HintsController.show("hintDodge")
		end
	end)
end

function HintsController.start()
	player:GetAttributeChangedSignal("Rushing"):Connect(function()
		if player:GetAttribute("Rushing") == true then
			HintsController.show("hintRush")
		end
	end)
	task.spawn(function()
		local folder = workspace:WaitForChild("Enemies", math.huge)
		if folder then
			watchTelegraphs(folder)
		end
	end)
	task.spawn(function()
		while true do
			checkEnemies()
			task.wait(TICK)
		end
	end)
end

return HintsController
