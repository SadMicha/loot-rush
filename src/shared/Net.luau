--!strict
-- All RemoteEvents in one place. The server creates them, the client waits for them.
--   CastSkill (C→S): slot: number, aim: Vector3, origin: Vector3 (client position)
--   Dash      (C→S): report for invulnerability, server counts its own charges
--   Fx        (S→C): kind: string, data: table (see Types.luau)
--   Inv       (S→C): { items: { Item }, equipped: { [slot]: Item }, capacity: number, level: number }
--                    capacity = bag slots (Shared/Bag), level = bag upgrade level
--   Equip     (C→S): itemId: string · Unequip (C→S): slot: string · Sell (C→S): itemId: string
--   Rift      (C→S): action: "enter" (region id, start depth?) | "deeper" (Path Card 1-3, nil = safe card) | "leave" | "tier" (World Tier number) - state comes via player attributes (Types.luau)
--   RiftResult (S→C): RiftRun.Summary - after every boss (kind "clear") and at the end of the run (kind "end")
--   Progress  (S→C): { progress: Progression.Data, materials: Progression.Materials }
--   Bloom     (C→S): action: "spend" | "reset", skillId: string, key: string? (Skill Bloom)
--   Star      (C→S): action: "alloc" | "remove" | "reset", starId: string? (Star Web)
--   ForgeAct  (C→S): actionId: string, itemId: string, affix: number? (Forge)
--   ForgeResult (S→C): { ok, text, itemId?, used? } - Forge feedback
--   Buy       (C→S): offerId: string - in-game purchase in the shop (Systems/Shop)
--   ShopResult (S→C): { ok, text, offerId?, robux? } - shop feedback; robux = true for a booked
--                    Robux purchase (offerId = Shared/Store offer id, the Shop window celebrates)
--   Wear      (C→S): slot: string, cosmeticId: string ("" = take off) - Systems/Cosmetics
--   Store     (S→C): { cosmetics = { id }, wear = { [slot]: id }, bought = { key } } - Robux shop state
--   Skin      (C→S): "buy", kind ("skin" | "set" | "cosmetic"), id - Soulstar purchase in the
--                    Daily Shop or the season shop (Systems/GearSkins checks rotation and season) |
--                    "wear", slot, skinId ("" = class look) | "sync"
--   SkinState (S→C): { owned = { skinId }, wear = { [slot]: skinId }, unlocked? = { skinId },
--                    result? = { ok, text, kind?, id? } } - gear skins of the account
--   Pet       (C→S): action: "hatch" | "equip" | "unequip", id: string (egg or pet ID)
--   Pets      (S→C): { owned, equipped, slots, odds } - pet state (Shared/Pets);
--                    odds = { [eggId]: { { rarity, percent } } } from Pets.odds (odds before purchase)
--   PetResult (S→C): { ok, text, kind, pet?, level?, shards? } - feedback (hatching, equipping);
--                    kind = "hatch" | "equip" | "unequip" (the request it answers)
--   Character (C→S): "list" | "setup", name, classId | "create", name, classId | "play", characterId
--                    (Systems/Characters: first-join setup, new characters, switching)
--   Characters (S→C): { active, max, list = { { id, name, class, level, league } } }
--   CharacterResult (S→C): { ok, text, action } - feedback for a Character request
--   Quest     (S→C): { step, count, target, text?, unlocks } - active onboarding quest (Shared/Quests);
--                    events: { done = { questText }, unlocked = { windowId } } on progress
--   Bag       (C→S): "upgrade", level: number - buy that bag level (must be the next one; Shared/Bag,
--                    Systems/Inventory). Player attributes BagLevel / BagMax carry the state.
--   BagResult (S→C): { ok, text, level, capacity, price? } - upgrade feedback (price = gold paid)
--   AutoSalvage (C→S): rarity: string ("" = off) - loot up to it is salvaged on pickup
--   Loadout   (C→S): "equip", slot: number, skillId: string | "auto", skillId: string, on: boolean
--   SkillCast (S→C): skillId: string, cooldown: number - a skill fired (manual or auto-cast)
--   SkillCooldown (S→C): { [skillId]: secondsLeft } - running cooldowns got shorter (Shared/Momentum)
--   Setting   (C→S): key: string, value: number | boolean | string - one setting (Shared/Settings)
--   Settings  (S→C): Settings.Data - the saved settings of the account, sent once after loading
--   Daily     (C→S): "claim" - claim today's daily reward (Systems/Daily; the server picks the day)
--   DailyState (S→C): { claimed, index, canClaim, secondsLeft, rewards = { Daily.Reward × 7 },
--                    paid? } - calendar state; paid = calendar index just claimed
--   Board     (C→S): boardId: string - ask for one leaderboard page (Shared/Leaderboard ids)
--   BoardData (S→C): Leaderboard.Page - top entries + the asking player's own best
--   Journey   (C→S): "claim", milestoneId: string | "sync" - claim a finished milestone (Systems/Journey)
--   JourneyState (S→C): { facts = Journey.Facts, claimed = { milestoneId }, paid? } - hero milestones
--   Season    (C→S): "claim", step: number | "sync" - claim a reward of the season track (Systems/Seasons)
--   SeasonState (S→C): { id, phase, secondsLeft, counts = { [challengeId] = n }, claimed = { step },
--                    paid?, finished? = { challengeId } } - Season Journey state
--   Stash     (C→S): "open" | "put", itemId: string, tab: number | "take", itemId: string |
--                    "all", tab: number - hub stash (Systems/Stash, only near the stash station)
--   StashData (S→C): { tabs = { { Item } }, slots, text? } - stash contents; text = why a move failed
--   GreatBuild (C→S): "donate", amount: number | "sync" - Great Build donation (Systems/GreatBuild,
--                    only at the donation chute in the hub)
--   GreatBuildState (S→C): { total, stages, bonus = { items, gold, xp }, mine = { total, today,
--                    left, paid }, shards,
--                    top = { { name, amount, me } }, shared, donated?, text?, paid? = { amount } }
--   Debug     (C→S): command: string, value: number? - test commands, Studio/DEV_USERS only (Systems/Debug)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"CastSkill",
	"Dash",
	"Fx",
	"Inv",
	"Equip",
	"Unequip",
	"Sell",
	"Rift",
	"RiftResult",
	"Progress",
	"Bloom",
	"Star",
	"ForgeAct",
	"ForgeResult",
	"Buy",
	"ShopResult",
	"Wear",
	"Store",
	"Skin",
	"SkinState",
	"Pet",
	"Pets",
	"PetResult",
	"Quest",
	"Character",
	"Characters",
	"CharacterResult",
	"AutoSalvage",
	"Bag",
	"BagResult",
	"Loadout",
	"SkillCast",
	"SkillCooldown",
	"Setting",
	"Settings",
	"Daily",
	"DailyState",
	"Board",
	"BoardData",
	"Journey",
	"JourneyState",
	"Season",
	"SeasonState",
	"Stash",
	"StashData",
	"GreatBuild",
	"GreatBuildState",
	"Debug",
}

local folder: Instance
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return table.freeze({
	CastSkill = get("CastSkill"),
	Dash = get("Dash"),
	Fx = get("Fx"),
	Inv = get("Inv"),
	Equip = get("Equip"),
	Unequip = get("Unequip"),
	Sell = get("Sell"),
	Rift = get("Rift"),
	RiftResult = get("RiftResult"),
	Progress = get("Progress"),
	Bloom = get("Bloom"),
	Star = get("Star"),
	ForgeAct = get("ForgeAct"),
	ForgeResult = get("ForgeResult"),
	Buy = get("Buy"),
	ShopResult = get("ShopResult"),
	Wear = get("Wear"),
	Store = get("Store"),
	Skin = get("Skin"),
	SkinState = get("SkinState"),
	Pet = get("Pet"),
	Pets = get("Pets"),
	PetResult = get("PetResult"),
	Quest = get("Quest"),
	Character = get("Character"),
	Characters = get("Characters"),
	CharacterResult = get("CharacterResult"),
	AutoSalvage = get("AutoSalvage"),
	Bag = get("Bag"),
	BagResult = get("BagResult"),
	Loadout = get("Loadout"),
	SkillCast = get("SkillCast"),
	SkillCooldown = get("SkillCooldown"),
	Setting = get("Setting"),
	Settings = get("Settings"),
	Daily = get("Daily"),
	DailyState = get("DailyState"),
	Board = get("Board"),
	BoardData = get("BoardData"),
	Journey = get("Journey"),
	JourneyState = get("JourneyState"),
	Season = get("Season"),
	SeasonState = get("SeasonState"),
	Stash = get("Stash"),
	StashData = get("StashData"),
	GreatBuild = get("GreatBuild"),
	GreatBuildState = get("GreatBuildState"),
	Debug = get("Debug"),
})
