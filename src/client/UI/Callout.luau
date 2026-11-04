--!strict
-- Tutorial callout: a card next to the HUD element it explains and a pulsing gold ring around that
-- element (HintsController). It lives on its own layer above the HUD that scales like the HUD
-- (Kit.hudDesign, device safe area), follows its target every frame and hides while the target is
-- hidden (flown out, window open, ScreenGui off). Tapping the card closes it.
--   local c = Callout.new(target, "DODGE", "Red zones are attacks…", true)
--   c.update() -> boolean   place it; false while the target cannot be seen
--   c.tapped() -> boolean   the player tapped the card
--   c.close()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Flat = require(script.Parent.Flat)
local Kit = require(script.Parent.Kit)

local Callout = {}

export type Callout = {
	card: Frame,
	update: () -> boolean,
	tapped: () -> boolean,
	close: () -> (),
}

local C = Theme.Color
local T = Theme.Callout

local layerRoot: Frame? = nil

-- The callout layer (built on first use)
function Callout.layer(): Frame
	local existing = layerRoot
	if existing and existing.Parent then
		return existing
	end
	local gui, root = Kit.scaledGui("LootRushHints", 15, false, Kit.hudDesign, true)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	layerRoot = root
	return root
end

local function scaleOf(root: Frame): number
	local s = root:FindFirstChildOfClass("UIScale")
	return if s and s.Scale > 0 then s.Scale else 1
end

-- Can the player see this element right now? (all ancestors shown, CanvasGroups not faded out,
-- ScreenGui enabled, has a size and lies on the screen)
function Callout.visible(target: GuiObject?): boolean
	if not target or not target.Parent then
		return false
	end
	local node: Instance? = target
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
			if node:IsA("CanvasGroup") and node.GroupTransparency > 0.5 then
				return false
			end
		elseif node:IsA("LayerCollector") then
			if not node.Enabled then
				return false
			end
			break
		end
		node = node.Parent
	end
	if not node then
		return false -- not under a ScreenGui
	end
	local size = target.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return false
	end
	local camera = workspace.CurrentCamera
	if camera then
		local p = target.AbsolutePosition + size / 2
		local v = camera.ViewportSize
		if p.X < 0 or p.Y < 0 or p.X > v.X or p.Y > v.Y then
			return false
		end
	end
	return true
end

function Callout.new(target: GuiObject, title: string, body: string, round: boolean?): Callout
	local root = Callout.layer()
	local touch = UserInputService.TouchEnabled
	local width = if touch then T.WidthTouch else T.Width

	-- Pulse ring around the target
	local ring = Instance.new("Frame")
	ring.Name = "CalloutRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, Theme.Flat.Radius.L * 2)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.GoldHi
	stroke.Thickness = T.RingStroke
	stroke.Parent = ring
	local pulse = Instance.new("UIScale")
	pulse.Parent = ring
	ring.Parent = root
	local info =
		TweenInfo.new(T.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local grow = TweenService:Create(pulse, info, { Scale = T.RingGrow })
	local fade = TweenService:Create(stroke, info, { Transparency = 0.6 })
	grow:Play()
	fade:Play()

	-- Pointer diamond between card and target
	local pointer = Instance.new("Frame")
	pointer.Name = "CalloutPointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(T.Pointer, T.Pointer)
	pointer.Rotation = 45
	pointer.BackgroundColor3 = C.GoldHi
	pointer.BorderSizePixel = 0
	pointer.Visible = false
	pointer.Parent = root

	-- Card: title, text, "Tap to close"
	-- The texts live in their own Body frame: the card's full-size children (Sheen, the close hit
	-- area) must stay out of the list layout, or the auto-sized card grows without end on a device
	-- (it filled the screen from top to bottom at the first boss on an iPad)
	local card = Kit.panel(Vector2.new(width, 0), C.GoldHi)
	card.Name = "Callout"
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Visible = false
	local content = Instance.new("Frame")
	content.Name = "Body"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.fromOffset(width, 0)
	content.ZIndex = 2
	content.Parent = card
	Kit.padding(content, T.Pad)
	local list = Kit.list(content, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Top)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local head = Flat.text(title, T.TitleSize, C.GoldHi, Theme.Font.Title)
	head.Name = "Title"
	head.LayoutOrder = 1
	head.Parent = content
	local text =
		Flat.text(body, if touch then T.BodySizeTouch else T.BodySize, C.Text, Theme.Font.Body)
	text.Name = "Body"
	text.LayoutOrder = 2
	text.TextWrapped = true
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.Size = UDim2.fromOffset(width - 2 * T.Pad, 0)
	text.Parent = content
	local foot = Flat.text(if touch then "Tap to close" else "Click to close", T.FootSize, C.Muted)
	foot.Name = "Foot"
	foot.LayoutOrder = 3
	foot.Parent = content
	card.Parent = root

	local closer = Instance.new("TextButton")
	closer.Name = "Close"
	closer.Text = ""
	closer.BackgroundTransparency = 1
	closer.Size = UDim2.fromScale(1, 1)
	closer.ZIndex = 5
	closer.Parent = card
	local wasTapped = false
	closer.Activated:Connect(function()
		wasTapped = true
	end)

	local popped = false
	local alive = true

	local function show(on: boolean)
		card.Visible = on
		ring.Visible = on
		pointer.Visible = on
	end

	local function update(): boolean
		if not alive then
			return false
		end
		if not Callout.visible(target) then
			show(false)
			return false
		end
		local s = scaleOf(root)
		local origin = root.AbsolutePosition
		local pos = (target.AbsolutePosition - origin) / s
		local size = target.AbsoluteSize / s
		local screen = root.AbsoluteSize / s
		local center = pos + size / 2
		ring.Position = UDim2.fromOffset(center.X, center.Y)
		ring.Size = UDim2.fromOffset(size.X + 2 * T.Ring, size.Y + 2 * T.Ring)

		local w = width
		local h = math.max(card.AbsoluteSize.Y / s, 60)
		local gap = T.Ring + T.Gap
		local x, y, px, py
		if center.Y < screen.Y * 0.35 then -- top of the screen: below the target
			x, y = center.X - w / 2, pos.Y + size.Y + gap
			px, py = center.X, y - T.Pointer / 2
		elseif center.X > screen.X * 0.6 then -- right side (skills, dash): to the left
			x, y = pos.X - gap - w, center.Y - h / 2
			px, py = x + w + T.Pointer / 2, center.Y
		elseif center.X < screen.X * 0.4 then -- left side: to the right
			x, y = pos.X + size.X + gap, center.Y - h / 2
			px, py = x - T.Pointer / 2, center.Y
		else -- bottom centre (hub bar, Rush meter): above
			x, y = center.X - w / 2, pos.Y - gap - h
			px, py = center.X, y + h + T.Pointer / 2
		end
		local m = T.Margin
		x = math.clamp(x, m, math.max(m, screen.X - w - m))
		y = math.clamp(y, m, math.max(m, screen.Y - h - m))
		card.Position = UDim2.fromOffset(x, y)
		pointer.Position = UDim2.fromOffset(px, py)
		show(true)
		if not popped then
			popped = true
			Flat.pop(card)
		end
		return true
	end

	local function close()
		if not alive then
			return
		end
		alive = false
		grow:Cancel()
		fade:Cancel()
		ring:Destroy()
		pointer:Destroy()
		card:Destroy()
	end

	return {
		card = card,
		update = update,
		tapped = function(): boolean
			return wasTapped
		end,
		close = close,
	}
end

return Callout
