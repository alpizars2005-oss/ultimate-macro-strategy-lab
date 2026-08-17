# Preview 0.1 build manifest

Baseline: Darksen official Ultimate Macro **1.3.3**.

## Verification

Local static/integration verification before packaging:

```text
python -m pytest -q
......                                                                   [100%]
6 passed in 0.05s
```

The six checks cover:

- Editor / Stats tab integration and Lab watchdog wiring.
- Reward tracking when Discord webhooks are disabled.
- Roblox-window screen offset handling for result OCR/capture.
- Conservative `SpawnTower(X,Y,...)` rewrites across bundled official strategies.
- Preservation of 1.3.3 actions such as `ChangeTargets()` and `ToggleAutoskip()` plus unknown future non-placement actions.
- Marker reuse/cleanup safety and coordinate normalization for the inherited GDI+ image-search fallback.

## Windows test package

```text
ed65aeb08162d0c96e3809c63f1855ea77b074d98f6f3c1951345a1b8ba24a12  Ultimate_Macro_Strategy_Lab_0.1.zip
```

The package contains the official 1.3.3 runtime/resources plus the integrated Lab entry point, result watchdog, editor/reward modules and reward templates.

## Key integrated source hashes

```text
1346988914c21ae405bca87a8c7fc52f68ed5546b911235d708d84da3e2d2fae  Main_Lab.ahk
86fa0a41fbb01155dd7fd85350d244f9289ed22413b792b449255b1e84cd3b43  submacros/watchdog_lab.ahk
036b99310857fe3f3df56791bf6143bb891d01dc8e005f37a688059b999c73dd  lib/StrategyLab/RewardTrackerCore.ahk
20618a93d16f6ac8f99d4dc5a4a09e4b30c7cf40dd63ef62a218c01a9441cc26  lib/StrategyLab/RewardTrackerTab.ahk
1a0547f0d0d4b14ddf31cd83ca5135b99ec58028dcc12bf05e7d2dd75c3e97cc  lib/StrategyLab/StrategyEditorCore.ahk
40ff142d2738924c22bebc27be91901a323b6c7654dc5260b8b543b592a148df  lib/StrategyLab/StrategyEditorTab.ahk
3d07aef80ea605b3b7daea61cc13ba6afd686a4650cdd674b9ba4fa0130c2844  tests/test_lab_preview.py
```

## Scope of Preview 0.1

This preview deliberately focuses on the first live-testable slice:

- Visual strategy editing by dragging recorded placements.
- Undo/Redo, layers, screenshot/current-Roblox capture, Save Copy and overwrite-with-backup.
- Persistent result/reward analytics.
- Coins/Gems/XP through the official result OCR.
- Conservative item-card recognition plus evidence capture for future calibration.
- Result capture robustness when Roblox is not positioned at desktop `(0,0)`.

Additional Kronox-derived ideas remain selective future ports. The fork's updater and wholesale `Main.ahk` are not imported, and no new polling is inserted into timing-sensitive `PlayStrategy()` execution.

## Runtime acceptance note

The build was assembled and statically/integration tested in a non-Windows environment. The bundled Windows AutoHotkey executable cannot be launched there, so the first Windows GUI/game run is the remaining acceptance step before this preview should be treated as stable.
