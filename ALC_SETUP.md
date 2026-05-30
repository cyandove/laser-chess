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
        col: 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14
            ┌─────────────────────────────────────────────┐
     row 0  │ O  T  .  .  .  .  .  .  .  .  .  .  .  T  O │
     row 1  │ T  P  .  .  .  .  .  #  .  .  .  .  .  P  T │
     row 2  │ B  O  .  .  .  .  .  .  .  .  .  .  .  O  B │
     row 3  │ ?  H  m  .  .  .  .  .  .  .  .  m  H  ?  . │   ← see note on col 2/12
     row 4  │ L  t  m  .  .  .  .  .  .  .  .  m  t  L  . │
     row 5  │ K  ?  m  .  .  .  .  *  .  .  .  m  ?  K  . │
     row 6  │ L  t  m  .  .  .  .  .  .  .  .  m  t  L  . │
     row 7  │ ?  H  m  .  .  .  .  .  .  .  .  m  H  ?  . │
     row 8  │ B  O  .  .  .  .  .  .  .  .  .  .  .  O  B │
     row 9  │ T  P  .  .  .  .  .  #  .  .  .  .  .  P  T │
     row 10 │ O  T  .  .  .  .  .  .  .  .  .  .  .  T  O │
            └─────────────────────────────────────────────┘
```

> ⚠️ The octagon **front rank** (the 5 `m`) reads as col **2** for Red and col **12**
> for Green — i.e. the front rank is one column *inward*, with the two back ranks at
> cols 0–1 / 13–14. I've drawn Green's octagons at col 11/12 to keep the symmetry; the
> exact column pairing is one of the things to confirm.

### Legend

| Symbol | Piece | Confidence |
|--------|-------|------------|
| `K` | King (diamond) | high |
| `L` | Laser / Stunner — **beam weapon**, funnel aimed east | **med — which is which?** |
| `O` | One-Way Mirror (rectangle + pass-through arrow) | high |
| `T` | Triangular Mirror (half-cell diagonal) | high |
| `t` | Triangular Mirror, small/rotated variant | med |
| `P` | Beam Splitter (flat triangle) | med |
| `B` | Bomb (diamond-in-square) | high |
| `H` | Hypergon (spoked wheel) | high |
| `m` | Octagon (Fully **or** Partially Mirrored) | **piece type high, which-octagon unknown** |
| `?` | **Unresolved "plus/cross" shape** — couldn't match to a legend icon | **low** |
| `#` | Hole | med (position) |
| `*` | Hyper Hole (board centre) | high |
| `.` | empty | — |

## What I'm confident about

- **King** at the centre of the back rank (Red `(0,5)`).
- **One-Way Mirrors** at the four corners of each side's back block, arrows pointing
  **east** (toward the enemy) so friendly beams pass through.
- **Bombs** at `(0,2)` and `(0,8)`.
- **Hypergons** (spoked wheels) at `(1,3)` and `(1,7)`.
- **Triangular Mirrors** and **Beam Splitters** filling the back ranks.
- **Five Octagons** forming the front rank `(2,3)…(2,7)`.
- A **Hyper Hole** dead centre at `(7,5)`, with **Holes** above and below it on the
  centre column.

## What I need you to confirm or correct

1. **The `?` "plus/cross" pieces** at `(0,3) (0,7) (1,5)` — these don't match any of the
   12 legend icons cleanly. Are they Stunners? A rotated Laser/Stunner? Something else?
2. **`L` beam weapons** at `(0,4)` and `(0,6)` — is it **one Laser + one Stunner**, or
   two of the same? Which row is which?
3. **The octagons** `(2,3)…(2,7)` — which are **Fully Mirrored** vs **Partially
   Mirrored**? (All five the same, or a pattern?)
4. **Holes / Hyper Hole** on the centre column — I read Holes at `(7,1)` and `(7,9)` and
   the Hyper Hole at `(7,5)`. Are there more/other holes?
5. **Front-rank column** — is the octagon rank at col **2/12** with back ranks at
   **0–1 / 13–14**, as drawn?
6. **Exact piece orientations** (each of 8 facings) — the diagram shows specific angles;
   I can transcribe per-piece facings once the types are confirmed.

Once you mark this up, I'll finalize the layout in code (with the east/west flip and
8-direction rotation).
