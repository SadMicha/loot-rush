--!strict
-- All RemoteEvents in one place. The server creates them, the client waits for them.
--   CastSkill (C→S): slot: number, aim: Vector3, origin: Vector3 (client position)
--   Dash      (C→S): report for invulnerability, server counts its own charges
--   Fx        (S→C): kind: string, data: table (see Types.luau)
--   Inv       (S→C): { items: { Item }, equipped: { [slot]: Item } }
--   Equip     (C→S): itemId: string · Unequip (C→S): slot: string · Sell (C→S): itemId: string
--   Rift      (C→S): action: "enter" | "deeper" | "leave" | "tier" (arg: World Tier number) - state comes via player attributes (Types.luau)
--   RiftResult (S→C): RiftRun.Summary - after every boss (kind "clear") and at the end of the run (kind "end")
--   Progress  (S→C): { progress: Progression.Data, materials: Progression.Materials }
--   Bloom     (C→S): action: "spend" | "reset", skillId: string, key: string? (Skill Bloom)
--   Star      (C→S): action: "alloc" | "remove" | "reset", starId: string? (Star Net)
--   ForgeAct  (C→S): actionId: string, itemId: string, affix: number? (Forge)
--   ForgeResult (S→C): { ok, text, itemId?, used? } - Forge feedback
--   Buy       (C→S): offerId: string - in-game purchase in the shop (Systems/Shop)
--   ShopResult (S→C): { ok, text, offerId? } - shop feedback
--   Pet       (C→S): action: "hatch" | "equip" | "unequip", id: string (egg or pet ID)
--   Pets      (S→C): { owned, equipped, slots, odds } - pet state (Shared/Pets);
--                    odds = { [eggId]: { { rarity, percent } } } from Pets.odds (odds before purchase)
--   PetResult (S→C): { ok, text, kind, pet?, level?, shards? } - feedback (hatching, equipping);
--                    kind = "hatch" | "equip" | "unequip" (the request it answers)
--   Class     (C→S): "choose", classId - pick/change the class (first join, or in the hub)
--   Quest     (S→C): { step, count, target, text?, unlocks } - active onboarding quest (Shared/Quests);
--                    events: { done = { questText }, unlocked = { windowId } } on progress
--   AutoSalvage (C→S): rarity: string ("" = off) - loot up to it is salvaged on pickup
--   Loadout   (C→S): "equip", slot: number, skillId: string | "auto", skillId: string, on: boolean
--   SkillCast (S→C): skillId: string, cooldown: number - a skill fired (manual or auto-cast)
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
	"Pet",
	"Pets",
	"PetResult",
	"Quest",
	"Class",
	"AutoSalvage",
	"Loadout",
	"SkillCast",
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
	Pet = get("Pet"),
	Pets = get("Pets"),
	PetResult = get("PetResult"),
	Quest = get("Quest"),
	Class = get("Class"),
	AutoSalvage = get("AutoSalvage"),
	Loadout = get("Loadout"),
	SkillCast = get("SkillCast"),
	Debug = get("Debug"),
})
