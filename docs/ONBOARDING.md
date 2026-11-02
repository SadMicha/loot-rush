# Onboarding: quest chain and unlocks

Rules: `src/shared/Quests.luau` · server: `src/server/Systems/Quests.luau` · client: `QuestController` +
quest panel in `HudController` · tests: `tests/Quests.spec.luau`.

- 16 quests in a fixed order (enter Rift → kills → pick up → equip → depth 3 → level 5 → star → depth 5
  → Forge → salvage → depth 8 → hatch → level 15 → depth 15 → depth 20). Each pays gold.
- Count goals come from `Util/Actions` (`Actions.fire(player, kind)` in Rift, Inventory, Progress,
  Forge, Pets) plus kills (`Combat.EnemyKilled`) and item pickups (`Loot.Picked`).
  Level/depth goals are checked on the attributes `Level` / `BestDepth`.
- Unlocks: Star Web at level 5, Forge at depth 5, Pets at depth 8 (`Quests.Unlocks`). Saved in
  `profile.quests.unlocks`, so they never lock again. Locked = dimmed hub bar button,
  hotkey and hub station show "Locked · <condition>" as a toast.
- Unlocks are pacing only: the server does not refuse requests for locked windows.
- Each finished quest logs `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, questId)`.
- New quest: append to `Quests.Chain` (never reorder – the save stores the step index).
