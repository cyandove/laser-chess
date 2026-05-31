# Advanced Laser Chess — Starting Setup (read from the board image)

> Transcribed from the official starting-position diagram
> <https://www.laserchess.org/assets/old_pieces/alc1.gif> (cross-checked against the
> in-progress game image and the Amiga screenshot). **Please correct anything wrong —
> a few pieces I couldn't resolve at the image's resolution are marked `?`.**

## Orientation correction (important)

The players are on the **left and right short edges**, not top/bottom:

- **Red** = columns **0–2** (left). **Green** = columns **12–14** (right).
- Lasers fire **horizontally**, across the 15-wide board.
- Each side has **2 full ranks of 11** (back columns) + a **front rank of 5** octagons.
- Green is Red rotated **180°** (point symmetry), so confirming Red confirms both.

Our current code puts players on north/south and fires vertically — that needs to flip
to east/west.

Coordinates below: `x` = column 0–14 (west→east), `y` = row 0–10 (north→south).

## The grid (my best reading)

```
        col:  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14 
            ┌─────────────────────────────────────────────────────────────┐
     row 0  │ Oe  Tse .   .   .   .   .   .   .   .   .   .   .   T   O   │
     row 1  │ Te  Tn  .   .   .   .   .   #   .   .   .   .   .   T   T   │
     row 2  │ Bo  Oe  .   .   .   .   .   .   .   .   .   .   .   O   B   │
     row 3  │ Sw  H   me  .   .   .   .   #   .   .   .   .   m   H   S   │   ← see note on col 2/12
     row 4  │ Le  Pw  me  .   .   .   .   .   .   .   .   .   m   P   L   │
     row 5  │ K   Sw  M   .   .   .   .   *   .   .   .   .   M   S   K   │
     row 6  │ Le  Pw  me  .   .   .   .   .   .   .   .   .   m   P   L   │
     row 7  │ Sw  H   me  .   .   .   .   #   .   .   .   .   m   H   S   │
     row 8  │ Bo  Oe  .   .   .   .   .   .   .   .   .   .   .   O   B   │
     row 9  │ Te  Ts  .   .   .   .   .   #   .   .   .   .   .   T   T   │
     row 10 │ Oe  Tne .   .   .   .   .   .   .   .   .   .   .   T   O   │
            └─────────────────────────────────────────────────────────────┘
```

### Legend

| Symbol | Piece | Confidence |
|--------|-------|------------|
| `K` | King (diamond) | high |
| `L` | Laser — **beam weapon**, funnel aimed east |
   Le   Laser, with the beam weapon pointing east
| `O` | One-Way Mirror (rectangle + pass-through arrow) | high |
   Oe   One-Way Mirror with mirrored face facing east
| `T` | Triangular Mirror | high |
   Te   Triangular Mirror, with the mirrored (hypotenuse) side facing east
| `t` | Triangular Mirror, small/rotated variant | med |
| `P` | Beam Splitter (flat triangle) | med |
   Pw   Beam Splitter, with pointed splitter end pointing west (a beam travelling west to east would be split to the North and South)
| `B` | Bomb (diamond-in-square) | high |
   Bo   Bomb (Orthogonal, not Diagonal)
| `H` | Hypergon (spoked wheel) | high |
| `me`| Octagon (Partially Mirrored, Mirrored on ne, e, and se)
   M    Octagon (Fully Mirrored)
| `S` | Stunner **Unresolved "plus/cross" shape** — couldn't match to a legend icon | **low** |
   Sw   Stunner, with the beam weapon pointing west
| `#` | Hole | med (position) |
| `*` | Hyper Hole (board centre) | high |
| `.` | empty | — |
