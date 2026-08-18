# Ultimate Macro Strategy Lab 0.2.5

Private experimental build based on Darksen's official Ultimate Macro 1.3.3.

## Strategy Editor 0.2.5

This build is a visual-polish and asset-reliability pass over the 0.2 editor.

### Polished tactical editor

- Cleaner two-row toolbar with map, layer, pan, zoom and asset controls grouped together.
- Larger tactical canvas and a dedicated dark details panel.
- Native ListView rows now use readable dark-background/light-text styling instead of white-on-white rows.
- The first placement is selected automatically when a strategy loads, so the unit portrait/name/coordinates are visible immediately.
- Selected placement markers grow slightly for a clearer editing focus.
- Single-placement towers use a clean initial marker instead of an unnecessary `#1`; multi-placement towers use their occurrence number.
- Empty map state now explains whether to use **Sync Assets** or **Capture** instead of showing a blank rectangle.

### Map Library

- **Capture** hides Strategy Lab before taking the Roblox screenshot and restores it in `finally`.
- Exact macro-camera captures are stored per map under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\camera` and remain authoritative for coordinate dragging.
- Wiki/Interactive-Map images are cached under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\reference` and remain reference-only until exact calibration exists.
- Asset sync now tries the Wiki's current `Map:<name>` Interactive Map artwork before falling back to legacy Top Down filename discovery. This improves support for current maps such as Dead Ahead.
- Missing assets are retried on later strategy loads instead of a stale `.done` marker permanently suppressing retries.

### Tower Library

The Lab reads `requiredTowers` and associates placements with a tower catalog.

- Tower portrait sync now searches each tower's Gallery first and strongly prefers images whose filenames match the tower plus `Default` and `Icon`/`Render`/`Portrait`-style terms; only then does it fall back to the article thumbnail.
- The selected placement shows portrait, display name, slot, X/Y and placement-limit metadata.
- Towers with a placement limit of exactly 1 are shown without `#1`.
- Multi-placement towers are displayed as `Tower #1`, `Tower #2`, etc.
- Placement limits live in `Resources\StrategyLab\Towers\catalog.ini` so they can be corrected independently of editor code.
- Catalog/placeholder paths are resolved from `A_ScriptDir`, not the current working directory, so launching the Lab from a different directory no longer breaks asset lookup.

### Asset sync status

`Sync Assets` now writes a small status file and reports real results, for example how many tower portraits and map references were downloaded, plus misses/errors. The Editor shows that state in the header instead of always saying only that sync finished.

The Lab remains usable when the Wiki is unavailable: placeholders, manual snapshots and exact Roblox Capture continue to work.

### Precision controls

- `−`, `+`, `100%`, and `Fit` zoom controls.
- Mouse-wheel zoom while the cursor is over the map.
- Arrow buttons pan the zoomed viewport.
- `Expand / Compact` provides a larger tactical surface without forcing the entire macro fullscreen.
- Marker coordinate conversion follows the current zoom/pan viewport.

## Saving

For live testing, prefer **Save Copy** first. `Overwrite + automatic backup` still creates a timestamped backup before replacing a strategy.

The editor only rewrites the first two arguments of the selected `SpawnTower(x, y, ...)` line. `UpgradeTower`, `SellTower`, `ChangeTargets`, `ToggleAutoskip`, abilities, waits, and unknown future actions are preserved.

## Reward Tracker

The existing reward tracker remains isolated at the result/watchdog boundary: Coins/Gems/XP, item reward catalog, per-run/session/lifetime ledgers, and evidence capture. It does not poll inside timing-sensitive `PlayStrategy()` execution.

## Auto updater / build safety

- Private updates remain SHA-256 verified and automatically backed up.
- `Resources\Strats` remains rejected as an updater target.
- Stable update hashes are now generated automatically in GitHub from `channel/stable/files.map`, removing manual manifest drift.
- CI sanity checks reject the AHK v2 mistakes that previously caused startup failures (`A_LocalAppData` and using reserved `local` as a variable), validate update-source mappings, run Python tests, and parse the PowerShell helpers.

A real Windows AutoHotkey/Roblox run is still the final acceptance test for GUI interaction and live Wiki asset retrieval.
