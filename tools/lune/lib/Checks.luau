--!nocheck
-- Layout-Prüfungen auf dem UI-Baum einer laufenden Sandbox.
-- Alle Textmaße sind Schätzungen (keine echten Fontmetriken) – darum „vermutlich“.

local roblox = require("@lune/roblox")
local Layout = require("./Layout")

local Enum = roblox.Enum
local get = Layout.get

local Checks = {}

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

local function textPadding(n, r)
	local pad = n:FindFirstChildOfClass("UIPadding")
	if not pad then
		return 0, 0
	end
	local function px(u, total)
		return total * u.Scale + u.Offset * r.s
	end
	local w = px(get(pad, "PaddingLeft", roblox.UDim.new()), r.w)
		+ px(get(pad, "PaddingRight", roblox.UDim.new()), r.w)
	local h = px(get(pad, "PaddingTop", roblox.UDim.new()), r.h)
		+ px(get(pad, "PaddingBottom", roblox.UDim.new()), r.h)
	return w, h
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

	for _, n in root:GetDescendants() do
		if n:IsA("GuiObject") and Layout.isShown(n) then
			local r = layout:rect(n)
			if r and r.w > 0 and r.h > 0 then
				local content = hasContent(n)
				local cx0, cy0, cx1, cy1, clipper = clipRect(layout, n)
				local vx0, vy0 = math.max(r.x, cx0), math.max(r.y, cy0)
				local vx1, vy1 = math.min(r.x + r.w, cx1), math.min(r.y + r.h, cy1)
				local visibleArea = math.max(0, vx1 - vx0) * math.max(0, vy1 - vy0)

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
							add(
								if truncate then "info" else "warn",
								"text-overflow",
								n,
								string.format(
									"Text „%s“ braucht vermutlich ~%dpx, Platz %dpx%s",
									get(n, "Text", ""):sub(1, 40),
									math.floor(b.X),
									math.floor(availW),
									if truncate then " (wird mit … gekürzt)" else ""
								)
							)
						elseif wrapped and b.Y > availH * 1.1 + 2 then
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
	return findings
end

return Checks
