#!/usr/bin/env python3
"""Sets the Creator Hub icon of every Developer Product and Game Pass through Open Cloud.

Icons: assets/monetization/<key>.png (512x512, the in-game store icon on the painted medallion,
docs/ART-STYLE.md). IDs come from src/shared/Monetization.luau. Re-running uploads the icons again.

Env: ROBLOX_API_KEY (developer-product:write, game-pass:write), ROBLOX_UNIVERSE_ID.
Run by .github/workflows/create-monetization.yml with the input "icons".
"""

import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location(
    "create_monetization", os.path.join(os.path.dirname(__file__), "create-monetization.py")
)
assert spec and spec.loader
cm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cm)

ICONS = "assets/monetization"


def main() -> int:
    key = os.environ.get("ROBLOX_API_KEY", "")
    universe = os.environ.get("ROBLOX_UNIVERSE_ID", "")
    if not key or not universe.isdigit():
        print("ERROR: ROBLOX_API_KEY / ROBLOX_UNIVERSE_ID missing")
        return 1

    with open(cm.LUAU, encoding="utf-8") as f:
        text = f.read()
    jobs = [
        ("product", k, pid, f"{cm.API}/developer-products/v2/universes/{universe}/developer-products/{pid}")
        for k, pid in cm.read_ids(text, "ProductIds").items()
    ] + [
        ("pass", k, gid, f"{cm.API}/game-passes/v1/universes/{universe}/game-passes/{gid}")
        for k, gid in cm.read_ids(text, "PassIds").items()
    ]

    failed = 0
    for kind, k, item_id, url in jobs:
        path = os.path.join(ICONS, f"{k}.png")
        if item_id <= 0 or not os.path.exists(path):
            print(f"skip   {kind} {k}: id {item_id}, icon {'found' if os.path.exists(path) else 'missing'}")
            continue
        body, headers = cm.multipart({}, "imageFile", path)
        status, res = cm.request("PATCH", url, key, body, headers)
        if status not in (200, 204):
            print(f"FAILED {kind} {k} ({item_id}): HTTP {status} {res}")
            failed += 1
            continue
        print(f"icon   {kind} {k} ({item_id})")

    print(f"Done, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
