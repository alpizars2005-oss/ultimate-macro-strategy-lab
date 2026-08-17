# Ultimate Macro Strategy Lab 0.2.0

Private experimental build based on Darksen's official Ultimate Macro 1.3.3.

## Strategy Editor 0.2

The Editor now understands the strategy's `map=` and `requiredTowers=` metadata.

### Map Library

- A clean **Capture** is stored automatically per map under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\camera`.
- The next time a strategy for that map is opened, the exact macro-camera image is loaded automatically.
- The Lab can also fetch lightweight **Top Down reference images** from the Tower Defense Simulator Wiki. These are stored under `%APPDATA%\Ultimate_Macro\StrategyEditor\MapLibrary\reference`.
- Wiki Top Down images are deliberately **reference-only**: perspective/elevation means they are not guaranteed to map directly to recorded screen coordinates. Dragging is locked until a camera capture exists. This prevents silent strategy corruption.
- `Capture` hides Strategy Lab before taking the Roblox image and restores it in `finally`.

### Precision controls

- `-`, `+`, `100%`, and `Fit` zoom controls.
- Mouse wheel zoom while the cursor is over the map.
- Arrow buttons pan the zoomed viewport.
- `Expand / Compact` toggles a larger 640x345 editing surface without making the entire macro fullscreen.
- Marker coordinate conversion follows the current zoom/pan viewport, so drag precision improves as you zoom in.

### Tower Library

The Lab reads `requiredTowers` and associates placements with a tower catalog.

- Default/base tower portraits are cached from the TDS Wiki on demand; skins are not selected.
- The selected placement shows its portrait, display name, and placement-limit metadata.
- Towers with a placement limit of exactly 1 are shown without `#1`.
- Multi-placement towers are displayed as `Tower #1`, `Tower #2`, etc.
- Placement limits live in `Resources\StrategyLab\Towers\catalog.ini` so they can be corrected by an update without changing editor code.

The 0.2 seed catalog covers every tower used by the official 1.3.3 strategies bundled with this Lab. Unknown limits are intentionally left as `0` rather than guessed.

### Asset sync

`Sync Assets` runs in the background. It uses the public TDS Fandom/MediaWiki API and stores only the current strategy's map reference and tower portraits. This keeps the Lab small instead of downloading an entire 4K map/tower library.

The first time the Editor opens a strategy for a map, asset sync is attempted automatically. It is safe to keep using the editor if the Wiki is unavailable; Capture and placeholder portraits continue to work.

## Saving

For testing, prefer **Save Copy** first. `Overwrite + automatic backup` still creates a timestamped backup before replacing a strategy.

The editor only rewrites the first two arguments of the selected `SpawnTower(x, y, ...)` line. `UpgradeTower`, `SellTower`, `ChangeTargets`, `ToggleAutoskip`, abilities, waits, and unknown future actions are preserved.

## Reward Tracker

The 0.1 reward tracker remains intact: result-boundary Coins/Gems/XP, item reward catalog, per-run/session/lifetime ledgers, and evidence capture. It does not run inside timing-sensitive `PlayStrategy()`.

## Auto updater

0.1.1 and later can receive this build through the private `stable` channel. Updates are SHA-256 verified and backed up, and the updater rejects `Resources\Strats` as a target.

## Test status

Static/integration suite for 0.2.0: **13 passed**. A Windows AutoHotkey/Roblox run is still the acceptance test for GUI interaction and live Wiki asset retrieval.
