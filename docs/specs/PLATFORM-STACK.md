# Platform stack: Fusion, ProfileStore, cross-server, Open Cloud support, analytics

Status: planned (nothing of this is built). Roadmap rows N8-N13 in `docs/ROADMAP.md`.
Written against HEAD `a773170`. Package versions checked on the Wally index on 2026-11-01.

## Goal

Move Loot Rush onto the stack the user chose for running a live game:

| Item | Chosen by user | Roadmap |
|---|---|---|
| Package tooling (Wally) | prerequisite for everything below | N8 |
| ProfileStore for player saves | ProfileStore by loleris | N9 |
| Live tracking / balancing | GameAnalytics and/or PlayFab, AnalyticsService evaluated | N10 |
| Customer support on player data | Open Cloud Data Stores v2 | N11 |
| UI framework | Fusion, replacing imperative Kit UI | N12 |
| Cross-server | MemoryStoreService (matchmaking, announcements), MessagingService only if justified | N13 |

Non-goals: co-op rifts, server browser, trading, global leaderboards, PlayFab LiveOps, an admin web panel,
a big-bang UI rewrite. See "Parked".

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
| GameAnalytics SDK | `gameanalytics/gameanalytics-sdk` | `3.0.0` | shared |

N8 only adds ProfileStore. Fusion is added in N12, GameAnalytics in N10b. That way no unused package ships.

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
- `docs/TEST-SAVING.md` gets a ProfileStore section (planner, after N9 lands). Do N9 **before** the TEST-SAVING round in N1,
  otherwise that playtest tests code about to be replaced.

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

**Evaluation:**

| | Roblox AnalyticsService | GameAnalytics | PlayFab |
|---|---|---|---|
| Package | built-in | `gameanalytics/gameanalytics-sdk@3.0.0` (Wally) | no official Roblox SDK (Microsoft ships C#/Java/JS/Python/Lua for Defold/Corona; `@rbxts/playfab` is community, roblox-ts only) |
| Events | economy, funnel, onboarding funnel, progression, custom (max 100 custom event names) | business, resource, progression, design, error + remote configs | events + player data + LiveOps (overlaps ProfileStore) |
| Latency | daily aggregation, up to 24 h | near real time | near real time |
| Setup | none, server only, published games only (not Studio) | account, game key + secret key in server code, `HttpService.HttpEnabled` | title, secret key, hand-written REST over HttpService |
| Privacy | stays with Roblox | third party (UserId + device info) | third party |
| Cost | free | core free, raw export paid | free dev tier, then paid |

**Recommendation:** one server facade `Systems/Analytics.luau` that gameplay calls once; sink 1 = AnalyticsService (now),
sink 2 = GameAnalytics (N10b, only if the user picks it and keys exist). PlayFab not adopted: no SDK, duplicates ProfileStore
and AnalyticsService, adds a secret and HTTP budget for no current need. See Decision D2.

**Event contract (fixed, backend owns):** `Analytics.economy(player, flow: "source"|"sink", currency: "gold"|"soulstars", amount, balance, txType, sku)`,
`Analytics.progression(player, "rift_<region>", "start"|"complete"|"fail", depth)`, `Analytics.onboarding(player, step, name)`,
`Analytics.custom(player, name, value?, fields?)`. Field values are enums/ids/numbers only, never free text.

- Onboarding steps: 1 joined, 2 first_kill, 3 first_pickup, 4 first_equip, 5 first_rift, 6 first_boss, 7 first_return_hub.
- Economy: gold sources (enemy, sell, salvage, shop pack), sinks (shop, forge, eggs); soulstars sources (robux, rebirth), sinks (shop, star_egg).
- Progression: every rift run per region, depth as level (complements `RiftResult`).
- Custom (<= 5 names): `rebirth`, `pet_hatch` (field rarity), `robux_purchase` (field sku), `skill_level` (field skill), `forge_use` (field action).
- Onboarding "first" flags: derived from existing save fields where possible; if a new save field is needed it goes
  through `Profile.luau` DEFAULTS (backend).

**Privacy/policy:** UserId only; never Name/DisplayName, chat or free text; no custom IDs. AnalyticsService needs no consent flow.
If GameAnalytics is added: mention third-party analytics in the experience description, keep `setEnabledEventSubmission`
wired to a server flag (kill switch), and on a right-to-erasure request also file a deletion with GameAnalytics for that UserId.

**User actions:** none for AnalyticsService (dashboards: Creator Hub -> experience -> Analytics). For GameAnalytics:
free account at gameanalytics.com, create game (platform Roblox) -> Game Key + Secret Key -> GitHub env `Roblox` secrets
`GA_GAME_KEY`, `GA_SECRET_KEY`; publish step injects them into a gitignored server module (never committed);
`HttpService.HttpEnabled = true` set via `default.project.json` (publish replaces the place, so Rojo is authoritative).
HttpService budget: 500 requests/min per server (GA batches, well within).

### Task order N10

| # | Owner | Task | Depends |
|---|---|---|---|
| N10.1 | backend-developer | `Systems/Analytics.luau` facade + AnalyticsService sink + call sites; Lune test with a fake sink | none (no package) |
| N10.2 | code-reviewer | Review: no PII, server only, no hot-path spam (no per-hit events) | N10.1 |
| N10b.1 | backend-developer | GameAnalytics sink behind keys, key injection at publish | N8, N10.1, D2 = GA |
| N10b.2 | frontend-developer | GameAnalytics client init in `init.client.luau` (SDK needs its client part) | N10b.1 |

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

**Depends on N9** (value format). Read-only first (N11.1), writes second (N11.2).

**User actions:** Creator Hub -> Open Cloud -> API Keys -> new key `loot-rush-support`, system **universe-datastores**:
`objects:list`, `objects:read`, `objects:update`, `objects:delete`, `versions:list`, `versions:read`, only for the test (later live)
universe; IP restriction = your own IP (local use). Keep it out of the repo: env var `ROBLOX_SUPPORT_API_KEY` locally.
Separate from the publish key (least privilege). Only if the user wants support from GitHub (D5): also store it in env
`Roblox` and add a `workflow_dispatch` workflow (then IP `0.0.0.0/0`). Optional: Creator Hub -> Data stores -> RTBF template for `p_{UserId}`.

**Cost:** free; volume is a handful of calls.

---

## 5. Fusion UI (N12)

**Package:** `elttob/fusion@0.3.0` (latest release; `main` is already `0.4.0-dev1`, so expect API breaks at 0.4).
Alternative checked: React-lua `jsdotlua/react` + `jsdotlua/react-roblox` `17.2.1` - heavier, JS idioms, more boilerplate; not recommended for a 1-person team.

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
| N12.1 | ui-designer | Spike: add Fusion, prove it runs in Lune sandbox + UI check with one Hydrated Kit button | N8, D1 |
| N12.2 | frontend-developer | `Client/State.luau` with the Shop's fields | N12.1 |
| N12.3 | ui-designer | Shop window in Fusion, same look/behavior, UI check green | N12.2 |
| N12.4 | code-reviewer + Micha | Review + playtest; go/no-go recorded here | N12.3 |

---

## 6. Cross-server: matchmaking and announcements (N13)

**Matchmaking:** not needed today. Rifts are solo on per-player arenas inside the current server; Roblox's own server
fill already "matches" players into hubs. Matchmaking (MemoryStore queue + `TeleportService:ReserveServer`) only makes
sense with co-op rifts, which are not designed. Decision D3.

**Announcements:** MessagingService is the justified primitive here: it is pub/sub (push) and best effort, messages
are small (~1 KB) and quotas scale with player count. MemoryStore would have to be polled, which costs request units
(quota `1000 + 120 x CCU` per minute) for no gain. MemoryStore is used only if D4 includes "show recent announcements
to players who join later": one sorted map `announce_recent`, TTL 10 min, last 5 entries (quota `64 KB + 1.2 KB x users` is plenty).

Minimal scope (D4 recommendation):
1. **Admin broadcast:** Micha sends a text to all servers via the Open Cloud Messaging API
   (`POST /cloud/v2/universes/{id}:publishMessage`, topic `lr_announce`) from `tools/support.luau announce "<text>"`.
   Needs `universe-messaging-service:publish` on the support key. Use: "update in 5 min".
2. **Player feats** (only those the user picks): e.g. rebirth, first clear of a region boss. Payload
   `{ kind: string, userId: number, region: string?, value: number? }`; the receiving server resolves the display name.
   Server-side rate limit per sender (1 per 30 s) and per server (10/min).

Contract (backend owns): topic `lr_announce`; new remote `Net.Announce` server->client `{ kind, text?, name?, region?, value? }`.
Client toast: ui-designer (look), frontend-developer (queue/timing).

| # | Owner | Task | Depends |
|---|---|---|---|
| N13.1 | backend-developer | `Systems/Announce.luau`: subscribe/publish, rate limits, `Net.Announce`; sandbox MessagingService stub (shared with N9.1) | D4 |
| N13.2 | backend-developer | `announce` command in `tools/support.luau` | N11.1, N13.1 |
| N13.3 | frontend-developer | Toast queue from `Net.Announce` | N13.1 |
| N13.4 | ui-designer | Toast look (Kit/Theme; Fusion if N12 is go) | N13.3 |

---

## Decisions needed (user)

| # | Question | Options | Recommendation |
|---|---|---|---|
| D1 | Fusion now? | (a) Pilot on Shop, then go/no-go; (b) commit to full migration now; (c) stay with Kit until after release; (d) React-lua instead | **(a)**. Nothing in the UI is playtested yet (N1); a pilot answers the sandbox/tooling risk cheaply without churning screens under test. |
| D2 | Analytics stack | (a) AnalyticsService now behind a facade, GameAnalytics later if daily data is not enough; (b) AnalyticsService + GameAnalytics both now; (c) GameAnalytics only; (d) PlayFab | **(a)**. Free, no keys, no third-party data, the facade makes adding GA a one-file job. Choose (b) if you want real-time numbers from the first public test. PlayFab not recommended. |
| D3 | Matchmaking | (a) none; (b) co-op rifts with reserved servers + MemoryStore queue (new feature spec) | **(a)**. No co-op design exists; it would be a new milestone, not platform work. |
| D4 | Cross-server announcements | (a) admin broadcast + 1-2 player feats you pick, MessagingService only; (b) (a) + MemoryStore "recent" list for late joiners; (c) none now | **(a)**, feats: rebirth and first region-boss clear. |
| D5 | Support tool where | (a) local CLI only; (b) also a GitHub `workflow_dispatch` (usable from phone, key in env `Roblox`, IP open) | **(a)** first; (b) is one small task later. |
| D6 | Timing of ProfileStore vs. playtest N1 | (a) N9 before the TEST-SAVING part of N1; (b) after N1 | **(a)**, otherwise TEST-SAVING is played twice. |

## Assumptions (planner, reversible)

- Wally, not pesde; `wally.lock` committed.
- Store `LootRush_Profile_v3`, key `p_<UserId>`, `profile.Data = { v, data }`.
- Tooling (`tools/**`, `default.project.json`, CI, setup) is done by backend-developer in this plan.
- Analytics events never on per-hit/per-frame paths; per run, per purchase, per milestone only.

## Recommended order

1. N8 package tooling (backend) ->
2. N9 ProfileStore (backend, review, TEST-SAVING) - before N1's saving test and before N4 monetization live.
3. N10.1 analytics facade + AnalyticsService (backend) - can start in parallel with N9 (no package).
4. N11 support CLI read-only, then writes (backend) - after N9.
5. N12 Fusion pilot (ui-designer + frontend) - after N8 and D1, parallel to 2-4 (different lane); after N1 UI testing is preferred.
6. N13 announcements - last, only useful with live traffic (several servers).

Parallel: N10.1 || N9; N12 || N9/N10/N11. Blocking: N8 -> N9, N12, N10b; N9 -> N11; N11.1 -> N13.2.

## Acceptance criteria

- N8: `bash tools/check.sh` green on a clean clone (CI) with packages installed; `luau-lsp` resolves `require(ServerScriptService.ServerPackages.ProfileStore)` types under `--!strict`.
- N9: all Lune tests green; Studio: TEST-SAVING passes (rejoin keeps gold/level/inventory; second server never loads an active save; Robux test purchase credited exactly once); store `LootRush_Profile_v3` visible in Creator Hub Data Stores Manager.
- N10.1: in a published test session, Creator Hub Analytics shows the onboarding funnel and gold economy within 24 h; no event contains a name or text.
- N11: `get` prints a player's save; `set data.gold` on an offline player shows up after rejoin; `set` on an online player is refused; `delete` removes the entry.
- N12: Shop in Fusion looks and behaves as before on 4 UI-check sizes and on a phone; UI check reports no new issues; go/no-go written in this spec.
- N13: admin broadcast appears on all running test servers within seconds; feats rate-limited; nothing breaks when MessagingService errors.

## Parked

Co-op rifts and matchmaking; MemoryStore weekly depth leaderboard; Open Cloud user-restrictions (ban) command; PlayFab; GameAnalytics remote configs / A/B tests.

---

## Briefs (first task of each item)

### Brief N8.1 - backend-developer: Wally package tooling

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

**Context.** Saves today: `src/server/Systems/Data.luau` (own session lock, store `LootRush_Profile_v2`, value `{ v, data, lock }`),
schema in `src/shared/Profile.luau`, tests `tests/Data.spec.luau`, `tests/DataLock.spec.luau`, `tests/Profile.spec.luau`.
The Lune sandbox fakes DataStores in `tools/lune/lib/Sandbox.luau` (`Sandbox:dataStore`): `UpdateAsync(k, fn)` calls `fn(value)` only,
no `DataStoreKeyInfo`, ignores returned userIds/metadata; there is no MessagingService stub. N8 installed
`lm-loleris/profilestore@1.0.3` into `ServerScriptService.ServerPackages`. Spec: `docs/specs/PLATFORM-STACK.md` section 2.

**Task.**
1. Extend the sandbox so ProfileStore runs unmodified: `UpdateAsync(k, fn)` passes `(value, keyInfo)` with
   `keyInfo:GetUserIds()`, `GetMetadata()`, `Version`, `CreatedTime`, `UpdatedTime`, stores returned userIds/metadata; add whatever else
   ProfileStore calls at startup (DataStore access check, `GetAsync` options); MessagingService `PublishAsync`/`SubscribeAsync`
   delivered in-process via the scheduler.
2. New test `tests/ProfileStore.spec.luau`: start a session for `p_1` in store `LootRush_Profile_v3`, change data, `Save()`, see it in
   `sim.datastores`; end session; second `StartSessionAsync` while a session is active elsewhere does not return two active profiles.
3. Write down for the planner (in your final report, not a file): the raw stored value shape (where `Data`, session and
   user IDs live), ProfileStore's session hand-off timing, and every sandbox addition.

**Contract to honor.** Do not change `Data.luau` yet (N9.2). Store name `LootRush_Profile_v3`, key `p_<UserId>`.

**Definition of done.** All existing tests still green; the new spec green; `Sandbox.luau` changes documented in its header comment.

**Do not touch.** `src/**`, existing `tests/Data*.spec` (concurrently edited by others), `docs/**`.

### Brief N10.1 - backend-developer: analytics facade + AnalyticsService

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

**Precondition:** user decision D4 (which feats). Context: no cross-server code exists; `src/shared/Net.luau` defines remotes;
`src/server/Util/RateLimit.luau` exists. Spec section 6.

**Task.** `Systems/Announce.luau`: subscribe topic `lr_announce` on start (in `pcall`, retry with backoff), `Announce.feat(player, kind, fields)`
publishes `{ kind, userId, region?, value? }` with rate limits (1 per player per 30 s, 10 per server per minute); on receive, resolve display name
and fire `Net.Announce` to all clients `{ kind, name?, region?, value? }`; admin messages `{ kind = "admin", text }` (developer-authored, only ever
published via Open Cloud) are passed through, text truncated to 200 chars; servers never publish `admin` themselves. Call `feat` from the systems picked in D4. Sandbox MessagingService stub
from N9.1; test: publish on server -> client receives `Net.Announce`; rate limit drops the 2nd feat within 30 s.

**Definition of done.** Check green; MessagingService errors never break gameplay.

**Do not touch.** Client code, `docs/**`.
