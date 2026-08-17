# Ultimate Macro Strategy Lab

Private development lab for experimental Ultimate Macro features before upstream review.

**Compatibility baseline: Darksen official Ultimate Macro 1.3.3.** Kronox improvements are evaluated as selective ports on top of that baseline, never as a wholesale replacement.

**Current Windows test build: Lab Preview 0.1.1.**

Current goals:

1. **Visual Strategy Editor** — parse `.strat` files, render `SpawnTower(x,y,slot,id)` actions on the macro recording plane, filter them as layers, drag placements, and rewrite only the selected coordinates while preserving every other recorded step.
2. **Reward Tracker** — attach to the existing result-screen/watchdog boundary, record standard currencies and extensible item rewards into per-run/session/lifetime ledgers, and save evidence for unknown rewards instead of guessing.
3. **Selective Kronox improvements** — evaluate and port reliability/analytics/editor ideas that do not weaken gameplay timing or the Remote safety boundary.
4. **Private Lab updater** — one-time private GitHub authorization followed by prompt-based self-updates, SHA-256 verification and rollback backups without replacing `Resources/Strats` or AppData state.

## Preview 0.1.1

- Integrated `Editor` and `Stats` tabs on top of official 1.3.3.
- `Capture` hides Strategy Lab before taking the Roblox client screenshot and restores the GUI in a `finally` path.
- Private update channel lives under `channel/stable/`.
- Installed Lab version is stored separately in `lab_version.ini`, allowing normal module updates without replacing the large `Main_Lab.ahk` just to bump a version number.
- The updater rejects traversal/rooted paths, refuses `Resources/Strats`, verifies SHA-256 before replacement and backs up files before applying changes.
- Static/integration suite: **8 tests passing** before packaging 0.1.1.

## Privacy / status

This lab is intentionally separate from the Remote repository currently shared for upstream review. Do not publish or invite upstream reviewers until the prototypes have passed local testing.

## Visual editor

The integrated editor does **not** execute strategy text. It edits only placement coordinates in memory until explicitly saved.

- Open a `.strat` or use current Strategy 1.
- Load a screenshot or capture the current Roblox client.
- Each `SpawnTower` becomes a draggable marker.
- Layer by hotbar slot/tower.
- Drag or type X/Y directly.
- Undo / Redo.
- Save Copy or Overwrite + automatic backup.
- Non-placement actions such as upgrades, abilities, `ChangeTargets()`, `ToggleAutoskip()` and unknown future actions are preserved.

## Reward tracker

The tracker runs at the confirmed result/watchdog boundary, never inside `PlayStrategy()`. It records runs and confirmed rewards, keeps session/lifetime totals, handles Roblox windows away from desktop `(0,0)`, and stores evidence when item recognition is uncertain.

See `docs/reward-tracker.md`, `docs/baseline-1.3.3.md` and `docs/port-plan.md`.

## Source notes

The design was compared against Darksen's Ultimate Macro and Kronox's GPL-3.0 fork. If implementation code is ported from GPL sources, preserve required license/attribution.
