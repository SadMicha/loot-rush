--!strict
-- Enemy zones (anti exploit, 2026-11-03): every enemy belongs to one zone, the Rift Trail
-- clearing it spawned in or the boss arena. It never walks out of that zone, so a player
-- standing outside it (corridor, next clearing, another map) could hit it while it cannot hit
-- back. The server only lets damage through while the attacker stands inside the enemy's zone
-- (plus a small margin for the body and latency), and enemies heal back to full when nobody
-- has been inside their zone for a while (no hit-and-run from the edge).
-- Pure rules; Systems/Enemies writes the zone as attributes, Systems/Combat checks it.

local Leash = {}

Leash.MIN_ATTR = "ZoneMin" -- Vector3 attribute on the enemy model (world, flat)
Leash.MAX_ATTR = "ZoneMax"
Leash.MARGIN = 4 -- studs outside the zone that still count as inside (body, latency)
Leash.RESET_AFTER = 5 -- seconds with nobody in the zone before a hurt enemy heals to full

-- Is the flat position inside the box min..max, grown by `margin` (default Leash.MARGIN)?
function Leash.inside(pos: Vector3, min: Vector3, max: Vector3, margin: number?): boolean
	local m = margin or Leash.MARGIN
	if pos.X ~= pos.X or pos.Z ~= pos.Z then -- NaN never counts
		return false
	end
	return pos.X >= min.X - m and pos.X <= max.X + m and pos.Z >= min.Z - m and pos.Z <= max.Z + m
end

-- Zone of an enemy model (nil when it has none, e.g. a model built by hand in a test)
function Leash.zoneOf(enemy: Instance): (Vector3?, Vector3?)
	local lo = enemy:GetAttribute(Leash.MIN_ATTR)
	local hi = enemy:GetAttribute(Leash.MAX_ATTR)
	if typeof(lo) == "Vector3" and typeof(hi) == "Vector3" then
		return lo, hi
	end
	return nil, nil
end

-- May an attacker standing at `pos` hurt this enemy? Enemies without a zone stay hittable.
function Leash.canHit(pos: Vector3?, enemy: Instance): boolean
	local lo, hi = Leash.zoneOf(enemy)
	if not lo or not hi then
		return true
	end
	if not pos then
		return false
	end
	return Leash.inside(pos, lo, hi)
end

return Leash
