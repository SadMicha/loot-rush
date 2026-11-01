--!strict
-- All RemoteEvents in one place. The server creates them, the client waits for them.
--   CastSkill (C→S): slot: number, aim: Vector3, origin: Vector3 (client position)
--   Dash      (C→S): report for invulnerability, server counts its own charges
--   Fx        (S→C): kind: string, data: table (see Types.luau)
--   Inv       (S→C): { items: { Item }, equipped: { [slot]: Item } }
--   Equip     (C→S): itemId: string · Unequip (C→S): slot: string · Sell (C→S): itemId: string
--   Rift      (C→S): action: "enter" | "deeper" | "leave" - state comes via player attributes (Types.luau)
--   RiftResult (S→C): RiftRun.Summary - after every boss (kind "clear") and at the end of the run (kind "end")
--   Progress  (S→C): { progress: Progression.Data, materials: Progression.Materials }
--   Bloom     (C→S): action: "spend" | "reset", skillId: string, key: string? (Skill Bloom)
--   Star      (C→S): action: "alloc" | "remove" | "reset", starId: string? (Star Net)
--   ForgeAct  (C→S): actionId: string, itemId: string, affix: number? (Forge)
--   ForgeResult (S→C): { ok, text, itemId?, used? } - Forge feedback
--   Buy       (C→S): offerId: string - in-game purchase in the shop (Systems/Shop)
--   ShopResult (S→C): { ok, text, offerId? } - shop feedback
--   Rebirth   (C→S): no arguments - Rebirth (Systems/Rebirth, rules Shared/Rebirth)
--   RebirthResult (S→C): { ok, text, rebirths? } - Rebirth feedback
--   Pet       (C→S): action: "hatch" | "equip" | "unequip", id: string (egg or pet ID)
--   Pets      (S→C): { owned, equipped, slots, odds } - pet state (Shared/Pets);
--                    odds = { [eggId]: { { rarity, percent } } } from Pets.odds (odds before purchase)
--   PetResult (S→C): { ok, text, pet?, level?, shards? } - feedback (hatching, equipping)
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
	"Rebirth",
	"RebirthResult",
	"Pet",
	"Pets",
	"PetResult",
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
	Rebirth = get("Rebirth"),
	RebirthResult = get("RebirthResult"),
	Pet = get("Pet"),
	Pets = get("Pets"),
	PetResult = get("PetResult"),
	Debug = get("Debug"),
})
