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
| funnel-users | FunnelUserTotalCount | 200 | ok |
| custom-events | CustomEventCountUser | 200 | ok |
| rift-fails-by-depth | CustomEventCountUser | 400 | {"done": true, "error": {"code": 2001, "message": "Dimension CustomField02 is not supported for metric CustomEventCountUser."}} |
| rift-clears-by-depth | CustomEventCountUser | 400 | {"done": true, "error": {"code": 2001, "message": "Dimension CustomField02 is not supported for metric CustomEventCountUser."}} |
| economy | EconomyTransactionAmount | 200 | ok |
