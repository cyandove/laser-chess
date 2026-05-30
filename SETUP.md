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
X = 0–14 (west→east), Y = 0–10 (north→south).

A quick way: rez a script in a single prim to auto-name siblings, or name them manually.
Cells that have no piece at game start still need the script — they handle highlighting
and destination clicks.

## Touch UV mapping

The root prim's flat face (the board) must be oriented so that UV (0,0) = northwest corner
and UV (1,1) = southeast corner.  Standard SL prim face mapping works if the board prim
is a flat box lying horizontally and you use the top face.

## Piece colours

Edit `piece.lsl` constants `COLOR_RED` / `COLOR_BLUE` to match your build palette.

## Turning the AI on/off

From any prim or external HUD, send:
```lsl
llMessageLinked(LINK_SET, 100, "AI_ON",   NULL_KEY);   // enable AI as Blue
llMessageLinked(LINK_SET, 100, "AI_OFF",  NULL_KEY);   // 2-player mode
llMessageLinked(LINK_SET, 100, "AI_BLUE", NULL_KEY);   // AI plays Blue (default)
llMessageLinked(LINK_SET, 100, "AI_RED",  NULL_KEY);   // AI plays Red
llMessageLinked(LINK_SET, 100, "RESET",   NULL_KEY);   // restart game
```

## Swapping the AI

Remove `ai_controller.lsl` from its prim and drop in a replacement script that:
1. Listens for `link_message` with `num == 20` (LM_AI_REQUEST).
2. Parses: `"boardCSV|player|actionsLeft"`.
3. Responds with `llMessageLinked(LINK_ROOT, 21, moveStr, NULL_KEY)`.

Move string format:
- `"FIRE"`
- `"MOVE:fx,fy,tx,ty"`
- `"ROTATE_CW:x,y"`
- `"ROTATE_CCW:x,y"`

## Board encoding

Cell integer = `type + owner*10 + orientation*100`

| Type | Value | Description |
|------|-------|-------------|
| Empty | 0 | — |
| Laser | 1 | Laser cannon |
| Deflector | 2 | Single 45° mirror |
| Defender | 3 | Armoured mirror piece |
| Switch | 4 | Double mirror |
| King | 5 | Win target |
| Splitter | 6 | Splits beam 90° |
| Teleporter | 7 | Centre displacement device |

Owner: 0 = Red, 1 = Blue  
Orientation: 0=N 1=E 2=S 3=W (direction the active face points)

## Gameplay

- Players alternate; each gets **2 actions** per turn.
- Touch any of your pieces → dialog appears: Move / Rotate CW / Rotate CCW / Fire / Cancel.
- **Move**: touch the highlighted destination cell.
- **Fire**: traces the laser; pieces hit on non-reflective sides are removed.
- If the laser reaches the opponent's King, that player wins.
- Touch board after game over to restart.
