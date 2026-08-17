# Ultimate Macro Strategy Lab

Private development lab for experimental Ultimate Macro features before upstream review.

**Compatibility baseline: Darksen official Ultimate Macro 1.3.3.** Kronox improvements are evaluated as selective ports on top of that baseline, never as a wholesale replacement.

Current goals:

1. **Visual Strategy Editor** — parse `.strat` files, render `SpawnTower(x,y,slot,id)` actions on a scaled 1920x1080 viewport, filter them as layers, drag placements, and rewrite only the selected coordinates while preserving every other recorded step.
2. **Reward Tracker** — attach to the existing result-screen/watchdog boundary, record standard currencies and extensible item rewards (crates, event currencies, ducks, etc.) into per-run/session/lifetime ledgers, and save evidence for unknown rewards instead of guessing.
3. **Selective Kronox improvements** — evaluate and port reliability/analytics/editor ideas that do not weaken gameplay timing or the Remote safety boundary.

## Privacy / status

This lab is intentionally separate from the Remote repository currently shared for upstream review. Do not publish or invite upstream reviewers until the prototypes have passed local testing.

## Visual editor prototype

`src/VisualStrategyEditor.ahk` is a standalone AutoHotkey v2 prototype. It does **not** execute a strategy. It only edits `.strat` text.

- Open a `.strat` file.
- Optionally load a screenshot of the Roblox/TDS viewport as the background.
- Each `SpawnTower` action becomes a draggable marker.
- Use the Layer selector to show all placements or only one hotbar slot/tower.
- Drag a marker to its corrected position.
- **Save Copy** writes a new file.
- **Overwrite + Backup** creates a timestamped backup before replacing the original.

The first prototype intentionally assumes the macro's normal 1920x1080 coordinate space. The eventual in-macro tab will derive the live Roblox client size and can capture the current viewport directly.

## Reward tracker design

See `docs/reward-tracker.md`. The first integration target is the watchdog's already-validated Triumph/result boundary, not the strategy playback loop.

See `docs/baseline-1.3.3.md` for the compatibility contract and `docs/port-plan.md` for the tracked Kronox improvements.

## Source notes

The design was compared against Darksen's Ultimate Macro and Kronox's GPL-3.0 fork. If implementation code is later ported from GPL sources, preserve the required license/attribution in the integrated project.
