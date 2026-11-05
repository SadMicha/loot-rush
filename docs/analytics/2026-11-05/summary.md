# Analytics 2026-11-05

Universe `10773139945`, 2026-10-08T00:00:00Z to 2026-11-05T00:00:00Z (end exclusive, UTC), 28 days.
Raw answers: one JSON file per query next to this file. Source: tools/fetch-analytics.py.

| Query | Metric | HTTP | Result |
|---|---|---|---|
| dau | DailyActiveUsers | 200 | ok |
| dau-by-platform | DailyActiveUsers | 200 | ok |
| dau-by-country | DailyActiveUsers | 200 | ok |
| new-users | NewUsers | 400 | {"done": true, "error": {"code": 2001, "message": "Query Error: The metric with name NewUsers was not found."}} |
| mau | MonthlyActiveUsers | 200 | ok |
| session-length | AverageSessionLength | 400 | {"done": true, "error": {"code": 2001, "message": "Query Error: The metric with name AverageSessionLength was not found."}} |
| playtime-per-user | PlaytimePerUser | 400 | {"done": true, "error": {"code": 2001, "message": "Query Error: The metric with name PlaytimePerUser was not found."}} |
| retention-d1 | D1Retention | 200 | ok |
| retention-d7 | D7Retention | 200 | ok |
| retention-d30 | D30Retention | 200 | ok |
| revenue | DailyRevenue | 200 | ok |
| revenue-total | Revenue | 400 | {"done": true, "error": {"code": 2001, "message": "Query Error: The metric with name Revenue was not found."}} |
| paying-users | PayingUsers | 200 | ok |
