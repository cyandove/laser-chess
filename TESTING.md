# Building & Testing — Phases 1 & 2

A step-by-step guide to build the board in Second Life and test everything that's
implemented so far. **Current scope: Phase 1 (setup, movement, rotation, capture) +
Phase 2 (beam physics).** Phase 3 mechanics (bomb blast, stun/thaw enforcement, hole
effects, per-turn caps) are **not** active yet — see "Not yet implemented" below.

---

## 0. Scripts in this branch

| Script | Goes in | Role |
|--------|---------|------|
| `game_controller.lsl` | board **root** prim | all game logic |
| `piece.lsl` | every **cell** prim (×165) | rendering, touch, dialog |
| `laser_fx.lsl` | one extra child prim (optional) | beam ribbon FX |
| `ai_controller.lsl` | — | **do NOT use yet** (still the old ruleset; rewritten in Phase 4) |
| `builder_rezzer.lsl`, `builder_cell_onrez.lsl` | build helpers | rez + self-position the 165 cells |
| `builder_layout.lsl` | (manual builds only) | **don't run with the rezzer** — it renames by link order |

> ⚠️ Leave the AI **off** (it's off by default). The current `ai_controller.lsl`
> predates the ALC rewrite and won't work — test as 2 players by clicking both
> sides yourself.

---

## 1. Build the board

The board is **15 × 11 = 165 cells**. Easiest path uses the rezzer.

### 1a. Make the cell template
1. Rez a flat box, size **1.0 × 1.0 × 0.05 m**. Name it exactly **`lc_cell`**.
2. Drop **`piece.lsl`** and **`builder_cell_onrez.lsl`** into its Contents.
3. Take it into your inventory (so it becomes an inventory object).

### 1b. Make the rezzer
1. Rez a small prim — this is the temporary rezzer (not part of the final board).
2. Drop **`builder_rezzer.lsl`** and the **`lc_cell`** object into its Contents.
3. Move the rezzer to where you want the board's **northwest corner** (cell 0,0).
   The board extends **east (+X)** and **south (−Y)** from there, so keep the whole
   15×11 m area **well inside the region** (not near an edge).
4. **Touch** it → it rezzes 165 cells *at the rezzer*, and each cell then **moves
   itself** to its slot, auto-named `cell_0_0` … `cell_14_10`.
   (Cells must self-position because `llRezObject` can't reach the far side of the
   board ~18 m away; they relocate with `llSetRegionPos`.)

### 1c. Link to a board root
The cells are **already named `cell_X_Y` and positioned** by step 1b.
**Do NOT run `builder_layout.lsl`** here — it renames cells by their (arbitrary) link
number and will scramble the board. Just link:

1. Rez a flat prim for the **board base**, positioned just under the cell grid. This
   becomes the **root**.
2. Select **all 165 cells, then the board base last**, and **Link** (Ctrl+L). The base
   must be the root (last selected). Linking does **not** move the cells, and each cell
   keeps its `cell_X_Y` name.
3. (Optional) delete the temporary rezzer prim.

> `builder_layout.lsl` is **only** for a manual build where cells have no names/positions
> (it assigns both by link order). It is **not** used with the self-positioning rezzer —
> running it after the rezzer is what scrambles the layout.

### 1d. Load the game scripts
1. Drop **`game_controller.lsl`** into the **root** prim.
2. (Optional) add one more small child prim, name it anything, drop **`laser_fx.lsl`**
   in it for the beam ribbon. Add it **after** layout so it caches cell positions
   correctly (it rescans on link changes anyway).
3. **Reset Scripts in Selection** on the whole linkset (Build ▸ Scripts ▸ Reset Scripts
   in Selection) so every `piece.lsl` re-reads its `cell_X_Y` name.
4. The root shows hovertext "Red's turn — 3 action(s) left." and the board paints the
   starting position.

`CELL_SIZE` defaults to **1.0 m** in both builder scripts — keep them equal if you change it.

---

## 2. Verify the starting position (Phase 1)

Compare against `ALC_SETUP.md`. You should see, **Red on the left (cols 0–2)** and
**Green on the right (cols 12–14)**:

- [ ] **King** (`KING`) centered in each back column — Red at (0,5), Green at (14,5).
- [ ] **Two Lasers** (`LASR E` / `LASR W`) flanking each King at rows 4 and 6.
- [ ] **Three Stunners** (`STUN`) per side — back column rows 3 & 7, middle column row 5.
- [ ] **One-Way Mirrors** (`1WAY`) at the four corners of each side's back block.
- [ ] **Bombs** (`BOMB +`) at rows 2 & 8 of the back column.
- [ ] **Hypergons** (`HYPR`) at rows 3 & 7 of the middle column.
- [ ] **Beam Splitters** (`SPLT`) at rows 4 & 6 of the middle column.
- [ ] **Front rank of 5 octagons** — four partial (`oct`) + one full (`OCT`, center) in
      col 2 (Red) / col 12 (Green), rows 3–7.
- [ ] **Triangular Mirrors** (`TRI`) filling the remaining back/middle slots.
- [ ] **Center column features**: Holes (`HOLE`) at (7,1) (7,3) (7,7) (7,9) and a
      **Hyper Hole** (`HOLE *`) at (7,5).
- [ ] Direction letters (N/E/S/W/NE/…) read correctly on each piece.

---

## 3. Test movement, rotation, capture (Phase 1)

Click any **Red** piece → a dialog appears (Move / Rot CW / Rot CCW / [Fire] / Cancel).

- [ ] **Move**: choose *Move* → legal squares highlight. Click one to move there.
- [ ] **Diagonal costs 2**: with 3 actions, diagonal targets are offered; after spending
      down to 1 action, diagonals stop being highlighted (only orthogonals remain).
- [ ] **Rotation**: *Rot CW* / *Rot CCW* turns the piece 45° (the direction label steps
      N→NE→E…). Costs 1 action.
- [ ] **3 actions/turn**: after 3 actions' worth, the turn flips to Green (hovertext
      updates). A diagonal move (2) + a rotation (1) should end the turn.
- [ ] **Capture by stomping**: move a **King** or an **Octagon** onto an *enemy*
      piece — it's removed and your piece takes the square. Try it.
- [ ] **Non-capturers can't stomp**: a Laser/Mirror/etc. is *not* offered a move onto an
      occupied square.
- [ ] **King capture wins**: stomp an enemy King with your King/Octagon → "WINS by
      capture!" and the board freezes. Touch the board to restart.
- [ ] **Turn alternation**: you control whichever side's turn it is; clicking the other
      side's pieces does nothing until their turn.

---

## 4. Test beam physics (Phase 2)

Select a **Laser** or **Stunner** and choose **Fire**. The beam path flashes (and the
ribbon draws if `laser_fx` is installed). Firing costs 1 action.

Good things to verify:

- [ ] **Straight beam** stops at the board edge.
- [ ] **Triangular Mirror** deflects: a diagonal-facing one turns the beam 90°, a
      cardinal-facing one bounces it straight back (180°).
- [ ] **Hitting a mirror's back face destroys it** (Triangular Mirror, One-Way Mirror
      perpendicular, Beam Splitter back).
- [ ] **One-Way Mirror**: beam passes through with the arrow, reflects against it.
- [ ] **Beam Splitter**: a head-on hit to the vertex makes **two** beams; a diagonal beam
      passes through (misses).
- [ ] **Octagons reflect 180°**; the **Full** octagon is indestructible, the **Partial**
      one is destroyed if the beam hits an unshielded face.
- [ ] **Hypergon**: beam emerges in a random direction (fire repeatedly — output varies).
- [ ] **Holes / Hyper Hole** absorb the beam.
- [ ] **Friendly fire**: route a beam (off a mirror) back into your own piece — it's
      destroyed. Into your own King → you lose.
- [ ] **Win**: get a Laser beam to the enemy King → "WINS!".
- [ ] **Stunner** doesn't destroy — the struck piece turns to its stunned state
      (the stun flag is set; *enforcement* that stunned pieces can't act is Phase 3).

---

## 5. Not yet implemented (don't be surprised)

These arrive in **Phase 3**:

- Bomb **blast** (center hit destroying the 8 neighbors; stun-to-center). Right now a
  beam just destroys the bomb itself.
- **Stunned pieces can still act** — the flag is set but not enforced; no auto-thaw yet.
- **Hyper Hole displacement** and **Hole removal-on-entry** — currently Holes just block
  movement and absorb beams.
- **Once-per-turn caps** on capture and on firing — currently you could capture/fire more
  than once per turn if you have the actions.

---

## 6. Troubleshooting

- **Some cells stayed stacked at the NW corner**: those cells' target was outside the
  region, so `llSetRegionPos` refused to move them. Move the rezzer further from the
  region edge (the board needs ~15 m east and ~11 m south of the corner) and re-rez.
- **Wrong piece at each square (names don't match positions)**: you ran
  `builder_layout.lsl` after the rezzer — it renamed cells by arbitrary link number.
  Recover by deleting the linkset and re-building **without** `builder_layout` (the
  rezzer already names + positions the cells). See §1c.
- **Pieces blank**: a cell prim isn't named `cell_X_Y`, or `piece.lsl` didn't re-read its
  name — Reset Scripts in Selection.
- **Nothing happens on touch**: make sure `game_controller.lsl` is in the **root** and
  every cell has `piece.lsl`.
- **Board never paints**: the controller waits 1s on start then broadcasts; if you reset
  scripts, touch the root or send the `RESET` config message
  (`llMessageLinked(LINK_SET, 100, "RESET", NULL_KEY)`).
- **Beam looks wrong at a diagonal split**: a minor known FX cosmetic — the logic is
  still correct; report what you see and I'll check it in Phase 3 review.
