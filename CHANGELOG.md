# Changelog

All notable changes to the Advanced Laser Chess LSL build, newest first.
Reconstructed from git history; versions track the `VERSION` file.
(Versions 0.0.1, 0.0.6, and 0.0.8 were never tagged — numbering skips them.)

## 0.0.18 — 2026-06-05
- Offloaded laser/beam **tracing** out of `game_controller.lsl` into the helper
  script to fix a stack-heap collision after Start. Renamed `board_init.lsl` →
  **`lc_logic.lsl`**, which now does both board-building and beam-tracing.
- `doFire()` is async: sends `LM_TRACE`, plays back the `LM_TRACE_RESULT`.
- Deploy: 3rd root script is now `lc_logic.lsl` (remove `board_init.lsl`).

## 0.0.17 — 2026-06-05
- Added **`board_init.lsl`** (3rd root script) to build the starting position in
  its own memory and stream it to the controller as one CSV — fixes the
  controller stack-heap collision when clicking **Start** (the 165-cell board
  build was churning the controller's memory).

## 0.0.16 — 2026-06-05
- Renderer seats tiles a small gap above the **measured** top of the root prim,
  so the root sits slightly under the board and no longer catches clicks meant
  for the cells (works for any root thickness).

## 0.0.15 — 2026-06-05
- Fixed a controller stack-heap collision on placement: moved all setup/confirm
  **rendering** (labels, colours, the board clear) into `board_renderer.lsl`.
  The controller now only sends settings (`LM_SETUP` / `LM_CONFIRM`).

## 0.0.14 — 2026-06-05
- Fixed LSL syntax: read `llGetScale()` into a variable before `.x` (no member
  access on a function return).

## 0.0.13 — 2026-06-05
- **Tile-measured board sizing:** the board derives its tile unit from the root
  prim's width and scales the whole grid (spacing, tiles, pieces, Z offsets) to
  it, re-laying-out on resize. Resize the board by resizing the root prim.

## 0.0.12 — 2026-06-05
- **Reset** control (`ctl_*_reset` prim) with a tile-based confirm prompt that
  returns to the setup screen.

## 0.0.11 — 2026-06-05
- **Menu-free play:** click a piece to select (move targets highlight), click a
  highlighted square to move, click another own piece to reselect; click the
  selected piece by zone to rotate (left/right) or fire (front). Removed the
  pop-up action dialog.
- **Pre-game setup screen** drawn on the tiles (row y=1, anchored on the north
  hole): toggle Pieces 3D/Flat, AI Off/On, AI Red/Green, and Start.
- Global **3D / Flat** render toggle.

## 0.0.10 — 2026-06-05
- **Piece-based side controls:** mirrored `ctl_red_*` / `ctl_green_*` prims
  (↺ ↻ 🔥) that rotate/fire the selected piece.

## 0.0.9 — 2026-06-05
- **Single root-side renderer:** replaced the 165 per-cell `piece.lsl` instances
  with one `board_renderer.lsl` in the root (cells hold no scripts; ~167 scripts
  → a handful). Renderer requests the board on start-up so it always paints.
- Added the `updated-ux` design plan.

## 0.0.7 — 2026-06-04
- Sculptie draft 2: all 10 piece sculpt maps wired up; per-type stitching
  (Sphere for the Hypergon, Cylinder for the rest); Bomb rotates 45° for its
  diagonal config; King-upright and tile-seating fixes; inverted-root-Z fixes.

## 0.0.5 — 2026-06-03
- **3D sculptie pieces:** each cell morphs between a flat tile (empty) and a
  sculptie (occupied), tinted by owner and rotated to face. King and
  Full-Octagon maps; mix with flat textures per type.

## 0.0.4 — 2026-06-01
- **Piece textures:** pieces drawn as sprites on the cell's top face, tinted by
  owner and rotated for facing, with a dependency-free PNG generator and a
  12-sprite set. Moved the `TEX` table into the cell script to dodge a
  controller memory collision.

## 0.0.3 — 2026-06-01
- **Watchable laser fire:** the shot animates cell-by-cell (`GS_FIRING` + the
  beam message), with the hit deferred and emphasized when the beam lands.
- `laser_fx.lsl` particle-ribbon emitter fixes (`PRIM_POS_LOCAL`).

## 0.0.2 — 2026-05-31
- First versioned release of the Advanced Laser Chess clone:
  - 15×11 board, 12 piece types, 8 orientations, 3 actions/turn; orthogonal move
    (diagonal costs 2), 45° rotation with refund-on-return, capture-by-stomp.
  - 8-direction beam physics: Laser destroys, Stunner stuns; mirrors, one-ways,
    triangular deflectors, splitters, partial/full octagons, bomb blast,
    hypergon scatter, holes, and Hyper-Hole displacement.
  - Per-turn fire/capture caps; stun enforcement with chance-to-thaw.
  - Optional AI opponent (`ai_controller.lsl`) + an AI toggle button.
  - Particle-ribbon laser FX (`laser_fx.lsl`).
  - Builder scripts (rezzer + on-rez self-placement; manual layout).
  - Docs: `INSTRUCTIONS.md`, `SETUP.md`, ALC design/piece specs.
