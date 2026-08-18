# Ultimate Macro Strategy Lab 0.3.0

Private experimental build based on Darksen's Ultimate Macro, with Strategy Lab features layered on top instead of replacing the upstream macro workflow.

## What 0.3.0 integrates

Strategy Lab now consolidates the useful macro-related work from the repositories available to this project:

- The visual Strategy Editor, calibrated map workflow, local tower portrait cache and placement-footprint guides from Strategy Lab.
- The safe command queue and between-match switching model from `ultimate-macro-remote`.
- Reliability ideas from `Macro-Recorder-JSON`: strict input validation, a global emergency stop, held-input cleanup and lightweight local run telemetry.
- The current Ultimate Macro gameplay/recording feature set remains upstream-owned and is not duplicated inside Strategy Lab.

Unrelated repositories such as portfolio, coursework, job-search and food/inventory projects are intentionally not copied into the macro.

## Visual Strategy Editor

- Mouse wheel zooms under the cursor.
- Click + drag empty map space pans the viewport.
- Click + drag a placement moves it through the safe coordinate-editing path.
- Exact camera captures are authoritative for editing; Wiki artwork is reference-only.
- Tower portraits are downloaded only when needed, cached locally and aspect-fitted into the selected-unit card.
- Circular placement markers and optional footprint circles can be shown for all towers, only the selected tower or hidden.
- Layer filtering affects both the map and placement table.
- The Editor automatically expands the Ultimate Macro window into a larger workspace and restores the compact size when leaving the tab.
- Map frame swaps use an atomic whole-window redraw boundary to reduce tearing/flicker while panning and zooming.

## Safe strategy loading and saving

Before the Editor loads a `.strat`, Strategy Lab rejects clearly malformed or unreasonable files, including empty files, missing `[Steps]`, oversized files, excessive placement counts and extreme placement coordinates.

For live testing, prefer **Save Copy** first. `Overwrite + automatic backup` creates a timestamped backup before replacing a strategy.

The editor only rewrites the selected `SpawnTower(x, y, ...)` coordinates. Upgrade, sell, targeting, autoskip, abilities, waits and unknown/future strategy actions are preserved.

## Discord Remote

Open **Editor → Remote** to configure the built-in Discord controller.

The settings helper stores the bot token with Windows DPAPI for the current Windows user. The plaintext token is not written to the Strategy Lab configuration file. Configure:

- Bot token
- Private Channel ID
- Allowed Discord User ID
- Poll interval

Recommended bot permissions are View Channel, Send Messages, Read Message History and Attach Files. Message Content Intent must be enabled for text commands.

Supported commands:

```text
!help
!ping
!status
!screenshot
!strategy list
!start <strategy>
!switch <strategy>
!strategy <strategy>
!stop
!stop now
!rings all
!rings selected
!rings off
!recalibrate
```

The worker deliberately seeds its Discord cursor from the newest existing message and does **not** execute that message. Only newer messages from the configured user are processed, preventing stale commands from replaying after a restart.

Network polling and screenshot upload run in a separate PowerShell worker. Gameplay-changing commands are written to tiny local INI queues. Safe stop and switch are consumed only at the `RunStrategy()` between-match boundary; Strategy Lab never inserts remote polling into `PlayStrategy()`.

A remote switch loads the new strategy before the next match. A safe stop marks the macro stopped, kills submacros and releases held input. `!stop now` invokes the emergency-stop path.

## Emergency stop

`F12` is reserved by Strategy Lab as a global emergency stop. It stops the strategy when possible and releases common held keyboard/mouse inputs. The same cleanup runs when Strategy Lab exits.

## Local telemetry

Strategy Lab observes official `state.ini` counters once per second and keeps local diagnostics under:

```text
%APPDATA%\Ultimate_Macro\StrategyEditor\telemetry\
```

- `heartbeat.ini` records whether the Lab is stopped/running/playback plus the current strategy and counters.
- `runs.jsonl` appends one local entry when the official win/loss counters advance and includes a SHA-256 fingerprint of the strategy file.

No OCR/network polling is added inside timing-sensitive strategy playback.

## Automatic map calibration

The calibration worker watches Ultimate Macro state and captures a clean Roblox camera reference the first time a map/resolution combination is encountered. Camera captures are kept under AppData rather than shipped inside the macro package, keeping Strategy Lab small.

## Asset caching

Tower and map artwork is stored under `%APPDATA%\Ultimate_Macro\StrategyEditor`. Downloads are validated before entering the cache and converted to small Windows/GDI+-friendly local derivatives. Invalid HTML/WebP/error responses are purged rather than reused forever.

## Auto updater / preflight safety

- Stable update files are SHA-256 verified.
- Existing files are backed up before replacement.
- `Resources\Strats` is never an updater target.
- Updates restart Strategy Lab after installation.
- `run_lab.bat` executes preflight before AutoHotkey parses `Main_Lab.ahk`.
- Preflight normalizes Windows paths, repairs only known high-confidence parser corruption, refuses merge-conflicted files and installs the Discord safe-boundary hook idempotently.
- The remote hook is inserted only in `RunStrategy()` at the between-match boundary; `PlayStrategy()` is intentionally untouched.
- CI checks the stable delivery map, Python tests, PowerShell parsing and the expected safety/remote integration markers.

A real Windows + AutoHotkey + Roblox run remains the final acceptance test for live input, camera geometry, Discord permissions and game UI changes.
