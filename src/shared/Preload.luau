--!strict
-- Pure list of every asset the game shows or plays, in preload order (Client/Controllers/
-- PreloadController feeds it to ContentProvider while the loading screen is up).
-- Order: images the HUD and windows paint first, then sounds, then animations. Entries are
-- deduplicated; empty ids and non-uploaded content (rbxasset://, no id) are dropped.
-- Weapon Model assets are not listed: the server inserts them and their mesh ids are unknown here.

local Assets = require(script.Parent.UI.Assets)
local Sounds = require(script.Parent.Sounds)
local Weapons = require(script.Parent.Weapons)

export type Kind = "image" | "sound" | "animation"
export type Entry = { id: string, kind: Kind }

local Preload = {}

Preload.BATCH_SIZE = 24 -- ids per PreloadAsync call: small enough that one stuck id costs one batch

function Preload.valid(id: any): boolean
	return typeof(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil
end

-- Every distinct asset, images first (HUD before windows), then sounds, then animations
function Preload.collect(): { Entry }
	local seen: { [string]: boolean } = {}
	local images: { Entry } = {}
	local sounds: { Entry } = {}
	local animations: { Entry } = {}
	local function add(kind: Kind, id: any)
		if Preload.valid(id) and not seen[id] then
			seen[id] = true
			local list = if kind == "image"
				then images
				elseif kind == "sound" then sounds
				else animations
			table.insert(list, { id = id :: string, kind = kind })
		end
	end
	-- Groups of { id } records, in the order the player sees them
	for _, group in
		{
			Assets.Hud,
			Assets.Fixed,
			Assets.Slice,
			Assets.IconImage,
			Assets.Icon,
			Assets.Class,
			Assets.Art,
		} :: { any }
	do
		local names: { string } = {}
		for name in group do
			table.insert(names, name)
		end
		table.sort(names) -- stable order between runs
		for _, name in names do
			add("image", group[name].id)
		end
	end
	for _, w in Assets.Weapon do
		add("image", w.texture)
	end
	for _, id in Assets.Vfx do
		add("image", id)
	end
	for _, group in { Sounds.Hooks, Sounds.Ambience, Sounds.Music } :: { any } do
		local names: { string } = {}
		for name in group do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			add("sound", group[name].id)
		end
	end
	for _, id in Weapons.HOLD_ANIM :: { [string]: string } do
		add("animation", id)
	end
	local out: { Entry } = {}
	for _, list in { images, sounds, animations } do
		for _, entry in list do
			table.insert(out, entry)
		end
	end
	return out
end

-- Splits entries into batches of at most `size` that never mix kinds (each kind needs its own
-- Instance type for the engine), keeping the order
function Preload.batches(entries: { Entry }, size: number?): { { Entry } }
	local limit = math.max(1, math.floor(size or Preload.BATCH_SIZE))
	local out: { { Entry } } = {}
	local current: { Entry } = {}
	for _, entry in entries do
		if #current >= limit or (#current > 0 and current[1].kind ~= entry.kind) then
			table.insert(out, current)
			current = {}
		end
		table.insert(current, entry)
	end
	if #current > 0 then
		table.insert(out, current)
	end
	return out
end

-- Temporary content instances for one batch, the form PreloadAsync really loads: an ImageLabel per
-- image, a Sound per sound, an Animation per animation (plain id strings report Failure even for
-- good ids). Not parented; the caller destroys them.
function Preload.instances(batch: { Entry }): { Instance }
	local out: { Instance } = {}
	for _, entry in batch do
		if entry.kind == "image" then
			local image = Instance.new("ImageLabel")
			image.Image = entry.id
			table.insert(out, image)
		elseif entry.kind == "sound" then
			local snd = Instance.new("Sound")
			snd.SoundId = entry.id
			table.insert(out, snd)
		else
			local anim = Instance.new("Animation")
			anim.AnimationId = entry.id
			table.insert(out, anim)
		end
	end
	return out
end

return table.freeze(Preload)
