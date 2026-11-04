-- Layout matrix: every window and HUD state on real device profiles (notch / home bar safe area,
-- Roblox buttons top left) at the HUD sizes of the Settings window. Nothing may stick out of the
-- screen or the safe area, overlap, run under the Roblox buttons or other layers' buttons, or have
-- text behind other text. Full matrix with pictures: lune run tools/lune/matrix (report + HTML).
-- A cut of the devices keeps CI fast: smallest phone, notched phone, tablet, desktop; XS, M, XL.
local DEVICES = { "iphone-se", "iphone", "ipad", "desktop" }
local SCALES = { 0.8, 1.2 }
local SCREENS = {
	"setup",
	"hud",
	"hud-combat",
	"boss",
	"rift-clear",
	"inventory",
	"inventory-compare",
	"stash",
	"skills",
	"skills-stones",
	"star-net",
	"forge",
	"atlas",
	"pets",
	"shop",
	"market",
	"settings",
	"switch-hero",
	"daily",
	"leaderboard",
	"journey",
	"season",
	"great-build",
}

-- one run for all screens while the spec loads (they share a stocked sandbox of their own), then
-- one test result per screen
local result = matrix(SCREENS, DEVICES, SCALES)

describe("Layout matrix", function()
	for _, screen in SCREENS do
		it(screen, function()
			local lines = result[screen]
			if #lines > 0 then
				error(table.concat(lines, "\n"), 2)
			end
		end)
	end
end)
