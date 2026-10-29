--!strict
-- Alle einstellbaren Spielwerte an einem Ort.
-- Achtung: wird an Clients repliziert – nichts Geheimes hier, und der Server
-- vertraut nie einem Wert, den der Client meldet.

return table.freeze({
	-- Kampf-/Ruhe-Zustand (steuert das Ein- und Ausfliegen des UIs)
	COMBAT_RADIUS = 40, -- Studs: Gegner in diesem Radius = Kampf
	CALM_DELAY = 3, -- Sekunden ohne Kampf bis „Ruhe“
	COMBAT_TICK = 0.25, -- Sekunden zwischen Server-Prüfungen

	-- Kamera (isometrische ARPG-Kamera)
	CAMERA_PITCH = 52, -- Grad von oben
	CAMERA_YAW = 20, -- Grad um die Hochachse (0 = Blick nach Norden)
	CAMERA_DISTANCE = 46,
	CAMERA_MIN_DISTANCE = 26,
	CAMERA_MAX_DISTANCE = 72,
	CAMERA_SMOOTHING = 12, -- höher = direkter

	-- Bewegung
	WALK_SPEED = 20,
	DASH_SPEED = 72, -- Studs pro Sekunde während des Dash
	DASH_DURATION = 0.2,
	DASH_CHARGES = 2,
	DASH_RECHARGE = 2.5, -- Sekunden pro Ladung

	-- Welt
	TILE_SIZE = 8,
	ARENA_TILES_X = 17, -- Kacheln je Gebiets-Arena (Raster gleich in allen Gebieten)
	ARENA_TILES_Z = 15,

	-- Kampf (Spieler)
	RESPAWN_TIME = 3,
	DASH_IFRAMES = 0.3, -- Sekunden Unverwundbarkeit pro Dash (prüft der Server)
	CRIT_CHANCE = 0.1,
	CRIT_MULT = 2,
	POTION_HEAL = 0.35, -- Anteil der max. Lebenspunkte
	POTION_COOLDOWN = 6,
	POTION_START = 5, -- Heiltränke für neue Spielstände (Nachschub im Shop)
	POTION_MAX = 20, -- so viele trägt man höchstens
	-- Leben je Level, XP-Kurve, Gegner-, Gold- und Beute-Werte je Tiefe: Shared/Balance (Tabelle)
	DAMAGE_PER_LEVEL = 0.02, -- +2 % Schaden je Level (eigene Annahme; die Tabelle skaliert über die Waffe)

	-- Gegner
	ENEMY_ZONE = Vector3.new(0, 0, -20), -- Mittelpunkt des Spawn-Bereichs
	ENEMY_ZONE_RADIUS = 16,
	AGGRO_RADIUS = 45,

	-- Messung (M5): Debug-Overlay mit F3 oder dem „Dbg“-Knopf unten links
	DEBUG_OVERLAY = true,

	-- Rift (Wellen → Boss → tiefer oder zurück)
	RIFT_START = Vector3.new(0, 4, 16), -- hier landet der Spieler beim Betreten
	HUB_ORIGIN = Vector3.new(-700, 0, 0), -- Mitte der Hub-Map „Lumenhafen“ (weit weg von der Arena)
	HUB_POS = Vector3.new(-700, 4, 44), -- Spawn im Hub und Rückkehr aus dem Rift
	RIFT_WAVES = 3, -- Wellen vor dem Boss
	RIFT_WAVE_BASE = 6, -- Gegner in Welle 1 auf Tiefe 1
	RIFT_WAVE_STEP = 2, -- zusätzliche Gegner je Welle und je Tiefe
	RIFT_WAVE_MAX = 24, -- Obergrenze Gegner pro Welle (Server-/Netzlast bei großer Tiefe)
	RIFT_WAVE_PAUSE = 1.5, -- Sekunden zwischen den Wellen

	-- Beute: Stufe, Gold, Drop-Chance und Seltenheit je Tiefe aus Shared/Balance
	LOOT_BOSS_ILVL = 1, -- Boss-Items liegen so viele Stufen (je 10 IP) darüber (eigene Annahme)
	LOOT_BOSS_GOLD_DROPS = 5, -- Boss-Gold verteilt auf so viele Münzen
})
