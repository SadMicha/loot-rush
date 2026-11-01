# Publishing to Roblox automatically

On every push to `main` (or via a button in GitHub), GitHub Actions checks the game, builds it with Rojo into an `.rbxl` and uploads it via Roblox Open Cloud to an existing place. After that it's playable in the Roblox app on phone and iPad.

> **Important:** The upload replaces the **whole** place. Everything that was only built in Studio and doesn't come through Rojo is gone there afterwards. Loot Rush builds arena and spawn in code, so that's fine. Still, use a **separate test game** instead of the later live game.

## 1. Create the test game (once)

1. Roblox Studio → **New → Baseplate** → **File → Publish to Roblox As …** → new game, e.g. "Loot Rush Test".
2. [Creator Hub](https://create.roblox.com/dashboard/creations) → the game → **⋯ → Copy Universe ID** → remember as `ROBLOX_UNIVERSE_ID`.
3. Open the game → **Places** → click the start place. The number in the address `…/places/<NUMBER>/configure` is `ROBLOX_PLACE_ID`.

## 2. Set up the game for phone/iPad

In Creator Hub for the test game:

- **Configure → Access:** leave it **Private**. You can still play it with your own account, strangers can't.
- **Devices:** tick **Phone** and **Tablet** (plus Computer).
- If Roblox asks for the maturity questionnaire: fill it in once.

## 3. Create an API key

[Creator Hub → Open Cloud → API Keys](https://create.roblox.com/dashboard/credentials) → **Create API Key**

- **Name:** e.g. `loot-rush-github`
- **Access Permissions:** add API system **universe-places** → select your **test game** → operation **write**.
- **Security → Accepted IP Addresses:** enter `0.0.0.0/0`. GitHub servers have changing IPs; without this entry you get `401`. In return the key may only upload this one test game, nothing more.
- **Expiration:** optional (e.g. 90 days); afterwards create a new key and replace the secret.
- **Save & Generate Key** → **copy the key immediately**, it's only shown once. Never write it into the repo, chats or `.env` files that get committed.

## 4. Create secrets in GitHub

GitHub → `SadMicha/loot-rush` → **Settings → Environments → New environment** named **`Roblox`** → **Add environment secret**, three of them:

| Name | Value |
|---|---|
| `ROBLOX_API_KEY` | the key from step 3 |
| `ROBLOX_UNIVERSE_ID` | number from step 1.2 |
| `ROBLOX_PLACE_ID` | number from step 1.3 |

Without these secrets the workflow just skips the upload with a warning.

## 5. Try it

GitHub → **Actions → Publish → Run workflow** (Published). If it runs green, the end shows `Done: {"versionNumber": …}`.

On the phone/iPad: Roblox app with **your** account, then open the link `https://www.roblox.com/games/<PLACE_ID>` (e.g. send it to yourself as a note) → **Play**. Tip: save it as a favorite in the phone's browser.

Running servers keep the old version. If you're already in: leave the game and rejoin, otherwise in Creator Hub at the place **⋯ → Shut down all servers**.

From now on every merge to `main` publishes automatically. `Saved` in the Run workflow menu only saves a version without making it playable.

## Uploading locally (without GitHub)

In Git Bash (Windows) or a terminal:

```bash
export ROBLOX_API_KEY='…' ROBLOX_UNIVERSE_ID='…' ROBLOX_PLACE_ID='…'
bash tools/publish.sh            # Published
bash tools/publish.sh Saved      # save only
```

The same IP rule as in step 3 applies locally.

## Errors

| HTTP | Meaning |
|---|---|
| 401 | key wrong/expired or IP not allowed |
| 403 | key has no `universe-places` → write for this game |
| 404 | universe or place ID wrong |
| 409 | place is currently being saved elsewhere (e.g. Studio/Team Create open) |

Tech: `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published`, header `x-api-key`, body = `.rbxl` (`application/octet-stream`). Docs: [Place publishing](https://create.roblox.com/docs/cloud/guides/usage-place-publishing).
