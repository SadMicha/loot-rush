--!strict
-- Vereinfachter Nachbau von Roblox' GUI-Layout: UDim2, AnchorPoint, UIScale, UIPadding,
-- UIListLayout, UIGridLayout, UIAspectRatioConstraint, UISizeConstraint, AutomaticSize,
-- ScrollingFrame. Rechnet auf echten Lune-Instanzen (nicht auf Sandbox-Proxys).
-- Ergebnis je Objekt: absolutes Rechteck in Bildschirm-Pixeln wie AbsolutePosition/AbsoluteSize.

local roblox = require("@lune/roblox")
local Enum = roblox.Enum :: any
local UDim = roblox.UDim
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

export type Rect = { x: number, y: number, w: number, h: number, s: number }

local Layout = {}
Layout.__index = Layout

export type Layout = typeof(setmetatable(
	{} :: { viewport: Vector2, inset: number, cache: { [string]: Rect | false } },
	Layout
))

function Layout.new(viewport: Vector2, inset: number?): Layout
	return setmetatable({ viewport = viewport, inset = inset or 58, cache = {} }, Layout)
end

local function get(inst: any, prop: string, default: any?): any
	local ok, v = pcall(function()
		return inst[prop]
	end)
	if ok and v ~= nil then
		return v
	end
	return default
end
Layout.get = get

local function id(inst: any): string
	return inst:GetDebugId()
end

function Layout.invalidate(self: Layout)
	self.cache = {}
end

-- Textbreite grob schätzen (keine echten Fontmetriken verfügbar). Absichtlich eher großzügig.
local WIDE = "[MWmw@%%]"
local NARROW = "[iljI!%.,:;'|%(%)%[%]]"
function Layout.textWidth(text: string, size: number, bold: boolean?): number
	local plain = text:gsub("<[^>]->", "")
	local w = 0
	for _, cp in utf8.codes(plain) do
		local ch = utf8.char(cp)
		if ch == " " then
			w += 0.28
		elseif ch:match(WIDE) then
			w += 0.82
		elseif ch:match(NARROW) then
			w += 0.3
		elseif ch:match("%u") then
			w += 0.64
		elseif ch:match("%d") then
			w += 0.56
		else
			w += 0.52
		end
	end
	return w * size * (if bold then 1.06 else 1)
end

function Layout.isBold(inst: any): boolean
	local face = get(inst, "FontFace")
	if face then
		local ok, weight = pcall(function()
			return face.Weight
		end)
		if ok and weight and weight.Value >= 600 then
			return true
		end
		local family = tostring(get(face, "Family", ""))
		if family:find("Fredoka") or family:find("Luckiest") or family:find("Bangers") then
			return true
		end
	end
	local font = get(inst, "Font")
	return font ~= nil and tostring(font):find("Bold") ~= nil
end

-- Benötigte Fläche eines Textes: Breite der längsten Zeile, Zeilen × Zeilenhöhe
function Layout.textBounds(text: string, size: number, bold: boolean, wrapWidth: number?): Vector2
	local lineH = size
	local lines, maxW = 0, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local w = Layout.textWidth(line, size, bold)
		if wrapWidth and wrapWidth > 0 and w > wrapWidth then
			lines += math.ceil(w / wrapWidth)
			maxW = math.max(maxW, wrapWidth)
		else
			lines += 1
			maxW = math.max(maxW, w)
		end
	end
	return Vector2.new(maxW, lines * lineH)
end

local function children(inst: any, class: string): { any }
	local out = {}
	for _, c in inst:GetChildren() do
		if c:IsA(class) then
			table.insert(out, c)
		end
	end
	return out
end

local function firstChild(inst: any, class: string): any?
	for _, c in inst:GetChildren() do
		if c:IsA(class) then
			return c
		end
	end
	return nil
end

-- Größe eines Objekts relativ zu einem Elternrechteck (vor Layout-Positionierung)
function Layout.sizeIn(
	self: Layout,
	inst: any,
	pw: number,
	ph: number,
	s: number
): (number, number, number)
	local size: UDim2 = get(inst, "Size", UDim2.new())
	local w = pw * size.X.Scale + size.X.Offset * s
	local h = ph * size.Y.Scale + size.Y.Offset * s

	local sizeConstraint = get(inst, "SizeConstraint")
	if sizeConstraint == Enum.SizeConstraint.RelativeXX then
		h = pw * size.Y.Scale + size.Y.Offset * s
	elseif sizeConstraint == Enum.SizeConstraint.RelativeYY then
		w = ph * size.X.Scale + size.X.Offset * s
	end

	local auto = get(inst, "AutomaticSize", Enum.AutomaticSize.None)
	if auto ~= Enum.AutomaticSize.None then
		-- Nur Y wächst: umbrochener Text bricht an der festen Breite um
		local wrapW = if auto == Enum.AutomaticSize.Y then w else nil
		local cw, ch = self:contentExtent(inst, s, wrapW)
		if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
			w = math.max(w, cw)
		end
		if auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY then
			h = math.max(h, ch)
		end
	end

	local limit = firstChild(inst, "UISizeConstraint")
	if limit then
		local mn: Vector2 = get(limit, "MinSize", Vector2.zero)
		local mx: Vector2 = get(limit, "MaxSize", Vector2.new(math.huge, math.huge))
		w = math.clamp(w, mn.X * s, math.max(mn.X, mx.X) * s)
		h = math.clamp(h, mn.Y * s, math.max(mn.Y, mx.Y) * s)
	end

	local aspect = firstChild(inst, "UIAspectRatioConstraint")
	if aspect then
		local ratio = get(aspect, "AspectRatio", 1)
		local dom = get(aspect, "DominantAxis", Enum.DominantAxis.Width)
		local typ = get(aspect, "AspectType", Enum.AspectType.FitWithinMaxSize)
		if typ == Enum.AspectType.ScaleWithParentSize then
			if dom == Enum.DominantAxis.Width then
				h = w / ratio
			else
				w = h * ratio
			end
		elseif w / math.max(h, 1e-6) > ratio then
			w = h * ratio
		else
			h = w / ratio
		end
	end

	local us = 1
	local uiScale = firstChild(inst, "UIScale")
	if uiScale then
		us = get(uiScale, "Scale", 1)
	end
	return w * us, h * us, us
end

-- Mindestgröße für AutomaticSize: Text oder Kinder
function Layout.contentExtent(self: Layout, inst: any, s: number, wrapW: number?): (number, number)
	local w, h = 0, 0
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		local size = get(inst, "TextSize", 14) * s
		local b = Layout.textBounds(
			get(inst, "Text", ""),
			size,
			Layout.isBold(inst),
			if get(inst, "TextWrapped", false) then wrapW else nil
		)
		w, h = b.X, b.Y
	end
	local list = firstChild(inst, "UIListLayout")
	local gap = 0
	if list then
		local pad: UDim = get(list, "Padding", UDim.new())
		gap = pad.Offset * s
	end
	local horizontal = list and get(list, "FillDirection") == Enum.FillDirection.Horizontal
	local sumW, sumH, maxW, maxH, n = 0, 0, 0, 0, 0
	for _, c in children(inst, "GuiObject") do
		if get(c, "Visible", true) then
			local cw, ch = self:sizeIn(c, 0, 0, s)
			local pos: UDim2 = get(c, "Position", UDim2.new())
			n += 1
			sumW += cw
			sumH += ch
			if list then
				maxW = math.max(maxW, cw)
				maxH = math.max(maxH, ch)
			else
				maxW = math.max(maxW, pos.X.Offset * s + cw)
				maxH = math.max(maxH, pos.Y.Offset * s + ch)
			end
		end
	end
	if list and n > 0 then
		if horizontal then
			w = math.max(w, sumW + gap * (n - 1))
			h = math.max(h, maxH)
		else
			w = math.max(w, maxW)
			h = math.max(h, sumH + gap * (n - 1))
		end
	else
		w, h = math.max(w, maxW), math.max(h, maxH)
	end
	local pad = firstChild(inst, "UIPadding")
	if pad then
		w += (get(pad, "PaddingLeft", UDim.new()).Offset + get(pad, "PaddingRight", UDim.new()).Offset) * s
		h += (get(pad, "PaddingTop", UDim.new()).Offset + get(pad, "PaddingBottom", UDim.new()).Offset) * s
	end
	return w, h
end

-- Innenfläche für Kinder: Rechteck minus UIPadding (bei ScrollingFrame: Canvas)
function Layout.contentRect(self: Layout, inst: any): Rect?
	local r = self:rect(inst)
	if not r then
		return nil
	end
	local x, y, w, h, s = r.x, r.y, r.w, r.h, r.s
	if inst:IsA("ScrollingFrame") then
		local canvas: UDim2 = get(inst, "CanvasSize", UDim2.new(0, 0, 2, 0))
		local cpos: Vector2 = get(inst, "CanvasPosition", Vector2.zero)
		local auto = get(inst, "AutomaticCanvasSize", Enum.AutomaticSize.None)
		local cw = w * canvas.X.Scale + canvas.X.Offset * s
		local ch = h * canvas.Y.Scale + canvas.Y.Offset * s
		if auto ~= Enum.AutomaticSize.None then
			local ew, eh = self:contentExtent(inst, s)
			if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
				cw = math.max(cw, ew)
			end
			if auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY then
				ch = math.max(ch, eh)
			end
		end
		x, y, w, h = x - cpos.X, y - cpos.Y, math.max(w, cw), math.max(h, ch)
	end
	local pad = firstChild(inst, "UIPadding")
	if pad then
		local function px(u: UDim, total: number): number
			return total * u.Scale + u.Offset * s
		end
		local l = px(get(pad, "PaddingLeft", UDim.new()), w)
		local rr = px(get(pad, "PaddingRight", UDim.new()), w)
		local t = px(get(pad, "PaddingTop", UDim.new()), h)
		local b = px(get(pad, "PaddingBottom", UDim.new()), h)
		x, y, w, h = x + l, y + t, math.max(0, w - l - rr), math.max(0, h - t - b)
	end
	return { x = x, y = y, w = w, h = h, s = s }
end

local function sortedChildren(parent: any, layout: any): { any }
	local list = {}
	for _, c in children(parent, "GuiObject") do
		if get(c, "Visible", true) then
			table.insert(list, c)
		end
	end
	local byName = get(layout, "SortOrder") == Enum.SortOrder.Name
	table.sort(list, function(a, b)
		if byName then
			return a.Name < b.Name
		end
		local la, lb = get(a, "LayoutOrder", 0), get(b, "LayoutOrder", 0)
		if la ~= lb then
			return la < lb
		end
		return false
	end)
	return list
end

local function align(
	start: number,
	space: number,
	used: number,
	alignment: any,
	low: any,
	high: any
): number
	if alignment == low then
		return start
	elseif alignment == high then
		return start + space - used
	end
	return start + (space - used) / 2
end

-- Positionen aller Kinder eines Elternteils mit UIListLayout/UIGridLayout
function Layout.arrange(self: Layout, parent: any, layout: any, P: Rect)
	local s = P.s
	local items = sortedChildren(parent, layout)
	local H = Enum.HorizontalAlignment
	local V = Enum.VerticalAlignment
	local ha = get(layout, "HorizontalAlignment", H.Left)
	local va = get(layout, "VerticalAlignment", V.Top)

	if layout:IsA("UIGridLayout") then
		local cell: UDim2 = get(layout, "CellSize", UDim2.fromOffset(100, 100))
		local cpad: UDim2 = get(layout, "CellPadding", UDim2.fromOffset(5, 5))
		local cw = P.w * cell.X.Scale + cell.X.Offset * s
		local ch = P.h * cell.Y.Scale + cell.Y.Offset * s
		local px = P.w * cpad.X.Scale + cpad.X.Offset * s
		local py = P.h * cpad.Y.Scale + cpad.Y.Offset * s
		local horizontal = get(layout, "FillDirection", Enum.FillDirection.Horizontal)
			== Enum.FillDirection.Horizontal
		local maxCells = get(layout, "FillDirectionMaxCells", 0)
		local fit = if horizontal
			then math.max(1, math.floor((P.w + px) / math.max(1, cw + px)))
			else math.max(1, math.floor((P.h + py) / math.max(1, ch + py)))
		local per = if maxCells > 0 then math.min(maxCells, fit) else fit
		local n = #items
		local cols = if horizontal then math.min(per, n) else math.ceil(n / per)
		local rows = if horizontal then math.ceil(n / per) else math.min(per, n)
		local usedW = cols * cw + math.max(0, cols - 1) * px
		local usedH = rows * ch + math.max(0, rows - 1) * py
		local x0 = align(P.x, P.w, usedW, ha, H.Left, H.Right)
		local y0 = align(P.y, P.h, usedH, va, V.Top, V.Bottom)
		for i, c in items do
			local k = i - 1
			local col = if horizontal then k % per else k // per
			local row = if horizontal then k // per else k % per
			local _, _, us = self:sizeIn(c, cw, ch, s)
			self.cache[id(c)] = {
				x = x0 + col * (cw + px),
				y = y0 + row * (ch + py),
				w = cw * us,
				h = ch * us,
				s = s * us,
			}
		end
		return
	end

	local horizontal = get(layout, "FillDirection", Enum.FillDirection.Vertical)
		== Enum.FillDirection.Horizontal
	local pad: UDim = get(layout, "Padding", UDim.new())
	local gap = (if horizontal then P.w else P.h) * pad.Scale + pad.Offset * s

	-- Wraps: waagerechte Liste bricht in Zeilen um (Zeilenabstand = Padding)
	if horizontal and get(layout, "Wraps", false) then
		local rows, row, rowW = {}, {}, 0
		for _, c in items do
			local w, h, us = self:sizeIn(c, P.w, P.h, s)
			local need = if #row > 0 then rowW + gap + w else w
			if #row > 0 and need > P.w + 0.5 then
				table.insert(rows, { items = row, w = rowW })
				row, rowW = {}, w
			else
				rowW = need
			end
			table.insert(row, { c, w, h, us })
		end
		if #row > 0 then
			table.insert(rows, { items = row, w = rowW })
		end
		local y = P.y
		for _, r in rows do
			local x = align(P.x, P.w, r.w, ha, H.Left, H.Right)
			local rowH = 0
			for _, e in r.items do
				local c, w, h, us = e[1], e[2], e[3], e[4]
				self.cache[id(c)] = { x = x, y = y, w = w, h = h, s = s * us }
				x += w + gap
				rowH = math.max(rowH, h)
			end
			y += rowH + gap
		end
		return
	end

	local sizes = {}
	local total = 0
	for i, c in items do
		local w, h, us = self:sizeIn(c, P.w, P.h, s)
		sizes[i] = { w, h, us }
		total += if horizontal then w else h
	end
	total += gap * math.max(0, #items - 1)
	local cursor = if horizontal
		then align(P.x, P.w, total, ha, H.Left, H.Right)
		else align(P.y, P.h, total, va, V.Top, V.Bottom)
	for i, c in items do
		local w, h, us = sizes[i][1], sizes[i][2], sizes[i][3]
		local x, y
		if horizontal then
			x = cursor
			y = align(P.y, P.h, h, va, V.Top, V.Bottom)
			cursor += w + gap
		else
			y = cursor
			x = align(P.x, P.w, w, ha, H.Left, H.Right)
			cursor += h + gap
		end
		self.cache[id(c)] = { x = x, y = y, w = w, h = h, s = s * us }
	end
end

function Layout.rect(self: Layout, inst: any): Rect?
	local key = id(inst)
	local cached = self.cache[key]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local result: Rect? = nil
	local vw, vh = self.viewport.X, self.viewport.Y

	if inst:IsA("ScreenGui") then
		local top = if get(inst, "IgnoreGuiInset", false) then 0 else self.inset
		result = { x = 0, y = top, w = vw, h = vh - top, s = 1 }
	elseif inst:IsA("LayerCollector") then
		local size: UDim2 = get(inst, "Size", UDim2.fromOffset(100, 100))
		result = {
			x = 0,
			y = 0,
			w = size.X.Offset + size.X.Scale * 50,
			h = size.Y.Offset + size.Y.Scale * 50,
			s = 1,
		}
	elseif inst:IsA("GuiObject") then
		local parent = inst.Parent
		if parent and parent:IsA("GuiBase2d") then
			local P = self:contentRect(parent)
			if P then
				local layout = firstChild(parent, "UIGridStyleLayout")
				if layout and get(inst, "Visible", true) then
					self:arrange(parent, layout, P)
					local placed = self.cache[key]
					if placed then
						return placed
					end
				end
				local w, h, us = self:sizeIn(inst, P.w, P.h, P.s)
				local pos: UDim2 = get(inst, "Position", UDim2.new())
				local anchor: Vector2 = get(inst, "AnchorPoint", Vector2.zero)
				local ax = P.x + P.w * pos.X.Scale + pos.X.Offset * P.s
				local ay = P.y + P.h * pos.Y.Scale + pos.Y.Offset * P.s
				result =
					{ x = ax - anchor.X * w, y = ay - anchor.Y * h, w = w, h = h, s = P.s * us }
			end
		end
	end
	self.cache[key] = result or false
	return result
end

-- Ist das Objekt tatsächlich sichtbar (alle Vorfahren sichtbar, ScreenGui aktiv, im PlayerGui)?
function Layout.isShown(inst: any): boolean
	local node = inst
	while node do
		if node:IsA("GuiObject") and not get(node, "Visible", true) then
			return false
		end
		if node:IsA("CanvasGroup") and get(node, "GroupTransparency", 0) >= 0.99 then
			return false
		end
		if node:IsA("LayerCollector") then
			return get(node, "Enabled", true)
		end
		node = node.Parent
	end
	return false
end

return Layout
