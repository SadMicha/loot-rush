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
	ARENA_TILES_X = 11,
	ARENA_TILES_Z = 9,

	-- Kampf (Spieler)
	RESPAWN_TIME = 3,
	DASH_IFRAMES = 0.3, -- Sekunden Unverwundbarkeit pro Dash (prüft der Server)
	CRIT_CHANCE = 0.1,
	CRIT_MULT = 2,
	POTION_HEAL = 0.35, -- Anteil der max. Lebenspunkte
	POTION_COOLDOWN = 6,
	POTION_START = 5, -- Heiltränke für neue Spielstände (Nachschub im Shop)
	POTION_MAX = 20, -- so viele trägt man höchstens
	BASE_HEALTH = 100,
	HEALTH_PER_LEVEL = 10,
	DAMAGE_PER_LEVEL = 0.1, -- +10 % Schaden je Level

	-- Gegner
	ENEMY_ZONE = Vector3.new(0, 0, -18), -- Mittelpunkt des Spawn-Bereichs
	ENEMY_ZONE_RADIUS = 10,
	AGGRO_RADIUS = 45,

	-- Messung (M5): Debug-Overlay mit F3 oder dem „Dbg“-Knopf unten links
	DEBUG_OVERLAY = true,

	-- Rift (Wellen → Boss → tiefer oder zurück)
	RIFT_START = Vector3.new(0, 4, 12), -- hier landet der Spieler beim Betreten
	HUB_POS = Vector3.new(0, 4, 28), -- Rückkehr (SpawnLocation der Arena)
	RIFT_WAVES = 3, -- Wellen vor dem Boss
	RIFT_WAVE_BASE = 6, -- Gegner in Welle 1 auf Tiefe 1
	RIFT_WAVE_STEP = 2, -- zusätzliche Gegner je Welle und je Tiefe
	RIFT_WAVE_MAX = 24, -- Obergrenze Gegner pro Welle (Server-/Netzlast bei großer Tiefe)
	RIFT_WAVE_PAUSE = 1.5, -- Sekunden zwischen den Wellen
	RIFT_HP_PER_DEPTH = 0.35, -- +35 % Leben je Tiefe
	RIFT_DMG_PER_DEPTH = 0.15,
	RIFT_XP_PER_DEPTH = 0.25,
})
