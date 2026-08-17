# Ultimate Macro Strategy Lab — Preview 0.1

Private experimental build based on Darksen's **official Ultimate Macro 1.3.3**.

The stock `Main.ahk` is preserved. Launch **`run_lab.bat`** (or `Main_Lab.ahk`) for the Lab build.

## Included in Preview 0.1

### Visual Strategy Editor
- `Editor` tab inside the macro.
- Open any `.strat` or load current Strategy 1.
- Reads the strategy's own `[DO NOT EDIT] width/height` recording plane.
- Shows every `SpawnTower()` as a draggable marker.
- Layers by hotbar slot/tower.
- Direct X/Y editing.
- Undo / Redo.
- Load any screenshot as a reference.
- Capture the current Roblox client directly as the editor background.
- Save edited copy.
- Overwrite only after confirmation and create a timestamped backup first.
- Only X/Y of the selected `SpawnTower()` are rewritten; other steps are preserved.

### Reward Tracker / Stats
- `Stats` tab.
- Works independently of Discord webhook being enabled.
- Tracks confirmed Triumph result rewards.
- Uses the official result OCR for Coins / Gems / XP.
- Fixes result OCR capture when Roblox is not at desktop `(0,0)` by applying the client-window offset.
- Template + OCR support for item cards.
- Preview templates included for the brown crate and the duck/event item from supplied real result screenshots.
- Ambiguous item quantities are not counted.
- Result evidence crops are saved under:
  `%APPDATA%\Ultimate_Macro\RewardEvidence`
- Session and lifetime reward totals.
- Per-run CSV ledger and reward CSV ledger.
- A manual `Start` begins a new reward session; automatic watchdog/macro restarts keep it.

## Safety / testing rules

This is a private preview. Keep the official `Main.ahk` as a fallback.

The editor never executes strategy text. Reward scanning runs only after a confirmed result screen; it is not called from `PlayStrategy()`, placements, upgrades, abilities or recorded timing loops.

For the first live test:
1. Back up any important custom `.strat`.
2. Run `run_lab.bat`.
3. Open `Editor`, load a strategy and use **Save Copy** first.
4. Confirm a moved tower changed only the selected `SpawnTower(X,Y,...)`.
5. Run that edited copy in a low-risk match.
6. After a Triumph, open `Stats` and check `%APPDATA%\Ultimate_Macro\RewardEvidence`.

The item templates are deliberately conservative. Real result screens from additional resolutions/rewards will be used to calibrate future catalog entries.
