#!/usr/bin/env python3
"""Fetches experience analytics from the Roblox Open Cloud Analytics Query API (beta) and writes
one JSON file per query plus summary.md into docs/analytics/<YYYY-MM-DD>/.

Queries: tools/analytics-queries.json. Each query is POSTed to
/analytics-query-api/v1/universes/{u}/metrics; a pending answer (done = false) is polled through
the operation path it returns. A query Roblox rejects (unknown metric, unsupported breakdown or
granularity) is written with its error and does not stop the others. A query with "split" (a
list of filter-only dimensions such as FunnelName) first reads the dimension values, then runs
once per value combination.

Env: ROBLOX_API_KEY (needs the "universe-analytics" system, scope universe.analytics:read, on the
universe), ROBLOX_UNIVERSE_ID. Optional: ANALYTICS_DAYS (default 28), ANALYTICS_UNIVERSE_ID
(overrides ROBLOX_UNIVERSE_ID, e.g. the live game instead of the test place), ANALYTICS_OUT.
The key is only ever sent as a header; it is never printed or written to a file.
Run by .github/workflows/fetch-analytics.yml. Docs: docs/ANALYTICS.md.
"""

import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request

HOST = "https://apis.roblox.com"
BASE = HOST + "/analytics-query-api/v1"
QUERIES = "tools/analytics-queries.json"
POLL_SECONDS = 90
MAX_SPLIT = 60  # sub-queries per split query; more are reported as an error in summary.md


def request(method, url, key, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"x-api-key": key, "Content-Type": "application/json", "Accept": "application/json"}
    for attempt in range(5):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read() or b"{}"
                try:
                    return r.status, json.loads(raw)
                except json.JSONDecodeError:
                    return r.status, {"raw": raw.decode("utf-8", "replace")}
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace")
            if e.code == 429 or e.code >= 500:
                time.sleep(2 ** (attempt + 1))
                continue
            try:
                return e.code, {"error": json.loads(text)}
            except json.JSONDecodeError:
                return e.code, {"error": text[:2000]}
        except urllib.error.URLError:
            time.sleep(2 ** (attempt + 1))
    return 0, {"error": "gave up after retries"}


def operation_url(universe, path):
    """Turns the operation path from a pending answer into a URL (Roblox returns it relative)."""
    path = path.strip()
    if path.startswith("http"):
        return path
    if path.startswith("/analytics-query-api/"):
        return HOST + path
    if path.startswith("analytics-query-api/"):
        return HOST + "/" + path
    # Relative forms such as "v1/universes/..." or "universes/...": keep everything from "universes/"
    i = path.find("universes/")
    if i >= 0:
        return BASE + "/" + path[i:]
    # Bare operation id
    return f"{BASE}/universes/{universe}/operations/metrics/{path}"


def post_and_poll(universe, key, endpoint, body):
    status, data = request("POST", f"{BASE}/universes/{universe}/{endpoint}", key, body)
    deadline = time.time() + POLL_SECONDS
    wait = 2
    # Large queries answer 202 Accepted with done = false and an operation path to poll.
    while 200 <= status < 300 and isinstance(data, dict) and data.get("done") is False and data.get("path"):
        if time.time() > deadline:
            return 0, {"error": "operation still pending after %ds" % POLL_SECONDS, "last": data}
        time.sleep(wait)
        wait = min(wait * 2, 10)
        status, data = request("GET", operation_url(universe, data["path"]), key)
    return status, data


def answer_ok(status, data):
    return 200 <= status < 300 and not (isinstance(data, dict) and ("error" in data or data.get("done") is False))


def run_query(universe, key, query, start, end):
    body = {"metric": query["metric"], "startTime": start, "endTime": end}
    for field in ("granularity", "breakdown", "filter", "limit"):
        if field in query:
            body[field] = query[field]
    if "split" not in query:
        status, data = post_and_poll(universe, key, "metrics", body)
        return body, status, data
    return run_split(universe, key, query, body)


def run_split(universe, key, query, body):
    """For filter-only dimensions (FunnelName, FunnelStep, CustomEventName, CurrencyType, ...):
    asks dimension-values for the values seen in the window, then runs the metric once per value
    combination with an In filter. Answer: {"dimensionValues": ..., "results": [{filter, status, response}]}."""
    dims = query["split"]
    dim_body = {"metric": body["metric"], "dimensions": dims, "startTime": body["startTime"], "endTime": body["endTime"]}
    if body.get("filter"):
        dim_body["filter"] = body["filter"]
    status, data = post_and_poll(universe, key, "dimension-values", dim_body)
    if not answer_ok(status, data):
        return body, status, data
    seen = {d.get("dimension"): [v.get("value") for v in d.get("values", [])] for d in data.get("response", {}).get("values", [])}
    combos = [[]]
    for dim in dims:
        combos = [c + [(dim, v)] for c in combos for v in seen.get(dim, [])]
    total = len(combos)
    combos = combos[:MAX_SPLIT]
    results = []
    for combo in combos:
        time.sleep(2.5)  # each sub-query counts against the 30 queries/minute limit
        sub = dict(body)
        sub["filter"] = list(body.get("filter", [])) + [{"dimension": d, "values": [v], "operation": "In"} for d, v in combo]
        s, d = post_and_poll(universe, key, "metrics", sub)
        ok = answer_ok(s, d)
        results.append({"filter": dict(combo), "status": s, "ok": ok, "response": d.get("response", d) if ok else d})
    failed = sum(1 for r in results if not r["ok"])
    out = {"dimensionValues": data.get("response"), "results": results}
    problems = []
    if failed:
        problems.append(f"{failed} of {len(results)} sub-queries failed")
    if total > len(combos):
        problems.append(f"only the first {len(combos)} of {total} combinations were queried (MAX_SPLIT)")
    if problems:
        out["error"] = "; ".join(problems)
    return dict(body, split=dims), 200, out


def short_error(data):
    err = data.get("error", data) if isinstance(data, dict) else data
    if isinstance(err, dict):
        err = err.get("message") or err.get("errors") or err
    return json.dumps(err)[:200] if not isinstance(err, str) else err[:200]


def main():
    key = os.environ.get("ROBLOX_API_KEY", "")
    universe = os.environ.get("ANALYTICS_UNIVERSE_ID") or os.environ.get("ROBLOX_UNIVERSE_ID", "")
    if not key or not universe.strip().isdigit():
        print("ROBLOX_API_KEY or ROBLOX_UNIVERSE_ID missing (environment 'Roblox').")
        return 1
    universe = universe.strip()
    try:
        days = max(1, min(365, int(os.environ.get("ANALYTICS_DAYS") or "28")))
    except ValueError:
        days = 28
    today = dt.datetime.now(dt.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    start = (today - dt.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    end = today.strftime("%Y-%m-%dT%H:%M:%SZ")  # exclusive: whole UTC days only
    out = os.environ.get("ANALYTICS_OUT") or os.path.join("docs", "analytics", today.strftime("%Y-%m-%d"))
    os.makedirs(out, exist_ok=True)

    with open(QUERIES, encoding="utf-8") as f:
        queries = json.load(f)["queries"]

    rows = []
    denied = 0
    for q in queries:
        body, status, data = run_query(universe, key, q, start, end)
        ok = answer_ok(status, data)
        if status in (401, 403):
            denied += 1
        with open(os.path.join(out, q["name"] + ".json"), "w", encoding="utf-8") as f:
            json.dump({"query": body, "status": status, "response": data}, f, indent=2, sort_keys=True)
            f.write("\n")
        note = "ok" if ok else short_error(data).replace("|", "/").replace("\n", " ")
        rows.append((q["name"], q["metric"], status, note))
        print(f"{q['name']:<20} {q['metric']:<24} {status}  {note}")
        time.sleep(2.5)  # stays under the 30 queries/minute limit

    with open(os.path.join(out, "summary.md"), "w", encoding="utf-8") as f:
        f.write(f"# Analytics {today:%Y-%m-%d}\n\n")
        f.write(f"Universe `{universe}`, {start} to {end} (end exclusive, UTC), {days} days.\n")
        f.write("Raw answers: one JSON file per query next to this file. Source: tools/fetch-analytics.py.\n\n")
        f.write("| Query | Metric | HTTP | Result |\n|---|---|---|---|\n")
        for name, metric, status, note in rows:
            f.write(f"| {name} | {metric} | {status} | {note} |\n")

    if denied == len(queries):
        print(
            "\nEvery query was denied (401/403). The ROBLOX_API_KEY needs the API system "
            "'universe-analytics' (scope universe.analytics:read) for this universe. See docs/ANALYTICS.md."
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
