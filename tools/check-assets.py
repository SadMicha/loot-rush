#!/usr/bin/env python3
"""Checks all image IDs from src/shared/UI/Assets.luau against public Roblox endpoints.

Runs in GitHub Actions (Roblox is blocked from the Claude cloud):
  python3 tools/check-assets.py [--fix] [--report report.md]

Per ID: asset type (1 = Image, 13 = Decal), name, creator and thumbnail state
(Completed = approved, Pending = in moderation, Blocked = rejected).
For decal IDs the matching image ID is looked up (decal XML via assetdelivery, otherwise
the IDs right before it with the same creator). --fix replaces found IDs in Assets.luau.
"""

import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ASSETS = os.path.join(os.path.dirname(__file__), "..", "src", "shared", "UI", "Assets.luau")
LOGGED: set = set()
TYPE_NAME = {1: "Image", 13: "Decal", 11: "Shirt", 12: "Pants", 2: "T-Shirt"}


def get(url: str, retries: int = 4):
    headers = {"User-Agent": "loot-rush-asset-check", "Accept": "application/json"}
    key = os.environ.get("ROBLOX_API_KEY")
    if key and ("apis.roblox.com" in url or "assetdelivery" in url):
        headers["x-api-key"] = key
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                time.sleep(2 * (attempt + 1))
                continue
            return e.code, e.read()
        except Exception as e:  # network error
            if attempt < retries - 1:
                time.sleep(1)
                continue
            return 0, str(e).encode()
    return 0, b""


def details(asset_id: int):
    status, body = get(f"https://economy.roblox.com/v2/assets/{asset_id}/details")
    time.sleep(0.25)
    if status != 200:
        return None
    try:
        return json.loads(body)
    except ValueError:
        return None


def thumbnails(ids):
    out = {}
    for i in range(0, len(ids), 50):
        chunk = ",".join(str(x) for x in ids[i : i + 50])
        status, body = get(
            "https://thumbnails.roblox.com/v1/assets?assetIds="
            + chunk
            + "&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false"
        )
        if status == 200:
            for d in json.loads(body).get("data", []):
                out[d["targetId"]] = d.get("state", "?")
    return out


def image_of_decal(decal_id: int, info) -> tuple:
    # 1. Decal XML: contains <url>…id=IMAGE</url>
    for url in (
        f"https://assetdelivery.roblox.com/v1/asset/?id={decal_id}",
        f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{decal_id}",
    ):
        status, body = get(url)
        if decal_id not in LOGGED:
            # Once per decal: why resolving fails (401/403 = key missing/permission missing)
            print(f"  {url.split('/')[2]} → HTTP {status}: {body[:160]!r}")
        if status == 200:
            text = body.decode("utf-8", "replace")
            loc = re.search(r'"location"\s*:\s*"([^"]+)"', text)
            if loc:
                s2, b2 = get(loc.group(1))
                if s2 == 200 and b2[:2] == b"\x1f\x8b":
                    b2 = gzip.decompress(b2)
                # XML or binary model (.rbxm): the texture URL is plain text in both
                text = b2.decode("latin-1") if s2 == 200 else ""
                if s2 != 200:
                    print(f"  content {decal_id} → HTTP {s2}")
            m = re.search(r"(?:asset/?\?id=|rbxassetid://)(\d+)", text)
            if m and int(m.group(1)) != decal_id:
                return int(m.group(1)), "decal content"
            if text and decal_id not in LOGGED:
                print(f"  content {decal_id}: no texture ID found, start {text[:60]!r}")
    # 2. On upload the image usually gets an ID shortly before the decal
    creator = (info or {}).get("Creator", {}).get("Id")
    for cand in range(decal_id - 1, decal_id - 16, -1):
        d = details(cand)
        if d and d.get("AssetTypeId") == 1 and d.get("Creator", {}).get("Id") == creator:
            return cand, f"neighbor ID ({decal_id - cand} before, same creator)"
    LOGGED.add(decal_id)
    return None, "not found"


def main():
    fix = "--fix" in sys.argv
    report_path = None
    if "--report" in sys.argv:
        report_path = sys.argv[sys.argv.index("--report") + 1]

    src = open(ASSETS, encoding="utf-8").read()
    entries = []  # (name, id)
    pattern = r'(\w+)\s*=\s*(?:(?:table\.freeze\()?\{[^{}]*?|")rbxassetid://(\d+)'
    for m in re.finditer(pattern, src):
        entries.append((m.group(1), int(m.group(2))))
    ids = sorted({i for _, i in entries})
    print(f"{len(entries)} entries, {len(ids)} distinct IDs")

    thumbs = thumbnails(ids)
    infos = {i: details(i) for i in ids}

    rows = []
    mapping = {}
    for name, asset_id in entries:
        info = infos.get(asset_id)
        type_id = info.get("AssetTypeId") if info else None
        type_name = TYPE_NAME.get(type_id, str(type_id)) if info else "unknown"
        state = thumbs.get(asset_id, "?")
        note = ""
        if type_id == 13:
            if asset_id not in mapping:
                mapping[asset_id] = image_of_decal(asset_id, info)
            img, how = mapping[asset_id]
            note = f"Image-ID {img} ({how})" if img else f"Image-ID {how}"
        elif info is None:
            note = "details not available"
        elif state == "Pending":
            note = "in moderation"
        elif state == "Blocked":
            note = "rejected"
        rows.append((name, asset_id, type_name, state, (info or {}).get("Name", ""), note))

    lines = [
        "# Asset ID check",
        "",
        "| Name | ID | Type | Thumbnail | Roblox name | Note |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append("| " + " | ".join(str(x) for x in r) + " |")
    decals = [r for r in rows if r[2] == "Decal"]
    problems = [r for r in rows if r[2] != "Image" or r[3] not in ("Completed", "?")]
    lines += ["", f"Decal IDs: {len(decals)} · flagged in total: {len(problems)} of {len(rows)}"]
    report = "\n".join(lines) + "\n"
    print(report)
    if report_path:
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(report)
    with open("asset-mapping.json", "w", encoding="utf-8") as f:
        json.dump({str(k): v[0] for k, v in mapping.items() if v[0]}, f, indent=2)

    if fix:
        changed = 0
        for decal, (img, _) in mapping.items():
            if img:
                src, n = re.subn(rf"rbxassetid://{decal}\b", f"rbxassetid://{img}", src)
                changed += n
        if changed:
            with open(ASSETS, "w", encoding="utf-8") as f:
                f.write(src)
        print(f"--fix: {changed} occurrences replaced")


if __name__ == "__main__":
    main()
