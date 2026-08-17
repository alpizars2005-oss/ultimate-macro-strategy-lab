# Strategy Lab 0.2.0

Baseline: Darksen official Ultimate Macro 1.3.3.

## Verification

```text
python -m pytest -q
.............                                                            [100%]
13 passed
```

## Scope

- Map-specific macro-camera library in AppData.
- Optional TDS Wiki top-down references; reference-only backgrounds are never trusted for direct coordinate edits.
- Zoom 100–400%, mouse-wheel zoom, pan, Fit/Reset, and Expand/Compact.
- Base/default tower portrait cache and tower-name association from `requiredTowers`.
- Catalog-driven placement labels: unique towers omit `#1`; repeatable towers show `#N`.
- Lazy asset synchronization for the currently loaded strategy.
- Capture hides/restores the Lab safely.
- Delivery through the private SHA-256 verified stable updater.

The first live Windows AutoHotkey + Roblox run remains the acceptance test for GUI interaction, GDI+ rendering and live Wiki asset retrieval.
