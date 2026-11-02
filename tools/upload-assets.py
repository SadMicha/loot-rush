#!/usr/bin/env python3
"""Uploads the images (and .fbx weapon meshes) from tools/upload-manifest.json via the Open Cloud Assets API.

  ROBLOX_API_KEY=... ROBLOX_CREATOR_USER_ID=... python3 tools/upload-assets.py [--only key,key] [--out assets/ui-asset-ids.csv]

The API key needs the Assets read + write permission. Writes a CSV (key,assetId,path) after
every upload and skips keys that are already in it, so re-runs only upload what is missing.
A key whose file was already uploaded under another key gets that asset id. Exits 1 if any
upload failed (the others are still recorded).
"""

import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.join(os.path.dirname(__file__), "..")
API = "https://apis.roblox.com/assets/v1"


def request(url: str, key: str, data: bytes | None = None, headers: dict | None = None):
    h = {"x-api-key": key, **(headers or {})}
    req = urllib.request.Request(url, data=data, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        return e.code, {"error": body}


def multipart(fields: dict, filename: str, content: bytes, content_type: str = "image/png"):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    parts.append(
        (
            f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
            f'filename="{filename}"\r\nContent-Type: {content_type}\r\n\r\n'
        ).encode()
        + content
        + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), {"Content-Type": f"multipart/form-data; boundary={boundary}"}


def upload(key: str, user_id: str, name: str, path: str):
    with open(path, "rb") as f:
        content = f.read()
    # .fbx = Model asset (weapon meshes, Shared/Weapons), everything else = Image
    is_model = path.lower().endswith(".fbx")
    meta = {
        "assetType": "Model" if is_model else "Image",
        "displayName": name[:50],
        "description": "Loot Rush weapon" if is_model else "Loot Rush UI",
        "creationContext": {"creator": {"userId": user_id}},
    }
    body, headers = multipart(
        {"request": json.dumps(meta)},
        os.path.basename(path),
        content,
        "model/fbx" if is_model else "image/png",
    )
    status, res = request(f"{API}/assets", key, body, headers)
    if status != 200:
        return None, f"upload failed ({status}): {res.get('error', res)}"
    op = res.get("path", "")
    for _ in range(40):
        if res.get("done"):
            break
        time.sleep(2)
        status, res = request(f"{API}/{op}", key)
        if status != 200:
            return None, f"operation poll failed ({status}): {res.get('error', res)}"
    if not res.get("done"):
        return None, "timed out waiting for the operation"
    if "error" in res:
        return None, f"operation error: {res['error']}"
    return str(res["response"]["assetId"]), ""


FIELDS = ["key", "assetId", "path"]


def write_csv(out: str, done: dict) -> None:
    # Rewritten in full after every change (temp file + replace), so a crash or Ctrl-C mid-run
    # never loses ids that were already uploaded.
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(done.values())
    os.replace(tmp, out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "ui-asset-ids.csv"))
    args = ap.parse_args()

    key = os.environ.get("ROBLOX_API_KEY", "")
    user_id = os.environ.get("ROBLOX_CREATOR_USER_ID", "")
    if not key or not user_id:
        print("ROBLOX_API_KEY and ROBLOX_CREATOR_USER_ID are required", file=sys.stderr)
        return 2

    with open(os.path.join(ROOT, "tools", "upload-manifest.json"), encoding="utf-8") as f:
        raw = json.load(f)
    # {"assets": [{"key", "file"}]} or {key: path}
    manifest = {e["key"]: e["file"] for e in raw["assets"]} if "assets" in raw else raw
    only = {k for k in args.only.split(",") if k}

    done: dict = {}
    if os.path.exists(args.out):
        with open(args.out, newline="", encoding="utf-8") as f:
            done = {row["key"]: row for row in csv.DictReader(f)}
    id_by_path = {row["path"]: row["assetId"] for row in done.values() if row.get("assetId")}

    failed = 0
    try:
        for k, rel in manifest.items():
            if (only and k not in only) or k in done:
                continue
            if rel in id_by_path:
                # Same file already uploaded under another key: reuse its id so every key has a row
                done[k] = {"key": k, "assetId": id_by_path[rel], "path": rel}
                write_csv(args.out, done)
                print(f"same {k} -> rbxassetid://{id_by_path[rel]} (file already uploaded)")
                continue
            try:
                asset_id, err = upload(key, user_id, k, os.path.join(ROOT, rel))
            except (urllib.error.URLError, OSError, KeyError, ValueError, TypeError) as e:
                # URLError/socket timeouts/missing files are OSError; KeyError/ValueError = odd reply.
                # Only the exception type and message are printed, never the request headers.
                asset_id, err = None, f"{type(e).__name__}: {e}"
            if asset_id:
                done[k] = {"key": k, "assetId": asset_id, "path": rel}
                id_by_path[rel] = asset_id
                write_csv(args.out, done)
                print(f"ok   {k} -> rbxassetid://{asset_id}", flush=True)
            else:
                failed += 1
                print(f"FAIL {k}: {err}", flush=True)
                if "(401)" in err or "(403)" in err:
                    break  # permission problem, the rest would fail the same way
    except KeyboardInterrupt:
        write_csv(args.out, done)
        print("interrupted - recorded ids are saved", file=sys.stderr)
        return 130

    write_csv(args.out, done)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
