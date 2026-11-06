# Analytics 2026-11-06

Universe `10773139945`, 2026-10-23T00:00:00Z to 2026-11-06T00:00:00Z (end exclusive, UTC), 14 days.
Raw answers: one JSON file per query next to this file. Source: tools/fetch-analytics.py.

| Query | Metric | HTTP | Result |
|---|---|---|---|
| dau | DailyActiveUsers | 200 | ok |
| dau-by-platform | DailyActiveUsers | 200 | ok |
| dau-by-country | DailyActiveUsers | 200 | ok |
| mau | MonthlyActiveUsers | 200 | ok |
| new-vs-returning | DailyActiveUsers | 200 | ok |
| session-length | AverageSessionLengthMinutes | 200 | ok |
| playtime-per-user | AveragePlayTimeMinutesPerDAU | 200 | ok |
| sessions | Visits | 200 | ok |
| retention-d1 | D1Retention | 200 | ok |
| retention-d7 | D7Retention | 200 | ok |
| retention-d30 | D30Retention | 200 | ok |
| revenue | DailyRevenue | 200 | ok |
| paying-users | PayingUsers | 200 | ok |
| revenue-total | DailyRevenue | 200 | ok |
| funnel-users | FunnelUserTotalCount | 400 | {"done": true, "error": {"code": 2001, "message": "Query Validation Errors: Query Error: Dimension FunnelName is filter-only for metric FunnelUserTotalCount and cannot be used as a breakdown. Please u |
| funnel-step-completion | FunnelUserStepCompletionRate | 400 | {"done": true, "error": {"code": 2001, "message": "Query Validation Errors: Query Error: Dimension FunnelName is filter-only for metric FunnelUserStepCompletionRate and cannot be used as a breakdown.  |
| custom-events | CustomEventCount | 400 | {"done": true, "error": {"code": 2001, "message": "Query Validation Errors: Query Error: Dimension CustomEventName is filter-only for metric CustomEventCount and cannot be used as a breakdown. Please  |
| economy | EconomyTransactionAmount | 400 | {"done": true, "error": {"code": 2001, "message": "Query Validation Errors: Query Error: Dimension CurrencyType is filter-only for metric EconomyTransactionAmount and cannot be used as a breakdown. Pl |
