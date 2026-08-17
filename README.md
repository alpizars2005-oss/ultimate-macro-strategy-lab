# Ultimate Macro Strategy Lab

Private development lab for experimental Ultimate Macro features before upstream review.

**Compatibility baseline: Darksen official Ultimate Macro 1.3.3.** Kronox improvements are evaluated as selective ports on top of that baseline, never as a wholesale replacement.

**Current Windows test build: Lab Preview 0.2.0.** The private `stable` updater channel is the preferred delivery path from 0.1.1 onward.

Current goals:

1. **Visual Strategy Editor** — edit recorded `SpawnTower(x,y,slot,id)` placements visually while preserving every other strategy action.
2. **Map Library** — auto-load map-specific macro-camera captures, optionally cache TDS Wiki top-down references, and provide zoom/pan/expanded precision editing without treating an uncalibrated aerial image as screen coordinates.
3. **Tower Library** — associate `requiredTowers` with base/default portraits, names and catalog-driven placement labels/limits.
4. **Reward Tracker** — record standard currencies and extensible item rewards into per-run/session/lifetime ledgers at the confirmed result boundary.
5. **Selective Kronox improvements** — evaluate reliability/analytics/editor ideas without weakening gameplay timing or the Remote safety boundary.
6. **Private Lab updater** — prompt-based self-updates with SHA-256 verification, backups, and an explicit block on `Resources/Strats`.

## Preview 0.2.0

- Map-specific camera images are cached under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\camera` and auto-loaded next time that map is edited.
- Optional Wiki Top Down images are cached as **reference-only**. Dragging on them is locked until a clean macro-camera Capture exists for the map.
- Zoom from 100–400%, mouse-wheel zoom, pan buttons, Fit/Reset and Expand/Compact editing.
- `Capture` hides the Strategy Lab, activates Roblox, captures the clean client and restores the GUI in `finally`.
- Tower portraits are requested lazily from the TDS Wiki for the towers used by the loaded strategy; placeholder portraits keep the editor usable offline.
- Unique-placement towers omit `#1`; repeatable towers show `#N`. Placement metadata is data-driven in `Resources/StrategyLab/Towers/catalog.ini` rather than hard-coded through the UI.
- Asset sync is lazy: only the currently loaded map/towers are requested, keeping the install small.
- Static/integration suite: **13 tests passing** before packaging 0.2.0.

## Editor safety contract

The editor never executes strategy text. It rewrites only the first two coordinates of the selected `SpawnTower` line when the user explicitly edits a placement. Upgrades, sells, abilities, waits, `ChangeTargets()`, `ToggleAutoskip()` and unknown future non-placement actions remain untouched.

For testing, prefer **Save Copy** before using Overwrite. Overwrite still creates a timestamped backup first.

## Reward tracker

The tracker runs at the confirmed result/watchdog boundary, never inside `PlayStrategy()`. It records runs and confirmed rewards, keeps session/lifetime totals, handles Roblox windows away from desktop `(0,0)`, and stores evidence when item recognition is uncertain.

## Asset/source boundary

The Lab does not vendor Kallly/TDS Mapper assets or code. The mapper was used only as product/UX research. Optional tower portraits and map references are requested on demand through the TDS Wiki/MediaWiki boundary and cached locally; see `Resources/StrategyLab/ATTRIBUTION.md`.

## Privacy / status

This lab is intentionally separate from the Remote repository currently shared for upstream review. Keep it private until live testing is mature enough for an upstream demo.

See `preview-0.2/BUILD.md`, `docs/reward-tracker.md`, `docs/baseline-1.3.3.md` and `docs/port-plan.md`.
