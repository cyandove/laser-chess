# Plan: Scriptless piece prims (slim rebuild)

## Context

Today the game has **no piece prims**. Each of the 165 board cells is a child prim running
`piece.lsl`, and a "piece" is just that cell rendering itself as floating **text + color +
glow** (`piece.lsl` `updateVisuals`). The controller broadcasts cell values
(`pushCell` → `LM_CELL_UPDATE`) and each cell filters/renders its own square.

The user wants the pieces to be **real prims** — pre-built art, **scriptless**, and **part of
the linkset** so there's nothing extra to rez or script at setup. SL caps a linkset at 256
prims, and 165 cells + a piece-per-cell would blow past that, so the chosen approach is a
**slim rebuild**: drop the 165 cell prims entirely, drive everything from the root, and show
pieces with a small pool of scriptless, pre-built prims. Outcome: far fewer prims, an easier
build, and pieces that look like pieces (with text labels kept as a readability aid).

## Target architecture

Linkset becomes:

```
root  (board base, flat)        ← game_controller.lsl   (all logic + rendering)
piece prims  (~59, scriptless)  ← pre-built art, pooled by type/owner
highlight prims (~16, scriptless) ← move-destination markers
laser_fx prim (optional)        ← laser_fx.lsl (beam ribbon)
ai_controller prim (optional)   ← ai_controller.lsl (unchanged)
```

Prim budget: ~78 total (was ~168). Comfortable under 256.

### Piece-prim pooling (no per-entity identity needed)

Pieces never change type during play and the board only loses pieces, so identical pieces are
interchangeable. The user pre-builds **one art prim per (type, owner)** facing a canonical
**north**, names it, and duplicates it to the max simultaneous count:

| Per side | K | Laser | Stun | 1Way | Tri | Bomb | Hypr | Split | pOct | OCT |
|----------|---|-------|------|------|-----|------|------|-------|------|-----|
| count    | 1 | 2     | 3    | 4    | 6   | 2    | 2    | 2     | 4    | 1   |

= 27/side ×2 = 54, plus 5 neutral board features (4 Holes + 1 Hyper Hole) = **59 piece prims**.
Plus ~16 highlight prims named `hl`.

- **Naming:** piece prims `pc_<owner>_<type>` (owner 1/2, 0 for neutral features; type per
  `ALC_DESIGN.md`, e.g. `pc_1_5` = Red Triangular Mirror). Same-name prims form a pool.
  Highlight prims all named `hl`. Positions at build time don't matter — the controller
  arranges everything.

## Key changes by file

### `game_controller.lsl` (major)
Absorbs all rendering/interaction that `piece.lsl` did. New/changed pieces:

- **`scanPools()`** (run in `state_entry`, and on `changed(CHANGED_LINK)`): walk child links,
  group by name into pools — `gPoolKey[]` (e.g. `"1_5"`) ↔ parallel lists of link numbers,
  and a separate `gHLLinks[]` for `hl`. Reuses the name-scan pattern from `layoutCells`
  (`game_controller.lsl:146`).
- **`renderPieces()`** replaces `broadcastBoard`/`pushCell`: for each occupied cell, take a
  free prim from that `owner_type` pool and set, in one `llSetLinkPrimitiveParamsFast`:
  `PRIM_POS_LOCAL` (grid slot, same math as `layoutCells`), `PRIM_ROT_LOCAL`
  (Z-rotation = `orient*45°`), `PRIM_TEXT` (label `"TRI\nSE"`, `"~STUN~"` when stunned —
  reuse `pieceLabel`/`dirStr` from `piece.lsl`), and `PRIM_COLOR` alpha 1. Hide leftover pool
  prims (alpha 0, text ""). Build the **`gPrimCell`** reverse map (link → cell idx) here for
  touch.
- **Highlights:** `showDestinations` positions `hl` prims at legal destinations (alpha/glow
  on), recording **`gHLCell`** (hl link → cell). `clearHL` hides them. Replaces the
  `LM_HIGHLIGHT`/`LM_CLEAR_HL` broadcasts.
- **Touch unification** (`touch_start`): read `llDetectedLinkNumber(0)`.
  - touched a piece prim (in `gPrimCell`) → that cell;
  - touched an `hl` prim (in `gHLCell`) → that cell;
  - else (board base / root) → existing UV map (`game_controller.lsl` `touch_start`,
    `st.x*BOARD_W`, `(1-st.y)*BOARD_H`).
  Then call the existing `handleTouch(x,y)` unchanged.
- **Dialog moves to root:** port `showActionDialog` + the dialog `listen` from `piece.lsl`
  into the root (it already has the toucher via `llDetectedKey(0)`), feeding the existing
  `handleAction`.
- **Remove** `pushCell`, `broadcastBoard`, `hlCell`, `clearHL` broadcasts and the
  `LM_CELL_UPDATE/HIGHLIGHT/CLEAR_HL` senders; replace their call sites (e.g. in `spendActions`,
  `doMove`, `doRotate`, `thawStunned`, `displacePiece`, `detonateBomb`, `applyHit`,
  `initBoard` flow) with `renderPieces()` (or a lighter "re-render changed cells" if perf
  needs it; full re-render of ≤59 prims per action is the simple default).
- The board model (`gBoard`, all Phase 1–4 logic) is **unchanged** — only the
  rendering/IO layer changes.

### `piece.lsl` — **deleted** (logic absorbed into root).

### `laser_fx.lsl` (update)
It currently caches positions by scanning `cell_X_Y` prims, which no longer exist. Change
`buildCellCache`/`measureSpacing` to **compute** cell world positions from board geometry
(root pos/rot + the `layoutCells` formula) instead of scanning cell prims. Beam ribbon logic
is otherwise unchanged. (Per-cell orange "flash" goes away with the cells; the ribbon remains
the beam visual, optionally plus a brief tint on hit piece prims.)

### Build helpers (replace)
`builder_rezzer.lsl` / `builder_cell_onrez.lsl` / `builder_layout.lsl` (cell builders) are
**obsolete**. New flow needs no rezzer: the user builds the art prims, names them by type,
duplicates to count, links them under the board base, and links ~16 `hl` prims. Optionally
add a tiny **`builder_check.lsl`** that reports pool counts vs. expected (sanity check) — but
no positioning script is needed (the controller arranges on start).

### Docs
- `SETUP.md`: replace the cell-build workflow with the art-prim + pool build (naming table,
  counts, link order, drop controller). Keep the AI/config + encoding sections.
- `TESTING.md`: update build steps + checklists (touch on board vs. piece; visible rotation).
- `ALC_DESIGN.md`: update the link-message/rendering section (cells removed; pools added).
- `INSTRUCTIONS.md`: player-facing controls are unchanged (touch a piece → dialog).

## Notable details / risks

- **Touch on the board face** must map UV→cell, so the board base's top face has to span the
  play area with standard 0–1 UV. A frame/border around it would skew the mapping — keep the
  touchable face = the grid, or inset accordingly.
- **Rotation:** pieces are built facing north; controller spins them about the board normal
  (local Z) by `orient*45°`. Symmetric pieces (King/Hypergon/Full Octagon) rotate harmlessly.
- **Scriptless prims can't set their own text** — the root sets `PRIM_TEXT` on each piece prim
  via SLPPF (that's why labels stay a root responsibility).
- **Full re-render per action** (≤59 SLPPF calls) is simplest; if it feels heavy, switch to
  re-rendering only changed cells (the move/rotate paths already know which cells changed).
- This is a **substantial refactor** of the root script and removes `piece.lsl`; the board
  rules engine itself is untouched, which contains the risk.

## Implementation phases

1. **Pools + render (alongside cells, de-risk):** add `scanPools` + `renderPieces` driving the
   piece-prim pool, *without* removing cells yet; verify pieces appear/move/rotate correctly.
2. **Move interaction to root:** port dialog + highlight (hl pool) + touch unification into the
   root; verify select/move/rotate/fire via piece and board touches.
3. **Remove cells:** delete `piece.lsl`, drop the cell prims/`LM_CELL_*` code; switch beam FX
   (`laser_fx`) to geometry-computed positions.
4. **Build helpers + docs:** retire the cell builders, add the build/naming guide, update
   `SETUP.md`/`TESTING.md`/`ALC_DESIGN.md`.

## Verification (in-world)

- Build a small test set (board base + a handful of named art prims of each type + a few `hl`
  prims), link, drop `game_controller.lsl`, Reset Scripts.
- Confirm `renderPieces` places each piece at the correct cell, rotated to its facing, with the
  right label; unused pool prims hidden.
- Touch a **piece prim** → dialog; touch an **empty board square** → (nothing / deselect);
  Move → `hl` markers appear → click one → piece prim relocates. Rotate → prim visibly turns
  45°. Capture → enemy prim disappears, yours takes the square.
- Fire → `laser_fx` ribbon traces the beam; hit pieces vanish/stun-label.
- Hyper Hole displacement relocates a piece prim; stun shows `~STUN~`; `AI_ON` plays Green.
- Check linkset prim count stays well under 256.
