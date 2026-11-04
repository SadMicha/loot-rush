--!strict
-- Interaction prompts in the Gilded Ink look. The hub stations' ProximityPrompts use the Custom
-- style (Systems/Hub), so Roblox draws nothing; this controller shows the prompt as a graphite
-- card with gold corner brackets at the bottom center of the screen, just above the hub icon bar:
--   [ E ]  RIFT GATE
--          OPEN ATLAS
-- Screen space instead of a billboard in the world: on phones the world prompt ran into the HUD
-- icon row and the quest card. Keyboard and gamepad keep Roblox's own input handling; on touch the
-- whole card is the button (InputHoldBegin / InputHoldEnd). Hold prompts fill a gold line.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)

local PromptController = {}

local player = Players.LocalPlayer
local C = Theme.Color
local P = Theme.Prompt
local H = Theme.Hud

local gui: ScreenGui
local root: Frame
local card: CanvasGroup
local hit: TextButton
local keyText: TextLabel
local objectText: TextLabel
local actionText: TextLabel
local holdFill: Frame
local shown: { ProximityPrompt } = {} -- prompts in range, newest last
local inputOf: { [ProximityPrompt]: Enum.ProximityPromptInputType } = {}
local current: ProximityPrompt? = nil
local holdTween: Tween? = nil
local visible = false

-- Text on the key cap for the input the prompt is shown for
local function keyLabel(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType): string
	if input == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif input == Enum.ProximityPromptInputType.Gamepad then
		local name = prompt.GamepadKeyCode.Name
		return (string.gsub(name, "^Button", ""))
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name <= 3 then string.upper(name) else name
end

local function stopHold()
	if holdTween then
		holdTween:Cancel()
		holdTween = nil
	end
	holdFill.Size = UDim2.new(0, 0, 0, P.Bar)
end

local function fill(prompt: ProximityPrompt)
	local input = inputOf[prompt] or Enum.ProximityPromptInputType.Keyboard
	local key = keyLabel(prompt, input)
	keyText.Text = key
	keyText.TextSize = if key == "TAP" then P.TapSize else P.KeySize
	objectText.Text = string.upper(prompt.ObjectText)
	objectText.Visible = prompt.ObjectText ~= ""
	actionText.Text = string.upper(prompt.ActionText)
	stopHold()
end

local function setVisible(on: boolean)
	if on == visible then
		return
	end
	visible = on
	hit.Active = on
	hit.Visible = on
	local info = TweenInfo.new(
		if on then P.FadeIn else P.FadeOut,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	if on then
		card.GroupTransparency = 1
		card.Position = UDim2.new(0.5, 0, 1, P.Rise)
		card.Visible = true
	end
	-- The card's own UIStroke is drawn outside the CanvasGroup, so GroupTransparency never fades
	-- it: fade it by hand and hide the whole card once the fade-out is done
	local edge = card:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		TweenService:Create(edge, info, { Transparency = if on then 0 else 1 }):Play()
	end
	local tween = TweenService:Create(card, info, {
		GroupTransparency = if on then 0 else 1,
		Position = UDim2.new(0.5, 0, 1, if on then 0 else P.Rise),
	})
	if not on then
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and not visible then
				card.Visible = false
			end
		end)
	end
	tween:Play()
end

-- The newest prompt in range, hidden while a window is open
local function refresh()
	local top: ProximityPrompt? = shown[#shown]
	if top ~= current then
		current = top
		if top then
			fill(top)
		end
	end
	setVisible(#shown > 0 and Window.openName() == nil)
end

-- Keeps the card above the hub icon bar (or the bottom edge when the bar is away)
local function place()
	local s = root:FindFirstChildOfClass("UIScale")
	local scale = if s then s.Scale else 1
	local barTop = Kit.bottomCenterTop()
	local area = Kit.guiArea(gui)
	local originY = gui.AbsolutePosition.Y
	local bottom = if barTop
		then (barTop - originY) / scale - P.Above
		else area.Y / scale - H.Margin
	local holder = card.Parent :: Frame
	holder.Position = UDim2.new(0.5, 0, 0, bottom)
end

local function build()
	local g, r = Kit.scaledGui("LootRushPrompt", 2, false, Kit.hudDesign, true)
	gui, root = g, r

	-- Holder: its bottom center is the card's rest point; the card slides inside it
	local holder = Instance.new("Frame")
	holder.Name = "Prompt"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Size = UDim2.fromOffset(P.MinWidth, P.Height)
	holder.Parent = root

	card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, P.Rise)
	card.Size = UDim2.fromScale(1, 1)
	card.GroupTransparency = 1
	card.Visible = false
	Shape.card(card, nil, C.Gold:Lerp(Theme.Flat.Edge, 0.55))
	Shape.brackets(card)
	local edge = card:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Transparency = 1
	end
	card.Parent = holder

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 2
	row.Parent = card
	local list = Kit.list(row, Enum.FillDirection.Horizontal, P.Gap)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, P.Pad)
	pad.PaddingRight = UDim.new(0, P.Pad + Theme.Space.S)
	pad.Parent = row

	-- Key cap: gold gradient square with the key
	local cap = Instance.new("Frame")
	cap.Name = "Key"
	cap.LayoutOrder = 1
	cap.Size = UDim2.fromOffset(P.Key, P.Key)
	cap.BackgroundColor3 = Color3.new(1, 1, 1)
	cap.BorderSizePixel = 0
	Shape.corner(cap, Theme.Flat.Radius.M)
	Shape.gradient(cap, C.GoldHi, C.GoldLo)
	Shape.stroke(cap, C.GoldHi, 1)
	cap.Parent = row
	keyText = Kit.label("E", P.KeySize, Theme.Flat.Surface0, Theme.Font.Title)
	keyText.AutomaticSize = Enum.AutomaticSize.None
	keyText.Size = UDim2.fromScale(1, 1)
	keyText.TextXAlignment = Enum.TextXAlignment.Center
	keyText.TextYAlignment = Enum.TextYAlignment.Center
	keyText.Parent = cap

	-- Object (small, muted caps) over the action (title font)
	local texts = Instance.new("Frame")
	texts.Name = "Texts"
	texts.LayoutOrder = 2
	texts.BackgroundTransparency = 1
	texts.Size = UDim2.fromOffset(0, P.Height)
	texts.AutomaticSize = Enum.AutomaticSize.X
	texts.Parent = row
	local tl = Kit.list(texts, Enum.FillDirection.Vertical, 0)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	objectText = Kit.label("", P.ObjectSize, C.Muted, Theme.Font.UI)
	objectText.LayoutOrder = 1
	objectText.Parent = texts
	actionText = Kit.label("", P.ActionSize, C.Text, Theme.Font.Title)
	actionText.LayoutOrder = 2
	actionText.Parent = texts
	-- The card is as wide as its texts (no AutomaticSize on the card: its scale-sized sheen and
	-- brackets would feed back into the size)
	texts:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local s = root:FindFirstChildOfClass("UIScale")
		local scale = if s then s.Scale else 1
		local textW = texts.AbsoluteSize.X / math.max(scale, 0.01)
		local w =
			math.max(P.MinWidth, math.ceil(P.Pad + P.Key + P.Gap + textW + P.Pad + Theme.Space.S))
		holder.Size = UDim2.fromOffset(w, P.Height)
	end)

	-- Hold progress along the bottom edge
	holdFill = Instance.new("Frame")
	holdFill.Name = "Hold"
	holdFill.AnchorPoint = Vector2.new(0, 1)
	holdFill.Position = UDim2.fromScale(0, 1)
	holdFill.Size = UDim2.new(0, 0, 0, P.Bar)
	holdFill.BackgroundColor3 = C.Gold
	holdFill.BorderSizePixel = 0
	holdFill.ZIndex = 3
	holdFill.Parent = card

	-- Touch: the whole card is the button (keyboard / gamepad keep Roblox's own handling)
	hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 5
	hit.Visible = false
	hit.Active = false
	hit.Parent = holder
	local holding: ProximityPrompt? = nil
	hit.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if
			current
			and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1)
			and input.UserInputState == Enum.UserInputState.Begin
		then
			holding = current
			Shape.ripple(card)
			current:InputHoldBegin()
		end
	end)
	hit.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if holding and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
			local p = holding
			holding = nil
			p:InputHoldEnd()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function PromptController.init()
	build()

	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType)
			if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
				return
			end
			inputOf[prompt] = input
			local i = table.find(shown, prompt)
			if i then
				table.remove(shown, i)
			end
			table.insert(shown, prompt)
			if prompt == current then
				fill(prompt) -- input type may have changed
			end
			refresh()
		end
	)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		local i = table.find(shown, prompt)
		if i then
			table.remove(shown, i)
		end
		inputOf[prompt] = nil
		refresh()
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		if prompt ~= current or prompt.HoldDuration <= 0 then
			return
		end
		stopHold()
		local t = TweenService:Create(
			holdFill,
			TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(1, 0, 0, P.Bar) }
		)
		holdTween = t
		t:Play()
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		if prompt == current then
			stopHold()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt == current then
			stopHold()
		end
	end)
end

function PromptController.start()
	-- Cheap per-frame work only while a prompt is up: follow the hub bar, step back for windows
	RunService.Heartbeat:Connect(function()
		if #shown == 0 and not visible then
			return
		end
		place()
		refresh()
	end)
end

return PromptController
