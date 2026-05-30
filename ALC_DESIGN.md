# Advanced Laser Chess — Implementation Design

Working design for the ALC rewrite (branch `alc-rules`). Built in phases; see the
task list. This file is the shared reference for the cell encoding, direction math,
and link-message protocol.

## Board

- 15 wide (x: 0–14, west→east) × 11 tall (y: 0–10, north→south).
- Red = cols 0–2 (west). Green = cols 12–14 (east). Lasers fire horizontally.
- Green is the 180° rotation of Red (≡ left/right mirror here, since Red is
  vertically symmetric).
- Index: `i = y*15 + x`.

## Cell encoding (single integer)

```
cell = type + owner*100 + orient*1000 + stunned*10000 + bombDiag*100000
```

| Field | Range | Meaning |
|-------|-------|---------|
| type | 0–12 | piece type (see table) |
| owner | 0–2 | 0 none, 1 Red, 2 Green |
| orient | 0–7 | facing (see directions) |
| stunned | 0–1 | piece is stunned (skips Phase 3) |
| bombDiag | 0–1 | bomb in diagonal (1) vs orthogonal (0) config |

### Types

| # | Type | Code | Captures? | Destructible by laser? |
|---|------|------|-----------|------------------------|
| 0 | Empty | `.` | — | — |
| 1 | King | `K` | yes (stomp) | yes (any beam) |
| 2 | Laser | `L` | no | yes; immune to own beam |
| 3 | Stunner | `S` | no | yes; fires non-destructive stun |
| 4 | One-Way Mirror | `O` | no | only by perpendicular beam |
| 5 | Triangular Mirror | `T`/`t` | no | back-face hit |
| 6 | Bomb | `B` | no | yes (area effect) |
| 7 | Hypergon | `H` | no | immune (random re-emit) |
| 8 | Beam Splitter | `P` | no | back-face hit |
| 9 | Partially-Mirrored Octagon | `m` | yes (stomp) | exposed (5 of 8) faces |
| 10 | Fully-Mirrored Octagon | `M` | yes (stomp) | indestructible by laser |
| 11 | Hole | `#` | — | board feature (absorbs) |
| 12 | Hyper Hole | `*` | — | board feature (absorbs + displaces) |

## Directions (8)

Index 0–7, clockwise from north:

| idx | dir | dx | dy |
|-----|-----|----|----|
| 0 | N  |  0 | -1 |
| 1 | NE |  1 | -1 |
| 2 | E  |  1 |  0 |
| 3 | SE |  1 |  1 |
| 4 | S  |  0 |  1 |
| 5 | SW | -1 |  1 |
| 6 | W  | -1 |  0 |
| 7 | NW | -1 | -1 |

- Rotate CW = `(orient+1)%8`, CCW = `(orient+7)%8` (45° steps).
- Cardinal dirs are even (0,2,4,6); diagonals odd (1,3,5,7).
- Opposite = `(orient+4)%8`.

## Turn structure

- 3 actions per turn. An action = move 1 orthogonal square, OR move 1 diagonal
  square (costs 2 actions, path must be clear), OR rotate 45°, OR fire a beam
  weapon (once per piece per turn).
- Capture: King and both Octagons may move onto an enemy piece (once per turn each).
- Win: a player's King is destroyed (beam, capture, or bomb).

## Link-message protocol (unchanged channel numbers where possible)

| num | name | dir | payload |
|-----|------|-----|---------|
| 1 | CELL_UPDATE | →child | `"x,y,cell"` |
| 2 | HIGHLIGHT | →child | `"x,y,on"` |
| 3 | CLEAR_HL | →child | — |
| 4 | LASER_PATH | →child | `"x0,y0;x1,y1;…"` (for FX/flash) |
| 5 | GAME_OVER | →child | winner owner id |
| 6 | STATUS | →child | status text |
| 10 | PIECE_TOUCH | child→ | `"x,y"` |
| 11 | ACTION | both | action verb / `"MENU:x,y"` |
| 20 | AI_REQUEST | →ai | `"boardCSV|player|actionsLeft"` |
| 21 | AI_RESPONSE | ai→ | move encoding |
| 100 | CONFIG | → | `RESET`,`AI_ON`,`AI_OFF`,`AI_RED`,`AI_GREEN` |

Players are now **Red (1)** and **Green (2)**.
