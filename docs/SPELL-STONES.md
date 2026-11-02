# Spell stones

Build order step 8 (`docs/DECISIONS.md`, concept "Zaubersteine"). Rules in
`src/shared/SpellStones.luau`, effect in `Progression.effectiveSkill`.

- Up to **3 stones per skill**. Stones are kept as counts (`profile.progress.stones`); a stone in a
  socket is in use (`profile.progress.sockets[skillId]`), unsocketing gives it back.
- Drops: 35 % per boss kill, 12 % per elite kill (random stone, popup over the player).
- Abilities window → skill detail: three socket buttons. Tap cycles through the owned stones that
  fit the skill, then back to empty. Remote `Net.Loadout` ("socket", skillId, { index, stoneId }),
  validated on the server (`Progression.socket`).

| Stone | Effect | Fits |
|---|---|---|
| Power | +30 % damage, +0.5 s cooldown | all |
| Haste | −0.6 s cooldown, −10 % damage | all |
| Wide | +2 studs radius | all |
| Ember | hits burn for 30 % damage | all |
| Echo | second wave with 35 % damage | nova |
| Link | +2 jumps | chain |
| Split | +2 projectiles in a fan | projectile |
| Pierce | 50 % chance to fly through the first enemy | projectile |
| Linger | zones and buffs last 50 % longer | zone, buff |
