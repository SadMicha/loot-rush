# Publishing to Roblox automatically

On every push to `main` that changes the game (or via a button in GitHub), GitHub Actions checks the game, builds it with Rojo into an `.rbxl` and uploads it via Roblox Open Cloud to an existing place as a **Published** version. After that it's playable in the Roblox app on phone and iPad.

**Speed:** the workflow runs only the fast gates (format, lint, types, Rojo build, about a second each) and then uploads; the toolchain comes from the Actions cache. The full Lune suite (~9 min) is not repeated here because CI already runs it on every PR. A run takes well under a minute. Pushes that only touch `docs/`, `tests/`, `assets/` or other non-game files don't publish at all, and a newer push cancels an older run that is still going. **Run workflow** has a `fullTests` box if you want the suite before an upload anyway.

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

## Test place (separate from the live game)

The `Roblox` environment now points at the **live** game. Everything that should be tried first goes to a private test experience through its own workflow, `.github/workflows/publish-test.yml`, with its own environment `Roblox-Test`.

**Why a separate experience (not a second place in the live one):** DataStores, analytics, badges, developer products and the Great Build pool all belong to the **universe**. A place inside the live universe would read and write live saves. A separate experience keeps all of that apart automatically, with no code change.

### Set it up (once)

1. Studio → **New → Baseplate** → **File → Publish to Roblox As … → New experience**, name it "Loot Rush Test". Keep it **Private** (Configure → Access); tick Phone and Tablet under Devices.
2. Copy its **Universe ID** (Creations → ⋯ → Copy Universe ID) and the start place's **Place ID** (`…/places/<NUMBER>/configure`).
3. Creator Hub → Open Cloud → API Keys → **Create API Key** `loot-rush-test`: API system **universe-places** → select **only the test experience** → **write**; Accepted IP `0.0.0.0/0`. (A separate key means a leaked test key can never touch the live game.)
4. GitHub → Settings → Environments → **New environment** `Roblox-Test` → three secrets: `ROBLOX_API_KEY`, `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID` (the values from steps 2-3).
5. GitHub → Issues → Labels → **New label** `test-place`.

### Use it

| Want | Do |
|---|---|
| Test place = what is on `main` | automatic on every merge |
| Try a PR before merging | add the label `test-place` to the PR; every new push to it re-publishes |
| Try any branch | Actions → **Publish test place** → Run workflow → "Use workflow from" = the branch |

Only one test place exists, so the newest upload wins. Play it at `https://www.roblox.com/games/<TEST_PLACE_ID>`.

### What differs in the test place

- **Saves, leaderboard, Great Build, analytics:** separate, start empty. Wipe freely.
- **Debug commands:** work for you as the experience owner (same rule as Studio).
- **Badges:** the IDs in `Shared/Badges` belong to the live experience, so they don't award here.
- **Developer products** (Soulstars, gold): IDs belong to the live experience, the prompt fails here. **Game passes** can be prompted from any experience and **charge real Robux**, so don't buy them in the test place. Test purchases in Studio, where they are free.

## Making the game public (one click, done by you)

The workflow publishes new **versions** of the place; it never changes who can play. Switching the game to public is up to you:

1. [Creator Hub → Creations](https://create.roblox.com/dashboard/creations) → on the game's tile click **⋯ → Make Public**
   (or open the game → **Configure → Access/Settings** → set it to **Public** → **Save**).
2. If Roblox asks first: fill in the **maturity & compliance questionnaire** once and confirm the devices (Computer, Phone, Tablet).
3. Back to private the same way (**⋯ → Make Private**).

Before going public with the real game, read [RELEASE.md](RELEASE.md) (Max Players, API access, product IDs, `DEV_USERS`).

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
