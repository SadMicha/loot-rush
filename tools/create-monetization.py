#!/usr/bin/env python3
"""Creates the Developer Products and Game Passes from docs/MONETIZATION.md through Open Cloud
and writes their IDs into src/shared/Monetization.luau.

Idempotent: a key whose ID in Monetization.luau is already non-zero is skipped, and an existing
product/pass with the same name in the universe is reused instead of created again. If the
existing items cannot be listed, nothing is created.

Env: ROBLOX_API_KEY (developer-product:read+write, game-pass:read+write), ROBLOX_UNIVERSE_ID.
Run by .github/workflows/create-monetization.yml.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

LUAU = "src/shared/Monetization.luau"
API = "https://apis.roblox.com"

PRODUCTS = [
    ("soulstars_s", "Handful of Stars", "100 Soulstars for your account.", 49),
    ("soulstars_m", "Pouch of Stars", "550 Soulstars for your account.", 249),
    ("soulstars_l", "Hoard of Stars", "1,200 Soulstars for your account.", 499),
    ("soulstars_xl", "Galaxy of Stars", "2,600 Soulstars for your account.", 999),
    ("gold_s", "Gold Pouch", "2,500 gold, scaled by your best Rift depth.", 25),
    ("gold_m", "Gold Chest", "11,000 gold, scaled by your best Rift depth.", 99),
    ("gold_l", "Gold Hoard", "30,000 gold, scaled by your best Rift depth.", 249),
    ("pack_ember", "Ember Pack", "Ember Trail and Ember Aura.", 199),
    ("pack_frost", "Frost Pack", "Frost Trail and Frost Aura.", 199),
    ("pack_void", "Void Pack", "Void Trail and Void Aura.", 399),
    (
        "starter",
        "Starter Pack",
        "300 Soulstars, 5,000 gold (scaled by depth) and the Gilded Trail. One per account.",
        99,
    ),
]

PASSES = [
    ("vip", "VIP", "+25% gold and +25% XP, forever.", 299, "assets/ui/icons/starsheet.png"),
    ("pet_slot", "Pet Slot", "Unlocks a second pet slot.", 199, "assets/ui/icons/pets.png"),
    ("magnet", "Loot Magnet", "+8 studs pickup radius and +10% item chance.", 149, "assets/ui/icons/backpack.png"),
]


def request(method: str, url: str, key: str, data: bytes | None = None, headers: dict | None = None):
    h = {"x-api-key": key, **(headers or {})}
    for attempt in range(4):
        req = urllib.request.Request(url, data=data, headers=h, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read() or b"{}"
                return r.status, json.loads(raw)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code == 429 or e.code >= 500:
                time.sleep(2 ** (attempt + 1))
                continue
            return e.code, {"error": body}
    return 0, {"error": "gave up after retries"}


def multipart(fields: dict, file_field: str | None = None, path: str | None = None):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    if file_field and path and os.path.exists(path):
        with open(path, "rb") as f:
            content = f.read()
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; '
            f'filename="{os.path.basename(path)}"\r\nContent-Type: image/png\r\n\r\n'.encode()
        )
        parts.append(content + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), {"Content-Type": f"multipart/form-data; boundary={boundary}"}


def find_id(obj: dict, names: tuple) -> int:
    for n in names:
        v = obj.get(n)
        if isinstance(v, (int, str)) and str(v).isdigit() and int(v) > 0:
            return int(v)
    return 0


def first_list(obj: dict) -> list:
    for v in obj.values():
        if isinstance(v, list):
            return v
    return []


def list_existing(url: str, key: str, id_names: tuple) -> dict:
    """name -> id of everything already in the universe. Exits if listing fails."""
    out: dict = {}
    token = ""
    for _ in range(50):
        sep = "&" if "?" in url else "?"
        status, body = request("GET", f"{url}{sep}pageSize=50" + (f"&pageToken={token}" if token else ""), key)
        if status != 200:
            print(f"ERROR listing {url}: HTTP {status} {body}")
            sys.exit(1)
        for item in first_list(body):
            if isinstance(item, dict) and item.get("name"):
                out[item["name"]] = find_id(item, id_names)
        token = body.get("nextPageToken") or ""
        if not token:
            break
    return out


def read_ids(text: str, block: str) -> dict:
    m = re.search(rf"Monetization\.{block} = table\.freeze\(\{{(.*?)\}}", text, re.S)
    if not m:
        sys.exit(f"ERROR: {block} block not found in {LUAU}")
    return {k: int(v) for k, v in re.findall(r"^\t(\w+) = (\d+),", m.group(1), re.M)}


def write_id(path: str, block: str, k: str, value: int) -> None:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(rf"Monetization\.{block} = table\.freeze\(\{{(.*?)\}}", text, re.S)
    assert m
    inner = re.sub(rf"^(\t{k} = )\d+(,)", rf"\g<1>{value}\g<2>", m.group(1), count=1, flags=re.M)
    text = text[: m.start(1)] + inner + text[m.end(1) :]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main() -> int:
    key = os.environ.get("ROBLOX_API_KEY", "")
    universe = os.environ.get("ROBLOX_UNIVERSE_ID", "")
    if not key or not universe.isdigit():
        print("ERROR: ROBLOX_API_KEY / ROBLOX_UNIVERSE_ID missing")
        return 1

    with open(LUAU, encoding="utf-8") as f:
        text = f.read()
    have_products = read_ids(text, "ProductIds")
    have_passes = read_ids(text, "PassIds")

    prod_url = f"{API}/developer-products/v2/universes/{universe}/developer-products"
    pass_url = f"{API}/game-passes/v1/universes/{universe}/game-passes"
    prod_ids = ("productId", "developerProductId", "id")
    pass_ids = ("gamePassId", "passId", "id")

    existing_products = list_existing(f"{prod_url}/creator", key, prod_ids)
    existing_passes = list_existing(f"{pass_url}/creator", key, pass_ids)
    print(f"Universe {universe}: {len(existing_products)} products, {len(existing_passes)} passes exist")

    failed = 0
    for k, name, desc, price in PRODUCTS:
        if have_products.get(k, 0) > 0:
            print(f"skip   product {k}: already {have_products[k]}")
            continue
        pid = existing_products.get(name, 0)
        if pid:
            print(f"reuse  product {k}: {pid} ({name})")
        else:
            body, headers = multipart({"name": name, "description": desc, "price": price, "isForSale": "true"})
            status, res = request("POST", prod_url, key, body, headers)
            pid = find_id(res, prod_ids)
            if status not in (200, 201) or not pid:
                print(f"FAILED product {k}: HTTP {status} {res}")
                failed += 1
                continue
            print(f"create product {k}: {pid} ({name}, {price} R$)")
        write_id(LUAU, "ProductIds", k, pid)

    for k, name, desc, price, image in PASSES:
        if have_passes.get(k, 0) > 0:
            print(f"skip   pass {k}: already {have_passes[k]}")
            continue
        gid = existing_passes.get(name, 0)
        if gid:
            print(f"reuse  pass {k}: {gid} ({name})")
        else:
            fields = {"name": name, "description": desc, "price": price, "isForSale": "true"}
            body, headers = multipart(fields, "imageFile", image)
            status, res = request("POST", pass_url, key, body, headers)
            gid = find_id(res, pass_ids)
            if status not in (200, 201) or not gid:
                print(f"FAILED pass {k}: HTTP {status} {res}")
                failed += 1
                continue
            print(f"create pass {k}: {gid} ({name}, {price} R$)")
        write_id(LUAU, "PassIds", k, gid)

    print(f"Done, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
