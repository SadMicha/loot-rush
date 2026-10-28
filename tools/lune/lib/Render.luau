--!nocheck
-- Rendert den UI-Baum als HTML (absolut positionierte Divs mit den berechneten Layout-Rechtecken).
-- Bilder kommen aus lokalen PNG-Ordnern (Name aus Assets.luau → Datei <name>.png),
-- sonst steht ein beschrifteter Platzhalter da. 9-Slice wird per CSS border-image nachgebaut.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Layout = require("./Layout")

local Enum = roblox.Enum
local get = Layout.get

local Render = {}

local function esc(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function rgba(c, transparency: number?): string
	return string.format(
		"rgba(%d,%d,%d,%.3f)",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
		1 - math.clamp(transparency or 0, 0, 1)
	)
end

local function px(n: number): string
	return string.format("%.1fpx", n)
end

-------------------------------------------------------------------------------
-- Bildquellen

-- Asset-ID → Name aus allen ModuleScripts (z. B. Assets.luau: `window_main = table.freeze({ id = "rbxassetid://…"`)
function Render.assetNames(placeRoot): { [string]: string }
	local names = {}
	for _, d in placeRoot:GetDescendants() do
		if d:IsA("ModuleScript") then
			local src = d.Source
			for name, id in
				src:gmatch('([%w_]+)%s*=%s*table%.freeze%(%s*{%s*id%s*=%s*"rbxassetid://(%d+)"')
			do
				names[id] = names[id] or name
			end
			for name, id in src:gmatch('([%w_]+)%s*=%s*{%s*id%s*=%s*"rbxassetid://(%d+)"') do
				names[id] = names[id] or name
			end
			for name, id in src:gmatch('([%w_]+)%s*=%s*"rbxassetid://(%d+)"') do
				names[id] = names[id] or name
			end
		end
	end
	return names
end

local function walk(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local p = dir .. "/" .. entry
		if fs.isDir(p) then
			walk(p, out)
		elseif entry:lower():match("%.png$") then
			table.insert(out, p)
		end
	end
end

local function versionOf(path: string): number
	return tonumber(path:match("_v(%d+)")) or 0
end

-- Name → PNG-Pfad; bei Doppelten gewinnt der neueste Upload-Ordner (…_v7 vor …_v3)
function Render.indexImages(dirs: { string }): { [string]: string }
	local files = {}
	for _, dir in dirs do
		if fs.isDir(dir) then
			walk(dir, files)
		end
	end
	local index = {}
	for _, f in files do
		local name = f:match("([^/\\]+)%.[pP][nN][gG]$")
		local prev = index[name]
		if not prev or versionOf(f) > versionOf(prev) then
			index[name] = f
		end
	end
	return index
end

local function pngSize(path: string): (number, number)
	local data = fs.readFile(path)
	if #data < 24 then
		return 0, 0
	end
	local w, h = string.unpack(">I4I4", data, 17)
	return w, h
end

export type ImageSource = {
	names: { [string]: string },
	files: { [string]: string },
	outDir: string,
	copied: { [string]: { rel: string, w: number, h: number } },
}

function Render.imageSource(names, files, outDir): ImageSource
	return { names = names, files = files, outDir = outDir, copied = {} }
end

local function resolveImage(src: ImageSource, image: string)
	local id = image:match("rbxassetid://(%d+)")
	if not id then
		return nil, image
	end
	local name = src.names[id] or id
	local cached = src.copied[name]
	if cached then
		return cached, name
	end
	local file = src.files[name]
	if not file then
		return nil, name
	end
	local w, h = pngSize(file)
	fs.writeDir(src.outDir .. "/img")
	fs.copy(file, src.outDir .. "/img/" .. name .. ".png", true)
	local info = { rel = "img/" .. name .. ".png", w = w, h = h }
	src.copied[name] = info
	return info, name
end

-------------------------------------------------------------------------------
-- Elemente

local function fontCss(n): string
	local family, weight = "Nunito", 400
	local face = get(n, "FontFace")
	if face then
		family = tostring(get(face, "Family", "")):match("families/([%w]+)%.json") or family
		local ok, w = pcall(function()
			return face.Weight.Value
		end)
		if ok and w then
			weight = w
		end
	end
	return string.format(
		"font-family:'%s',Nunito,'Segoe UI',sans-serif;font-weight:%d;",
		family,
		weight
	)
end

local function gradientCss(n, base): string?
	local g = n:FindFirstChildOfClass("UIGradient")
	if not g or not get(g, "Enabled", true) then
		return nil
	end
	local seq = get(g, "Color")
	if not seq then
		return nil
	end
	local stops = {}
	for _, k in seq.Keypoints do
		local c = k.Value
		local mixed = roblox.Color3.new(c.R * base.R, c.G * base.G, c.B * base.B)
		table.insert(stops, rgba(mixed, 0) .. " " .. string.format("%.0f%%", k.Time * 100))
	end
	local angle = 90 + get(g, "Rotation", 0)
	return string.format("linear-gradient(%ddeg,%s)", angle, table.concat(stops, ","))
end

local function cornerCss(n, r): string
	local c = n:FindFirstChildOfClass("UICorner")
	if not c then
		return ""
	end
	local u = get(c, "CornerRadius", roblox.UDim.new(0, 8))
	local radius = math.min(r.w, r.h) * u.Scale + u.Offset * r.s
	return "border-radius:" .. px(radius) .. ";"
end

local function richText(text: string): string
	local out = esc(text)
	out = out:gsub("&lt;(/?)([biu])&gt;", "<%1%2>")
	out = out:gsub("&lt;br%s*/?&gt;", "<br>")
	out = out:gsub("&lt;font color=&quot;(#%x+)&quot;&gt;", '<span style="color:%1">')
	out = out:gsub(
		"&lt;font color=&quot;rgb%((%d+),%s*(%d+),%s*(%d+)%)&quot;&gt;",
		'<span style="color:rgb(%1,%2,%3)">'
	)
	out = out:gsub("&lt;font size=&quot;(%d+)&quot;&gt;", '<span style="font-size:%1px">')
	out = out:gsub("&lt;/font&gt;", "</span>")
	return out
end

local function textHtml(n, r): string
	local text = get(n, "Text", "")
	if n:IsA("TextBox") and text == "" then
		text = get(n, "PlaceholderText", "")
	end
	if text == "" or get(n, "TextTransparency", 0) >= 0.99 then
		return ""
	end
	local size = get(n, "TextSize", 14) * r.s
	if get(n, "TextScaled", false) then
		local one = Layout.textBounds(text, 1, Layout.isBold(n))
		size = math.clamp(
			math.min(r.h / math.max(one.Y, 1), r.w / math.max(one.X, 0.01)),
			1,
			100 * r.s
		)
	end
	local xa = get(n, "TextXAlignment", Enum.TextXAlignment.Center)
	local ya = get(n, "TextYAlignment", Enum.TextYAlignment.Center)
	local justify = if xa == Enum.TextXAlignment.Left
		then "flex-start"
		elseif xa == Enum.TextXAlignment.Right then "flex-end"
		else "center"
	local alignItems = if ya == Enum.TextYAlignment.Top
		then "flex-start"
		elseif ya == Enum.TextYAlignment.Bottom then "flex-end"
		else "center"
	local textAlign = if xa == Enum.TextXAlignment.Left
		then "left"
		elseif xa == Enum.TextXAlignment.Right then "right"
		else "center"
	local color = get(n, "TextColor3", roblox.Color3.new())
	local style = {
		"position:absolute;inset:0;display:flex;",
		"justify-content:"
			.. justify
			.. ";align-items:"
			.. alignItems
			.. ";text-align:"
			.. textAlign
			.. ";",
		"font-size:" .. px(size) .. ";line-height:1;",
		"color:" .. rgba(color, get(n, "TextTransparency", 0)) .. ";",
		fontCss(n),
		if get(n, "TextWrapped", false) then "white-space:normal;" else "white-space:pre;",
	}
	local pad = n:FindFirstChildOfClass("UIPadding")
	if pad then
		local function p(u, total)
			return px(total * u.Scale + u.Offset * r.s)
		end
		table.insert(
			style,
			string.format(
				"padding:%s %s %s %s;",
				p(get(pad, "PaddingTop", roblox.UDim.new()), r.h),
				p(get(pad, "PaddingRight", roblox.UDim.new()), r.w),
				p(get(pad, "PaddingBottom", roblox.UDim.new()), r.h),
				p(get(pad, "PaddingLeft", roblox.UDim.new()), r.w)
			)
		)
	end
	local strokeT = get(n, "TextStrokeTransparency", 1)
	local stroke = n:FindFirstChildOfClass("UIStroke")
	if
		stroke
		and get(stroke, "ApplyStrokeMode", Enum.ApplyStrokeMode.Contextual)
			== Enum.ApplyStrokeMode.Contextual
	then
		local t = get(stroke, "Thickness", 1) * r.s
		local c = rgba(get(stroke, "Color", roblox.Color3.new()), get(stroke, "Transparency", 0))
		table.insert(
			style,
			string.format("-webkit-text-stroke:%s %s;paint-order:stroke fill;", px(t * 2), c)
		)
	elseif strokeT < 0.99 then
		local c = rgba(get(n, "TextStrokeColor3", roblox.Color3.new()), strokeT)
		table.insert(
			style,
			string.format("-webkit-text-stroke:%s %s;paint-order:stroke fill;", px(2 * r.s), c)
		)
	end
	local g = gradientCss(n, color)
	if g then
		table.insert(
			style,
			"background-image:"
				.. g
				.. ";-webkit-background-clip:text;background-clip:text;color:transparent;"
		)
	end
	local body = if get(n, "RichText", false) then richText(text) else esc(text)
	return string.format(
		'<div class="t" style="%s"><span>%s</span></div>',
		table.concat(style),
		body
	)
end

local function imageHtml(src: ImageSource, n, r): string
	local image = get(n, "Image", "")
	if image == "" then
		return ""
	end
	local transparency = get(n, "ImageTransparency", 0)
	if transparency >= 0.99 then
		return ""
	end
	local info, name = resolveImage(src, image)
	local opacity = string.format("opacity:%.3f;", 1 - transparency)
	if not info then
		return string.format('<div class="ph" style="%s"><span>%s</span></div>', opacity, esc(name))
	end
	local url = "url('" .. info.rel .. "')"
	local scaleType = get(n, "ScaleType", Enum.ScaleType.Stretch)
	local rectSize = get(n, "ImageRectSize", roblox.Vector2.zero)
	local rectOffset = get(n, "ImageRectOffset", roblox.Vector2.zero)
	local tint = get(n, "ImageColor3", roblox.Color3.new(1, 1, 1))
	local tinted = tint.R < 0.99 or tint.G < 0.99 or tint.B < 0.99

	if scaleType == Enum.ScaleType.Slice and rectSize.Magnitude == 0 then
		local c = get(n, "SliceCenter", roblox.Rect.new(0, 0, 0, 0))
		local scale = get(n, "SliceScale", 1) * r.s
		local l, t = c.Min.X, c.Min.Y
		local rr, b = info.w - c.Max.X, info.h - c.Max.Y
		if c.Max.X == 0 and c.Max.Y == 0 then
			l, t, rr, b = 0, 0, 0, 0
		end
		return string.format(
			'<div class="img" style="%sborder-style:solid;border-width:%s %s %s %s;border-image:%s %d %d %d %d fill stretch;"></div>',
			opacity,
			px(t * scale),
			px(rr * scale),
			px(b * scale),
			px(l * scale),
			url,
			t,
			rr,
			b,
			l
		)
	end

	local layer
	if rectSize.Magnitude > 0 then
		local sx, sy = r.w / rectSize.X, r.h / rectSize.Y
		local ox, oy = 0, 0
		if scaleType == Enum.ScaleType.Fit then
			local s = math.min(sx, sy)
			ox, oy = (r.w - rectSize.X * s) / 2, (r.h - rectSize.Y * s) / 2
			sx, sy = s, s
		end
		layer = string.format(
			"background-image:%s;background-size:%s %s;background-position:%s %s;background-repeat:no-repeat;",
			url,
			px(info.w * sx),
			px(info.h * sy),
			px(ox - rectOffset.X * sx),
			px(oy - rectOffset.Y * sy)
		)
	else
		local size = if scaleType == Enum.ScaleType.Fit
			then "contain"
			elseif scaleType == Enum.ScaleType.Crop then "cover"
			elseif scaleType == Enum.ScaleType.Tile then px(
				get(n, "TileSize", roblox.UDim2.fromScale(1, 1)).X.Scale * r.w
			)
			else "100% 100%"
		layer = string.format(
			"background-image:%s;background-size:%s;background-position:center;background-repeat:%s;",
			url,
			size,
			if scaleType == Enum.ScaleType.Tile then "repeat" else "no-repeat"
		)
	end
	if tinted then
		local mask = layer:gsub("background%-", "-webkit-mask-")
		layer ..= "background-color:" .. rgba(tint, 0) .. ";background-blend-mode:multiply;" .. mask
	end
	return string.format('<div class="img" style="%s%s"></div>', opacity, layer)
end

local function nodeHtml(src: ImageSource, layout, n, parentRect, out: { string }, root)
	if not n:IsA("GuiObject") or not get(n, "Visible", true) then
		return
	end
	local r = layout:rect(n)
	if not r then
		return
	end
	local style = {
		string.format(
			"left:%s;top:%s;width:%s;height:%s;",
			px(r.x - parentRect.x),
			px(r.y - parentRect.y),
			px(r.w),
			px(r.h)
		),
		"z-index:" .. tostring(get(n, "ZIndex", 1)) .. ";",
	}
	local bgT = get(n, "BackgroundTransparency", 0)
	if bgT < 0.99 then
		local bg = get(n, "BackgroundColor3", roblox.Color3.new(1, 1, 1))
		local g = if not (n:IsA("TextLabel") or n:IsA("TextButton"))
			then gradientCss(n, bg)
			else nil
		if g then
			table.insert(
				style,
				"background-image:" .. g .. ";opacity:" .. string.format("%.3f", 1 - bgT) .. ";"
			)
		else
			table.insert(style, "background-color:" .. rgba(bg, bgT) .. ";")
		end
	end
	table.insert(style, cornerCss(n, r))
	local stroke = n:FindFirstChildOfClass("UIStroke")
	if stroke and get(stroke, "Enabled", true) then
		local mode = get(stroke, "ApplyStrokeMode", Enum.ApplyStrokeMode.Contextual)
		local isTextObj = n:IsA("TextLabel") or n:IsA("TextButton") or n:IsA("TextBox")
		if mode == Enum.ApplyStrokeMode.Border or not isTextObj then
			local t = get(stroke, "Thickness", 1) * r.s
			table.insert(
				style,
				string.format(
					"box-shadow:0 0 0 %s %s;",
					px(t),
					rgba(get(stroke, "Color", roblox.Color3.new()), get(stroke, "Transparency", 0))
				)
			)
		end
	end
	if get(n, "ClipsDescendants", false) or n:IsA("ScrollingFrame") or n:IsA("CanvasGroup") then
		table.insert(style, "overflow:hidden;")
	end
	if n:IsA("CanvasGroup") then
		table.insert(style, string.format("opacity:%.3f;", 1 - get(n, "GroupTransparency", 0)))
	end
	local rot = get(n, "Rotation", 0)
	if rot ~= 0 then
		table.insert(style, string.format("transform:rotate(%sdeg);", tostring(rot)))
	end
	local path = Render.pathOf(n, root)
	table.insert(
		out,
		string.format(
			'<div class="n %s" data-path="%s" title="%s" style="%s">',
			n.ClassName,
			esc(path),
			esc(
				string.format("%s (%s) %d×%d", path, n.ClassName, math.floor(r.w), math.floor(r.h))
			),
			table.concat(style)
		)
	)
	if n:IsA("ImageLabel") or n:IsA("ImageButton") then
		table.insert(out, imageHtml(src, n, r))
	end
	if n:IsA("TextLabel") or n:IsA("TextButton") or n:IsA("TextBox") then
		table.insert(out, textHtml(n, r))
	end
	if n:IsA("ViewportFrame") then
		table.insert(out, '<div class="ph"><span>ViewportFrame</span></div>')
	end
	local kids = n:GetChildren()
	for _, c in kids do
		nodeHtml(src, layout, c, r, out, root)
	end
	table.insert(out, "</div>")
end

function Render.pathOf(native, root): string
	local parts = {}
	local node = native
	while node and node ~= root do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

local CSS = [[
*{box-sizing:border-box;margin:0;padding:0}
body{background:#1b1f2e;color:#ddd;font:13px system-ui,sans-serif}
#bar{position:fixed;top:0;left:0;right:0;height:32px;background:#000c;display:flex;gap:16px;align-items:center;padding:0 10px;z-index:100000}
#bar label{cursor:pointer}
#stage{position:relative;overflow:hidden;margin-top:32px;background:radial-gradient(circle at 50% 40%,#3a5a3a,#1e2c22 70%)}
.n{position:absolute}
.img{position:absolute;inset:0;pointer-events:none}
.t{pointer-events:none;overflow:visible}
.ph{position:absolute;inset:0;border:1px dashed #ff6fd8;background:repeating-linear-gradient(45deg,#ff6fd820 0 6px,#0000 6px 12px);display:flex;align-items:center;justify-content:center;overflow:hidden}
.ph span{font:10px monospace;color:#ffb3ec;text-shadow:0 0 2px #000}
body.outline .n{outline:1px solid #00e5ff55}
body.issues .bad{outline:2px solid #ff3355 !important;outline-offset:1px}
#list{position:fixed;right:0;top:32px;bottom:0;width:420px;overflow:auto;background:#000d;padding:8px;z-index:100001;display:none;font:12px monospace}
body.showlist #list{display:block}
#list div{padding:3px 0;border-bottom:1px solid #333;cursor:pointer}
.lv-error{color:#ff6b6b}.lv-warn{color:#ffd166}.lv-info{color:#8ecae6}
]]

local SCRIPT = [[
const bad = FINDINGS;
for (const f of bad) for (const el of document.querySelectorAll('[data-path="'+CSS.escape(f.path)+'"]')) el.classList.add('bad');
const list = document.getElementById('list');
for (const f of bad) { const d=document.createElement('div'); d.className='lv-'+f.level; d.textContent='['+f.kind+'] '+f.path+' – '+f.message;
  d.onclick=()=>{for(const el of document.querySelectorAll('[data-path="'+CSS.escape(f.path)+'"]')){el.scrollIntoView({block:'center'});el.animate([{outlineColor:'#fff'},{outlineColor:'#ff3355'}],{duration:600,iterations:3});}}; list.appendChild(d); }
for (const id of ['outline','issues','showlist']) { const cb=document.getElementById('cb-'+id); const set=()=>document.body.classList.toggle(id, cb.checked); cb.onchange=set; set(); }
]]

local function jsonString(s: string): string
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("[%c]", "") .. '"'
end

function Render.page(sb, src: ImageSource, title: string, findings): string
	local pg = sb:nativeOf(sb:playerGui())
	local layout = sb.layout
	local vw, vh = sb.viewport.X, sb.viewport.Y
	local guis = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and get(g, "Enabled", true) then
			table.insert(guis, g)
		end
	end
	table.sort(guis, function(a, b)
		return get(a, "DisplayOrder", 0) < get(b, "DisplayOrder", 0)
	end)
	local out = {}
	for i, g in guis do
		local r = layout:rect(g)
		table.insert(
			out,
			string.format(
				'<div class="n gui" data-path="%s" style="left:0;top:0;width:%dpx;height:%dpx;z-index:%d">',
				esc(g.Name),
				vw,
				vh,
				i
			)
		)
		for _, c in g:GetChildren() do
			nodeHtml(src, layout, c, { x = 0, y = 0, w = vw, h = vh, s = r.s }, out, pg)
		end
		table.insert(out, "</div>")
	end
	local items = {}
	for _, f in findings do
		table.insert(
			items,
			string.format(
				"{level:%s,kind:%s,path:%s,message:%s}",
				jsonString(f.level),
				jsonString(f.kind),
				jsonString(f.path),
				jsonString(f.message)
			)
		)
	end
	return table.concat({
		"<!doctype html><html lang=de><head><meta charset=utf-8><title>",
		esc(title),
		"</title>",
		'<link rel="preconnect" href="https://fonts.googleapis.com">',
		'<link href="https://fonts.googleapis.com/css2?family=Merriweather:wght@400;700;900&family=Nunito:wght@400;600;700;800;900&display=block" rel="stylesheet">',
		"<style>",
		CSS,
		"</style></head><body class=issues>",
		'<div id="bar"><b>',
		esc(title),
		"</b>",
		string.format("<span>%d×%d</span>", vw, vh),
		'<label><input type=checkbox id="cb-outline"> Umrisse</label>',
		'<label><input type=checkbox id="cb-issues" checked> Probleme markieren</label>',
		string.format(
			'<label><input type=checkbox id="cb-showlist"> Liste (%d)</label>',
			#findings
		),
		"</div>",
		string.format('<div id="stage" style="width:%dpx;height:%dpx">', vw, vh),
		table.concat(out),
		'</div><div id="list"></div><script>',
		(SCRIPT:gsub("FINDINGS", function()
			return "[" .. table.concat(items, ",") .. "]"
		end)),
		"</script></body></html>",
	})
end

return Render
