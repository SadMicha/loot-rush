--!strict
-- Every game sound in one place (docs/DECISIONS.md §4).
--   Hooks    one-shots by game moment (SoundController.play, UI through Shape.sound)
--   Ambience looped bed per place (Shared/Looks `ambience` key, AmbienceController) and the
--            positional loops in the Hub (`waterfall`, `forge`, Systems/Hub)
--   Music    one track per mood (MusicController)
-- Ids are Creator Store audio ("rbxassetid://<id>"). Almost all come from the libraries Roblox
-- licensed for every experience (@ProSoundEffects sound effects, @APMOfficial music, the old
-- Roblox uploads); the few community uploads are marked. An empty id stays silent, a failed load
-- only warns once (SoundController), nothing errors. To swap a sound, change only the id here.
--
-- Fields: volume 0-1 before the player's channel volume (Client/Audio); pitch = random ± share
-- so repeats do not sound robotic; speed = base playback speed (pitches the whole clip);
-- gap = minimum seconds between two plays of the hook; voices = pooled Sound instances
-- (how many may overlap); channel = Client/Audio volume channel.

export type Channel = "sfx" | "ui"
export type Sound = {
	id: string,
	volume: number,
	pitch: number,
	speed: number,
	gap: number,
	voices: number,
	channel: Channel,
}
export type Loop = { id: string, volume: number }

type Opts = { pitch: number?, speed: number?, gap: number?, voices: number?, ui: boolean? }

local function id(n: number): string
	return "rbxassetid://" .. tostring(n)
end

local function s(asset: number, volume: number, o: Opts?): Sound
	local opts: Opts = o or {}
	return table.freeze({
		id = id(asset),
		volume = volume,
		pitch = opts.pitch or 0.08,
		speed = opts.speed or 1,
		gap = opts.gap or 0.04,
		voices = opts.voices or 2,
		channel = if opts.ui then "ui" else "sfx",
	} :: Sound)
end

local function loop(asset: number, volume: number): Loop
	return table.freeze({ id = id(asset), volume = volume })
end

local Sounds = {}

-- Default volume per Client/Audio channel (the settings window changes them per player)
Sounds.DEFAULT_VOLUME = table.freeze({
	master = 1,
	music = 0.6,
	sfx = 1,
	ambience = 1,
	ui = 1,
})

Sounds.Hooks = table.freeze({
	-- Own combat
	attack = s(9119749145, 0.25, { pitch = 0.12, gap = 0.08, voices = 3 }), -- Sword Swish 102: basic melee swing
	attack_shot = s(9114444328, 0.18, { pitch = 0.12, speed = 1.3, gap = 0.08, voices = 3 }), -- Fire Whoosh 10: basic ranged shot
	hit = s(9118628948, 0.3, { pitch = 0.12, gap = 0.05, voices = 4 }), -- Rock Impacts 13: own hit on a brick enemy
	crit = s(9113964719, 0.45, { gap = 0.06, voices = 3 }), -- Cracky Punch 1
	kill = s(9119049084, 0.4, { pitch = 0.1, gap = 0.05, voices = 4 }), -- Shale Break 2: brick shatter
	kill_big = s(9114224800, 0.7, { pitch = 0.04, gap = 0.3 }), -- Earthquake Explosion 2: boss/elite shatter
	dodge = s(9113318154, 0.4, { gap = 0.1 }), -- Baseball Swish 2
	cast_projectile = s(9114444008, 0.4), -- Fire Whoosh 3
	cast_nova = s(9116384799, 0.45), -- Magic Burst 2
	cast_chain = s(9116273112, 0.35), -- Lightning Flashes Quick Electrical Bursts 19
	cast_arc = s(9119749822, 0.45), -- Sword Swishes 1
	cast_leap = s(9113081793, 0.5), -- Airy Whoosh Blast 4
	cast_zone = s(9120705982, 0.45), -- Whoosh Explosion 1
	cast_buff = s(9126073011, 0.45, { pitch = 0.02 }), -- Synth Sparkle Tone High Pitch Bell Tone Ding
	-- Taking damage
	hurt = s(9113511616, 0.45, { gap = 0.15 }), -- Body Hit Slap 5: the local player takes damage
	blocked = s(9116673068, 0.4, { pitch = 0.05, gap = 0.1 }), -- Metal Impact Dropping Clanky Piece 12: "Dodged" / "Blocked" / "Shield"
	death = s(9125651607, 0.6, { pitch = 0, gap = 1 }), -- Male Scream Short Yelling Bursts Death Cries
	-- Enemies (only near the player, see SoundController)
	telegraph = s(9126284289, 0.22, { speed = 0.7, pitch = 0.06, gap = 0.25 }), -- Wood Swish Ruler Whoosh: a danger zone appears
	boss_intro = s(9113985604, 0.7, { pitch = 0, gap = 2 }), -- Creature Roar Mix Of Animals Gate Creaks 1
	boss_phase = s(9125470501, 0.75, { pitch = 0, gap = 1 }), -- Creature Growls Lion Deep Guttural Rumbling
	boss_break = s(9114224800, 0.65, { pitch = 0.03, speed = 1.2, gap = 0.5 }), -- Earthquake Explosion 2, higher: a boss is Broken
	counter = s(9113964719, 0.5, { pitch = 0.05, speed = 1.25, gap = 0.2 }), -- Cracky Punch 1, higher: own Counter
	area_clear = s(9126073011, 0.4, { pitch = 0.02, speed = 0.9, gap = 0.5 }), -- Synth Sparkle Bell Tone Ding, lower: a trail area is clear
	-- Loot (own drops only)
	loot_normal = s(9120907213, 0.18, { pitch = 0.15, gap = 0.08 }), -- Wood Impact 2
	loot_gold = s(1169755927, 0.22, { pitch = 0.15, gap = 0.08 }), -- Coin Collect - SFX (@Everyedit, community upload, marked free to use)
	loot_magic = s(9120156870, 0.35, { pitch = 0.04, gap = 0.08 }), -- Tone Clusters Mostly High Pitch Tones 28
	loot_rare = s(9119834605, 0.45, { pitch = 0.03, gap = 0.1 }), -- Synth Sparkle Tone High Pitch Tone Burst 10
	loot_epic = s(9126072433, 0.55, { pitch = 0.02, gap = 0.15 }), -- Synth Sparkle Tone High Pitch Bell Tone Burst
	loot_unique = s(9125601934, 0.6, { pitch = 0, gap = 0.3 }), -- Heavenly Harmonic Presence Choral Ethereal
	loot_legend = s(9125601934, 0.7, { pitch = 0, speed = 0.85, gap = 0.3 }), -- same choir, lower
	pickup = s(9120156870, 0.25, { speed = 1.25, pitch = 0.06, gap = 0.05 }), -- Tone Clusters 28, higher
	pickup_gold = s(1169755927, 0.3, { pitch = 0.1, gap = 0.05 }), -- Coin Collect - SFX
	-- Progress and moments
	level_up = s(12222253, 0.6, { pitch = 0, gap = 1 }), -- victory.wav (Roblox)
	rush = s(9116410978, 0.6, { pitch = 0, gap = 1 }), -- Magic Swoosh Fast Zooming Pass Bys 7: Stud Rush starts
	rift_clear = s(12222253, 0.55, { pitch = 0, speed = 0.9, gap = 1 }), -- victory.wav, lower: boss of a depth down
	purchase = s(9125594507, 0.45, { pitch = 0, gap = 0.3, ui = true }), -- Graphic Tings Sharp Metallic Hits Tonal Ring
	forge = s(9116675065, 0.45, { gap = 0.2, ui = true }), -- Metal Impact Railroad Hammer 6
	hatch = s(9126072433, 0.5, { pitch = 0, speed = 0.9, gap = 0.3, ui = true }), -- Synth Sparkle Bell Tone Burst
	-- UI (client/UI/Shape.sound)
	ui_click = s(9114479860, 0.35, { pitch = 0.05, gap = 0.05, ui = true }), -- Flashlight On Off Clicks 5
	ui_open = s(9126284289, 0.2, { speed = 1.25, pitch = 0.03, gap = 0.1, ui = true }), -- Wood Swish Ruler Whoosh
	ui_close = s(9126284289, 0.16, { speed = 0.95, pitch = 0.03, gap = 0.1, ui = true }), -- same, lower
	ui_reward = s(9126073011, 0.4, { pitch = 0.02, gap = 0.2, ui = true }), -- Synth Sparkle Bell Tone Ding
} :: { [string]: Sound })

Sounds.Ambience = table.freeze({
	hub = loop(9112742473, 0.3), -- Asylum Birds 1: peaceful daytime birds
	meadow = loop(9112781510, 0.35), -- Forest Ambience 1: wind in trees, distant birds
	cave = loop(9112775175, 0.4), -- Eerie Ambience 1: slow rumbly presence
	swamp = loop(9112808170, 0.3), -- Jungle Frogs 1: frogs, insects
	lava = loop(9125351660, 0.4), -- Afterworld Ambience Weird Rumbling Ambience
	wind = loop(9125515917, 0.35), -- Eastern Wind Constant Resonant Humming Ambience
	rift = loop(9125351660, 0.3), -- Afterworld Ambience (shared with lava, quieter)
	-- Positional loops in the Hub (Systems/Hub, heard within EMITTER_RANGE studs)
	waterfall = loop(9120549564, 0.5), -- Waterfall Background Water Roar 1
	forge = loop(9112780462, 0.45), -- Fireplace Constant Burning Flame 4
} :: { [string]: Loop })

Sounds.EMITTER_RANGE = 70 -- studs until a positional Hub loop is silent

Sounds.Music = table.freeze({
	hub = loop(1845306767, 0.3), -- Medieval Times (APM): gentle, relaxed theme
	rift = loop(1843109962, 0.25), -- Battle Scars (APM, Fantasy Adventure): brass and strings
	boss = loop(1840955854, 0.3), -- Sword Of Darkness (A) (APM, Overkill): orchestral hybrid
} :: { [string]: Loop })

-- Loot drop sound per item rarity (unknown rarities fall back to magic)
function Sounds.lootHook(rarity: string?): string
	if rarity == nil then
		return "loot_gold"
	end
	local name = "loot_" .. rarity
	return if Sounds.Hooks[name] then name else "loot_magic"
end

return table.freeze(Sounds)
