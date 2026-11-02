--!strict
-- Combat sound hooks (docs/DECISIONS.md §4): one entry per game moment. Paste a Creator Store
-- audio id ("rbxassetid://<id>") into `id`; an empty id stays silent, so the game runs without
-- any audio. SoundController plays them; `pitch` adds random variation (± share) so repeated
-- hits do not sound robotic. Ambience loops live in Assets.Sound (AmbienceController).

export type Sound = { id: string, volume: number, pitch: number }

local function s(volume: number, pitch: number?): Sound
	return table.freeze({ id = "", volume = volume, pitch = pitch or 0.08 })
end

return table.freeze({
	hit = s(0.35, 0.12), -- own hit on an enemy
	crit = s(0.5),
	kill = s(0.45, 0.1), -- brick shatter
	kill_big = s(0.8, 0.04), -- boss or elite shatter
	hurt = s(0.5), -- the local player takes damage
	dodge = s(0.4), -- dodge roll
	blocked = s(0.4, 0.05), -- "Dodged" / "Blocked" / "Shield"
	cast_projectile = s(0.4),
	cast_nova = s(0.5),
	cast_chain = s(0.45),
	cast_arc = s(0.45),
	cast_leap = s(0.5),
	cast_zone = s(0.45),
	cast_buff = s(0.5, 0.02),
	level_up = s(0.7, 0),
	boss_phase = s(0.8, 0),
	boss_intro = s(0.8, 0),
} :: { [string]: Sound })
