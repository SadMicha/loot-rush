# Platform stack: Fusion, ProfileStore, cross-server, Open Cloud support, analytics

Status: planned, decisions D1-D6 made by the user on 2026-11-01 (nothing of this is built). Roadmap rows N8-N13 in `docs/ROADMAP.md`.
Written against HEAD `a773170`, decisions recorded against `a5f95e1`. Package versions checked on the Wally index on 2026-11-01.

## Goal

Move Loot Rush onto the stack the user chose for running a live game:

| Item | Chosen by user | Roadmap |
|---|---|---|
| Package tooling (Wally) | prerequisite for everything below | N8 |
| ProfileStore for player saves | ProfileStore by loleris | N9 |
| Live tracking / balancing | Roblox AnalyticsService behind a server facade (D2) | N10 |
| Customer support on player data | Open Cloud Data Stores v2, local CLI (D5) | N11 |
| UI framework | Fusion, pilot on the Shop window, then go/no-go (D1) | N12 |
| Cross-server | Announcements over MessagingService, MemoryStore only for a "recent" list (D4); no matchmaking (D3) | N13 |

Non-goals: co-op rifts, matchmaking, server browser, trading, global leaderboards, PlayFab, GameAnalytics (parked),
a GitHub support workflow (parked), an admin web panel, a big-bang UI rewrite. See "Parked".

---

## 0. What exists today (checked in the repo)

- **No packages at all.** `wally.toml` has only commented entries (`# ProfileStore = "loleris/profilestore@1"`),
  no `Packages/` mapping in `default.project.json`, `.gitignore` ignores `Packages/`, `ServerPackages/` **and `wally.lock`**.
  `rokit.toml` already pins `wally 0.3.2`. CI (`tools/check.sh`, `tools/setup.sh`) never runs `wally install`.
- **Saving:** `src/server/Systems/Data.luau` (273 lines) - own UpdateAsync session lock, retry/backoff, budget wait,
  autosave 60 s, BindToClose, store `LootRush_Profile_v2`, key `p_<UserId>`, value `{ v, data, lock }`.
  Schema/defaults/migration/sanitize in `src/shared/Profile.luau` (`VERSION = 3`). Public API used by 12 systems:
  `Data.get`, `Data.saveNow` (ProcessReceipt in `Monetization.luau` depends on its boolean), `Data.waitFor`, `init/start`.
  Tests: `tests/Data.spec.luau` (4), `tests/DataLock.spec.luau` (1), `tests/Profile.spec.luau` (pure schema).
  Lune sandbox fakes DataStores in `tools/lune/lib/Sandbox.luau` (`Sandbox:dataStore`: Get/Set/Update/Increment/Remove;
  `UpdateAsync` passes only the value, no `DataStoreKeyInfo`, ignores returned userIds/metadata).
  History: M3b already went "ProfileStore -> own DataStore system"; going back is the user's call (made).
- **Analytics:** none. `src/server/Systems/Metrics.luau` writes local run reports and server health attributes (dev tool,
  stays). No `AnalyticsService`, no `HttpService` requests (only `GenerateGUID` in `Shared/Items.luau`).
- **Open Cloud:** used only for publishing (`tools/publish.sh`, workflow `publish.yml`, env `Roblox` with
  `ROBLOX_API_KEY` scoped to `universe-places:write`, `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID`; `docs/PUBLISH.md`).
- **Cross-server:** none. No MemoryStore, MessagingService, TeleportService. Rifts are solo, one arena per player,
  up to `Config.RIFT_SLOTS = 12` per server (M14). The Hub is the only shared space.
- **UI:** imperative. `src/client/UI/Kit.luau` (1046 lines, image-skinned builders), `Window.luau` (332), tokens in
  `Shared/UI/Theme.luau`, images in `Shared/UI/Assets.luau`. Screens are controllers: Hud 761, Inventory 792,
  Forge 487, Abilities 452, Shop 326, StarNet 319, Atlas 319 lines (~3.5k lines of UI code). README rule:
  "UI only from Kit". Headless UI check `tools/lune/ui.luau` presses every button with an `Activated`/`MouseButton1Click`
  handler in 4 screen sizes.

---

## 1. Package tooling (N8) - prerequisite

**Change:** real `wally.toml` dependencies, `wally install` in setup/CI, Rojo mapping, types for packages.

- `[dependencies]` (shared) -> `ReplicatedStorage.Packages`; `[server-dependencies]` -> `ServerScriptService.ServerPackages`.
- `tools/setup.sh` and CI run `wally install` before `rojo build`/`sourcemap`; luau-lsp gets package types via
  `wally-package-types` (re-export thunks otherwise lose types under `--!strict`), selene/StyLua keep linting `src` only.
- Commit `wally.lock` (remove it from `.gitignore`) so CI and Studio get identical versions. **Assumption (planner)**, reversible.
- pesde is not used: the project already pins Wally in `rokit.toml` and all three packages below are on the Wally index.

| Package | Wally name | Version | Realm |
|---|---|---|---|
| ProfileStore | `lm-loleris/profilestore` | `1.0.3` | server |
| Fusion | `elttob/fusion` | `0.3.0` | shared |
N8 only adds ProfileStore. Fusion is added in N12.1. GameAnalytics (`gameanalytics/gameanalytics-sdk@3.0.0`) is parked (D2)
and not installed. That way no unused package ships.

---

## 2. ProfileStore (N9)

**What changes:** `Systems/Data.luau` keeps its public API (`get`, `saveNow`, `waitFor`, `init`, `start`) and its
kick messages, but its internals become ProfileStore. No gameplay system changes. `Shared/Profile.luau` stays the
schema owner (defaults, `migrate`, `reconcile`, `sanitize`); the lock helpers (`Lock`, `lockedByOther`) become unused
and are removed after N9 is green.

**Decided:**
- Store `LootRush_Profile_v3`, key `p_<UserId>` (user/main session: new store name, no data migration; the game is
  not live, v2 saves on the test place are test data and are dropped).
- `profile.Data` holds the existing record shape **without lock**: `{ v: number, data: Profile.Data }`. On load:
  `Profile.migrate(profile.Data)` -> write back into `profile.Data`. This keeps `Profile.luau` and `Profile.spec`
  unchanged and keeps schema versioning. (Planner, reversible until live.) Do **not** use `ProfileStore.New(name, template)`
  reconcile for fields; `Profile.reconcile` remains the single source of defaults. Template = `{ v = Profile.VERSION, data = Profile.fresh() }`.
- `profile:AddUserId(player.UserId)` on first session (GDPR / right-to-erasure tooling, see 4).
- `Data.saveNow` = `profile:Save()` then wait for `OnAfterSave` (timeout ~15 s); return `true` only if it fired.
  ProcessReceipt keeps returning `NotProcessedYet` otherwise.
- Kick on `StartSessionAsync` returning `nil`; `Cancel = function() return player.Parent ~= Players end`;
  `OnSessionEnd` -> kick with the existing "opened on another server" text. Never use `Steal`.
- `Profile.sanitize` runs in `OnSave` (keeps the NaN repair test meaningful).
- Studio without API access: ProfileStore reports `DataStoreState ~= "Access"` -> use `ProfileStore.Mock` with an
  empty save (same behavior as today: playable, not stored).

**Risk / migration:**
- Lune sandbox compatibility is the main risk. ProfileStore calls `UpdateAsync` with the `(value, keyInfo)` callback
  form and returns `(value, userIds, metadata)`, uses MessagingService to speed up session hand-off, and checks
  DataStore access at startup. Sandbox must gain: `DataStoreKeyInfo` stub, userIds/metadata storage, MessagingService
  `PublishAsync`/`SubscribeAsync` stubs. Task N9.1 is a spike that finds the exact set.
- Tests: `Data.spec` intents stay (loads, saves level/XP on autosave, repairs NaN, releases on shutdown); `DataLock.spec`
  is rewritten to ProfileStore semantics ("a save with an active foreign session is never loaded into two servers";
  ProfileStore waits for/requests the other session instead of an immediate kick). Seed data must use ProfileStore's
  raw value format, which N9.1 documents in this spec. **Other agents are editing `tests/` concurrently; rebase before touching `tests/Data*.spec`.**
- `docs/TEST-SAVING.md` gets a ProfileStore section (planner, after N9 lands). N9 lands **before** the TEST-SAVING round in N1
  (D6); the rest of N1 does not wait for N9.

**User actions:** none new (Studio: *Game Settings -> Security -> Enable Studio Access to API Services*, already in TEST-SAVING).

**Cost/limits:** DataStores are free within Roblox's per-experience storage and request quotas; one profile is a few KB;
ProfileStore autosaves roughly every 5 min (fewer writes than today's 60 s).

### Task order N9

| # | Owner | Task | Depends |
|---|---|---|---|
| N9.1 | backend-developer | Spike + sandbox support: install ProfileStore, make it run in the Lune sandbox, document raw value format | N8 |
| N9.2 | backend-developer | Rewrite `Data.luau` internals on ProfileStore, keep API; adapt `Data*.spec` | N9.1 |
| N9.3 | code-reviewer | Review: receipts/saveNow, session end, BindToClose, no `Steal`, Mock in Studio | N9.2 |
| N9.4 | planner | Update `TEST-SAVING.md`; Micha plays it | N9.3 |

---

## 3. Analytics (N10)

**Decided (D2):** one server facade `Systems/Analytics.luau` that gameplay calls; the only sink now is Roblox
AnalyticsService (built-in, free, server only, works in published games only, daily aggregation up to 24 h, max 100 custom
event names). The facade keeps sinks pluggable so a GameAnalytics sink stays a one-file job if daily data proves too slow
(parked, see "Parked"). PlayFab not adopted: no official Roblox SDK and it duplicates ProfileStore/AnalyticsService.

**Event contract (fixed, backend owns):** `Analytics.economy(player, flow: "source"|"sink", currency: "gold"|"soulstars", amount, balance, txType, sku)`,
`Analytics.progression(player, "rift_<region>", "start"|"complete"|"fail", depth)`, `Analytics.onboarding(player, step, name)`,
`Analytics.custom(player, name, value?, fields?)`. Field values are enums/ids/numbers only, never free text.

- Onboarding steps: 1 joined, 2 first_kill, 3 first_pickup, 4 first_equip, 5 first_rift, 6 first_boss, 7 first_return_hub.
- Economy: gold sources (enemy, sell, salvage, shop pack), sinks (shop, forge, eggs); soulstars sources (robux, rebirth), sinks (shop, star_egg).
- Progression: every rift run per region, depth as level (complements `RiftResult`).
- Custom (<= 5 names): `rebirth`, `pet_hatch` (field rarity), `robux_purchase` (field sku), `skill_level` (field skill), `forge_use` (field action).
- Onboarding "first" flags: derived from existing save fields where possible; if a new save field is needed it goes
  through `Profile.luau` DEFAULTS (backend).

**Privacy/policy:** UserId only; never Name/DisplayName, chat or free text; no custom IDs. AnalyticsService needs no consent flow
and no third party sees player data.

**User actions:** none (dashboards: Creator Hub -> experience -> Analytics; data only from published sessions).

### Task order N10

| # | Owner | Task | Depends |
|---|---|---|---|
| N10.1 | backend-developer | `Systems/Analytics.luau` facade + AnalyticsService sink + call sites; Lune test with a fake sink | none (no package) |
| N10.2 | code-reviewer | Review: no PII, server only, no hot-path spam (no per-hit events) | N10.1 |
| ~~N10b~~ | - | GameAnalytics sink + client init: **parked** (D2); reopen only if 24 h AnalyticsService data blocks balancing | - |

---

## 4. Open Cloud support tooling (N11)

**What it is:** a local CLI `tools/support.luau` (Lune, `@lune/net`), same toolchain as the tests, against
`https://apis.roblox.com/cloud/v2/universes/{universe}/data-stores/LootRush_Profile_v3/entries/p_<UserId>`.

Commands (minimal): `get <userId>` (prints `data` pretty), `revisions <userId>`, `restore <userId> <revisionId>`,
`set <userId> <path> <json>` (e.g. `data.gold 5000`), `delete <userId>`.

- Writes: print a diff, require `--yes`, refuse while the ProfileStore session field shows an active session
  (player online; the live server would overwrite the edit). Whole value is sent on PATCH (Open Cloud v2 has no partial
  update; omitting attributes/users clears them, so the tool must re-send users/attributes it read).
- Invalid edits are repaired by `Profile.reconcile/sanitize` on next load; the tool only checks JSON types of the edited field.
- `delete` serves right-to-erasure requests. Roblox can also auto-delete data store entries whose key matches a
  configured RTBF template (key contains the UserId, which `p_<UserId>` does); configure that in Creator Hub (user action).

**Depends on N9** (value format). Read-only first (N11.1), writes second (N11.2). **Local CLI only (D5).** A GitHub
`workflow_dispatch` version is parked (would need the key in env `Roblox` and an open IP range).

**User actions:** Creator Hub -> Open Cloud -> API Keys -> new key `loot-rush-support`, system **universe-datastores**:
`objects:list`, `objects:read`, `objects:update`, `objects:delete`, `versions:list`, `versions:read`, only for the test (later live)
universe; IP restriction = your own IP (local use). For N13.2 add **universe-messaging-service** `publish` to the same key.
Keep it out of the repo: env var `ROBLOX_SUPPORT_API_KEY` locally. Separate from the publish key (least privilege).
Optional: Creator Hub -> Data stores -> RTBF template for `p_{UserId}`.

**Cost:** free; volume is a handful of calls.

### Task order N11

| # | Owner | Task | Depends |
|---|---|---|---|
| N11.0 | Micha | Create API key `loot-rush-support` (scopes above), set `ROBLOX_SUPPORT_API_KEY` locally | none |
| N11.1 | backend-developer | `tools/support.luau` read-only: `get`, `revisions` | N9.2, N11.0 |
| N11.2 | backend-developer | Writes: `set`, `restore`, `delete` with diff, `--yes`, online-session refusal | N11.1 |
| N11.3 | code-reviewer | Review: no key in repo, whole-value PATCH keeps users/attributes, refusal works | N11.2 |
| N11.4 | planner | Support section in `docs/PUBLISH.md` | N11.3 |

---

## 5. Fusion UI (N12)

**Decided (D1):** pilot on the Shop window, then a recorded go/no-go before any further screen. Not a full migration
commitment yet: nothing in the UI is playtested (N1), so the pilot answers the sandbox/tooling risk without churning screens under test.

**Package:** `elttob/fusion@0.3.0` (latest release; `main` is already `0.4.0-dev1`, so expect API breaks at 0.4).
React-lua not chosen: heavier, JS idioms, more boilerplate for a 1-person team.

**Coexistence plan (no big bang):**
- Theme and Assets stay the only source of tokens/images. Kit stays the visual primitive layer: Fusion components
  call Kit builders and bind state with `scope:Hydrate(kitInstance)({ ... })`, or use `scope:New` with Theme tokens for plain
  elements. Kit is not rewritten. `Window.luau` stays; a Fusion screen mounts into `Window` body.
- Client state for UI: one `src/client/State.luau` (frontend-developer) holding Fusion `Value`s fed from Net remotes/attributes,
  **only with the fields the migrated screens need** (pilot: gold, soulstars, owned passes, last ShopResult).
- Headless UI check: Fusion creates real Instances and connects `Activated` via `OnEvent`, so `tools/lune/ui.luau` should
  keep working. Risk: Fusion's `typeof(x) == "Instance"` checks and its RunService-driven updates (Tween/Spring) inside the
  sandbox. The pilot's first step is proving that.
- Screen order: **Shop** (pilot: self-contained, 326 lines, state-driven buttons) -> go/no-go -> Atlas -> Forge -> Star Web
  -> Abilities -> Inventory. **HUD last or never** (per-frame updates, recently rebuilt, imperative is fine there).
- README rule "UI only from Kit" and `.claude/agents/ui-designer.md` need a line about Fusion after go (user edits `.claude`).

**Cost:** zero money; time is the cost (~3.5k lines if fully migrated). Mobile: Fusion 0.3 updates lazily, no frame cost
when nothing changes; the pilot must show no extra per-frame work in the Shop.

### Task order N12

| # | Owner | Task | Depends |
|---|---|---|---|
| N12.1 | ui-designer | Spike: add Fusion, prove it runs in Lune sandbox + UI check with one Hydrated Kit button | N8 |
| N12.1b | backend-developer | Only if N12.1 reports sandbox gaps: fix them in `tools/lune/**` | N12.1 |
| N12.2 | frontend-developer | `Client/State.luau` with the Shop's fields | N12.1 green |
| N12.3 | ui-designer | Shop window in Fusion, same look/behavior, UI check green | N12.2 |
| N12.4 | code-reviewer + Micha | Review + playtest; go/no-go recorded here | N12.3 |

Further screens (Atlas -> Forge -> Star Web -> Abilities -> Inventory) are planned only after a "go" in N12.4.

---

## 6. Cross-server announcements (N13)

**Matchmaking: dropped (D3).** Rifts are solo on per-player arenas inside the current server and Roblox's server fill
already places players into hubs. Matchmaking only makes sense with co-op rifts, which are not designed; that would be a
new feature spec, not platform work.

**Announcements (D4):** MessagingService carries all live announcements (push, best effort, ~1 KB messages, quotas scale
with players). MemoryStore is used **only** for a short "recent announcements" list so players who join later still see them.

Scope:
1. **Admin broadcast:** Micha sends a text to all servers via the Open Cloud Messaging API
   (`POST /cloud/v2/universes/{id}:publishMessage`, topic `lr_announce`) from `lune run tools/support announce "<text>"`.
   Needs `universe-messaging-service:publish` on the support key. Use: "update in 5 min".
2. **Player feats:** exactly two kinds, `rebirth` and `boss_first_clear` (first time *this player* defeats a given region's
   boss). Published by the server where it happened; the receiving server resolves the display name.
   Rate limits: per player 1 per 30 s, per server 10 published per minute; excess is dropped silently.
3. **Recent list for late joiners:** MemoryStore sorted map `lr_announce_recent`, entry key = message `id`, sort key =
   publish time, TTL 600 s. On `PlayerAdded`, the server reads the 5 newest and sends them to that player only.
   Writers: the publishing server for feats; for admin messages every receiving server upserts the same `id`
   (idempotent; admin messages are rare, quota `1000 + 120 x CCU` requests/min is ample). Read once per join, never polled.

**Contract (backend owns, fixed):**
- Topic `lr_announce`, message `{ id: string, kind: "admin"|"rebirth"|"boss_first_clear", t: number, userId: number?, region: string?, value: number?, text: string? }`
  (`id` = `HttpService:GenerateGUID(false)` or generated by the CLI; `t` = `os.time()`; `text` only for `admin`, max 200 chars,
  never published by game servers; `value` = rebirth count for `rebirth`).
- Remote `Net.Announce` server->client, payload `{ id: string, kind: string, t: number, name: string?, region: string?, value: number?, text: string?, recent: boolean }`
  (`recent = true` for entries replayed from the MemoryStore list on join). Client dedupes by `id`.
- Client toast: frontend-developer (queue/timing, dedupe), ui-designer (look).

| # | Owner | Task | Depends |
|---|---|---|---|
| N13.1 | backend-developer | `Systems/Announce.luau`: subscribe/publish, feats from Rebirth + boss kill, rate limits, recent list, `Net.Announce`; sandbox MessagingService (from N9.1) + MemoryStore sorted-map stub | N9.1 |
| N13.2 | backend-developer | `announce` command in `tools/support.luau` | N11.1, N13.1 |
| N13.3 | frontend-developer | Toast queue from `Net.Announce` (dedupe by `id`, recent entries shown once after spawn) | N13.1 |
| N13.4 | ui-designer | Toast look (Kit/Theme; Fusion only if N12.4 is go) | N13.3 |
| N13.5 | code-reviewer | Review: servers cannot publish `admin`, no free text from players, errors never break gameplay | N13.4 |

---

## Decisions (made by the user, 2026-11-01)

| # | Question | Chosen | Why the others were not taken |
|---|---|---|---|
| D1 | Fusion now? | **Pilot on the Shop window, then go/no-go** | Full migration now would churn untested screens; staying on Kit leaves the tooling risk unanswered; React-lua is heavier. |
| D2 | Analytics stack | **Server facade, Roblox AnalyticsService now; GameAnalytics only later if needed (parked)** | GameAnalytics adds keys, HTTP and a third party before daily data has proven too slow; PlayFab has no Roblox SDK. |
| D3 | Matchmaking | **None (dropped)** | No co-op design exists; it would be a new feature, not platform work. |
| D4 | Cross-server announcements | **Admin broadcast + `rebirth` and `boss_first_clear` feats over MessagingService; MemoryStore only for a recent-announcements list for late joiners** | Without the recent list, players joining after a broadcast (e.g. "update in 5 min") miss it; "none now" gives up the admin channel. |
| D5 | Support tool where | **Local command-line tool first; GitHub workflow version parked** | A workflow needs the key in GitHub and an open IP range; not needed yet. |
| D6 | ProfileStore vs. playtest N1 | **N9 lands before the saving part of N1 (TEST-SAVING)** | Otherwise TEST-SAVING would be played on code about to be replaced. |

## Assumptions (planner, reversible)

- Wally, not pesde; `wally.lock` committed.
- Store `LootRush_Profile_v3`, key `p_<UserId>`, `profile.Data = { v, data }`.
- Tooling (`tools/**`, `default.project.json`, CI, setup) is done by backend-developer in this plan.
- Analytics events never on per-hit/per-frame paths; per run, per purchase, per milestone only.
- `boss_first_clear` = first clear per player per region (not server-wide or global first). No save field tracks boss clears
  today (`Profile.atlas` stores only highest depth per region); if detection needs a field it goes through `Profile.luau` DEFAULTS.
- Recent list: 5 entries, 10 min TTL; admin entries upserted by every receiving server (idempotent by `id`).

## Final task order

1. **N8.1** package tooling (backend-developer) -> N8.2 review (code-reviewer). Start condition: see "Sequencing against running work".
2. **N10.1** analytics facade (backend-developer) - no package, may run before or alongside N8; N10.2 review.
3. **N9.1** ProfileStore spike + sandbox (backend-developer) -> N9.2 `Data.luau` rewrite -> N9.3 review -> N9.4 TEST-SAVING update (planner) -> Micha plays TEST-SAVING (N1 saving part).
4. **N12.1** Fusion spike (ui-designer) - after N8, parallel to N9 (different lane) -> N12.1b if gaps -> N12.2 -> N12.3 -> N12.4 go/no-go.
5. **N11.0** API key (Micha, any time) -> **N11.1** read-only CLI -> N11.2 writes -> N11.3 review -> N11.4 docs. After N9.2.
6. **N13.1** announcements server (backend-developer) -> N13.2 CLI `announce` -> N13.3 toast queue -> N13.4 toast look -> N13.5 review. Last.

Blocking: N8 -> N9, N12; N9.1 -> N13.1; N9.2 -> N11; N11.1 -> N13.2. Parallel: N10.1 || N8/N9 (but not in the same files at
the same time, see below); N12 || N9/N10/N11. One backend-developer runs one backend task at a time.

Dropped/parked: matchmaking (dropped, D3); GameAnalytics sink, former N10b (parked, D2); support workflow on GitHub,
former N11-with-workflow (parked, D5).

## Sequencing against running work

Other agents are editing `src/`, `tools/`, `tests/` and `.github/` right now.
- **N8.1 starts only when no other agent is editing `tools/`, `tests/`, `wally.toml`, `default.project.json` or
  `.github/workflows/ci.yml`.** It changes setup/CI/Rojo mapping that every other task's check run depends on.
- **N9 touches `src/server/Systems/Data.luau` and the Lune sandbox (`tools/lune/lib/Sandbox.luau`)** plus `tests/Data*.spec.luau`.
  Do not run N9 while any other task edits those files (including N10.1 if it needs a `Profile.luau` field, and N13.1, which
  extends the same sandbox).
- N10.1 touches many server Systems (call sites); schedule it when no other backend task is editing gameplay Systems.
- N12.1 touches `wally.toml` (Fusion line) and the Shop controller; run it after N8 is merged.
- Every brief starts with "run `git status` first and only touch your area".

## Acceptance criteria

- N8: `bash tools/check.sh` green on a clean clone (CI) with packages installed; `luau-lsp` resolves `require(ServerScriptService.ServerPackages.ProfileStore)` types under `--!strict`.
- N9: all Lune tests green; Studio: TEST-SAVING passes (rejoin keeps gold/level/inventory; second server never loads an active save; Robux test purchase credited exactly once); store `LootRush_Profile_v3` visible in Creator Hub Data Stores Manager.
- N10.1: in a published test session, Creator Hub Analytics shows the onboarding funnel and gold economy within 24 h; no event contains a name or text.
- N11: `get` prints a player's save; `set data.gold` on an offline player shows up after rejoin; `set` on an online player is refused; `delete` removes the entry.
- N12: Shop in Fusion looks and behaves as before on 4 UI-check sizes and on a phone; UI check reports no new issues; go/no-go written in this spec.
- N13: admin broadcast appears on all running test servers within seconds; a player joining within 10 min after it sees it once
  (marked recent); a rebirth and a first region-boss clear show on other servers with the player's display name; feats rate-limited;
  nothing breaks when MessagingService or MemoryStore errors.

## Parked / dropped

- Dropped: matchmaking and co-op rifts (D3).
- Parked: GameAnalytics sink and client init, former N10b (D2; reopen if 24 h AnalyticsService data blocks balancing).
- Parked: support tool as a GitHub `workflow_dispatch` (D5).
- Parked: MemoryStore weekly depth leaderboard; Open Cloud user-restrictions (ban) command; PlayFab; Fusion migration beyond the Shop (until N12.4 go).

---

## Briefs (first task of each item)

Send order: N8.1 (when its start condition holds) -> N10.1 -> N9.1 -> N12.1 -> N11.1 -> N13.1. Details in "Final task order".

### Brief N8.1 - backend-developer: Wally package tooling

Other agents may be editing files concurrently; run git status first and only touch your area.
Start condition: no other agent is editing `tools/`, `tests/`, `wally.toml`, `default.project.json` or `.github/workflows/ci.yml`.

**Context.** Loot Rush (Roblox ARPG, Rojo, Luau `--!strict`). No packages are used yet. `rokit.toml` pins `wally 0.3.2`.
`wally.toml` has only comments. `.gitignore` ignores `Packages/`, `ServerPackages/`, `wally.lock`. CI runs `tools/check.sh`
(format, lint, types, build, test, ui) after `tools/setup.sh`. The Lune sandbox (`tools/lune/lib/Sandbox.luau`) loads the
Rojo-built place. Spec: `docs/specs/PLATFORM-STACK.md` sections 1-2.

**Task.**
1. `wally.toml`: `[server-dependencies] ProfileStore = "lm-loleris/profilestore@1.0.3"` (only this one now).
2. `default.project.json`: `ReplicatedStorage.Packages` <- `Packages`, `ServerScriptService.ServerPackages` <- `ServerPackages`.
   If Rojo 7.7 cannot tolerate a missing folder, make `setup.sh`/`check.sh` always run `wally install` first.
3. `tools/setup.sh` / `tools/check.sh` / `.github/workflows/*.yml`: run `wally install` before sourcemap/build; add
   `wally-package-types` (via rokit) so luau-lsp keeps package types; keep selene/StyLua scoped to `src`.
4. Remove `wally.lock` from `.gitignore`, commit the lock file.
5. Prove it: a throwaway `require` of ProfileStore type-checks (do not leave gameplay code using it; N9 does that).

**Definition of done.** `bash tools/check.sh` green locally and in CI from a clean clone; `Packages`/`ServerPackages` appear in the
built place; README "Setup" mentions `wally install` (one line).

**Do not touch.** `src/**` gameplay, `tests/**` (other agents edit them concurrently), `docs/**`.

### Brief N9.1 - backend-developer: ProfileStore spike in the Lune sandbox

Other agents may be editing files concurrently; run git status first and only touch your area.
Precondition: N8 merged. Must land before Micha plays TEST-SAVING (user decision D6).

**Context.** Saves today: `src/server/Systems/Data.luau` (own session lock, store `LootRush_Profile_v2`, value `{ v, data, lock }`),
schema in `src/shared/Profile.luau`, tests `tests/Data.spec.luau`, `tests/DataLock.spec.luau`, `tests/Profile.spec.luau`.
The Lune sandbox fakes DataStores in `tools/lune/lib/Sandbox.luau` (`Sandbox:dataStore`): `UpdateAsync(k, fn)` calls `fn(value)` only,
no `DataStoreKeyInfo`, ignores returned userIds/metadata; there is no MessagingService stub. N8 installed
`lm-loleris/profilestore@1.0.3` into `ServerScriptService.ServerPackages`. Spec: `docs/specs/PLATFORM-STACK.md` section 2.

**Task.**
1. Extend the sandbox so ProfileStore runs unmodified: `UpdateAsync(k, fn)` passes `(value, keyInfo)` with
   `keyInfo:GetUserIds()`, `GetMetadata()`, `Version`, `CreatedTime`, `UpdatedTime`, stores returned userIds/metadata; add whatever else
   ProfileStore calls at startup (DataStore access check, `GetAsync` options); MessagingService `PublishAsync`/`SubscribeAsync`
   delivered in-process via the scheduler (N13.1 reuses this stub, keep it generic: any topic, `{ Data, Sent }` message shape).
2. New test `tests/ProfileStore.spec.luau`: start a session for `p_1` in store `LootRush_Profile_v3`, change data, `Save()`, see it in
   `sim.datastores`; end session; second `StartSessionAsync` while a session is active elsewhere does not return two active profiles.
3. Write down for the planner (in your final report, not a file): the raw stored value shape (where `Data`, session and
   user IDs live), ProfileStore's session hand-off timing, and every sandbox addition.

**Contract to honor.** Do not change `Data.luau` yet (N9.2). Store name `LootRush_Profile_v3`, key `p_<UserId>`.

**Definition of done.** All existing tests still green; the new spec green; `Sandbox.luau` changes documented in its header comment.

**Do not touch.** `src/**`, existing `tests/Data*.spec` (concurrently edited by others), `docs/**`.

### Brief N10.1 - backend-developer: analytics facade + AnalyticsService

Other agents may be editing files concurrently; run git status first and only touch your area.
User decision D2: AnalyticsService is the only sink; GameAnalytics is parked (do not add it, but keep `setSink` so it could be added later).

**Context.** No analytics exist; `Systems/Metrics.luau` is a local dev tool (keep it). Server systems: Rift (runs, regions, depth),
Shop, Forge, Pets, Rebirth, Monetization (ProcessReceipt), Inventory/Loot (pickup/equip), Combat (kills). Spec:
`docs/specs/PLATFORM-STACK.md` section 3 (event contract and event list are fixed there).

**Task.**
1. `src/server/Systems/Analytics.luau` with `economy`, `progression`, `onboarding`, `custom` exactly as in the spec contract.
   Sink = `AnalyticsService` (`LogEconomyEvent`, `LogProgressionEvent` family, `LogOnboardingFunnelStepEvent`, `LogCustomEvent`),
   every call in `pcall`, no-op in Studio (`RunService:IsStudio()`), sinks pluggable (`Analytics.setSink(fn)`) for tests and for a later GameAnalytics sink.
2. Call sites per the spec list (onboarding steps 1-7, gold/soulstars sources and sinks with ending balance, rift progression
   start/complete/fail with depth, the 5 custom events). Onboarding "first" detection from existing save data; if a field is unavoidable,
   add it via `Profile.luau` DEFAULTS.
3. `tests/Analytics.spec.luau`: fake sink records events for a booted sim: join -> onboarding 1; enter rift -> progression start;
   shop purchase -> gold sink with correct ending balance.

**Rules.** UserId only, no names/text in fields; never per-hit or per-frame; field values from fixed enums/ids.

**Definition of done.** `bash tools/check.sh` green; event list in the report matches the spec.

**Do not touch.** Client code, `docs/**`, packages (no GameAnalytics yet).

### Brief N11.1 - backend-developer: Open Cloud support CLI (read-only)

Other agents may be editing files concurrently; run git status first and only touch your area.
Preconditions: N9.2 merged; Micha has created key `loot-rush-support` (N11.0). User decision D5: local CLI only, no GitHub workflow.

**Context.** After N9, saves live in data store `LootRush_Profile_v3`, key `p_<UserId>`, ProfileStore value format (documented in
`docs/specs/PLATFORM-STACK.md` section 2 after N9.1). Tooling uses Lune (`tools/lune/*`); publishing already calls Open Cloud with curl
(`tools/publish.sh`). Spec section 4.

**Task.** `tools/support.luau` (run with `lune run tools/support <cmd>`), reading `ROBLOX_SUPPORT_API_KEY` and `ROBLOX_UNIVERSE_ID`
from env, using Open Cloud v2 `GET /cloud/v2/universes/{u}/data-stores/LootRush_Profile_v3/entries/p_<id>` and the revisions list:
- `get <userId>`: pretty-print `data`, schema `v`, whether a session is active, user IDs.
- `revisions <userId>`: list revision ids with timestamps.
Clear errors for 401/403 (point to key scopes), 404 (no save). A section in `docs/PUBLISH.md` is written by the planner; put usage in the script header.

**Definition of done.** Against the test universe: `get` for Micha's UserId prints his save; `revisions` lists entries. No key in the repo.

**Do not touch.** `src/**`, `tests/**`, writes (N11.2).

### Brief N12.1 - ui-designer: Fusion spike (one Hydrated Kit button)

Other agents may be editing files concurrently; run git status first and only touch your area.
Precondition: N8 merged. User decision D1: this is a pilot; further screens only after a recorded go (N12.4).

**Context.** UI is imperative: `src/client/UI/Kit.luau` (builders), `Window.luau`, tokens `Shared/UI/Theme.luau`, images
`Shared/UI/Assets.luau`; screens are controllers in `src/client/Controllers/`. Headless UI check `tools/lune/ui.luau` (Lune sandbox)
presses every button with an `Activated` handler. The user chose Fusion; plan is a pilot (spec `docs/specs/PLATFORM-STACK.md` section 5).
Package tooling exists (N8).

**Task.**
1. Add `Fusion = "elttob/fusion@0.3.0"` to `[dependencies]` in `wally.toml`, `wally install`.
2. In the Shop window only, replace the buy button of one offer card with a Fusion-bound version: create it with `Kit.button(...)`,
   then `scope:Hydrate(button)({ ... })` binding its enabled state to a `Value` (affordable or not) and `[OnEvent "Activated"]` to the
   existing buy request. Clean up the scope when the window closes.
3. Run `bash tools/check.sh` incl. `ui`. Report: does Fusion load in the sandbox, does the UI check find and press the button, any
   sandbox gaps (e.g. `typeof` checks on Instances, RunService updates), any strict-type friction.

**Definition of done.** Check green, Shop looks identical, short report with go/blocked and the exact sandbox issues (for a tooling brief if blocked).

**Do not touch.** Other screens, Kit/Theme/Assets internals, `tools/**` (report gaps instead), server code.

### Brief N13.1 - backend-developer: cross-server announcements (server side)

Other agents may be editing files concurrently; run git status first and only touch your area.
Precondition: N9.1 merged (MessagingService stub) and no other task is editing `tools/lune/lib/Sandbox.luau`.
User decision D4: admin broadcast + feats `rebirth` and `boss_first_clear`, MessagingService for delivery, MemoryStore only for a recent list.

**Context.** No cross-server code exists; `src/shared/Net.luau` defines remotes; `src/server/Util/RateLimit.luau` exists;
`Systems/Rebirth.luau` handles rebirth; boss kills happen in the rift/enemy systems. `Profile.atlas` stores only the highest depth per region,
no boss-clear flags. Spec `docs/specs/PLATFORM-STACK.md` section 6 (contract fixed there).

**Task.**
1. `Systems/Announce.luau`: subscribe topic `lr_announce` on start (in `pcall`, retry with backoff). `Announce.feat(player, kind, fields)`
   publishes `{ id, kind, t, userId, region?, value? }` with rate limits (1 per player per 30 s, 10 per server per minute, excess dropped).
   On receive: resolve display name, fire `Net.Announce` to all clients with the spec payload (`recent = false`). Admin messages
   `{ id, kind = "admin", t, text }` come only from Open Cloud; pass through with text truncated to 200 chars; servers never publish `admin`.
2. Feats: call `feat(player, "rebirth", { value = rebirthCount })` from Rebirth; `feat(player, "boss_first_clear", { region })` the first time
   this player defeats that region's boss. If detecting "first" needs a save field, add it via `Profile.luau` DEFAULTS (+ sanitize).
3. Recent list: MemoryStore sorted map `lr_announce_recent`, key = `id`, sort key = `t`, TTL 600 s. Publishing server writes feats; every receiving
   server upserts admin entries (same `id`, idempotent). On `PlayerAdded` read the 5 newest once and `FireClient` them with `recent = true`. Never poll.
4. Sandbox: extend `tools/lune/lib/Sandbox.luau` with a minimal `MemoryStoreService:GetSortedMap` stub (`SetAsync(key, value, ttl, sortKey)`,
   `GetRangeAsync(direction, count)`), documented in the header comment.
5. Tests `tests/Announce.spec.luau`: feat on one server -> client receives `Net.Announce`; second feat within 30 s dropped; a player joining after a
   feat receives it with `recent = true`; MessagingService/MemoryStore throwing does not error the caller.

**Definition of done.** `bash tools/check.sh` green; MessagingService/MemoryStore errors never break gameplay; `Net.Announce` payload exactly as in the spec.

**Do not touch.** Client code (N13.3), `tools/support.luau` (N13.2), `docs/**`.
