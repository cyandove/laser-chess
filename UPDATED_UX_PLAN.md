# Updated UX — design plan (`updated-ux` branch)

Menu-free interaction. The board's tiles and a few named control prims are the
whole interface: a pre-game setup screen on the tiles, click-to-select then
click-to-act for pieces, mirrored rotate/fire buttons per side, and a board that
scales by measuring its own tiles. The renderer stays a dumb view + input
forwarder; the controller owns all state and rules.

---

## 1. Game states

| State | Meaning |
|---|---|
| `GS_SETUP` | **New.** Pre-game menu drawn on the tiles. |
| `GS_IDLE` | Playing, nothing selected. |
| `GS_SELECTED` | A piece is selected; move targets highlighted; awaiting move / rotate / fire / reselect / deselect. |
| `GS_CONFIRM_RESET` | **New.** Modal confirm before returning to setup. |
| `GS_FIRING` | Beam animation playing; input ignored. *(unchanged)* |
| `GS_GAMEOVER` | Win shown; click to return to setup. *(unchanged)* |

`GS_AWAIT_DST` is **removed** — moving is now direct (click a highlighted
destination straight from `GS_SELECTED`).

---

## 2. Pre-game setup screen (`GS_SETUP`)

Boot → `GS_SETUP`. The board becomes a menu. Option tiles sit on **row y = 1**
(the northern hole's row), anchored on the hole at **(7,1)**:

```
 Red(0-2) │ opt1 │  ·  │ opt2 │  ·  │ HOLE │  ·  │ opt3 │  ·  │ opt4 │ Green(12-14)
            (3,1)        (5,1)       (7,1)        (9,1)        (11,1)
```

| Tile | Option | Toggles between |
|---|---|---|
| (3,1) | **Pieces** | `3D` ⇄ `Flat` |
| (5,1) | **AI** | `Off` ⇄ `On` |
| (9,1) | **AI plays** | `Red` ⇄ `Green` *(dimmed when AI Off)* |
| (11,1) | **▶ Start Game** | begins the game |

- Spaces at x = 4,6,8,10 stay blank; the Red/Green home columns frame it.
- Option tiles render as labeled, color-coded buttons (active value tinted);
  a click toggles the value and re-renders just that tile.
- Optional title banner across the top rows (hovertext or a textured tile).
- **Start** → `initBoard()`, `gState = GS_IDLE`, paint the board.

The controller owns this screen: in `GS_SETUP` it pushes those five tiles as
buttons and, on a touch, maps the clicked coordinate to a toggle or to Start.
No new renderer logic except the global render-mode flag below.

---

## 3. Global render mode (3D / Flat)

- `gFlatMode` lives in the controller; pushed to the renderer via **`LM_RENDER_MODE`** (`"FLAT"` / `"3D"`).
- Renderer: in Flat mode it always takes the textured-box path and **ignores `SCULPT[]`**; in 3D mode it uses a sculpt where one exists (today's behavior).
- The (3,1) tile toggles it; the controller flips the flag, sends `LM_RENDER_MODE`, and re-renders.

---

## 4. In-play interaction (menu-free)

Two-step everywhere: the **first** click on a piece only selects; a **second**
click acts.

- **Click own piece** (current player's) → `GS_SELECTED`; highlight legal move
  destinations (steady, no flash); show the floating-text hint on the piece.
- While `GS_SELECTED`:
  - **Click a highlighted destination** → move (direct; cost applied; capture rules as today).
  - **Click the selected piece** → resolve a click-zone and act:
    - left third → `ROTATE_CCW`
    - right third → `ROTATE_CW`
    - front (toward its facing) → `FIRE` *(laser/stunner only; otherwise no-op)*
  - **Click a different own piece** → reselect it.
  - **Click empty/non-target or off the board** → deselect (`GS_IDLE`).
  - **Click a side control** (`↺ ↻ 🔥`) → same actions on the selection.

Both input paths — click-zones and side buttons — emit the **existing**
`ROTATE_CW` / `ROTATE_CCW` / `FIRE` actions, so the controller's
`handleAction()` and the rotation cost/refund logic are unchanged.

### Click-zone math
On a touch of the selected piece, take `llDetectedTouchPos(0)`, subtract the
cell's center, rotate the offset into the board-local frame (divide by the root
rotation), and read it in the board plane:
- forward axis (toward the piece's facing) positive & dominant → **Fire**
- else sign of the left/right axis → **CCW / CW**

Works on sculpties (single face) because it uses the world hit point, not UVs.
Keep the zones coarse (thirds); an invalid/`<-1,-1,-1>` hit → no-op (fall back
to the side buttons).

### Floating-text hint
On select, the piece's hovertext shows e.g. `◀ turn · FIRE ▲ · turn ▶`
(the `FIRE ▲` segment only for a laser/stunner). Cleared on deselect.

---

## 5. Controls — named child prims

Mirrored clusters so each player reaches their own; both act on the current
selection.

| Prim name | Action |
|---|---|
| `ctl_red_ccw` / `ctl_green_ccw` | `ROTATE_CCW` on selection |
| `ctl_red_cw` / `ctl_green_cw` | `ROTATE_CW` on selection |
| `ctl_red_fire` / `ctl_green_fire` | `FIRE` selection |
| `ctl_reset` (single or mirrored) | Reset → confirm → setup |

The renderer scans these names alongside `cell_X_Y` into a **control map**; a
touch on a control forwards its action (via `LM_ACTION`, or a dedicated
`LM_CONTROL`) to the controller. Controls are inert unless something is selected
(except reset).

---

## 6. Reset + confirmation

- A `ctl_reset` click → `GS_CONFIRM_RESET`, showing a small **tile confirm**
  near the center: **Confirm** / **Cancel** (consistent with the tile UI;
  `llDialog` Yes/No is the simpler fallback if preferred).
- **Confirm** → `GS_SETUP` (chosen options preserved). **Cancel** → prior state.

---

## 7. Resizable board — measure the tile, don't hardcode

Replace the `CELL_SIZE` constant with a **measured unit**:
- On start-up and on `CHANGED_SCALE`, read a reference cell's `PRIM_SIZE.x` →
  that's the tile footprint = grid spacing.
- Express every other length as a **fraction of that unit** (they're already
  tuned per 1 m tile, so just multiply): `CELL_ZOFF`, `TILE_SIZE`,
  `SCULPT_SIZE[]`, `SCULPT_BASE_Z`.
- Recompute + relayout on `CHANGED_SCALE`, so resizing the linkset rescales the
  whole board uniformly (pieces scale with it).
- Builders keep a nominal rez spacing; the renderer owns final layout by
  measurement (the render-ready handshake already triggers a repaint).

---

## 8. Touch routing (renderer)

Renderer maps each touched link to one of: **cell `(x,y)`**, **control
`action`**, or (in setup) an **option tile** (still a cell coord). It forwards
with enough context for the controller to decide by state:

- `GS_SETUP`: option-tile coords → toggles / Start; everything else ignored.
- `GS_IDLE` / `GS_SELECTED`: cell/piece/control → select / move / act / reselect / deselect.
- `GS_CONFIRM_RESET`: only the confirm/cancel tiles.
- `GS_FIRING`: ignored.

---

## 9. Message protocol changes

- **Add** `LM_RENDER_MODE` (controller → renderer): `"FLAT"` / `"3D"`.
- **Add** a hint mechanism for the floating text (extend the cell render, or a small `LM_HINT`).
- Control-prim touches: reuse `LM_ACTION` with the resolved action, or add `LM_CONTROL`.
- **Reuse** `LM_ACTION` (`ROTATE_CW`/`ROTATE_CCW`/`FIRE`/`MOVE`) and the
  render-ready handshake unchanged.

## 10. Removed

- The per-piece action `llDialog` menu and its `listen`.
- `GS_AWAIT_DST` (moving is direct).

---

## 11. Open / assumptions (flag if you want changes)

- Option order on the row (assumed Pieces, AI, AI-side, Start — reorder freely).
- `ctl_reset` count/placement (single vs mirrored) and exact cluster positions.
- Confirm UI: tile-based (assumed) vs `llDialog`.
- Title banner: optional, not yet specced.
