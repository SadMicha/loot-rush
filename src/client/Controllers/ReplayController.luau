--!strict
-- "Play again" card after a Rift run ends (audit #10, docs/CRITERIA-AUDIT.md): death, "Leave" or
-- "Back to Hub" bring the player to the Hub, and the way back used to be Atlas → region → tier →
-- depth → Travel. Once the player stands in the Hub again, a small card offers one tap back into the
-- same region at its resume depth (Net.Rift "enter" without a depth: the server picks the first
-- depth not cleared yet on the selected World Tier). "Atlas" opens the full picker instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)

local ReplayController = {}

local player = Players.LocalPlayer
local C = Theme.Color

local CARD_W, BTN_H = 330, 40
local WAIT_HUB = 20 -- seconds to wait for the Hub respawn before giving up on the card
local SHOW_TIME = 25 -- the card hides by itself after this long

local card: Frame
local title: TextLabel
local playLabel: TextLabel
local region: string? = nil
local shownAt = 0

local function inRift(): boolean
	return (player:GetAttribute("RiftPhase") or "") ~= ""
end

local function alive(): boolean
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Depth the next run of the region starts at (server attribute, falls back to the region start)
local function resumeDepth(r: Atlas.Region): number
	local v = player:GetAttribute(Atlas.startAttr(r.id))
	return if typeof(v) == "number" then math.max(r.depth, v) else r.depth
end

local function hide()
	card.Visible = false
	region = nil
end

local function show(summary: { [string]: any })
	local r = Atlas.ById[summary.region]
	if not r then
		return
	end
	local depth = tonumber(summary.depth) or r.depth
	title.Text = if summary.reason == "failed"
		then string.format("%s - Defeated at Depth %d", r.name, depth)
		else string.format("%s - Run over at Depth %d", r.name, depth)
	playLabel.Text = string.format("Play again - D%d", resumeDepth(r))
	region = r.id
	local stamp = os.clock()
	shownAt = stamp
	if not card.Visible then
		Flat.pop(card)
	end
	card.Visible = true
	task.delay(SHOW_TIME, function()
		if shownAt == stamp then
			hide()
		end
	end)
end

-- After the run ends: wait until the player stands in the Hub again (death respawns first)
local function offer(summary: { [string]: any })
	local stamp = os.clock()
	shownAt = stamp
	task.spawn(function()
		local deadline = os.clock() + WAIT_HUB
		while os.clock() < deadline do
			if shownAt ~= stamp then
				return -- a newer run ended in the meantime
			end
			if not inRift() and alive() then
				task.wait(0.6) -- let the Hub spawn settle (camera, fade)
				if shownAt == stamp and not inRift() then
					show(summary)
				end
				return
			end
			task.wait(0.25)
		end
	end)
end

local function build(root: Frame)
	card = Flat.card(UDim2.fromOffset(CARD_W, 0), nil, C.Gold)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Name = "PlayAgain"
	-- Same spot as the "Depth cleared" card: top center, clear of the hero and the skills
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 84)
	card.Visible = false
	Shape.brackets(card, C.GoldHi, 8, 0)

	local body = Flat.frame(UDim2.fromScale(1, 0))
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Name = "Body"
	body.ZIndex = 2
	Kit.padding(body, 12)
	local list = Kit.list(body, Enum.FillDirection.Vertical, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	body.Parent = card

	title = Flat.text("", 14, C.GoldHi, Theme.Font.Title, Enum.TextXAlignment.Center)
	title.LayoutOrder = 1
	title.Parent = body

	local row = Flat.frame(UDim2.fromOffset(CARD_W - 24, BTN_H))
	row.LayoutOrder = 2
	local rl = Kit.list(row, Enum.FillDirection.Horizontal, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local playW = math.floor((CARD_W - 24 - 8) * 0.62)
	local play
	play, playLabel = Flat.button("Play again", "primary", Vector2.new(playW, BTN_H), "portal")
	play.Name = "PlayAgain"
	play.LayoutOrder = 1
	play.Activated:Connect(function()
		local id = region
		hide()
		if id and not inRift() then
			Net.Rift:FireServer("enter", id)
		end
	end)
	play.Parent = row
	local atlas = Flat.button("Atlas", "secondary", Vector2.new(CARD_W - 24 - 8 - playW, BTN_H))
	atlas.Name = "Atlas"
	atlas.LayoutOrder = 2
	atlas.Activated:Connect(function()
		hide()
		-- Required lazily: AtlasController requires RiftController, keep this module light
		local AtlasController = require(script.Parent.AtlasController) :: any
		AtlasController.toggle()
	end)
	atlas.Parent = row
	row.Parent = body
	card.Parent = root
end

function ReplayController.init()
	local gui, root = Kit.scaledGui("LootRushReplay", 3, false, Kit.hudDesign, true)
	build(root)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function ReplayController.start()
	Net.RiftResult.OnClientEvent:Connect(function(summary: any)
		if typeof(summary) == "table" and summary.kind == "end" then
			offer(summary)
		end
	end)
	player:GetAttributeChangedSignal("RiftPhase"):Connect(function()
		if inRift() and card.Visible then
			hide() -- entered a Rift some other way
		end
	end)
end

return ReplayController
