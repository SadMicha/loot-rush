--!strict
-- Release notes shown in the game ("What's New" window, Client/Controllers/ChangelogController;
-- Settings → About shows the newest version). The single source for every live release:
-- docs/PUBLISH.md "Release flow".
--
-- New release: add an entry at the TOP with `build` one higher than the previous one. Players who
-- saw an older build get the window once on their next join; brand-new players don't.
--   build    whole number, +1 per live release (the seen-marker in the player's settings)
--   version  shown to players ("1.0 Beta", "1.1" …)
--   date     "YYYY-MM-DD" of the live release
--   title    one short headline
--   notes    3-8 player-facing lines, each under ~90 characters

local Changelog = {}

export type Release = {
	build: number,
	version: string,
	date: string,
	title: string,
	notes: { string },
}

Changelog.MAX_NOTE = 90 -- characters per line (fits two rows on a phone)

Changelog.Releases = table.freeze({
	{
		build = 1,
		version = "1.0 Beta",
		date = "2026-11-05",
		title = "The Beta Season begins",
		notes = {
			"Four heroes to pick from: Brix, Fynn, Zap and Mora, each with their own skills.",
			"Dive into Rifts, beat the bosses and push deeper for better loot.",
			"Build your hero with the Star Web, the Forge and pets.",
			"Help raise the Beta Beacon together with every player.",
			"Daily rewards, a leaderboard and gear skins to collect.",
		},
	},
} :: { Release })

-- The newest release (top of the list)
function Changelog.latest(): Release
	return Changelog.Releases[1]
end

-- Releases newer than `seenBuild`, newest first
function Changelog.since(seenBuild: number): { Release }
	local out: { Release } = {}
	for _, r in Changelog.Releases do
		if r.build > seenBuild then
			table.insert(out, r)
		end
	end
	return out
end

return Changelog
