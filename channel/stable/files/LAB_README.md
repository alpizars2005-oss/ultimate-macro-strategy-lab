# Ultimate Macro Strategy Lab 0.2.6

Private experimental build based on Darksen's official Ultimate Macro 1.3.3.

## Strategy Editor 0.2.6

This build continues the visual-polish pass and makes the tactical canvas directly manipulable with the mouse.

### Direct tactical interaction

- Mouse wheel zooms the tactical map directly under the cursor.
- The point under the cursor stays anchored while zooming, so precision work feels natural instead of zooming only toward the center.
- Click + drag empty map space pans the zoomed viewport.
- Click + drag a placement continues to move that tower placement through the existing safe coordinate-editing path.
- The legacy four pan-arrow buttons are disabled and moved out of the toolbar; direct manipulation replaces them.
- `100%`, `Fit`, `Expand` and `Sync Assets` remain available for explicit reset/actions.
- Live panning is capped to roughly 30 FPS because viewport rendering uses GDI+, avoiding unnecessary CPU churn.

### Polished tactical editor

- Cleaner two-row toolbar and a larger tactical canvas with a dedicated dark details panel.
- Native ListView rows use readable dark-background/light-text styling.
- The first placement is selected automatically when a strategy loads, so portrait/name/coordinates are useful immediately.
- A small state guard repairs stale `No strategy loaded.` text after asynchronous refreshes without touching strategy data.
- Selected placement markers grow slightly for clear editing focus.
- Single-placement towers use a clean initial marker instead of an unnecessary `#1`; multi-placement towers use their occurrence number.
- Empty map state explains whether to use **Sync Assets** or **Capture** instead of showing an unexplained blank rectangle.

### Map Library

- **Capture** hides Strategy Lab before taking the Roblox screenshot and restores it in `finally`.
- Exact macro-camera captures are stored per map under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\camera` and remain authoritative for coordinate dragging.
- Wiki/Interactive-Map images are cached under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\reference` and remain reference-only until exact calibration exists.
- Asset sync tries the Wiki's current `Map:<name>` Interactive Map artwork before falling back to legacy Top Down filename discovery.
- Missing assets are retried on later strategy loads instead of a stale `.done` marker permanently suppressing retries.

### Tower Library

The Lab reads `requiredTowers` and associates placements with a tower catalog.

- Tower portrait sync searches each tower's Gallery first and strongly prefers filenames matching the tower plus `Default` and `Icon`/`Render`/`Portrait` terms; only then does it fall back to the article thumbnail.
- The selected placement shows portrait, display name, slot, X/Y and placement-limit metadata.
- Towers with a placement limit of exactly 1 are shown without `#1`.
- Multi-placement towers are displayed as `Tower #1`, `Tower #2`, etc.
- Placement limits live in `Resources\StrategyLab\Towers\catalog.ini` so they can be corrected independently of editor code.
- Catalog/placeholder paths resolve from `A_ScriptDir`, not the process working directory.

### Asset sync reliability

`Sync Assets` now has two network paths. It first uses normal PowerShell web requests; if Fandom rejects/fails that request it automatically retries through Windows `curl.exe`.

Downloaded files are validated by their actual file signature before being cached. HTML/error pages and unsupported WebP payloads are rejected instead of being saved under a misleading `.png` filename. Existing invalid cached variants are purged on the next sync attempt.

The sync status file reports real counts for tower portraits, map references, misses and errors. The Lab remains usable when the Wiki is unavailable: placeholders, manual snapshots and exact Roblox Capture continue to work.

### Precision controls

- Mouse wheel: zoom in/out under the pointer.
- Drag empty map: pan.
- Drag a placement: move that placement.
- `100%` / `Fit`: reset the viewport.
- `Expand / Compact`: larger tactical surface without fullscreen.
- Marker coordinate conversion follows current zoom/pan state.

## Saving

For live testing, prefer **Save Copy** first. `Overwrite + automatic backup` still creates a timestamped backup before replacing a strategy.

The editor only rewrites the first two arguments of the selected `SpawnTower(x, y, ...)` line. `UpgradeTower`, `SellTower`, `ChangeTargets`, `ToggleAutoskip`, abilities, waits, and unknown future actions are preserved.

## Reward Tracker

The existing reward tracker remains isolated at the result/watchdog boundary: Coins/Gems/XP, item reward catalog, per-run/session/lifetime ledgers, and evidence capture. It does not poll inside timing-sensitive `PlayStrategy()` execution.

## Auto updater / build safety

- Private updates remain SHA-256 verified and automatically backed up.
- `Resources\Strats` remains rejected as an updater target.
- Stable update hashes are generated automatically in GitHub from `channel/stable/files.map`.
- CI sanity checks reject the AHK v2 mistakes that previously caused startup failures, validate update-source mappings, run Python tests, and parse PowerShell helpers.

A real Windows AutoHotkey/Roblox run remains the final acceptance test for GUI interaction and live Wiki asset retrieval.
