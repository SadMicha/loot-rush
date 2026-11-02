# Seasons – a new mechanic every season, the good ones stay

As of 2026-11-02. Status: **plan, nothing built**. Owner request (Micha, 2026-11-02): "each season
has a different mechanic and if it's well received, it stays in the game." Season 1 is the map
system, see `docs/specs/SEASON-1-BLUEPRINTS.md`. Starts after release 1.0 (`docs/DECISIONS.md` §6).

Loot Rush stays a pure ARPG: seasons add **things to fight, loot and chase**, never idle income,
timers to wait on or loss gambles.

## 1. What a season is

| Part | Rule |
|---|---|
| Length | **10 weeks** + 1 week break between seasons (break = the previous mechanic keeps running, patch week). |
| Mechanic | Exactly **one new mechanic** per season, built as its own module behind a flag (§4). |
| Character | **Same character, no fresh start** (recommended, see open decision 1). Season content is layered into the normal rifts and endgame. |
| Season Journey | ~30 challenges per season (e.g. "Clear 10 Blueprints", "Defeat a Master Build boss on Elite"). Rewards are **cosmetic** (stud trail, portal colour, title, hub banner) plus a few useful one-time items. Progress resets each season. |
| Season Ladder | Leaderboard per class for the season's own stat (Season 1: highest Blueprint tier cleared + time). New OrderedDataStore per season. |
| Great Build | One global monument per season that the whole player base builds together (§7). |
| Season name | "Season 1: Blueprints", shown in the hub and on the HUD season badge. |

Why same character: our players are mostly kids on phones with short sessions; wiping progress
every 10 weeks pushes them out, and a separate season realm doubles the save schema. The novelty
comes from the mechanic, the Journey and the ladder instead.

## 2. Lifecycle of a mechanic

```
Proposal → Trial (season live) → Evaluation (weeks 6–9) → Promote | Encore | Retire
```

| State | Meaning | In game |
|---|---|---|
| `trial` | Current season mechanic. Full drop rates, Journey challenges, ladder. | Everywhere it is designed for. |
| `core` | Promoted: permanent part of the game. | Stays, usually at a lower encounter rate (§5). Its items keep dropping. |
| `encore` | Liked but not ready (numbers weak or needs rework). Vaulted, may return as a later season's secondary twist. | Off; items keep working. |
| `retired` | Not wanted. | Off for good; items keep working but stop dropping; season currencies convert (§6). |

**Rule: nothing a player earned is ever deleted.** Retiring stops drops, it does not take items away.

## 3. How "well received" is measured

Data comes from `Systems/Metrics` (Roblox AnalyticsService custom events) plus an in-game vote.
Measured on players who reached the endgame (depth 20 on any World Tier), weeks 1–8.

| # | Signal | Target to promote |
|---|---|---|
| 1 | **Reach**: share of weekly endgame players who used the mechanic at least once that week | ≥ 50 % |
| 2 | **Share of play**: share of endgame play minutes spent in mechanic content | ≥ 25 % |
| 3 | **Retention**: D7 retention of the season-start cohort vs. the previous season (or 1.0 baseline) | not worse by more than 2 points |
| 4 | **Vote**: in-game "Keep Blueprints in the game?" (Yes / No), weeks 6–8, only players with ≥ 5 uses of the mechanic | ≥ 60 % yes |
| 5 | **Health**: no open crash/save bugs, server memory and frame time within the budget of `docs/RELEASE.md` | pass |

Decision (owner makes the final call, Claude prepares a short report in `docs/seasons/S<n>-REPORT.md`
in week 9):

| Result | Outcome |
|---|---|
| All five pass | **Promote** (`core`). |
| Vote passes, 1–3 miss | **Encore**: rework, try again later. |
| Vote fails | **Retire**. |
| 5 fails | Fix first; decision moves to the break week. |

The vote: one small card in the hub after a player's 5th use, never during combat. Stored in the
profile (`season.vote`) so each player votes once per season; counted with a DataStore counter per
season (`UpdateAsync` +1 per vote, batched per server every 60 s).

## 4. Code shape (for the developer threads)

- `Shared/Seasons.luau`: list of seasons `{ id, name, mechanic, startsAt, endsAt }` (UTC
  timestamps) and mechanic states `{ [mechanicId]: "trial" | "core" | "encore" | "retired" }`.
  Pure, testable (`Seasons.current(now)`, `Seasons.isActive(mechanicId, now)`).
- `Systems/Seasons.luau`: season clock (server `os.time()`), rollover on profile load (§6), Journey
  progress, ladder writes, vote counter. Sets attributes `SeasonId`, `SeasonEndsAt` for the HUD.
- **Live switch**: on server start and every 5 min the server reads `LootRush_LiveConfig` (one
  DataStore key) that can override a mechanic state (`off` as a kill switch, or extend a season by
  days) without publishing. Fallback when the read fails: `Shared/Seasons` values.
- **Each mechanic is one module** with the same small interface, so promotion or retirement is a
  state change, not a code rewrite:

```lua
export type Mechanic = {
	id: string,
	fresh: () -> any, -- default save data for profile.mech[id]
	reconcile: (raw: any) -> any, -- sanitize on load (same rules as Profile.reconcile)
	onRiftDepth: ((ctx: any) -> ())?, -- hook: may spawn its encounter in a depth
	onKill: ((ctx: any) -> ())?,
	convert: ((data: any) -> { gold: number, materials: any })?, -- on retire (§6)
}
```

- Rift hooks: `Systems/Rift` asks every active mechanic once per depth whether it wants an
  **encounter slot** (§5). Mechanics never edit Rift internals directly.
- Remotes: one `RemoteEvent` per mechanic (`Net.Blueprint`, …), validated like every remote
  (type, range, NaN, ownership, rate limit).

## 5. Encounter budget (so promoted mechanics do not pile up)

Every rift depth has **at most 2 extra encounter slots**: 1 for the trial mechanic (high chance,
e.g. 60 %) and 1 shared by all `core` mechanics (e.g. 25 %, picked by weight). Rift variants
(`Shared/RiftVariants`) stay separate. After four promoted seasons, core mechanics with low usage
can drop to a lower weight instead of being removed. Endgame systems that are not depth encounters
(Blueprints are a whole mode) do not use a slot.

## 6. Save data and DataStore

Store stays `LootRush_Profile_v3` (CLAUDE.md). All new fields are **additive** in `DEFAULTS`, so no
`Profile.VERSION` bump. New fields:

```lua
season = {
	id = "", -- season the fields below belong to ("" = none)
	journey = {}, -- { [challengeId]: number } progress
	claimed = {}, -- { challengeId } rewards taken
	best = {}, -- { [statId]: number } ladder stats of this season
	vote = "", -- "" | "keep" | "drop"
},
seasonHistory = {}, -- { { id, journeyDone, best } }, newest first, max 20 entries
mech = {}, -- { [mechanicId]: any } persistent mechanic data, sanitized by each module
cosmetics = {}, -- { [cosmeticId]: true } earned season rewards (titles, trails)
```

- **Rollover on load**: if `season.id ~= Seasons.current(now).id`, the old block is summarized into
  `seasonHistory`, `season` is reset to the new id. `mech[...]` is **not** reset (it holds the
  mechanic's permanent progress, e.g. the Blueprint atlas).
- **Retire**: on load, `mech[id]` of a retired mechanic runs once through `convert` (season
  currencies and unused consumables → gold and Forge materials, popup "Your Season 1 items were
  converted"), then the block is kept as `{ converted = true }`.
- **Items** get an optional field `season: string?` (season id) for mechanic-specific items. It is
  display only ("Season 1" tag in the tooltip); stats never depend on it.
- **Size**: each mechanic declares a hard cap (Blueprints: 60 stashed maps ≈ 6 KB). Total budget
  for `mech` 40 KB, far under ProfileStore's 4 MB.
- **Ladder**: OrderedDataStore `LootRush_Ladder_S<n>_<class>`, key = UserId, value = encoded
  stat (tier × 10,000 + (9,999 − seconds)). Write at most once per run end per player.
- **Vote counter**: DataStore `LootRush_SeasonVotes`, key `S<n>`, `{ keep, drop }`, batched.

## 7. The Great Build – one monument for the whole player base

Owner idea (Micha, 2026-11-02): idea #8 "Server Build" becomes **global**, so every server builds
the same thing and no server is left behind.

**Mechanic.** In the middle of Lumenhaven stands a giant brick monument under construction (Season
1: the *Grand Blueprint Tower*). Players donate **spare bricks** (from salvaging items and from
breaking props) at the donation chute. The monument has **10 stages**; the whole player base fills
the same progress bar, live on every server. Every finished stage:
- adds the next brick section to the monument on all servers (built in with a brick-by-brick
  animation, a big hub moment),
- gives **everyone** a **2-hour global buff** (+20 % gold, +10 % item quantity), also players who
  did not donate,
- puts the top donors of that stage on a **name plaque brick** at the monument.
Personal milestones (donate 100 / 1,000 / 10,000 bricks) give Journey points and a cosmetic.
The finished monument stays in the hub until the next season builds a new one.

**Feasibility on Roblox: yes, with batching.** Sketch:

| Piece | How |
|---|---|
| Donation | Server-side only: `Net.GreatBuild "donate", amount`; validated against the profile's brick count, rate limited (1 per 2 s), daily cap per player (e.g. 2,000) so one player cannot finish a stage alone. Bricks leave the profile at once. |
| Local batch | Each server sums donations in memory and flushes every **30 s**. |
| Global total | **DataStore is the single source of truth**: key `LootRush_GreatBuild/S<n>`, one `UpdateAsync` per flush that adds the batch and also records `flushes[serverId] = seq` (last applied batch number per server, pruned after 1 h), so a retried batch with the same `seq` is not added twice. Flushes are **strictly sequential per server**: while a batch is unconfirmed (failed or timed out) no later batch is sent; it is retried with the same `seq` until confirmed, and new donations wait in a separate buffer. So `seq` values are applied in order and "last applied" is enough. Quota: DataStore writes are 60 + 10 × players per minute **per server**; one write per 30 s is far below it. |
| Fast read cache | After a successful DataStore write the server **sets** (not adds) the returned public record `{ total, stageDoneAt }` into MemoryStore HashMap `GreatBuild`, key `S<n>`, only if its total is higher than the cached one (`UpdateAsync`). The cache holds the buff timestamps too, so new servers and servers that missed the message see active buffs. MemoryStore is a cache only: if it is empty or expired (45 days max) servers fall back to reading the DataStore. MemoryStore quota (1,000 + 100 × players requests/min for the experience) stays far below the limit with one read per server per 30 s. |
| Read | Each server reads the cached record (total + `stageDoneAt`) every 30 s, falling back to the DataStore when the cache is empty, and tweens the bar; the client sees an attribute `GreatBuildTotal`. |
| Stage complete | The `UpdateAsync` that crosses a stage threshold writes `stageDoneAt[stage] = os.time()` into the same DataStore entry (only one server can win the transform) and publishes a MessagingService message `GreatBuildStage` so all servers play the build animation within seconds. Servers that miss the message see it on the next 30 s read. |
| Global buff | Time based, not message based: the buff is active while `now < stageDoneAt + 7200`. New servers and late joiners get it right. |
| Top donors | Per-player stage donations in the profile (`mech.greatbuild`), plus **one OrderedDataStore per stage**, `LootRush_GreatBuildDonors_S<n>_<stage>` (key UserId, value = that player's donations in that stage), written on flush (max once per player per minute). Plaques read the top 5 of each stage's store; a season-wide `LootRush_GreatBuildDonors_S<n>` holds the overall ranking. |
| Failure | Only the DataStore write can lose or duplicate donations, and the `seq` check makes its retries idempotent: a failed write keeps the batch (with its `seq`) in memory and retries with backoff; new donations go into the next batch. A failed MemoryStore set is simply skipped (next flush fixes the cache). On `BindToClose` the server flushes once more. Worst case a server loses ≤ 30 s of donations on a hard crash (the players' bricks are already spent; acceptable, mention in the patch notes). |
| Testing | `Shared/GreatBuild.luau` pure (thresholds, stage from total, buff window); MemoryStore/DataStore wrapped so Lune tests use a fake. |

Stage thresholds scale with player count, so the build finishes in the season but not in a day:
start low (stage 1 = 50,000 bricks) and grow ×1.6 per stage; numbers go to `Shared/Balance` and
are retuned after week 1 through `LootRush_LiveConfig`.

Effort **M**. It is not tied to the season mechanic, so it can also ship with 1.0 as a smaller
"Season 0" monument.

## 8. Season roadmap (proposal)

| Season | Mechanic | Spec |
|---|---|---|
| 0 (launch) | No mechanic, but Great Build + Journey to test the framework | – |
| 1 | **Blueprints** (repeatable maps, PoE-style, stud world) | `docs/specs/SEASON-1-BLUEPRINTS.md` |
| 2 | **Smoothing Breaches** (`docs/IDEAS.md` #13) | later |
| 3 | **Build Kits** (`docs/IDEAS.md` #14) | later |

Candidates beyond that: Boss Parts (#9), Living Loot (#10), Echo Builders (#11).

## 9. Build steps (one PR each, `tools/check.sh` green)

1. `Shared/Seasons` + `Systems/Seasons` (clock, rollover, profile fields, attributes, live switch,
   HUD season badge) + tests for rollover and retire conversion.
2. Season Journey window (Kit) + ladder + vote card.
3. Great Build (§7) with the MemoryStore/DataStore wrapper and fakes in tests.
4. Season 1 mechanic (own steps in its spec).

## Open decisions for Micha

1. **Fresh season characters or same character?** Recommended: same character (above).
2. **Paid season pass?** Recommended for later only and cosmetic only (no power, no faster
   progress); Season 1 launches with a free Journey.
