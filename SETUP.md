# Advanced Laser Chess — LSL Setup

## Build structure

One linked object, root prim = game board face:

```
Root prim          ← game_controller.lsl + board_renderer.lsl
Child prims ×165   ← (no script — just named cell_X_Y; the renderer drives them)
Any child prim     ← ai_controller.lsl  (one copy anywhere in linkset)
1 child prim        ← laser_fx.lsl  (optional, named "fxbeam" — beam ribbon FX)
```

`board_renderer.lsl` replaces the old per-cell `piece.lsl`: one script in the root
maps every `cell_X_Y` child to a link number and morphs it between a flat tile and a
3D sculptie. The cell prims hold **no scripts** — so two scripts run instead of ~167,
and deploying/updating piece art means editing one script in the root, not 165 cells.
It **must** live in the root (it talks to `game_controller.lsl` via `LINK_THIS`).

## Laser beam FX (optional)

`laser_fx.lsl` adds a glowing particle ribbon that traces the beam's real path on
each shot, on top of the per-cell flash that `board_renderer.lsl` already does. Put it in one
dedicated child prim — keep that prim small; it auto-names itself `fxbeam` and hides
its own faces so only the particles show. It caches every `cell_X_Y` position at
start-up, so add/position it **after** the board cells are laid out (it also rescans
on `CHANGED_LINK`). Delete the prim or the script to disable the ribbon; the game and
the cell-flash keep working.

## Naming child prims

Each of the 165 cell prims **must** be named `cell_X_Y` (e.g. `cell_0_0`, `cell_7_5`).
X = 0–14 (west→east), Y = 0–10 (north→south). The cells need **no script** — the root's
`board_renderer.lsl` finds them by name and handles rendering, highlighting, and clicks.

Two builder scripts automate the tedious part. Their file headers carry full
step-by-step usage; in short:

**Workflow A — rezzer (recommended, fully automated)**
1. Make one flat box prim named `lc_cell`; put `builder_cell_onrez.lsl` inside it
   (no `piece.lsl` — cells carry no script anymore).
2. Make a second prim (the rezzer); put `builder_rezzer.lsl` + the `lc_cell` object
   inside it; position it at the board's northwest corner (keep the whole board in-region).
3. Touch the rezzer → it rezzes 165 cells, and each cell **self-positions and self-names**
   `cell_X_Y` via `llSetRegionPos` (needed because `llRezObject` can't reach the far side).
4. Select all 165 + the board root (root last) and **link** — the cells are already named
   and placed, so **do not run `builder_layout`**. Then drop `game_controller.lsl` and
   `board_renderer.lsl` into the root and Reset Scripts.

**Workflow B — manual layout (no rezzer)**
1. Duplicate one flat prim to 165, link them all under the board root.
2. Drop `builder_layout.lsl` into the root prim.
3. Touch the root → it names every child cell **by link order**.
4. Remove `builder_layout.lsl`; drop in `game_controller.lsl` + `board_renderer.lsl`.

(The cell *positions* are set by `board_renderer.lsl` as it renders, so the builders only
need to name the cells; exact placement is handled in-script.)

> ⚠️ `builder_layout.lsl` assigns names/positions by **link number**, so it must be the
> *only* thing naming the cells. Never run it after the rezzer (Workflow A) — it will
> overwrite the rezzer's correct `cell_X_Y` names with link-order ones and scramble the board.

**Board size is measured, not fixed.** `board_renderer.lsl` derives the tile unit from the
**root prim's width** (`gUnit = root X size / 15`) and scales the whole grid — spacing, tile
size, piece sizes, and Z offsets — to it, re-laying-out on `CHANGED_SCALE`. So **resize the
board by resizing the root prim** (the board fills its width). The builders' `CELL_SIZE` only
sets the transient rez spacing before the renderer relays everything out, so just keep it
roughly sane (`1.0`).

## Touch handling

Touches are resolved **per cell**: `board_renderer.lsl` (a root script) reads the touched
child prim's link number and maps it back to a board square via the cell's `cell_X_Y` name.
You click the cell prims directly, so **no special board-face UV mapping is needed** (the old
root-face UV requirement is gone).

## Piece colours

Edit `board_renderer.lsl` constants `COLOR_RED` / `COLOR_GREEN` to match your build palette.
These tint the piece textures per owner.

## Piece textures

Pieces are drawn by texturing the cell prim (sprite by type, tinted by owner, rotated
for facing). Until you supply textures, pieces show as **solid tinted tiles** with text
labels — the game is fully playable like that.

To use the sprites in `textures/` (see `textures/README.md`):

1. Upload the twelve `textures/tex_*.png` in-world (L$10 each).
2. In **`board_renderer.lsl`**, paste each texture's UUID into the **`TEX`** list — entries
   **1–12**, in the order shown (King, Laser, Stunner, One-Way, Triangular, Bomb,
   Hypergon, Splitter, Partial-Oct, Full-Oct, Hole, Hyper-Hole). Leave entry 0 (empty)
   as the blank UUID.
3. Re-drop `board_renderer.lsl` into the root and **Reset Scripts**.

> The `TEX`/`SCULPT` tables live in `board_renderer.lsl`, not `game_controller.lsl`: the
> controller is near the 64 KB script-memory limit, and the renderer (a separate root
> script) has the room.

Notes:
- The sprites are **white on transparent**, so the owner tint shows the piece and the
  background is see-through (the icon "floats" on the board). For solid tiles, give the
  sprites an opaque background (regenerate with `tools/gen_textures.py`).
- If a piece's **facing looks rotated the wrong way**, flip `TEX_ROT_SIGN` in
  `board_renderer.lsl` (1.0 ↔ -1.0).

## Sculptie pieces (optional 3D)

Pieces can be shown as **3D sculpties** instead of flat textures. Each cell prim morphs:
a piece with a sculpt map becomes a sculptie; empty squares (and pieces without a map yet)
stay flat tiles. So you can add 3D pieces one type at a time and mix them with textured ones.

1. Upload the maps in `sculpties/` (e.g. `king_sculptmap.png`, `foct_sculptmap.png`) with
   **"Use lossless compression"** checked.
2. In **`board_renderer.lsl`**, paste each map's UUID into the **`SCULPT`** list (same type
   indices as `TEX` — King = 1, Full-Oct = 10, …). Leave a type `""` to keep its flat texture.
3. Re-drop `board_renderer.lsl` into the root and **Reset Scripts**.

The script tints sculpties red/green by owner and **rotates the prim** to show facing.
Tuning knobs in `board_renderer.lsl`:
- `SCULPT_SIZE` — per-type prim size `<x,y,z>` (the maps fill `[-1,1]`; make tokens taller in Z).
- `SCULPT_STITCH` — per-type stitching list (Cylinder for most; Sphere for the Hypergon gem; see `sculpties/README.md`).
- `SCULPT_ROT_SIGN` — flip if a piece faces the wrong way.
- `SCULPT_BASE_Z` / `CELL_ZOFF` / `TILE_SIZE` — how tokens sit on the board vs. the flat tiles.

## Turning the AI on/off

From any prim or external HUD, send on the config channel (num 100):
```lsl
llMessageLinked(LINK_SET, 100, "AI_ON",    NULL_KEY);   // enable the AI
llMessageLinked(LINK_SET, 100, "AI_OFF",   NULL_KEY);   // 2-player mode
llMessageLinked(LINK_SET, 100, "AI_GREEN", NULL_KEY);   // AI plays Green (default)
llMessageLinked(LINK_SET, 100, "AI_RED",   NULL_KEY);   // AI plays Red
llMessageLinked(LINK_SET, 100, "RESET",    NULL_KEY);   // restart game
```

## Swapping the AI

Remove `ai_controller.lsl` from its prim and drop in a replacement that:
1. Listens for `link_message` with `num == 20` (LM_AI_REQUEST).
2. Parses `"boardCSV | player | actionsLeft | firedCSV | capturedCSV"`, where
   `firedCSV`/`capturedCSV` are board indices (`y*15+x`) of pieces that already
   fired / captured this turn.
3. Responds (once per request) with `llMessageLinked(LINK_ROOT, 21, moveStr, NULL_KEY)`.

The controller applies one action and re-requests until the AI's turn ends.
Move string format:
- `"FIRE:x,y"` — fire the weapon at (x,y)
- `"MOVE:fx,fy,tx,ty"`
- `"ROTATE_CW:x,y"` / `"ROTATE_CCW:x,y"`
- `"PASS"` — skip the rest of the turn

Players are **Red = 1**, **Green = 2**.

## Board encoding

Cell integer = `type + owner*100 + orient*1000 + stunned*10000 + bombDiag*100000`

| Type | Value | Type | Value |
|------|-------|------|-------|
| Empty | 0 | Hypergon | 7 |
| King | 1 | Beam Splitter | 8 |
| Laser | 2 | Partial-Mirrored Octagon | 9 |
| Stunner | 3 | Fully-Mirrored Octagon | 10 |
| One-Way Mirror | 4 | Hole | 11 |
| Triangular Mirror | 5 | Hyper Hole | 12 |
| Bomb | 6 | | |

Owner: 0 = none, 1 = Red, 2 = Green.
Orientation: 0–7 = N, NE, E, SE, S, SW, W, NW.
`stunned` 0/1; `bombDiag` 0 = orthogonal `+`, 1 = diagonal `X`.
See `ALC_DESIGN.md` for the full model and beam rules.

## Gameplay

See **[INSTRUCTIONS.md](INSTRUCTIONS.md)** for the rules, the full piece roster, how
the laser/mirrors behave, and win conditions. Quick version: players alternate, 3
actions each turn (move / rotate / fire); reach the opponent's King with the laser to
win.
