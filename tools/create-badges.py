#!/usr/bin/env python3
"""Creates the Roblox badges from src/shared/Badges.luau through Open Cloud and writes their IDs
into Badges.Ids.

Icons: assets/badges/<key>.png (512x512, prompts in docs/STORE-ICON-PROMPTS.md). A badge without
an icon is skipped. Never spends Robux: every create sends expectedCost=0, so once the free daily
quota is used up Roblox refuses the rest (run again the next day).

Idempotent: a key whose ID in Badges.luau is already non-zero is skipped, and a badge with the
same name already in the universe is reused instead of created again.

Env: ROBLOX_API_KEY (scope legacy-universe.badge: write + manage), ROBLOX_UNIVERSE_ID.
Run by .github/workflows/create-badges.yml.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

LUAU = "src/shared/Badges.luau"
ICONS = "assets/badges"
CREATE = "https://apis.roblox.com/legacy-badges/v1/universes/{u}/badges"
LIST = "https://badges.roblox.com/v1/universes/{u}/badges?limit=100&sortOrder=Asc"
QUOTA = "https://badges.roblox.com/v1/universes/{u}/free-badges-quota"


def request(method, url, key=None, data=None, headers=None):
    h = {**({"x-api-key": key} if key else {}), **(headers or {})}
    for attempt in range(4):
        req = urllib.request.Request(url, data=data, headers=h, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read() or b"{}"
                try:
                    return r.status, json.loads(raw)
                except json.JSONDecodeError:
                    return r.status, {"raw": raw.decode("utf-8", "replace")}
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code == 429 or e.code >= 500:
                time.sleep(2 ** (attempt + 1))
                continue
            return e.code, {"error": body}
        except urllib.error.URLError:
            time.sleep(2 ** (attempt + 1))
    return 0, {"error": "gave up after retries"}


def multipart(fields, file_field, path):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    with open(path, "rb") as f:
        content = f.read()
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; '
        f'filename="{os.path.basename(path)}"\r\nContent-Type: image/png\r\n\r\n'.encode()
    )
    parts.append(content + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), {"Content-Type": f"multipart/form-data; boundary={boundary}"}


def lua_unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


def read_badges(text):
    """[(key, name, desc)] in list order, from the b("key", "name", "desc", ...) calls."""
    out = []
    for m in re.finditer(r'\bb\(\s*"(\w+)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"', text):
        out.append((m.group(1), lua_unescape(m.group(2)), lua_unescape(m.group(3))))
    return out


def ids_block(text):
    m = re.search(r"Badges\.Ids = table\.freeze\(\{(.*?)\}", text, re.S)
    if not m:
        sys.exit(f"ERROR: Badges.Ids block not found in {LUAU}")
    return m


def read_ids(text):
    return {k: int(v) for k, v in re.findall(r"^\t(\w+) = (\d+),", ids_block(text).group(1), re.M)}


def write_id(k, value):
    with open(LUAU, encoding="utf-8") as f:
        text = f.read()
    m = ids_block(text)
    inner = re.sub(rf"^(\t{k} = )\d+(,)", rf"\g<1>{value}\g<2>", m.group(1), count=1, flags=re.M)
    text = text[: m.start(1)] + inner + text[m.end(1) :]
    with open(LUAU, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def existing(universe):
    """name -> id of the badges already in the universe (public list, no key needed)."""
    out, cursor = {}, ""
    for _ in range(20):
        url = LIST.format(u=universe) + (f"&cursor={cursor}" if cursor else "")
        status, body = request("GET", url)
        if status != 200:
            print(f"ERROR listing existing badges: HTTP {status} {body}")
            sys.exit(1)
        for item in body.get("data", []):
            if item.get("name") and item.get("id"):
                out[item["name"]] = int(item["id"])
        cursor = body.get("nextPageCursor") or ""
        if not cursor:
            break
    return out


def main():
    key = os.environ.get("ROBLOX_API_KEY", "")
    universe = os.environ.get("ROBLOX_UNIVERSE_ID", "")
    if not key or not universe.isdigit():
        print("ERROR: ROBLOX_API_KEY / ROBLOX_UNIVERSE_ID missing")
        return 1

    with open(LUAU, encoding="utf-8") as f:
        text = f.read()
    badges = read_badges(text)
    have = read_ids(text)
    if not badges:
        sys.exit("ERROR: no badges found in Badges.List")
    there = existing(universe)
    status, quota = request("GET", QUOTA.format(u=universe))
    print(f"Universe {universe}: {len(there)} badges exist, free quota today: {quota if status == 200 else '?'}")

    failed = 0
    for k, name, desc in badges:
        if have.get(k, 0) > 0:
            print(f"skip    {k}: already {have[k]}")
            continue
        bid = there.get(name, 0)
        if bid:
            print(f"reuse   {k}: {bid} ({name})")
            write_id(k, bid)
            continue
        icon = os.path.join(ICONS, f"{k}.png")
        if not os.path.exists(icon):
            print(f"no icon {k}: put {icon} in the repo first")
            continue
        fields = {
            "request.name": name,
            "request.description": desc,
            "request.paymentSourceType": "1",  # user funds (only used if it would cost Robux)
            "request.expectedCost": "0",  # never pay: refused once the free quota is used up
        }
        body, headers = multipart(fields, "request.files", icon)
        status, res = request("POST", CREATE.format(u=universe), key, body, headers)
        bid = res.get("id") if isinstance(res, dict) else None
        if status not in (200, 201) or not str(bid or "").isdigit():
            print(f"FAILED  {k}: HTTP {status} {res}")
            failed += 1
            continue
        print(f"create  {k}: {bid} ({name})")
        write_id(k, int(bid))

    print(f"Done, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
