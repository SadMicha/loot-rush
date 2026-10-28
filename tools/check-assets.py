#!/usr/bin/env python3
"""Prüft alle Bild-IDs aus src/shared/UI/Assets.luau gegen öffentliche Roblox-Endpunkte.

Läuft in GitHub Actions (Roblox ist aus der Claude-Cloud gesperrt):
  python3 tools/check-assets.py [--fix] [--report report.md]

Je ID: Asset-Typ (1 = Image, 13 = Decal), Name, Ersteller und Vorschau-Status
(Completed = freigegeben, Pending = in Moderation, Blocked = abgelehnt).
Bei Decal-IDs wird die zugehörige Image-ID gesucht (Decal-XML über assetdelivery, sonst
die IDs direkt davor mit gleichem Ersteller). --fix ersetzt gefundene IDs in Assets.luau.
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
        except Exception as e:  # Netzwerkfehler
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
    # 1. Decal-XML: enthält <url>…id=IMAGE</url>
    for url in (
        f"https://assetdelivery.roblox.com/v1/asset/?id={decal_id}",
        f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{decal_id}",
    ):
        status, body = get(url)
        if decal_id not in LOGGED:
            # Einmal je Decal: warum die Auflösung scheitert (401/403 = Key fehlt/Recht fehlt)
            print(f"  {url.split('/')[2]} → HTTP {status}: {body[:160]!r}")
        if status == 200:
            text = body.decode("utf-8", "replace")
            loc = re.search(r'"location"\s*:\s*"([^"]+)"', text)
            if loc:
                s2, b2 = get(loc.group(1))
                if s2 == 200 and b2[:2] == b"\x1f\x8b":
                    b2 = gzip.decompress(b2)
                # XML- oder Binär-Modell (.rbxm): die Texture-URL steht in beiden als Klartext
                text = b2.decode("latin-1") if s2 == 200 else ""
                if s2 != 200:
                    print(f"  Inhalt {decal_id} → HTTP {s2}")
            m = re.search(r"(?:asset/?\?id=|rbxassetid://)(\d+)", text)
            if m and int(m.group(1)) != decal_id:
                return int(m.group(1)), "Decal-Inhalt"
            if text and decal_id not in LOGGED:
                print(f"  Inhalt {decal_id}: keine Texture-ID gefunden, Anfang {text[:60]!r}")
    # 2. Beim Hochladen entsteht das Image meist mit einer ID kurz vor dem Decal
    creator = (info or {}).get("Creator", {}).get("Id")
    for cand in range(decal_id - 1, decal_id - 16, -1):
        d = details(cand)
        if d and d.get("AssetTypeId") == 1 and d.get("Creator", {}).get("Id") == creator:
            return cand, f"Nachbar-ID ({decal_id - cand} davor, gleicher Ersteller)"
    LOGGED.add(decal_id)
    return None, "nicht gefunden"


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
    print(f"{len(entries)} Einträge, {len(ids)} verschiedene IDs")

    thumbs = thumbnails(ids)
    infos = {i: details(i) for i in ids}

    rows = []
    mapping = {}
    for name, asset_id in entries:
        info = infos.get(asset_id)
        type_id = info.get("AssetTypeId") if info else None
        type_name = TYPE_NAME.get(type_id, str(type_id)) if info else "unbekannt"
        state = thumbs.get(asset_id, "?")
        note = ""
        if type_id == 13:
            if asset_id not in mapping:
                mapping[asset_id] = image_of_decal(asset_id, info)
            img, how = mapping[asset_id]
            note = f"Image-ID {img} ({how})" if img else f"Image-ID {how}"
        elif info is None:
            note = "Details nicht abrufbar"
        elif state == "Pending":
            note = "in Moderation"
        elif state == "Blocked":
            note = "abgelehnt"
        rows.append((name, asset_id, type_name, state, (info or {}).get("Name", ""), note))

    lines = [
        "# Asset-ID-Prüfung",
        "",
        "| Name | ID | Typ | Vorschau | Roblox-Name | Hinweis |",
        "|---|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append("| " + " | ".join(str(x) for x in r) + " |")
    decals = [r for r in rows if r[2] == "Decal"]
    problems = [r for r in rows if r[2] != "Image" or r[3] not in ("Completed", "?")]
    lines += ["", f"Decal-IDs: {len(decals)} · Auffällig gesamt: {len(problems)} von {len(rows)}"]
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
        print(f"--fix: {changed} Stellen ersetzt")


if __name__ == "__main__":
    main()
