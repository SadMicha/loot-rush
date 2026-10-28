--!nocheck
-- Layout-Prüfungen auf dem UI-Baum einer laufenden Sandbox.
-- Alle Textmaße sind Schätzungen (keine echten Fontmetriken) – darum „vermutlich“.

local roblox = require("@lune/roblox")
local Layout = require("./Layout")

local Enum = roblox.Enum
local get = Layout.get

local Checks = {}

-- Lune liefert für dieselbe Instanz nicht immer dasselbe Objekt: Tabellen-Schlüssel über die Debug-ID
local function id(inst): string
	return inst:GetDebugId()
end


export type Finding = { level: string, kind: string, path: string, message: string }

local function pathOf(native, root): string
	local parts = {}
	local node = native
	while node and node ~= root do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end
Checks.pathOf = pathOf

local function isText(n): boolean
	return n:IsA("TextLabel") or n:IsA("TextButton") or n:IsA("TextBox")
end

local function isImage(n): boolean
	return n:IsA("ImageLabel") or n:IsA("ImageButton")
end

-- Hat das Objekt selbst etwas Sichtbares (Fläche, Text oder Bild)?
local function hasContent(n): boolean
	if get(n, "BackgroundTransparency", 1) < 0.99 then
		return true
	end
	if isText(n) and get(n, "Text", "") ~= "" and get(n, "TextTransparency", 0) < 0.99 then
		return true
	end
	if isImage(n) and get(n, "Image", "") ~= "" and get(n, "ImageTransparency", 0) < 0.99 then
		return true
	end
	return false
end
Checks.hasContent = hasContent

-- Sichtbarer Ausschnitt: Rechteck geschnitten mit allen abschneidenden Vorfahren
local function clipRect(layout, n)
	local node = n.Parent
	local x0, y0, x1, y1 = -math.huge, -math.huge, math.huge, math.huge
	local clipper = nil
	while node and node:IsA("GuiObject") do
		if
			get(node, "ClipsDescendants", false)
			or node:IsA("CanvasGroup")
			or node:IsA("ScrollingFrame")
		then
			local r = layout:rect(node)
			if r then
				x0, y0 = math.max(x0, r.x), math.max(y0, r.y)
				x1, y1 = math.min(x1, r.x + r.w), math.min(y1, r.y + r.h)
				clipper = clipper or node
			end
		end
		node = node.Parent
	end
	return x0, y0, x1, y1, clipper
end

local function isTextScaled(n): boolean
	return get(n, "TextScaled", false)
end

-- Innenabstand links, rechts, oben, unten in Bildschirmpixeln
local function paddings(n, r)
	local pad = n:FindFirstChildOfClass("UIPadding")
	if not pad then
		return 0, 0, 0, 0
	end
	local function px(u, total)
		return total * u.Scale + u.Offset * r.s
	end
	local zero = roblox.UDim.new()
	return px(get(pad, "PaddingLeft", zero), r.w),
		px(get(pad, "PaddingRight", zero), r.w),
		px(get(pad, "PaddingTop", zero), r.h),
		px(get(pad, "PaddingBottom", zero), r.h)
end

local function textPadding(n, r)
	local l, rr, t, b = paddings(n, r)
	return l + rr, t + b
end

-- Text für Meldungen kürzen, ohne UTF-8-Zeichen zu zerschneiden (sonst scheitert report.json)
local function short(text: string, n: number): string
	local plain = text:gsub("<[^>]->", "")
	local len = utf8.len(plain)
	if not len then
		return "?"
	end
	if len > n then
		return plain:sub(1, utf8.offset(plain, n + 1) - 1) .. "…"
	end
	return plain
end
Checks.short = short

-- Geschätztes Rechteck, das der Text tatsächlich bedeckt (nach Ausrichtung, Umbruch, TextScaled)
local function inkRect(n, r)
	local l, rr, t, b = paddings(n, r)
	local availW, availH = r.w - l - rr, r.h - t - b
	local text = get(n, "Text", "")
	local bold = Layout.isBold(n)
	local w, h
	if get(n, "TextScaled", false) then
		local one = Layout.textBounds(text, 1, bold)
		local maxSize = 100 * r.s
		local c = n:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			maxSize = get(c, "MaxTextSize", 100) * r.s
		end
		local size = math.min(availH / math.max(one.Y, 1), availW / math.max(one.X, 0.01), maxSize)
		w, h = one.X * size, one.Y * size
	else
		local wrapped = get(n, "TextWrapped", false)
		local bnd = Layout.textBounds(
			text,
			get(n, "TextSize", 14) * r.s,
			bold,
			if wrapped then availW else nil
		)
		w, h = bnd.X, bnd.Y
		if wrapped or get(n, "TextTruncate", Enum.TextTruncate.None) ~= Enum.TextTruncate.None then
			w = math.min(w, availW)
		end
	end
	local xa = get(n, "TextXAlignment", Enum.TextXAlignment.Center)
	local ya = get(n, "TextYAlignment", Enum.TextYAlignment.Center)
	local x = if xa == Enum.TextXAlignment.Left
		then r.x + l
		elseif xa == Enum.TextXAlignment.Right then r.x + r.w - rr - w
		else r.x + l + (availW - w) / 2
	local y = if ya == Enum.TextYAlignment.Top
		then r.y + t
		elseif ya == Enum.TextYAlignment.Bottom then r.y + r.h - b - h
		else r.y + t + (availH - h) / 2
	return { x = x, y = y, w = w, h = h }
end
Checks.inkRect = inkRect

local function intersect(a, b)
	local x0, y0 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x1, y1 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	return { x = x0, y = y0, w = math.max(0, x1 - x0), h = math.max(0, y1 - y0) }
end

local function contains(outer, inner, slack: number): boolean
	return inner.x >= outer.x - slack
		and inner.y >= outer.y - slack
		and inner.x + inner.w <= outer.x + outer.w + slack
		and inner.y + inner.h <= outer.y + outer.h + slack
end

local function hasText(n): boolean
	return isText(n) and get(n, "Text", "") ~= "" and get(n, "TextTransparency", 0) < 0.99
end

-- Zeichenreihenfolge: Schlüssel vergleichen, größerer Schlüssel = später gezeichnet = liegt oben.
-- Sibling: Pfad aus (ZIndex, Kind-Index) je Ebene, Vorfahren vor Nachkommen. Global: ZIndex, dann Baumreihenfolge.
local function drawKey(n, index: { [any]: number }, preorder: { [any]: number }): { number }
	local chain = {}
	local node = n
	while node and not node:IsA("LayerCollector") do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	local key = { if node then get(node, "DisplayOrder", 0) else 0 }
	if
		node
		and get(node, "ZIndexBehavior", Enum.ZIndexBehavior.Sibling)
			== Enum.ZIndexBehavior.Global
	then
		table.insert(key, get(n, "ZIndex", 1))
		table.insert(key, preorder[id(n)] or 0)
		return key
	end
	for _, c in chain do
		table.insert(key, get(c, "ZIndex", 1))
		table.insert(key, index[id(c)] or 0)
	end
	return key
end

local function drawnAbove(a: { number }, b: { number }): boolean
	for i = 1, math.min(#a, #b) do
		if a[i] ~= b[i] then
			return a[i] > b[i]
		end
	end
	return #a > #b
end

local function isOpaque(n): boolean
	if get(n, "BackgroundTransparency", 1) < 0.5 then
		return true
	end
	return isImage(n) and get(n, "Image", "") ~= "" and get(n, "ImageTransparency", 0) < 0.5
end

local NUMBER_ONLY = "^[%d%s%.,%+%-/%%kKMB×x]+$"

local function isNumberOnly(text: string): boolean
	local plain = text:gsub("<[^>]->", "")
	return plain:match("%d") ~= nil and plain:match(NUMBER_ONLY) ~= nil
end

local function isCloseButton(n): boolean
	if not n:IsA("GuiButton") then
		return false
	end
	local name = n.Name:lower()
	if name:find("schlie", 1, true) or name:find("close", 1, true) then
		return true
	end
	local t = if isText(n) then get(n, "Text", "") else ""
	return t == "X" or t == "×" or t == "✕" or t == "✖"
end

function Checks.run(sb, profile: { name: string, touch: boolean? }): { Finding }
	local findings: { Finding } = {}
	local pg = sb:playerGui()
	if not pg then
		return findings
	end
	local root = sb:nativeOf(pg)
	local layout = sb.layout
	local vw, vh = sb.viewport.X, sb.viewport.Y

	local function add(level, kind, n, message)
		table.insert(
			findings,
			{ level = level, kind = kind, path = pathOf(n, root), message = message }
		)
	end

	local index, preorder = {}, {}
	for i, n in root:GetDescendants() do
		preorder[id(n)] = i
		for k, c in n:GetChildren() do
			index[id(c)] = k
		end
	end

	local entries = {} -- sichtbare GuiObjects für die Prüfungen über mehrere Objekte
	local byNode = {}
	local overflowing = {} -- Texte mit eigenem text-overflow-Befund

	for _, n in root:GetDescendants() do
		if n:IsA("GuiObject") and Layout.isShown(n) then
			local r = layout:rect(n)
			if r and r.w > 0 and r.h > 0 then
				local content = hasContent(n)
				local cx0, cy0, cx1, cy1, clipper = clipRect(layout, n)
				local vx0, vy0 = math.max(r.x, cx0), math.max(r.y, cy0)
				local vx1, vy1 = math.min(r.x + r.w, cx1), math.min(r.y + r.h, cy1)
				local visibleArea = math.max(0, vx1 - vx0) * math.max(0, vy1 - vy0)
				if visibleArea > 0 then
					local e = {
						n = n,
						r = r,
						vis = { x = vx0, y = vy0, w = vx1 - vx0, h = vy1 - vy0 },
						clip = { x = cx0, y = cy0, w = cx1 - cx0, h = cy1 - cy0 },
						content = content,
						text = hasText(n),
						gui = n:FindFirstAncestorWhichIsA("LayerCollector"),
						guiId = "",
						clipper = clipper,
					}
					if e.text then
						e.ink = inkRect(n, r)
						local seen = intersect(e.ink, e.clip)
						e.inkVis = if seen.w > 0 and seen.h > 0 then seen else nil
					end
					e.guiId = if e.gui then id(e.gui) else ""
					table.insert(entries, e)
					byNode[id(n)] = e
				end

				-- 1. Ragt aus dem Bildschirm (komplett draußen = absichtlich ausgeblendet, z. B. weggeflogen)
				if content and visibleArea > 0 then
					local out = math.max(0, -vx0, vx1 - vw, -vy0, vy1 - vh)
					if out > 2 then
						add(
							"warn",
							"offscreen",
							n,
							string.format("ragt %dpx aus dem Bildschirm", math.floor(out + 0.5))
						)
					end
				end

				-- 2. Von ClipsDescendants abgeschnitten (nur Text und Knöpfe; Scrollbereiche sind Absicht)
				if
					clipper
					and not clipper:IsA("ScrollingFrame")
					and (isText(n) or n:IsA("GuiButton"))
					and content
				then
					local cut = math.max(0, cx0 - r.x, r.x + r.w - cx1, cy0 - r.y, r.y + r.h - cy1)
					if cut > 2 and visibleArea > 0 then
						add(
							"warn",
							"clipped",
							n,
							string.format(
								"wird von %s um %dpx abgeschnitten",
								clipper.Name,
								math.floor(cut + 0.5)
							)
						)
					end
				end

				-- 3. Text passt nicht
				if
					isText(n)
					and get(n, "Text", "") ~= ""
					and get(n, "TextTransparency", 0) < 0.99
				then
					local size = get(n, "TextSize", 14) * r.s
					local padW, padH = textPadding(n, r)
					local availW, availH = r.w - padW, r.h - padH
					local bold = Layout.isBold(n)
					if isTextScaled(n) then
						local one = Layout.textBounds(get(n, "Text", ""), 1, bold)
						local fit =
							math.min(availH / math.max(one.Y, 1), availW / math.max(one.X, 0.01))
						local maxSize = 100
						local c = n:FindFirstChildOfClass("UITextSizeConstraint")
						if c then
							maxSize = get(c, "MaxTextSize", 100) * r.s
						end
						if math.min(fit, maxSize) < 9 then
							add(
								"warn",
								"text-small",
								n,
								string.format(
									"TextScaled ergibt vermutlich nur ~%dpx Schrift",
									math.floor(math.min(fit, maxSize))
								)
							)
						end
					else
						local wrapped = get(n, "TextWrapped", false)
						local b = Layout.textBounds(
							get(n, "Text", ""),
							size,
							bold,
							if wrapped then availW else nil
						)
						local truncate = get(n, "TextTruncate", Enum.TextTruncate.None)
							~= Enum.TextTruncate.None
						if not wrapped and b.X > availW * 1.05 + 2 then
							overflowing[id(n)] = true
							add(
								if truncate then "info" else "warn",
								"text-overflow",
								n,
								string.format(
									"Text „%s“ braucht vermutlich ~%dpx, Platz %dpx%s",
									short(get(n, "Text", ""), 40),
									math.floor(b.X),
									math.floor(availW),
									if truncate then " (wird mit … gekürzt)" else ""
								)
							)
						elseif wrapped and b.Y > availH * 1.1 + 2 then
							overflowing[id(n)] = true
							add(
								"warn",
								"text-overflow",
								n,
								string.format(
									"umbrochener Text braucht vermutlich ~%dpx Höhe, Platz %dpx",
									math.floor(b.Y),
									math.floor(availH)
								)
							)
						end
						if size < 9 then
							add(
								"warn",
								"text-small",
								n,
								string.format("Schrift nur %.1fpx groß", size)
							)
						end
					end
				end

				-- 4. Bild-IDs
				if isImage(n) then
					local img = get(n, "Image", "")
					if img ~= "" then
						local id = img:match("^rbxassetid://(%d+)$")
						if
							not id
							and not img:match("^rbxasset://")
							and not img:match("^https?://")
							and not img:match("^rbxthumb://")
						then
							add(
								"error",
								"image-id",
								n,
								string.format("ungültige Bild-ID „%s“", img)
							)
						elseif id == "0" then
							add("error", "image-id", n, "Bild-ID ist 0")
						end
					elseif get(n, "ImageRectSize", roblox.Vector2.zero).Magnitude > 0 then
						add("warn", "image-id", n, "ImageRectSize gesetzt, aber kein Bild")
					end
				end

				-- 5. Zu kleine Touch-Ziele
				if
					profile.touch
					and n:IsA("GuiButton")
					and sb:hasHandlers(sb:wrap(n))
					and visibleArea > 0
				then
					if r.w < 32 or r.h < 32 then
						add(
							"warn",
							"touch-target",
							n,
							string.format(
								"Knopf nur %d×%dpx (Touch: mind. 32px)",
								math.floor(r.w),
								math.floor(r.h)
							)
						)
					end
				end
			end
		end
	end

	local vArea = vw * vh

	local keys = {}
	local function key(n)
		local k = keys[id(n)]
		if not k then
			k = drawKey(n, index, preorder)
			keys[id(n)] = k
		end
		return k
	end

	-- Verdeckt: ein großes deckendes Objekt (z. B. Fenster-Hintergrund über dem HUD) liegt darüber.
	-- Verdeckte Objekte prüfen die folgenden Regeln nicht.
	local covers = {}
	for _, e in entries do
		if e.vis.w * e.vis.h >= vArea * 0.25 and isOpaque(e.n) then
			table.insert(covers, e)
		end
	end
	local visible = {}
	for _, e in entries do
		local hidden = false
		for _, c in covers do
			if
				c ~= e
				and not e.n:IsDescendantOf(c.n)
				and not c.n:IsDescendantOf(e.n)
				and contains(c.vis, e.vis, 0)
				and drawnAbove(key(c.n), key(e.n))
			then
				hidden = true
				break
			end
		end
		if not hidden then
			table.insert(visible, e)
		else
			byNode[id(e.n)] = nil
		end
	end
	entries = visible

	-- 6. Roblox-Knöpfe oben links (Logo, Menü, Chat) verdecken Text, Knöpfe und Icons
	local bar = sb:topbarButtons()
	local tb = { x = 0, y = 0, w = bar.X, h = bar.Y }
	for _, e in entries do
		local n = e.n
		if e.gui and get(e.gui, "IgnoreGuiInset", false) then
			local box = if e.text then e.inkVis else e.vis
			local relevant = e.text
				or (n:IsA("GuiButton") and sb:hasHandlers(sb:wrap(n)))
				or (isImage(n) and e.content and e.vis.w * e.vis.h < vArea * 0.05)
			if relevant and box then
				local ov = intersect(box, tb)
				if ov.w > 2 and ov.h > 2 then
					add(
						"warn",
						"topbar",
						n,
						string.format(
							"%s liegt unter der Roblox-Topbar (oben links %d×%dpx)",
							if e.text
								then "Text „" .. short(get(n, "Text", ""), 30) .. "“"
								else n.ClassName,
							bar.X,
							bar.Y
						)
					)
				end
			end
		end
	end

	-- 6b. Scrollbereich schneidet quer zur Scrollrichtung ab (z. B. Item-Reihe oben gekappt)
	for _, e in entries do
		local sf = e.clipper
		if sf and sf:IsA("ScrollingFrame") and e.content and (e.n:IsA("GuiButton") or e.text) then
			local dir = get(sf, "ScrollingDirection", Enum.ScrollingDirection.XY)
			local r, c = e.r, e.clip
			local cutX = math.max(0, c.x - r.x, r.x + r.w - (c.x + c.w))
			local cutY = math.max(0, c.y - r.y, r.y + r.h - (c.y + c.h))
			local cut = if dir == Enum.ScrollingDirection.X
				then cutY
				elseif dir == Enum.ScrollingDirection.Y then cutX
				else 0
			if cut > 2 then
				add(
					"warn",
					"scroll-cut",
					e.n,
					string.format(
						"%s schneidet %dpx quer zur Scrollrichtung ab (nicht erreichbar)",
						sf.Name,
						math.floor(cut + 0.5)
					)
				)
			end
		end
	end

	-- 7. Text liegt unter einem Icon/Knopf oder auf anderem Text
	local pairsSeen = {}
	for _, t in entries do
		local ink = t.inkVis
		if ink then
			local inkArea = ink.w * ink.h
			for _, e in entries do
				if
					e ~= t
					and e.guiId == t.guiId -- Fenster über dem HUD ist Absicht
					and get(e.n, "Rotation", 0) == 0
					and not t.n:IsDescendantOf(e.n)
					and not e.n:IsDescendantOf(t.n)
				then
					if e.text and e.inkVis then
						local ov = intersect(ink, e.inkVis)
						local small = math.min(inkArea, e.inkVis.w * e.inkVis.h)
						local same = get(e.n, "Text", "") == get(t.n, "Text", "")
							and math.abs(e.inkVis.x - ink.x) <= 4
							and math.abs(e.inkVis.y - ink.y) <= 4 -- Schatten-Kopie
						if ov.w > 2 and ov.h > 2 and ov.w * ov.h > small * 0.2 and not same then
							local a, b = pathOf(t.n, root), pathOf(e.n, root)
							local pk = if a < b then a .. "|" .. b else b .. "|" .. a
							if not pairsSeen[pk] then
								pairsSeen[pk] = true
								add(
									"warn",
									"text-overlap",
									t.n,
									string.format(
										"Text „%s“ überlappt Text „%s“ (%s)",
										short(get(t.n, "Text", ""), 24),
										short(get(e.n, "Text", ""), 24),
										e.n.Name
									)
								)
							end
						end
					elseif isOpaque(e.n) or (e.n:IsA("GuiButton") and e.content) then
						local eArea = e.vis.w * e.vis.h
						local enclosing = contains(e.vis, ink, 0) and eArea >= inkArea * 4
						if not enclosing and drawnAbove(key(e.n), key(t.n)) then
							local ov = intersect(ink, e.vis)
							if ov.w > 2 and ov.h > 2 and ov.w * ov.h > inkArea * 0.12 then
								add(
									"warn",
									"text-covered",
									t.n,
									string.format(
										"Text „%s“ läuft zu %d %% hinter %s",
										short(get(t.n, "Text", ""), 30),
										math.floor(ov.w * ov.h / inkArea * 100 + 0.5),
										e.n.Name
									)
								)
							end
						end
					end
				end
			end
		end
	end

	-- 8. Text ragt aus seinem Panel (nächster Vorfahr mit Fläche/Bild oder Kind „Skin“)
	for _, t in entries do
		if t.inkVis and not overflowing[id(t.n)] then
			local node = t.n.Parent
			local panel = nil
			while node and node:IsA("GuiObject") and not node:IsA("ScrollingFrame") do
				local skin = node:FindFirstChild("Skin")
				if hasContent(node) or (skin and skin:IsA("GuiObject") and hasContent(skin)) then
					panel = node
					break
				end
				node = node.Parent
			end
			local pe = panel and byNode[id(panel)]
			if pe and pe.r.w * pe.r.h < vArea * 0.9 then
				local ink, p = t.ink, pe.r
				local inside = intersect(ink, p)
				-- ganz außerhalb = Beschriftung neben/unter dem Objekt (Absicht), nur Überstand zählt
				if inside.w <= 0 or inside.h <= 0 then
					continue
				end
				local out = math.max(
					p.x - ink.x,
					ink.x + ink.w - (p.x + p.w),
					p.y - ink.y,
					ink.y + ink.h - (p.y + p.h)
				)
				if out > 3 then
					add(
						"warn",
						"text-outside",
						t.n,
						string.format(
							"Text „%s“ ragt %dpx aus %s",
							short(get(t.n, "Text", ""), 30),
							math.floor(out + 0.5),
							panel.Name
						)
					)
				end
			end
		end
	end

	-- 9. Kapsel zeigt nur eine Zahl (kein Icon, keine Beschriftung)
	for _, t in entries do
		if t.text and isNumberOnly(get(t.n, "Text", "")) then
			local node = t.n
			local box = nil
			while node and node:IsA("GuiObject") do
				local self = id(node) == id(t.n)
				if
					(not self and hasContent(node))
					or (self and get(node, "BackgroundTransparency", 1) < 0.99)
				then
					box = node
					break
				end
				node = node.Parent
			end
			local be = box and byNode[id(box)]
			if be and be.r.w * be.r.h < vArea * 0.06 then
				local area = be.r.w * be.r.h
				local labelled = false
				for _, d in box:GetDescendants() do
					local de = byNode[id(d)]
					if de and id(d) ~= id(t.n) then
						if de.text and not isNumberOnly(get(d, "Text", "")) then
							labelled = true
						elseif isImage(d) and de.content and de.r.w * de.r.h < area * 0.7 then
							labelled = true
						end
					end
					if labelled then
						break
					end
				end
				if not labelled then
					add(
						"warn",
						"unlabeled",
						box,
						string.format(
							"zeigt nur „%s“ – Icon oder Beschriftung fehlt",
							short(get(t.n, "Text", ""), 12)
						)
					)
				end
			end
		end
	end

	-- 10. Leere Zeile in einer Liste, deren andere Zeilen Text haben
	local function rowHasText(n): boolean
		if byNode[id(n)] and byNode[id(n)].text then
			return true
		end
		for _, d in n:GetDescendants() do
			local de = byNode[id(d)]
			if de and de.text then
				return true
			end
		end
		return false
	end
	local function rowHasContent(n): boolean
		if byNode[id(n)] and byNode[id(n)].content then
			return true
		end
		for _, d in n:GetDescendants() do
			local de = byNode[id(d)]
			if de and de.content then
				return true
			end
		end
		return false
	end
	for _, list in root:GetDescendants() do
		local parent = list.Parent
		local pe = parent and byNode[id(parent)]
		if
			list:IsA("UIListLayout")
			and pe
			and get(list, "FillDirection", Enum.FillDirection.Vertical)
				== Enum.FillDirection.Vertical
		then
			local rows, withText, textH = {}, 0, 0
			for _, c in parent:GetChildren() do
				local ce = byNode[id(c)]
				if ce and ce.r.w >= pe.r.w * 0.5 then
					local ht = rowHasText(c)
					table.insert(rows, { n = c, text = ht, h = ce.r.h })
					if ht then
						withText += 1
						textH += ce.r.h
					end
				end
			end
			if withText >= 2 then
				for _, row in rows do
					-- schmale Zeilen (Balken, Trennlinien) sind keine leeren Einträge
					if
						not row.text
						and row.h >= textH / withText * 0.6
						and rowHasContent(row.n)
					then
						add(
							"warn",
							"empty-row",
							row.n,
							"Zeile ohne Text, die anderen Zeilen haben Text"
						)
					end
				end
			end
		end
	end

	-- 11. Überlappende Bausteine: direkte Kinder des Root-Frames einer ScreenGui (HUD-Gruppen, Fenster)
	for _, gui in root:GetChildren() do
		if gui:IsA("ScreenGui") and get(gui, "Enabled", true) then
			local top = gui:FindFirstChild("Root") or gui
			local boxes = {}
			for _, n in top:GetChildren() do
				local r = n:IsA("GuiObject") and Layout.isShown(n) and layout:rect(n)
				-- Vollbild-Flächen (abgedunkelter Hintergrund) und Weggeflogenes zählen nicht
				local full = r and r.w * r.h >= vw * vh * 0.9
				local onScreen = r and r.x < vw and r.y < vh and r.x + r.w > 0 and r.y + r.h > 0
				if r and r.w > 0 and r.h > 0 and not full and onScreen then
					table.insert(boxes, { n = n, r = r })
				end
			end
			for i = 1, #boxes do
				for j = i + 1, #boxes do
					local a, b = boxes[i].r, boxes[j].r
					local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
					local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
					if w > 2 and h > 2 then
						add(
							"warn",
							"overlap",
							boxes[i].n,
							string.format(
								"überlappt %s um %d×%dpx",
								boxes[j].n.Name,
								math.floor(w + 0.5),
								math.floor(h + 0.5)
							)
						)
					end
				end
			end
		end
	end

	return findings
end

-- Schließen-Knöpfe mit Aussehen, damit sich Fenster vergleichen lassen (siehe ui.luau / Handy-Test)
function Checks.closeButtons(sb): { { path: string, look: string } }
	local out = {}
	local pg = sb:playerGui()
	if not pg then
		return out
	end
	local root = sb:nativeOf(pg)
	for _, n in root:GetDescendants() do
		if isCloseButton(n) and Layout.isShown(n) then
			local r = sb.layout:rect(n)
			if r and r.w > 0 then
				local color = get(n, "ImageColor3", roblox.Color3.new(1, 1, 1))
				table.insert(out, {
					path = pathOf(n, root),
					look = string.format(
						"%s %s %s #%02x%02x%02x %d×%d",
						n.ClassName,
						if isImage(n) then get(n, "Image", "") else "",
						if isText(n) then get(n, "Text", "") else "",
						math.floor(color.R * 255 + 0.5),
						math.floor(color.G * 255 + 0.5),
						math.floor(color.B * 255 + 0.5),
						math.floor(r.w / r.s + 0.5),
						math.floor(r.h / r.s + 0.5)
					),
				})
			end
		end
	end
	return out
end

-- Weichen Schließen-Knöpfe voneinander ab? Häufigstes Aussehen gilt als Vorgabe.
function Checks.compareClose(list: { { path: string, look: string, state: string? } }): { Finding }
	local count = {}
	for _, c in list do
		count[c.look] = (count[c.look] or 0) + 1
	end
	local best, bestN = nil, 0
	for look, n in count do
		if n > bestN then
			best, bestN = look, n
		end
	end
	local out = {}
	for _, c in list do
		if c.look ~= best then
			table.insert(out, {
				level = "warn",
				kind = "close-style",
				path = c.path,
				message = string.format(
					"Schließen-Knopf sieht anders aus (%s statt %s)",
					c.look,
					best
				),
			})
		end
	end
	return out
end

return Checks
