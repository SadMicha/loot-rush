# Analytics (Roblox Open Cloud)

Experience metrics come from the **Roblox Open Cloud Analytics Query API** (beta). The game itself
logs only through Roblox `AnalyticsService` (ROADMAP N10, D2; GameAnalytics is parked), so the
Creator Hub dashboards and this API show the same data.

## How to fetch

GitHub → Actions → **Fetch analytics** → Run workflow (inputs: days back, optional universe ID,
commit yes/no). It also runs every Monday 06:00 UTC.

- Script: `tools/fetch-analytics.py`; queries: `tools/analytics-queries.json` (metric, granularity,
  optional breakdown such as `Platform` or `Country`).
- Output: `docs/analytics/<YYYY-MM-DD>/` with one JSON per query (`query`, `status`, `response`) and
  `summary.md`, committed to main. The same folder is a 90-day run artifact.
- Window: the last N whole UTC days; today is left out because it is incomplete.
- A metric or breakdown Roblox rejects shows its error in `summary.md`; the other queries still
  run. Fix the name in `tools/analytics-queries.json`.

## Key and secrets

Environment `Roblox` (Settings → Environments): `ROBLOX_API_KEY`, `ROBLOX_UNIVERSE_ID` (same as
publish/badges). The key needs the API system **universe-analytics** with the operation
**universe.analytics:read** for the universe. If every query answers 401/403, add it:

1. Creator Hub → Open Cloud → API Keys → the key used for `ROBLOX_API_KEY` → Edit.
2. Access Permissions → add API system **universe-analytics** → choose the experience → tick
   **universe.analytics:read** → Save. (Editing keeps the secret; no GitHub change needed.)

`ROBLOX_UNIVERSE_ID` points at the test place. For the live game, enter its universe ID as the
workflow input (the key must have the scope for that universe too).

## Limits

Beta API: about 30 queries per minute per key owner (the script waits 2.5 s between queries).
Results are bucketed in UTC. Not every metric supports every granularity or breakdown.
