# Flop-or-top audit: six criteria

Second pass, 2026-11-04, `main` @ `2cad4a2` (#123). Owner ask (Micha): check the game against the six
things that decide flop or top: **fast paced, easy to pick up, great tutorial, dopamine, everything
clearly visible, everything makes sense.** First pass: same file at `aab1e00` (#106).

**How this was made:** read the code on `main` and the two open feature PRs (#124 Journey/Season,
#125 gradual skills), walked the first session as a new phone player through the code paths, and
ran the specs that simulate it: `Balancing` (depth 1–30 sim), `Bosses`, `Hints`, `Quests`, `Daily`,
`FirstDrops`, `LevelUp`, `Phone`, `Loadout`, `Skills` (all pass). **Nothing was playtested.**
Lines marked 📱 can only be judged in Studio or on a phone; they are in the launch checklist in
`docs/TEST-RELEASE.md`.

## 1. Scores

| # | Criterion | Before (#106) | Now | Why it moved | What still holds it back |
|---|---|---|---|---|---|
| 1 | Fast paced | 6 | **7** | First boss 38 s → 21 s; depth 1–5 in ~5 min; depth 6 wall 5 → 2 farm runs; "Play again" card after every run | The boss is still 36–44 % of every run (21–39 s of 58–88 s) |
| 2 | Easy to pick up | 5 | **7** | Boss ideas arrive one at a time (phase 2/Openings/Counter d3, Pursuit d4, adds/enrage d5); Pursuit respects class range | Four skills at once until #125 merges; ~10 resources; 13 menu buttons in the hub once #124 merges |
| 3 | Tutorial | 4 | **7** | Callouts next to their button, shown only when calm, saved as seen only once on screen; Break/Counter/Equip hints; quest ticker in runs; Daily waits for the first Rift; quests hand over a stone, materials, a free egg | 📱 Unverified on a phone; nothing explains Star Web, Forge or Pets beyond the unlock card |
| 4 | Dopamine | 7 | **8** | Light pillars + ground ring + bigger box for Rare+; green UPGRADE tag; arrow markers in the bag; level-up card with "New skill" | Boss loot has no chest/burst moment; most drops minutes 3–10 come from the boss (8 % per normal kill) |
| 5 | Clearly visible | 6 | **6** | Layout matrix across all HUD sizes (#119); red rim on burning ground; nameplates and station labels | 📱 Still never seen on a phone: phase 3 boss with adds on 844×390, Fire Desert pools, pillars at camera distance 46 |
| 6 | Makes sense | 5 | **7** | One name per thing (Star Web, Skills, Forge, Shop/Market); full bag salvages non-upgrades and warns; hero switch is a teleport with a loading cover | "Rune Candy" (Forge material); README still says "plays like an incremental"; switch falls back to a kick if the teleport fails 📱 |

**Overall: from "would flop in the first 15 minutes" to "solid on paper".** All six ship blockers
of the first pass are merged. What is left is (a) the phone check that nobody has done yet, and
(b) pace in the mid game, where every run is still half boss.

## 2. First session as a new phone player (code walk)

| Time | What happens | Verdict |
|---|---|---|
| 0:00 | Loading screen, hero setup (name + four class cards) | Fine |
| 0:20 | Hub, quest "Enter a Rift", gold beam to the gate; no Daily popup | Fixed (#110) |
| 0:40 | Atlas: Green Plains selected, "Travel" | OK; tier and depth picker are extra, but the default is right |
| 1:00 | Depth 1: auto attack, callouts for Skills and Dodge in the first calm moment; first 3 kills drop gear with pillars | Good. With #125: 2 skills, not 4 |
| 1:30 | "UPGRADE" tag, Equip callout at the Inventory button, arrow markers in the bag | Good 📱 (callout position at small HUD sizes) |
| 2:00 | Boss d1: phase 1 only, Break meter + "Break" callout, ~21 s | Good |
| 2:30 | VICTORY, cleared card, Daily popup back in the hub, level-up card | Good. With #124 the hub also shows Journey and Season dots: four gold dots at once (Daily, Journey, Season, Inventory) |
| 3–5 | Depth 3: Counter, Openings, stone from the quest; depth 4 Pursuit; depth 5 adds, enrage, Forge | Pacing is right, one idea per depth |
| 5–17 | Level 5 Star Web, depth 5 Forge, depth 8 Pets, depth 10 Auto-Salvage; 2+2+1 farm runs at d6, 7, 9 | OK; runs feel the same length because the boss dominates |

## 3. Remaining blockers, ranked

| Rank | Issue | Criteria | Impact | |
|---|---|---|---|---|
| 1 | **No phone playtest yet.** Every UI change of the last two days (callouts, pillars, layout matrix, nameplates, level-up card) is code-only. | 5, 3 | H | 🚩 📱 |
| 2 | **Boss = 36–44 % of each run** at every depth (sim). After depth 5 a run is "30 s trash, 30 s boss". | 1 | H | 🚩 |
| 3 | **Notification pile on the first hub visit** once #124 lands: Daily, Journey, Season and Inventory dots at the same time, plus 5 top-right icons and 8 bar buttons. | 2, 3 | M | |
| 4 | **Four skills at once** until #125 merges. | 2 | M | in flight |
| 5 | **Mid-game drops thin** (8 % per normal kill, minutes 3–10 mostly boss loot). | 4 | M | 📱 |
| 6 | Small names: "Rune Candy", README tagline. | 6 | L | |

## 4. Recommended changes

Effort: XS (< 1 h), S (one small PR), M (one thread). Not started; Micha picks.

| # | Change | Fixes | Effort |
|---|---|---|---|
| R1 | **Micha's 20-minute phone pass** with the launch checklist (`docs/TEST-RELEASE.md`). Fixes come out of it. | 1 | S (Micha) |
| R2 | **Shorter bosses from depth 2 on:** target 15–25 s (now 24–39 s), e.g. a lower `Balance.P.boss_hp` (40) with `Bosses.EASE_HEALTH` (now ×0.55–0.9 for depth 1–4)
retuned, or a bigger Break payoff (longer stun, more damage taken) so skilled play shortens the fight. Re-run the sim; keep "ready" rule ≤ 40 s. | 2 | S |
| R3 | **Gate Journey and Season icons** behind `Quests.Unlocks` (e.g. Journey after the first boss, Season from depth 3) and show at most one gold dot pulse at a time. | 3 | XS–S |
| R4 | Merge #125 (gradual skills) and #124 (Journey/Season) together with R3. | 3, 4 | XS |
| R5 | **Boss loot burst:** the boss drop fans out with a short delay per item and one guaranteed Magic+ piece per boss at depth 1–10. | 5 | S |
| R6 | Raise `drop_normal` from 8 % to ~10 % for depth 1–10 only, check the sim's items per minute. | 5 | XS |
| R7 | One "what is this?" line on first open of Star Web, Forge and Pets (same callout system). | tutorial | S |
| R8 | Rename "Rune Candy" (display name only), fix the README tagline. | 6 | XS |

### Suggested order

1. R1 first (Micha), since it may reshuffle everything else.
2. One thread "Pace and loot": R2, R5, R6 (all `Balance`/`Bosses` numbers plus one sim run).
3. One small PR "First hub visit": R3, R4, R7, R8.

Exit check (unchanged): a new player on a phone reaches depth 3 without help, can say what Break
and Rush are, and equips their first upgrade without being told.
