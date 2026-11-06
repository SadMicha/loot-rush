--!strict
-- Settings window (the gear on the HUD): sound on the left, gameplay and display on the right,
-- About and the Roblox menu at the bottom. Values live in Client/Prefs (applied live, saved per
-- account on the server, Systems/Settings); this module only builds the window and applies the
-- settings that belong to no other controller (HUD scale).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Settings)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Prefs = require(script.Parent.Parent.Prefs)
local Controls = require(script.Parent.Parent.UI.Controls)
local Flat = require(script.Parent.Parent.UI.Flat)
local Kit = require(script.Parent.Parent.UI.Kit)
local Shape = require(script.Parent.Parent.UI.Shape)
local Window = require(script.Parent.Parent.UI.Window)
local ChangelogController = require(script.Parent.ChangelogController)
local CharacterController = require(script.Parent.CharacterController)

local SettingsController = {}

local C = Theme.Color
local F = Theme.Flat

local GAP = 24
local PAD = 28
local FOOT_H = 96 -- About strip at the bottom
local FOOT_BUTTONS_W = 760 -- Switch Hero, Defaults, Roblox Menu
local ROW_H = 80
local LABEL_W = 250
-- Smallest phones (see Theme.SmallPhoneMaxSide): grown touch targets and text no longer fit the
-- two-column rows, so labels stack above their controls, hints are dropped and cards scroll
local SMALL_FOOT_H = 168
local SMALL_ROW_H = 96
local SMALL_BAR_W = 10 -- scroll bar room at the right of a card's rows

-- Sliders (volume channels): key, caption
local VOLUME_ROWS: { { string } } = {
	{ "master", "Master volume" },
	{ "music", "Music" },
	{ "sfx", "Combat sounds" },
	{ "ambience", "Ambience" },
	{ "ui", "Interface sounds" },
}

local win: Window.Window
local setters: { [string]: (value: any) -> () } = {} -- key → refresh the control from Prefs
local small = false -- smallest-phone layout (decided in build)

local function isSmallPhone(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil
		and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < Theme.SmallPhoneMaxSide
end

local function percent(v: number): string
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

-- Card with a gilded heading; returns the card and the vertical list for its rows
local function card(title: string, size: Vector2, pos: UDim2): (Frame, Frame)
	local f = Kit.panel(size)
	f.Name = "Card_" .. string.gsub(title, "%W", "")
	f.Position = pos
	Shape.brackets(f)
	local head = Window.gilded(title, 22)
	head.Position = UDim2.fromOffset(PAD, PAD - 6)
	head.Parent = f
	local rule = Shape.accentRule(180)
	rule.Position = UDim2.fromOffset(PAD, PAD + 34)
	rule.Parent = f
	local rowsSize = if small
		then UDim2.new(0, size.X - 2 * PAD, 1, -(PAD + 56)) -- follows the card height
		else UDim2.fromOffset(size.X - 2 * PAD, size.Y - PAD - 56)
	local rowsPos = UDim2.fromOffset(PAD, PAD + 48)
	local rows: Frame
	if small then
		-- Rows scroll vertically when they do not fit
		local sf = Instance.new("ScrollingFrame")
		sf.BackgroundTransparency = 1
		sf.BorderSizePixel = 0
		sf.Size = rowsSize
		sf.Position = rowsPos
		sf.ScrollingDirection = Enum.ScrollingDirection.Y
		sf.ScrollBarThickness = 6
		sf.ScrollBarImageColor3 = C.Gold
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.CanvasSize = UDim2.new()
		rows = sf :: any
	else
		rows = Flat.frame(rowsSize, rowsPos)
	end
	rows.Name = "Rows"
	Kit.list(rows, Enum.FillDirection.Vertical, 4, Enum.VerticalAlignment.Top)
	rows.Parent = f
	return f, rows
end

-- One row: caption (and optional hint below it) on the left, control on the right
-- The texts end before the control (truncated, never under it). Phones grow touch controls and text
-- to their minimum sizes, so the text width follows the control's real width.
local function row(
	parent: Frame,
	order: number,
	caption: string,
	hint: string?,
	control: GuiObject,
	stack: boolean?
)
	local width = parent.Size.X.Offset - (if small then SMALL_BAR_W else 0)
	if small then
		hint = nil
	end
	if stack then
		-- Smallest phones: caption on its own line, the control below it
		local sr = Flat.frame(UDim2.fromOffset(width, 0))
		sr.Name = "Row_" .. order
		sr.LayoutOrder = order
		sr.AutomaticSize = Enum.AutomaticSize.Y
		local sl = Kit.list(sr, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Top)
		sl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = sr
		if order > 1 then
			local line = Flat.rule(width, F.Edge)
			line.BackgroundTransparency = 0.5
			line.LayoutOrder = 0
			line.Parent = sr
		end
		local st = Flat.text(caption, 17, C.Text, Theme.Font.UI)
		st.AutomaticSize = Enum.AutomaticSize.Y
		st.Size = UDim2.fromOffset(width, 0)
		st.TextTruncate = Enum.TextTruncate.AtEnd
		st.LayoutOrder = 1
		st.Parent = sr
		-- The holder is as tall as the (touch-grown) control, which keeps its own design height
		local holder = Flat.frame(UDim2.fromOffset(width, Controls.HEIGHT))
		holder.Name = "Control"
		holder.LayoutOrder = 2
		control.AnchorPoint = Vector2.new(1, 0.5)
		control.Position = UDim2.fromScale(1, 0.5)
		control.Parent = holder
		holder.Parent = sr
		local function fitHolder()
			local ratio = sr.AbsoluteSize.X / width -- screen px per design px
			if ratio > 0 then
				holder.Size = UDim2.fromOffset(
					width,
					math.max(Controls.HEIGHT, math.ceil(Kit.MIN_TOUCH_PX / ratio))
				)
			end
		end
		sr:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHolder)
		fitHolder()
		sr.Parent = parent
		return
	end
	local r = Flat.frame(UDim2.fromOffset(width, if small then SMALL_ROW_H else ROW_H))
	r.Name = "Row_" .. order
	r.LayoutOrder = order
	local texts: { TextLabel } = {}
	local function fit(t: TextLabel)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.TextTruncate = Enum.TextTruncate.AtEnd
		table.insert(texts, t)
	end
	local text = Flat.text(caption, 17, C.Text, Theme.Font.UI)
	fit(text)
	text.AnchorPoint = Vector2.new(0, if hint then 1 else 0.5)
	text.Position = UDim2.new(0, 0, 0.5, if hint then 2 else 0)
	text.Parent = r
	if hint then
		local h = Flat.text(hint, 13, C.Muted, Theme.Font.Body)
		fit(h)
		h.AnchorPoint = Vector2.new(0, 0)
		h.Position = UDim2.new(0, 0, 0.5, 4)
		h.Parent = r
	end
	local function sync()
		local rw = r.AbsoluteSize.X
		local cw = control.AbsoluteSize.X
		local controlW = if rw > 0 and cw > 0
			then cw * width / rw -- screen px → design px of this row
			else control.Size.X.Offset
		local textW = math.max(80, width - controlW - 16)
		for _, t in texts do
			t.Size = UDim2.fromOffset(textW, 0)
		end
	end
	control:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	r:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	control.AnchorPoint = Vector2.new(1, 0.5)
	control.Position = UDim2.fromScale(1, 0.5)
	control.Parent = r
	sync()
	if order > 1 then
		local line = Flat.rule(width, F.Edge)
		line.BackgroundTransparency = 0.5
		line.Parent = r
	end
	r.Parent = parent
end

local function sliderRow(parent: Frame, order: number, key: string, caption: string)
	local def = Settings.Defs[key]
	local width = if small
		then parent.Size.X.Offset - SMALL_BAR_W
		else parent.Size.X.Offset - LABEL_W
	local s = Controls.slider(width, def.step or 0.05, percent, function(v: number)
		Prefs.preview(key, v)
	end, function(v: number)
		Prefs.set(key, v)
	end)
	setters[key] = function(v: any)
		s.set(v)
	end
	row(parent, order, caption, nil, s.frame, small)
end

local function switchRow(parent: Frame, order: number, key: string, caption: string, hint: string?)
	local sw = Controls.switch(function(on: boolean)
		Prefs.set(key, on)
	end)
	setters[key] = function(v: any)
		sw.set(v == true)
	end
	row(parent, order, caption, hint, sw.frame)
end

local function choiceRow(
	parent: Frame,
	order: number,
	key: string,
	caption: string,
	hint: string?,
	options: { { id: string, text: string, value: any } },
	segment: number
)
	local list = {}
	local byId: { [string]: any } = {}
	for _, o in options do
		table.insert(list, { id = o.id, text = o.text })
		byId[o.id] = o.value
	end
	if small then
		-- Equal buttons across the whole row
		local gaps = 6 * (#options - 1)
		segment = math.floor((parent.Size.X.Offset - SMALL_BAR_W - gaps) / #options)
	end
	local ch = Controls.choice(list, segment, function(id: string)
		Prefs.set(key, byId[id])
	end)
	setters[key] = function(v: any)
		for _, o in options do
			if o.value == v then
				ch.set(o.id)
				return
			end
		end
		ch.set("")
	end
	row(parent, order, caption, hint, ch.frame, small)
end

-- Sync every control with the current values (on open and after the save arrived)
local function refresh()
	for key, fn in setters do
		fn(Prefs.get(key))
	end
end

local function build()
	small = isSmallPhone()
	local body = Window.BODY
	local footH = if small then SMALL_FOOT_H else FOOT_H -- small: first guess, measured below
	local cardH = body.Y - footH - GAP
	local cardW = (body.X - GAP) / 2

	-- Sound
	local soundCard, sound = card("Sound", Vector2.new(cardW, cardH), UDim2.fromOffset(0, 0))
	soundCard.Parent = win.body
	switchRow(sound, 1, "muted", "Mute all", "Silences music and sounds")
	for i, spec in VOLUME_ROWS do
		sliderRow(sound, i + 1, spec[1], spec[2])
	end

	-- Gameplay & display
	local playCard, play =
		card("Gameplay & Display", Vector2.new(cardW, cardH), UDim2.fromOffset(cardW + GAP, 0))
	playCard.Parent = win.body
	choiceRow(play, 1, "shake", "Camera shake", "Hits and kills shake the view", {
		{ id = "off", text = "Off", value = 0 },
		{ id = "half", text = "Low", value = 0.5 },
		{ id = "full", text = "Full", value = 1 },
	}, 96)
	switchRow(play, 2, "damageNumbers", "Damage numbers", "Numbers over hit enemies")
	choiceRow(play, 3, "quality", "Effects quality", "Bricks and minimap detail", {
		{ id = "auto", text = "Auto", value = "auto" },
		{ id = "low", text = "Low", value = "low" },
		{ id = "medium", text = "Med", value = "medium" },
		{ id = "high", text = "High", value = "high" },
	}, 86)
	switchRow(play, 4, "minimap", "Minimap", nil)
	choiceRow(play, 5, "hudScale", "HUD size", "Scales the HUD", {
		{ id = "s80", text = "XS", value = 0.8 },
		{ id = "s90", text = "S", value = 0.9 },
		{ id = "s100", text = "M", value = 1 },
		{ id = "s110", text = "L", value = 1.1 },
		{ id = "s120", text = "XL", value = 1.2 },
	}, 70)
	local camDef = Settings.Defs.camera
	local camMin, camMax = camDef.min or 0.5, camDef.max or 2
	local camRange = camMax - camMin
	local cam = Controls.slider(
		if small then play.Size.X.Offset - SMALL_BAR_W else play.Size.X.Offset - LABEL_W - 60,
		(camDef.step or 0.1) / camRange,
		function(v: number)
			return string.format("%.1fx", camMin + v * camRange)
		end,
		function(v: number)
			Prefs.preview("camera", camMin + v * camRange)
		end,
		function(v: number)
			Prefs.set("camera", camMin + v * camRange)
		end
	)
	setters.camera = function(v: any)
		cam.set(((v :: number) - camMin) / camRange)
	end
	row(play, 6, "Camera speed", "Mouse or finger turning", cam.frame, small)
	switchRow(play, 7, "hideHelmet", "Hide helmet", "Show hair and hats instead")

	-- About + Roblox menu
	local foot = Kit.panel(Vector2.new(body.X, footH))
	-- Smallest phones: the footer content sets its own height (text and buttons grow with the screen
	-- scale), the cards take the rest
	local inner = Flat.frame(UDim2.fromOffset(body.X, 0))
	inner.Name = "Content"
	inner.AutomaticSize = Enum.AutomaticSize.Y
	if small then
		local il2 = Kit.list(inner, Enum.FillDirection.Vertical, 8, Enum.VerticalAlignment.Top)
		il2.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local ip = Instance.new("UIPadding")
		ip.PaddingTop = UDim.new(0, 12)
		ip.PaddingBottom = UDim.new(0, 12)
		ip.Parent = inner
		inner.Parent = foot
		local function relayout()
			local ax = inner.AbsoluteSize.X
			if ax <= 0 then
				return
			end
			local h = math.ceil(inner.AbsoluteSize.Y * body.X / ax)
			foot.Size = UDim2.fromOffset(body.X, h)
			foot.Position = UDim2.fromOffset(0, body.Y - h)
			local ch = body.Y - h - GAP
			soundCard.Size = UDim2.fromOffset(cardW, ch)
			playCard.Size = UDim2.fromOffset(cardW, ch)
		end
		inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		task.defer(relayout)
	end
	foot.Name = "About"
	foot.Position = UDim2.fromOffset(0, body.Y - footH)
	-- Smallest phones: the version line gets the full width on its own, the buttons (What's New
	-- included) sit in a row below it
	local info = if small
		then Flat.frame(UDim2.fromOffset(body.X - 2 * PAD, 0))
		else Flat.frame(
			UDim2.fromOffset(body.X - FOOT_BUTTONS_W - 40, FOOT_H),
			UDim2.fromOffset(PAD, 0)
		)
	local il = Kit.list(info, Enum.FillDirection.Vertical, 4)
	il.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local buildNo = if game.PlaceVersion > 0 then ` - Build {game.PlaceVersion}` else ""
	local top = Flat.frame(UDim2.fromOffset(0, if small then 0 else 44))
	top.Name = "Version"
	top.AutomaticSize = if small then Enum.AutomaticSize.XY else Enum.AutomaticSize.X
	top.LayoutOrder = 1
	local tl = Kit.list(top, Enum.FillDirection.Horizontal, 12)
	tl.VerticalAlignment = Enum.VerticalAlignment.Center
	local title = Flat.text(`Loot Rush {Settings.GAME_VERSION}{buildNo}`, 16, C.Text, Theme.Font.UI)
	title.LayoutOrder = 1
	title.Parent = top
	-- Release notes (Shared/Changelog) any time
	-- Smallest phones: four equal buttons across the footer (wrapping if the text ever outgrows them)
	local btnW = (body.X - 2 * PAD - 3 * 12) / 4
	local news = Flat.button(
		"What's New",
		"ghost",
		if small then Vector2.new(btnW, 56) else Vector2.new(160, 40)
	)
	news.Name = "WhatsNew"
	news.LayoutOrder = 2
	news.Activated:Connect(function()
		win.close()
		ChangelogController.open()
	end)
	if not small then
		news.Parent = top
	end
	top.Parent = info
	if small then
		info.AutomaticSize = Enum.AutomaticSize.Y
		info.LayoutOrder = 1
	end
	info.Parent = if small then inner else foot

	local buttons = if small
		then Flat.frame(UDim2.fromOffset(body.X - 2 * PAD, 0))
		else Flat.frame(UDim2.fromOffset(FOOT_BUTTONS_W, FOOT_H))
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(1, 0)
	if not small then
		buttons.Position = UDim2.new(1, -PAD, 0, 0)
	end
	local bl = Kit.list(buttons, Enum.FillDirection.Horizontal, 12)
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	if small then
		buttons.AutomaticSize = Enum.AutomaticSize.Y
		buttons.LayoutOrder = 2
		bl.Wraps = true
		bl.VerticalAlignment = Enum.VerticalAlignment.Top
		bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	-- Heroes: switch to another hero or create a new one (the class belongs to the hero)
	local heroes =
		Flat.button("Switch Hero", "primary", Vector2.new(if small then btnW else 240, 56), "crown")
	heroes.Name = "SwitchHero"
	heroes.LayoutOrder = 0
	heroes.Activated:Connect(function()
		win.close()
		CharacterController.open()
	end)
	heroes.Parent = buttons
	local reset = Flat.button("Defaults", "ghost", Vector2.new(if small then btnW else 190, 56))
	reset.Name = "Reset"
	reset.LayoutOrder = 1
	reset.Activated:Connect(function()
		Prefs.reset()
		refresh()
	end)
	reset.Parent = buttons
	local roblox = Flat.button(
		"Roblox Menu",
		"secondary",
		Vector2.new(if small then btnW else 250, 56),
		"settings"
	)
	roblox.Name = "RobloxMenu"
	roblox.LayoutOrder = 2
	roblox.Activated:Connect(function()
		win.close()
		pcall(function()
			GuiService:SetMenuIsOpen(true)
		end)
	end)
	roblox.Parent = buttons
	if small then
		news.LayoutOrder = 3
		news.Parent = buttons
	end
	buttons.Parent = if small then inner else foot
	foot.Parent = win.body
end

function SettingsController.toggle()
	win.toggle()
end

function SettingsController.open()
	if not win.isOpen() then
		win.toggle()
	end
end

function SettingsController.isOpen(): boolean
	return win.isOpen()
end

function SettingsController.init()
	win = Window.new({ name = "Settings", title = "Settings", icon = "settings" })
	build()
	refresh()
	win.onOpen(refresh)
	Kit.setHudScale(Prefs.get("hudScale"))
	Prefs.changed:Connect(function(key: string, value: any)
		if key == "hudScale" then
			Kit.setHudScale(value)
		end
		if win.isOpen() and setters[key] then
			setters[key](value)
		end
	end)
end

return SettingsController
