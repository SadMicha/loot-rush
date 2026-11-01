# Loot Rush – working rules for Claude

Roblox ARPG that plays like an incremental (Luau, Rojo). Read `README.md` and `docs/ROADMAP.md` first.
Longer specs: `docs/specs/`. Playtest checklists: `docs/TEST-*.md`.

## Language
Everything is English: code, identifiers, comments, UI text, docs. Do not hardcode translations
(the owner localizes through the Roblox translator). Numbers use English formats (`1,240`, `4.5%`).

## Layout
- `src/server` → ServerScriptService/Server (game state, authority)
- `src/shared` → ReplicatedStorage/Shared (config, types, rules; `src/shared/UI` = Theme/Assets)
- `src/client` → StarterPlayerScripts/Client (controllers; `src/client/UI` = Kit and views)
- `tests/*.spec.luau` run headless in Lune (`tools/lune`); `tools/` = check, setup, upload scripts
- Packages come from Wally (`bash tools/packages.sh`); `ServerPackages/` is generated, do not edit.

## Code rules
- Every file starts with `--!strict`. StyLua formatting, Selene linting, `task.*` only.
- Server is authoritative; never trust remote arguments (validate type, range, NaN, rate limit).
- Colors, fonts, sizes, icons only from `Theme`; UI only through `Kit`; images registered in `Assets`.
- Persisted ids, remote names, attributes, tags are English and stable. Saves: ProfileStore store
  `LootRush_Profile_v3` (old stores are ignored on purpose, test place, no migrations).
- Tunable numbers live in `Config`/`Balance`, not inline.

## Checks (Windows, Git Bash)
- Put `~/.rokit/bin` first on PATH (the old Aftman shims break the tools).
- `bash tools/check.sh [packages|format|lint|types|build|test|ui]`; no argument runs all of them.
- **Usage budget: do not run the full Lune suite (~4-5 min) while working.** Run
  `bash tools/check.sh format lint types` plus only the specs you touched:
  `lune run tools/lune/test <name-fragment>` (e.g. `Data`, `Items`). CI runs everything on every
  PR; the main session runs the full suite once before a commit/merge and reads the last
  "N passed, M failed" line.
- After a `.gitattributes` change, checkouts must be LF (StyLua line_endings = Unix).
- Smoke test for a quick playtest: `docs/SMOKE-TEST.md` (10 steps); long checklists are for releases.

## Agents (`.claude/agents`)
- `project-planner` (docs/ only) → briefs for the others; owns ROADMAP and specs.
- `backend-developer`: `src/server`, `src/shared` except `UI/`, `tests`, `tools/lune`. Writes code only.
- `frontend-developer`: client behavior (effects, camera, input, loot in the world).
- `ui-designer`: `src/client/UI`, `src/shared/UI`, windows/HUD, image prompts for ChatGPT.
- `code-reviewer`: read-only; reviews the committed state; reports PASS / PASS WITH NOTES / BLOCK.
- Stay in your lane; describe cross-lane needs as a contract in your report instead of editing.
- Several agents may edit the working tree at once: run `git status` first, touch only your files,
  never revert files you did not change.
- Parallel agents: the main session starts each with `isolation: "worktree"` when their files
  could overlap, and merges their branches; otherwise it splits work by folder.
- Models: `backend-developer` runs Opus (risky server/data code); the main session overrides it to
  Sonnet for routine tasks (translations, docs, adding tests, small fixes). Reviewer/planner run Sonnet;
  override to Opus only for saving, purchases, remotes or security reviews.
- Review once per milestone or PR, not after every step; review early only for saving, purchases,
  remotes and security. Cosmetic UI shares one review at the end.
- Do not commit unless asked. Commit messages end with the Co-Authored-By line from the session.
- Ask the user (AskUserQuestion) only for real design decisions; collect them in one question.

## Images and assets
The owner makes art with ChatGPT. Source PNGs live in `assets/`; uploads go through the
"Upload UI assets" GitHub workflow (Open Cloud, key stays in the GitHub environment `Roblox`).
The resulting ids are in `assets/ui-asset-ids.csv`; register them in `src/shared/UI/Assets.luau`.
A missing or empty id must fall back to the flat style, never error.

## Studio
The `Roblox_Studio` MCP server (local scope) can playtest, read the Output and take screenshots when
Studio is open with the place connected through Rojo (`rojo serve`, Connect). Rojo owns the scripts:
edit files on disk, use MCP only to inspect, run and playtest. Always stop play when done and
report what was actually verified.

## Reporting
Short: files changed, checks run with their real result, anything not verified, open decisions.
Never claim something works that was only reasoned about.
