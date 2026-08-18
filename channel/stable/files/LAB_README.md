# Ultimate Macro Strategy Lab 0.2.7

Private experimental build based on Darksen's official Ultimate Macro 1.3.3.

## Strategy Editor 0.2.7

This build fixes the remaining startup/state and asset-cache problems found during live Windows testing of 0.2.6.

### Direct tactical interaction

- Mouse wheel zooms the tactical map directly under the cursor.
- Click + drag empty map space pans the zoomed viewport.
- Click + drag a placement moves that placement through the existing safe coordinate-editing path.
- The legacy four pan-arrow buttons remain disabled/hidden.
- The interaction layer no longer reads Main.ahk's `CurrentTab` global. It determines Editor activity from the actual Editor canvas controls instead, eliminating startup crashes when upstream tab state has not been assigned yet.
- Live panning remains capped to roughly 30 FPS because viewport rendering uses GDI+.

### Loaded-state repair

- The Editor state guard now runs based on actual Editor visibility instead of `CurrentTab`.
- If a strategy is loaded but stale UI text still says `No strategy loaded.`, the dirty/status summary is refreshed automatically.
- If the details panel loses its selected row during an asynchronous refresh, the first placement is selected again without altering strategy data.

### Map / portrait cache validation

- Cached map images and tower portraits are validated with GDI+ before use.
- Invalid files are automatically deleted so a stale HTML/WebP/error response cannot remain permanently cached under a `.png`/`.jpg` filename.
- Exact macro-camera captures remain authoritative for coordinate editing.
- Wiki/Interactive-Map artwork remains reference-only until exact calibration exists.

### Asset sync reliability

The 0.2.7 synchronizer moves the fallback to the correct layer:

- MediaWiki JSON/API queries first use PowerShell `Invoke-RestMethod` and automatically retry through Windows `curl.exe` if the request is blocked or fails.
- Image downloads first use PowerShell and also retry with `curl.exe`.
- The synchronizer requests original Wiki image files whenever possible instead of thumbnail URLs, reducing accidental WebP responses that GDI+ cannot decode.
- Downloaded bytes are signature-checked as PNG/JPEG/BMP before entering the cache.
- The status file records real tower/map counts, misses/errors, API fallback count and download fallback count.

### Tactical editor UX

- Dark readable placement table.
- First placement selected automatically.
- Selected marker is visually larger.
- Unique towers omit unnecessary `#1`; multi-placement towers show their occurrence number.
- Tower details show portrait, display name, slot, X/Y and placement-limit metadata.
- `100%`, `Fit`, `Expand` and `Sync Assets` remain available as explicit controls.

## Saving

For live testing, prefer **Save Copy** first. `Overwrite + automatic backup` always creates a timestamped backup before replacing a strategy.

The editor only rewrites the first two arguments of the selected `SpawnTower(x, y, ...)` line. `UpgradeTower`, `SellTower`, `ChangeTargets`, `ToggleAutoskip`, abilities, waits and unknown future actions remain untouched.

## Reward Tracker

The reward tracker remains isolated at the result/watchdog boundary. It does not poll inside timing-sensitive `PlayStrategy()` execution.

## Auto updater / build safety

- Private updates remain SHA-256 verified and automatically backed up.
- `Resources\Strats` remains rejected as an updater target.
- Stable update hashes are generated automatically in GitHub from `channel/stable/files.map`.
- CI sanity checks validate the update source map, run Python tests and parse PowerShell helpers.

A real Windows AutoHotkey/Roblox run remains the final acceptance test for GUI interaction and live Wiki asset retrieval.