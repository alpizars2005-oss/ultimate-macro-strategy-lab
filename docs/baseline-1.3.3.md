# Official baseline: Ultimate Macro 1.3.3

This lab now treats Darksen's official **Ultimate Macro 1.3.3** release as the compatibility baseline.

## Why this matters

The Strategy Lab is not based on the older 1.3.2a snapshot. Experimental features must preserve all 1.3.3 strategy semantics and UI/runtime behavior before they are considered merge candidates.

## Strategy actions the editor must preserve

The visual editor currently rewrites only the first two numeric arguments of `SpawnTower(x, y, slot, towerId)`.

Everything else remains byte-for-byte untouched unless a future editor operation explicitly targets it. In particular, 1.3.3 actions such as these must survive coordinate edits unchanged:

- `UpgradeTower(...)`
- `SellTower(...)`
- `ChangeTargets(towerId, target)`
- `ToggleAutoskip()`
- abilities and other recorded actions
- timing/recorded input steps

The editor must never reserialize the whole `[Steps]` section from an abstract model. It edits the smallest possible text span so unknown/new actions remain forward-compatible.

## Integration rules for 1.3.3

1. Official 1.3.3 behavior wins when it conflicts with an older fork implementation.
2. Kronox features are ported as isolated ideas/modules, not by replacing `Main.ahk` wholesale.
3. No editor, analytics, reward recognition, heartbeat, or recovery polling is inserted into timing-sensitive recorded playback.
4. Reward recognition attaches only after the normal result screen is validated.
5. Any future in-macro Editor tab must refuse destructive overwrite while a strategy is actively running.
6. Before upstream review, run acceptance against unmodified 1.3.3 strats that exercise new actions such as `ChangeTargets()` and `ToggleAutoskip()`.

## Compatibility test target

For every editor save:

- selected `SpawnTower` coordinates may change;
- tower ID and hotbar slot must not change unless the user explicitly requests that operation;
- all non-selected `SpawnTower` lines must remain unchanged;
- all non-`SpawnTower` actions must remain unchanged;
- newline style should be preserved;
- overwrite must create a backup first.
