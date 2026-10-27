--!strict
-- Gemeinsame Typen für Client und Server.
-- Alles, was über die Netzwerkgrenze geht (Remote-Payloads, Spielstand), wird hier definiert.

export type PlayerProfile = {
	version: number,
	gold: number,
}

-- Player-Attribute, die der Server setzt und die der Client nur liest
export type PlayerAttributes = {
	InCombat: boolean, -- true, solange Gegner nah sind oder kürzlich Schaden kam
	Level: number,
	XP: number,
	XPNext: number, -- XP bis zum nächsten Level
}

-- Rift-Zustand als Player-Attribute des Rift-Besitzers (Systems/Rift)
--   RiftPhase: "" (kein Rift) | "wave" | "boss" | "clear" (Boss tot, Wahl: tiefer/zurück) | "failed"
--   RiftDepth, RiftWave, RiftWaves: number · RiftLeft: Gegner, die noch leben

-- Gegner-Attribute (auf dem Model, Tag "Enemy")
export type EnemyAttributes = {
	Health: number,
	MaxHealth: number,
	Boss: boolean?,
}

-- Net.Fx-Ereignisse (Server → alle Clients): Art → Daten
--   dmg     { pos, amount?, text?, crit?, hurt?, heal? }
--   proj    { from, to, time, color, size }
--   nova    { pos, radius, color }
--   chain   { points: {Vector3}, color }
--   death   { pos, color }
--   levelup { pos, level }

return nil
