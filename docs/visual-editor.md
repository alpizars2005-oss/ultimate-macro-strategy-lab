# Visual Strategy Editor design

## Mental model

The macro's recorded `SpawnTower` coordinates are screen/client coordinates, so the editor visualizes the same coordinate plane rather than pretending to know Roblox world coordinates.

Example:

```text
SpawnTower(592, 474, 3, 1)
```

becomes a marker at `(592,474)` in a 1920x1080 reference viewport. Dragging that marker to `(620,490)` rewrites only that line to:

```text
SpawnTower(620, 490, 3, 1)
```

Dependent actions such as `UpgradeTower(1)`, abilities, targeting and sells still refer to the same tower ID and therefore do not need rewriting.

## Layers

The initial layers are based on hotbar slot because `.strat` settings already map `requiredTowers` in slot order. Example:

- All placements
- Slot 1 — Farm
- Slot 2 — DJ
- Slot 3 — Ranger

Future layers can add tower-ID groups, action type, wave/time region, and custom groups.

## Background modes

Prototype: user selects a screenshot file.

Integrated tab:

- **Live Roblox snapshot**: capture the current Roblox client with the macro's existing GDI+ helper.
- **Last recording snapshot**: optionally save a frame when recording begins.
- **Blank coordinate grid**: always available when no image exists.

The screenshot is only a visual reference. Coordinates remain the source of truth.

## Safety

- Never evaluate or execute text from a `.strat` while editing.
- Parse only supported `SpawnTower(...)` shapes for draggable placement markers.
- Preserve unknown steps byte-for-byte/line-for-line where practical.
- Overwrite only after making a backup.
- Save-copy is the default action.
- Reject files outside normal local filesystem paths when integrated into the packaged macro.
