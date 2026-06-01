# Advanced Laser Chess — LSL Setup

## Build structure

One linked object, root prim = game board face:

```
Root prim          ← game_controller.lsl
Child prims ×165   ← piece.lsl  (one per board cell)
Any child prim     ← ai_controller.lsl  (one copy anywhere in linkset)
1 child prim        ← laser_fx.lsl  (optional, named "fxbeam" — beam ribbon FX)
```

## Laser beam FX (optional)

`laser_fx.lsl` adds a glowing particle ribbon that traces the beam's real path on
each shot, on top of the per-cell flash that `piece.lsl` already does. Put it in one
dedicated child prim — keep that prim small; it auto-names itself `fxbeam` and hides
its own faces so only the particles show. It caches every `cell_X_Y` position at
start-up, so add/position it **after** the board cells are laid out (it also rescans
on `CHANGED_LINK`). Delete the prim or the script to disable the ribbon; the game and
the cell-flash keep working.

## Naming child prims

Each of the 165 cell prims **must** be named `cell_X_Y` (e.g. `cell_0_0`, `cell_7_5`).
X = 0–14 (west→east), Y = 0–10 (north→south). Every cell needs `piece.lsl` even if it
starts empty — empty cells handle highlighting and destination clicks.

Two builder scripts automate the tedious part. Their file headers carry full
step-by-step usage; in short:

**Workflow A — rezzer (recommended, fully automated)**
1. Make one flat box prim named `lc_cell`; put `piece.lsl` + `builder_cell_onrez.lsl`
   inside it.
2. Make a second prim (the rezzer); put `builder_rezzer.lsl` + the `lc_cell` object
   inside it; position it at the board's northwest corner (keep the whole board in-region).
3. Touch the rezzer → it rezzes 165 cells, and each cell **self-positions and self-names**
   `cell_X_Y` via `llSetRegionPos` (needed because `llRezObject` can't reach the far side).
4. Select all 165 + the board root (root last) and **link** — the cells are already named
   and placed, so **do not run `builder_layout`**. Reset Scripts, then add `game_controller.lsl`.

**Workflow B — manual layout (no rezzer)**
1. Duplicate one flat prim to 165, link them all under the board root.
2. Drop `builder_layout.lsl` into the root prim.
3. Touch the root → it names and positions every child cell **by link order**.
4. Remove `builder_layout.lsl`; drop in `game_controller.lsl`.

> ⚠️ `builder_layout.lsl` assigns names/positions by **link number**, so it must be the
> *only* thing naming the cells. Never run it after the rezzer (Workflow A) — it will
> overwrite the rezzer's correct `cell_X_Y` names with link-order ones and scramble the board.

`CELL_SIZE` defaults to `1.0`m (a 15×11m board) — keep it identical across
`builder_rezzer.lsl`, `builder_cell_onrez.lsl`, and `builder_layout.lsl` if you change it.

## Touch UV mapping

The root prim's flat face (the board) must be oriented so that UV (0,0) = northwest corner
and UV (1,1) = southeast corner.  Standard SL prim face mapping works if the board prim
is a flat box lying horizontally and you use the top face.

## Piece colours

Edit `piece.lsl` constants `COLOR_RED` / `COLOR_GREEN` to match your build palette.
These tint the piece textures per owner.

## Piece textures

Pieces are drawn by texturing the cell prim (sprite by type, tinted by owner, rotated
for facing). Until you supply textures, pieces show as **solid tinted tiles** with text
labels — the game is fully playable like that.

To use the sprites in `textures/` (see `textures/README.md`):

1. Upload the twelve `textures/tex_*.png` in-world (L$10 each).
2. In **`piece.lsl`**, paste each texture's UUID into the **`TEX`** list — entries
   **1–12**, in the order shown (King, Laser, Stunner, One-Way, Triangular, Bomb,
   Hypergon, Splitter, Partial-Oct, Full-Oct, Hole, Hyper-Hole). Leave entry 0 (empty)
   as the blank UUID.
3. Put the updated `piece.lsl` in your `lc_cell` template (or drop it into all cells via
   "Edit Linked" / select-all) and **Reset Scripts**.

> The `TEX` table lives in `piece.lsl` (not the controller) on purpose: the controller is
> near the 64 KB script-memory limit, and the cell scripts have the spare room.

Notes:
- The sprites are **white on transparent**, so the owner tint shows the piece and the
  background is see-through (the icon "floats" on the board). For solid tiles, give the
  sprites an opaque background (regenerate with `tools/gen_textures.py`).
- If a piece's **facing looks rotated the wrong way**, flip `TEX_ROT_SIGN` in `piece.lsl`
  (1.0 ↔ -1.0).

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
the laser/mirrors behave, and win conditions. Quick version: players alternate, 2
actions each turn (move / rotate / fire); reach the opponent's King with the laser to
win.
