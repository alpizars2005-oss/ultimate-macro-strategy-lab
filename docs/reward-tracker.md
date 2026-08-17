# Reward Tracker design

## Goal

Record what a completed run actually awarded, including nonstandard rewards such as crates, ducks/event currency, consumables, and future items.

## Integration boundary

The scanner runs only after the watchdog has already proven a Triumph/result screen. It must not run inside placement/upgrades/abilities/recorded timing.

## Recognition pipeline

1. Use the existing result button/title detection as the trusted screen-state anchor.
2. Capture a bounded result/reward region.
3. Match known reward icon templates at a conservative confidence threshold.
4. Read the quantity from a small region adjacent to the matched icon using the macro's existing Windows OCR helper.
5. Require quantity sanity checks and deduplicate overlapping matches.
6. Append confirmed observations to `reward_ledger.csv` keyed by the active run ID.
7. Update session/lifetime totals.
8. If a card cannot be classified confidently, save an evidence crop and record `UNKNOWN` rather than guessing.

## Proposed storage

`%APPDATA%\\Ultimate_Macro\\reward_ledger.csv`

```text
recorded_at,run_id,map,mode,reward_key,display_name,quantity,confidence,evidence
2026-08-17 08:40:00,run-...,Simplicity,Molten,duck,Ducks,12,0.94,template
2026-08-17 08:40:00,run-...,Simplicity,Molten,crate_summer,Summer Crate,1,0.91,template
```

`%APPDATA%\\Ultimate_Macro\\reward_totals.ini`

```ini
[Lifetime]
duck=532
crate_summer=18

[Session]
duck=34
crate_summer=2
```

## Template catalog

Templates live under `Resources/RewardTracker/Templates/` and are registered in a small catalog. The framework must support adding a new icon without changing the result handler.

Suggested starter keys:

- `coins`
- `gems`
- `xp`
- `duck`
- `crate_*`
- `consumable_*`

Coin/gem/XP can continue using the macro's existing text parsing while item/card rewards use icon + quantity recognition.

## Evidence / learning mode

When enabled, the tracker saves a single bounded PNG of the result/reward area for any run containing an unknown reward. This makes it easy to add a clean template later without storing full-session screenshots.
