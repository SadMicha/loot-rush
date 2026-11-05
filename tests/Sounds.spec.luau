-- Sound config: every hook the game plays exists with a valid asset id and sane values, and the
-- controllers run without errors.
local Looks = require("ReplicatedStorage.Shared.Looks")
local Skills = require("ReplicatedStorage.Shared.Skills")
local Sounds = require("ReplicatedStorage.Shared.Sounds")

local PLAYED = {
	"attack",
	"attack_shot",
	"hit",
	"crit",
	"kill",
	"kill_big",
	"dodge",
	"hurt",
	"blocked",
	"death",
	"telegraph",
	"boss_intro",
	"boss_phase",
	"boss_break",
	"counter",
	"area_clear",
	"pickup",
	"pickup_gold",
	"level_up",
	"rush",
	"rift_clear",
	"purchase",
	"forge",
	"hatch",
	"cosmetic_equip",
	"cosmetic_equip_legend",
	"ui_click",
	"ui_open",
	"ui_close",
	"ui_reward",
}

local function validId(id: string): boolean
	return id:match("^rbxassetid://%d+$") ~= nil
end

describe("Sounds", function()
	it("cover every skill kind and every played moment", function()
		for _, skill in Skills.ById do
			expect(Sounds.Hooks["cast_" .. skill.kind]).never.toBeNil()
		end
		for _, name in PLAYED do
			expect(Sounds.Hooks[name]).never.toBeNil()
		end
	end)

	it("have valid ids and values", function()
		for _, def in Sounds.Hooks do
			expect(validId(def.id)).toBe(true)
			expect(def.volume > 0 and def.volume <= 1).toBe(true)
			expect(def.pitch >= 0 and def.pitch < 0.5).toBe(true)
			expect(def.speed > 0.3 and def.speed < 3).toBe(true)
			expect(def.gap >= 0).toBe(true)
			expect(def.voices >= 1 and def.voices <= 6).toBe(true)
			expect(def.channel == "sfx" or def.channel == "ui").toBe(true)
		end
		for _, set in { Sounds.Ambience, Sounds.Music } do
			for _, def in set do
				expect(validId(def.id)).toBe(true)
				expect(def.volume > 0 and def.volume <= 1).toBe(true)
			end
		end
	end)

	it("have an ambience loop for every place and music for every mood", function()
		expect(Sounds.Ambience[Looks.Hub.ambience]).never.toBeNil()
		for _, look in Looks.Regions do
			if look.ambience then
				expect(Sounds.Ambience[look.ambience]).never.toBeNil()
			end
		end
		for _, mood in { "hub", "rift", "boss" } do
			expect(Sounds.Music[mood]).never.toBeNil()
		end
	end)

	it("pick a loot sound for every rarity", function()
		expect(Sounds.lootHook(nil)).toBe("loot_gold")
		for _, rarity in { "normal", "magic", "rare", "epic", "unique", "legend" } do
			expect(Sounds.Hooks[Sounds.lootHook(rarity)]).never.toBeNil()
		end
		expect(Sounds.lootHook("nonsense")).toBe("loot_magic")
	end)

	it("play, throttle and change volume in game without errors", function()
		sim:boot({ seconds = 2 })
		local first, second, unknown = false, true, true
		local volume, clamped, nan = 0, 0, true
		sim:runAs("client", function(req)
			local SoundController =
				req("StarterPlayer.StarterPlayerScripts.Client.Controllers.SoundController")
			local Audio = req("StarterPlayer.StarterPlayerScripts.Client.Audio")
			first = SoundController.play("level_up")
			second = SoundController.play("level_up") -- inside its gap
			unknown = SoundController.play("no_such_sound")
			Audio.setVolume("music", 0.25)
			volume = Audio.group("music").Volume
			Audio.setVolume("sfx", 4)
			clamped = Audio.getVolume("sfx")
			nan = Audio.setVolume("ui", 0 / 0)
			Audio.setMuted(true)
		end)
		expect(first).toBe(true)
		expect(second).toBe(false)
		expect(unknown).toBe(false)
		expect(volume).toBe(0.25)
		expect(clamped).toBe(1)
		expect(nan).toBe(false)
		sim:run(1)
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)
