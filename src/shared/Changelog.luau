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
		build = 3,
		version = "1.0.2 Beta",
		date = "2026-11-06",
		title = "Resizable window and fresh colours",
		notes = {
			"Resize the game window any time: the UI and text now follow right away.",
			"Crystal Caves glows violet, and the Mushroom Swamp is a green bog again.",
			"The Rift title no longer runs under the Leave button.",
			"Loot for an empty gear slot is equipped at once.",
			"The equip quest finishes when your hero already wears gear.",
		},
	},
	{
		build = 2,
		version = "1.0.1 Beta",
		date = "2026-11-06",
		title = "Phone-ready windows and richer worlds",
		notes = {
			"Lock your favorite items so they are never salvaged by accident.",
			"Salvage all downgrades in one tap; auto-salvage now keeps your upgrades.",
			"Every window fits small phones: Inventory, Atlas, Shop, Skills, Forge and more.",
			"Each region has its own horizon, and the hub has farms, a road and a stream.",
			"Rift rooms are more varied, with bends, landmarks and no dead ends.",
			"Armor looks right on every hero; Crystal Caves and Sky Islands got new lighting.",
			"Clearer item comparison card, and Star Web mouse dragging works again.",
			"New What's New window: open it any time from Settings.",
		},
	},
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
