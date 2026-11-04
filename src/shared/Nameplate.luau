--!strict
-- Overhead nameplates and floating station labels (2026-11-04).
-- Players: hero name (player attribute "CharacterName", Systems/Characters) + level above a thin
-- life bar (Humanoid health, the server's HP model in Systems/Combat) with the shield ("Shield"
-- player attribute) as a cyan strip on top. Roblox's own name/health overlay is switched off
-- (Systems/PlayerSetup).
-- Stations: hub parts tagged STATION_TAG carry a LABEL_ATTR ("Stash", "Forge", ...) that the
-- client floats above them while the player is in range (Systems/Hub, Client/NameplateController).
-- Pure rules and tunables; the client controller only builds and moves instances.

local Nameplate = {}

Nameplate.STATION_TAG = "Station" -- CollectionService tag on a hub station trigger part
Nameplate.LABEL_ATTR = "Label" -- string attribute: the floating text of a station
Nameplate.WINDOW_ATTR = "Window" -- string attribute: the window the station opens (quest waypoint)

Nameplate.TICK = 0.15 -- seconds between fade updates (cheap on phones)

-- Players (studs from the local character)
Nameplate.PLAYER_FAR = 70 -- fully gone at this distance (BillboardGui.MaxDistance culls beyond)
Nameplate.PLAYER_FADE = 15 -- fade band before PLAYER_FAR
Nameplate.PLAYER_OFFSET = 3.2 -- studs above the head
Nameplate.NAME_MAX = 16 -- characters (Profile.validName allows 3-16)

-- Stations
Nameplate.LABEL_NEAR = 10 -- hidden this close (the ProximityPrompt shows the name from 12 on)
Nameplate.LABEL_NEAR_FADE = 4 -- fade band after LABEL_NEAR
Nameplate.LABEL_FAR = 95 -- the hub is ~160 studs across: from the plaza every station is labelled
Nameplate.LABEL_FADE = 20
Nameplate.LABEL_OFFSET = 7 -- studs above the trigger part (above the stall roofs)
Nameplate.SUB_FAR = 45 -- the "Locked - ..." line only shows closer than this (less clutter)
Nameplate.SUB_FADE = 10
Nameplate.LABEL_GAP = 6 -- screen pixels kept between two labels and between a label and the HUD
Nameplate.DECLUTTER_STEP = 0.35 -- share of a full fade per tick when a label gives way / returns

local function finite(x: any): boolean
	return typeof(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Visibility 0..1 at `dist`: 0 closer than `near`, fades in over `nearFade`, full until the
-- `farFade` band before `far`, 0 from `far` on. NaN / bad input = hidden.
function Nameplate.alpha(
	dist: number,
	near: number,
	nearFade: number,
	far: number,
	farFade: number
): number
	if not finite(dist) or dist < 0 then
		return 0
	end
	local a = 1
	if nearFade > 0 then
		a = math.clamp((dist - near) / nearFade, 0, 1)
	elseif dist < near then
		a = 0
	end
	if farFade > 0 then
		a = math.min(a, math.clamp((far - dist) / farFade, 0, 1))
	elseif dist >= far then
		a = 0
	end
	return a
end

function Nameplate.playerAlpha(dist: number): number
	return Nameplate.alpha(dist, 0, 0, Nameplate.PLAYER_FAR, Nameplate.PLAYER_FADE)
end

function Nameplate.labelAlpha(dist: number): number
	return Nameplate.alpha(
		dist,
		Nameplate.LABEL_NEAR,
		Nameplate.LABEL_NEAR_FADE,
		Nameplate.LABEL_FAR,
		Nameplate.LABEL_FADE
	)
end

-- Visibility 0..1 of the "Locked - ..." line under a station label at `dist`
function Nameplate.subAlpha(dist: number): number
	return Nameplate.alpha(dist, 0, 0, Nameplate.SUB_FAR, Nameplate.SUB_FADE)
end

-- Screen rectangle { x0, y0, x1, y1 } (pixels)
export type Rect = { number }

local function overlaps(a: Rect, b: Rect, gap: number): boolean
	return a[1] < b[3] + gap and b[1] < a[3] + gap and a[2] < b[4] + gap and b[2] < a[4] + gap
end

-- Screen-space declutter for station labels: the labels are taken by priority (higher first, e.g.
-- the quest station, then the nearest); one that would overlap an already shown label or a HUD
-- block (`blocks`) gives way. A label without a rectangle (false: behind the camera) is never
-- shown.
-- Returns one boolean per entry of `rects`, in the same order.
function Nameplate.declutter(
	rects: { Rect | false },
	priority: { number },
	blocks: { Rect },
	gap: number
): { boolean }
	local order = {}
	for i = 1, #rects do
		if rects[i] then
			table.insert(order, i)
		end
	end
	table.sort(order, function(a: number, b: number): boolean
		local pa, pb = priority[a] or 0, priority[b] or 0
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	local shown: { boolean } = table.create(#rects, false)
	local taken: { Rect } = {}
	for _, i in order do
		local r = rects[i] :: any
		local free = true
		for _, b in blocks do
			if overlaps(r, b, gap) then
				free = false
				break
			end
		end
		if free then
			for _, t in taken do
				if overlaps(r, t, gap) then
					free = false
					break
				end
			end
		end
		if free then
			shown[i] = true
			table.insert(taken, r)
		end
	end
	return shown
end

-- Text under a locked station's name: the hint without a doubled "Locked"
function Nameplate.lockText(hint: string): string
	return "Locked · " .. hint
end

-- Bar fill 0..1 (life or shield over max life); bad numbers = empty
function Nameplate.fill(value: any, max: any): number
	if not finite(value) or not finite(max) or max <= 0 then
		return 0
	end
	return math.clamp(value / max, 0, 1)
end

-- Text shown for a player: the hero name, else the Roblox display name; trimmed and capped
function Nameplate.displayName(heroName: any, fallback: string): string
	local name = if typeof(heroName) == "string" then heroName else ""
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	if name == "" then
		name = fallback
	end
	if utf8.len(name) == nil then
		name = fallback -- invalid UTF-8 never reaches a TextLabel
	end
	if (utf8.len(name) or 0) > Nameplate.NAME_MAX then
		local cut = utf8.offset(name, Nameplate.NAME_MAX + 1)
		name = if cut then string.sub(name, 1, cut - 1) else name
	end
	return name
end

-- Level badge text ("" when unknown)
function Nameplate.levelText(level: any): string
	if not finite(level) or level < 1 then
		return ""
	end
	return tostring(math.floor(level))
end

-- Own plate: no name (the HUD shows it), the bar only while hurt or shielded
function Nameplate.showOwnBar(health: number, max: number, shield: number): boolean
	return Nameplate.fill(health, max) < 0.999 or Nameplate.fill(shield, max) > 0
end

-- Window a station part opens: the attribute, else the "Station_<window>" part name
function Nameplate.windowOf(part: Instance): string?
	local w = part:GetAttribute(Nameplate.WINDOW_ATTR)
	if typeof(w) == "string" and w ~= "" then
		return w
	end
	local name = string.match(part.Name, "^Station_(.+)$")
	return name
end

return Nameplate
