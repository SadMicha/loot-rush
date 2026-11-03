--!strict
-- Shared types for client and server.
-- Everything that crosses the network boundary (remote payloads, save data) is defined here.

export type PlayerProfile = {
	version: number,
	gold: number,
}

-- Player attributes the server sets and the client only reads
export type PlayerAttributes = {
	InCombat: boolean, -- true while enemies are near or damage was taken recently
	Level: number,
	XP: number,
	XPNext: number, -- XP to the next level
}

-- Rift state as player attributes of the Rift owner (Systems/Rift)
--   RiftPhase: "" (no Rift) | "wave" | "boss" | "clear" (boss dead, choice: deeper/back) | "failed"
--   RiftDepth, RiftWave, RiftWaves: number · RiftLeft: enemies still alive

-- Enemy attributes (on the model, tag "Enemy")
export type EnemyAttributes = {
	Health: number,
	MaxHealth: number,
	Boss: boolean?,
}

-- Net.Fx events (server → all clients): kind → data
--   dmg     { pos, amount?, text?, crit?, critTier?, hurt?, pickup? }
--           pickup = item rarity or "gold" on the owner's own pickup popup (pickup sound)
--           crit = tier >= 1; critTier (optional, >= 1 only on crits) = overcrit tier, 2 = double crit
--   proj    { from, to, time, color, size }
--   nova    { pos, radius, color }
--   chain   { points: {Vector3}, color }
--   death   { pos, color }
--   levelup { pos, level, who }
--   rush    { who } - Stud Rush started · intro { text, color } - boss intro (owner only)
--   phase   { pos, stage } - boss phase change
--   act     { by, kind, skill?, basic, at? } - an attack, cast ("projectile", "arc", …, the
--           Skills kind) or "dash" of player `by`; drives AnimController (Shared/Anim)

return nil
