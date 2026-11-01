# Checklist (template for every PR)

Copy, paste into the PR text and fill in. Goal: Micha sees in 2 minutes what's new and what to look at in Studio or on the phone.

```markdown
## Checklist

**What changed?** (1–3 sentences, from the player's view)
-

**Checked automatically** (`bash tools/check.sh`)
- [ ] format · lint · types · build · test · ui green
- [ ] UI report without new warnings (`.tools/out/ui/report.md`, CI artifact "ui-check")

**Please look at** (only what this PR touches)
| Where | What to do | What should happen |
|---|---|---|
| Studio / phone / tablet | e.g. open the Forge (B), select an item | Texts stay inside their rows, nothing under the top bar |

**Get there faster** (Dbg button bottom left → test commands, Studio only)
- e.g. "+10 Items", "+100 Material", "Regions unlocked"

**Known gaps / not tested**
-
```

## Notes

- Only fill **Please look at** with things the check can't see: real images, feel while playing, phone controls, saving across restart.
- Phone test works in Studio via *Test → Device* (e.g. iPhone, landscape) or for real via the Roblox app.
- Debug menu: always available in Studio. In the published game only for UserIds in `DEV_USERS` (`src/server/Systems/Debug.luau`).
- Among other things, the UI check reports text under the Roblox top bar (top left), text behind icons/buttons, text over the panel edge, empty rows and capsules without a label, deviating close buttons. Fix false alarms in `tools/lune/lib/Checks.luau` first, don't work around them in game code.
