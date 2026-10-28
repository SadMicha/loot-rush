--!strict
-- Alle RemoteEvents an einem Ort. Der Server legt sie an, der Client wartet darauf.
--   CastSkill (C→S): slot: number, aim: Vector3, origin: Vector3 (Client-Position)
--   UsePotion (C→S)
--   Dash      (C→S): Meldung für Unverwundbarkeit, Server zählt eigene Ladungen
--   Fx        (S→C): kind: string, data: table (siehe Types.luau)
--   Inv       (S→C): { items: { Item }, equipped: { [slot]: Item } }
--   Equip     (C→S): itemId: string · Unequip (C→S): slot: string · Sell (C→S): itemId: string
--   Rift      (C→S): action: "enter" | "deeper" | "leave" – Zustand kommt über Player-Attribute (Types.luau)
--   Progress  (S→C): { progress: Progression.Data, materials: Progression.Materials }
--   Bloom     (C→S): action: "spend" | "reset", skillId: string, key: string? (Skill-Blüte)
--   Star      (C→S): action: "alloc" | "remove" | "reset", starId: string? (Sternennetz)
--   ForgeAct  (C→S): actionId: string, itemId: string, affix: number? (Schmiede)
--   ForgeResult (S→C): { ok, text, itemId?, used? } – Rückmeldung der Schmiede
--   Debug     (C→S): command: string, value: number? – Test-Befehle, nur Studio/DEV_USERS (Systems/Debug)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"CastSkill",
	"UsePotion",
	"Dash",
	"Fx",
	"Inv",
	"Equip",
	"Unequip",
	"Sell",
	"Rift",
	"Progress",
	"Bloom",
	"Star",
	"ForgeAct",
	"ForgeResult",
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
	UsePotion = get("UsePotion"),
	Dash = get("Dash"),
	Fx = get("Fx"),
	Inv = get("Inv"),
	Equip = get("Equip"),
	Unequip = get("Unequip"),
	Sell = get("Sell"),
	Rift = get("Rift"),
	Progress = get("Progress"),
	Bloom = get("Bloom"),
	Star = get("Star"),
	ForgeAct = get("ForgeAct"),
	ForgeResult = get("ForgeResult"),
	Debug = get("Debug"),
})
