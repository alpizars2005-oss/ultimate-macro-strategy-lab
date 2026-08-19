# Ultimate Macro Strategy Lab 0.4.0

Private experimental build based on Darksen's Ultimate Macro, with Strategy Lab features layered on top instead of replacing the upstream macro workflow.

## Visual Strategy Editor 0.4

The Editor was rebuilt around a deliberately simple rule: **one screenshot, one canvas**.

- The map source is the exact Roblox view captured by Ultimate Macro, cached locally per map.
- **Capture Map** captures Roblox and saves that map's camera view.
- **Snapshot** can load a manual screenshot when needed.
- The Editor does not download wiki/top-down map art or tower portraits.
- Placement-radius circles and compact numbered/initial markers are composited directly into the screenshot before it reaches the GUI.
- There are no per-placement marker HWNDs and no transparent sibling ring controls, removing the square/black stacking path from the 0.3.x implementation.
- `Radii: All`, `Radii: 1` and `Radii: Off` control the generated placement guides.
- Layer filtering affects both the rendered canvas and placement table from the same visibility predicate.
- Clicking/dragging uses geometric hit-testing against the painted markers.
- Mouse wheel zooms under the cursor and dragging empty map space pans the viewport.
- The selected-unit panel uses a local circular badge and strategy metadata instead of website images.
- The Editor automatically expands Ultimate Macro into a larger workspace and restores the compact size when leaving the tab.

## Safe strategy loading and saving

Before the Editor loads a `.strat`, Strategy Lab rejects clearly malformed or unreasonable files, including empty files, missing `[Steps]`, oversized files, excessive placement counts and extreme placement coordinates.

For live testing, prefer **Save Copy** first. `Overwrite + automatic backup` creates a timestamped backup before replacing a strategy.

The editor only rewrites the selected `SpawnTower(x, y, ...)` coordinates. Upgrade, sell, targeting, autoskip, abilities, waits and unknown/future strategy actions are preserved.

## Discord Remote

Open **Editor → Remote** to configure the built-in Discord controller. The bot token is stored with Windows DPAPI for the current Windows user. Network polling and screenshot upload run in a separate PowerShell worker; gameplay-changing commands are consumed through the safe between-match queue rather than injected into `PlayStrategy()`.

Supported commands include `!help`, `!ping`, `!status`, `!screenshot`, strategy list/start/switch, safe stop, emergency stop, radii control and recalibration.

## Stats, rewards and telemetry

The Stats tab reads existing macro state/telemetry only and is guarded against destroyed GUI controls during updater/ExitApp transitions. Strategy Lab tracks confirmed win/loss runs and Coins/Gems/EXP deltas locally under:

```text
%APPDATA%\Ultimate_Macro\StrategyEditor\telemetry\
```

The separate RewardLibrary may optionally cache small reward/drop reference icons from the TDS Wiki. That network work is cosmetic and is not part of the Editor render loop or gameplay timing.

## Emergency stop

`F12` is reserved by Strategy Lab as a global emergency stop. It stops the strategy when possible and releases common held keyboard/mouse inputs. The same cleanup runs when Strategy Lab exits.

## Auto updater / safety

- Stable update files are SHA-256 verified.
- Existing Lab files are backed up before replacement.
- `Resources\Strats` is never an updater target.
- Updates restart Strategy Lab after installation.
- `run_lab.bat` executes preflight before AutoHotkey parses `Main_Lab.ahk`.
- CI validates the real AutoHotkey include contract, startup/teardown timing, strategy encodings, Discord Remote settings, and the 0.4 single-canvas render/layer/hit-test runtime contract.

A real Windows + AutoHotkey + Roblox run remains the final acceptance test for live camera geometry, input and game UI changes.
