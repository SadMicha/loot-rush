# Loot Rush

Roblox ARPG that plays like an incremental. Built with [Rojo](https://rojo.space).

## Setup (once)

1. Install the toolchain: install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in the project folder
2. In VS Code, install the extensions **Rojo** and **Luau Language Server**
3. In Roblox Studio, install the Rojo plugin (Plugins → Rojo)

## Working

1. Run `rojo serve` in the project folder
2. In Studio, open an empty Baseplate → Rojo plugin → **Connect**
3. Press **Play**

Rojo also sets the Lighting settings (Future Lighting, Atmosphere, Bloom, SunRays, ColorCorrection).

## Structure

- `src/shared` → ReplicatedStorage/Shared – types, config, UI theme, helpers
- `src/server` → ServerScriptService/Server – everything that decides game state
- `src/client` → StarterPlayerScripts/Client – camera, input, UI, effects
- Exactly one server script and one client script (`init`); everything else is a module with `init()`/`start()`.

## Rules

- Every file starts with `--!strict`.
- Colors, fonts, icons and animations **only** from `Shared/UI/Theme.luau`, UI **only** from `Client/UI/Kit.luau` – that keeps everything consistent.
- The server never trusts values from the client.
- Language: all code, comments, UI text and docs are English; localization happens via the Roblox translator.

## Checking (without Roblox Studio)

Everything at once (downloads the tools into `.tools/` on first run):

```bash
bash tools/check.sh              # format, lint, types, build, test, ui
bash tools/check.sh test ui      # only selected steps
```

| Step | Tool | checks |
|---|---|---|
| `format` | StyLua | formatting (`stylua src` fixes it) |
| `lint` | selene | suspicious code, unknown globals/enums |
| `types` | luau-lsp | strict types with Roblox type definitions and Rojo sourcemap |
| `build` | Rojo | project builds to `.tools/out/LootRush.rbxl` |
| `test` | Lune | `tests/*.spec.luau` (Jest style: `describe`, `it`, `expect(x).toBe(y)`) |
| `ui` | Lune + Playwright | starts server and client headless, checks the UI, renders preview images |

**Sandbox:** `tools/lune/lib/Sandbox.luau` loads the built game in [Lune](https://lune-org.github.io/docs) and runs the real server and client scripts: virtual time (`task.wait` doesn't really wait), events, remotes (client ↔ server in the same process), tweens, attributes, `AbsoluteSize`/`AbsolutePosition` from an emulated GUI layout. There is no physics, rendering or raycasting. Roblox functions that only exist as stubs are listed in the report.

**UI check** (`lune run tools/lune/ui`): startup in 4 screen sizes (1920×1080, 1366×768, tablet, phone landscape), every button with a handler is pressed once, plus a scenario "inventory with 24 items" and typical keys. Reported: runtime errors (with `src/…luau:line`), elements off screen, clipped or too long text (estimated), invalid image IDs, touch buttons that are too small. Output in `.tools/out/ui/`: `report.md`, `index.html` and one HTML snapshot per state (+ PNG if Playwright is installed). With `LOOTRUSH_IMAGES="folder1;folder2"` the preview shows the real PNGs (file name = name in `Assets.luau`), otherwise placeholders.

**Your own tests:** new file `tests/Name.spec.luau`. `require("ReplicatedStorage.Shared.Items")` loads modules by their game path; `sim:boot()` starts the whole game, `sim:runAs("server", function(req) … end)` runs code on the server.

**Windows:** `rokit install` installs the same tools; `bash tools/setup.sh --data-only` (Git Bash) only downloads the Roblox data. CI runs `tools/check.sh` on every push/PR and attaches the UI report as artifact `ui-check`.

## Publishing

Every push to `main` automatically uploads the game to the test place (workflow `Publish`, locally `bash tools/publish.sh`). Setup and secrets: [docs/PUBLISH.md](docs/PUBLISH.md).
