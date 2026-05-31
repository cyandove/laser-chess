# Plan: Texture the existing cell prims to show pieces

## Context

Each of the 165 board cells is a child prim running `piece.lsl`; a "piece" is currently drawn
as floating **text + flat color + glow** (`piece.lsl` `updateVisuals`). The controller owns the
board model and broadcasts each square's value (`pushCell` → `LM_CELL_UPDATE` → cells filter by
name and render themselves).

Goal: make pieces look like pieces by putting a **texture (sprite) on the existing cell prim**
for its piece type, rotated to show the 8-way facing and tinted by owner — **no new prims, no
slim rebuild**. This is the minimal-change visual upgrade: it touches only the render layer; the
board rules engine and interaction are untouched.

## Approach

For an occupied cell, set the cell prim's face to the piece's sprite with a texture **rotation**
encoding facing and a **color tint** encoding owner. SL's `PRIM_TEXTURE` rule carries the
texture *and* its rotation in one call:
`[PRIM_TEXTURE, face, texUUID, <1,1,0> repeats, <0,0,0> offsets, rotation_radians]`. So a single
sprite per type covers all 8 facings via `rotation = orient * PI/4` (1×1 square tiles rotate
cleanly around center). Owner is `PRIM_COLOR` tint; stun stays a text label.

### Single source of texture UUIDs (recommended)

Keep the **texture table in the root** (`game_controller.lsl`) and **append the sprite UUID to
the existing broadcast**, so UUIDs are edited in exactly one place rather than re-deployed to
165 cells:

- Add `list TEX` indexed by piece type (12 entries; `""`/transparent for empty/holes as desired).
- `pushCell` sends `"x,y,cell,texUUID"` (UUID for that cell's type; empty cells send the empty
  sentinel). Reuse the existing `pushCell`/`broadcastBoard` plumbing (`game_controller.lsl:122`,
  `:135`) — only the appended field is new.
- The cell still decodes `type/owner/orient/stun` from the cell value it already receives.

*(Alternative considered: hardcode the `TEX` list inside `piece.lsl` and deploy via the rezzer's
`lc_cell` template. Simpler controller, but changing art means re-dropping the script into all
165 cells. The root-table approach is preferred for iteration.)*

## Key changes by file

### `game_controller.lsl` (small)
- Add `list TEX` (texture UUIDs by type) near the top, with a clear "paste your uploaded texture
  keys here" block.
- `pushCell(x,y)`: append `TEX[cType(bGet(x,y))]` to the `LM_CELL_UPDATE` payload.
- No other logic changes.

### `piece.lsl` (small, render only)
- Parse the extra `texUUID` field in the `LM_CELL_UPDATE` handler; stash it; call `updateVisuals`.
- In `updateVisuals`, replace the flat-color body with a batched
  `llSetLinkPrimitiveParamsFast(LINK_THIS, [...])` that sets, on `ALL_SIDES`:
  - `PRIM_TEXTURE` → sprite, `<1,1,0>`, `<0,0,0>`, `rotation = cOrient(cell)*PI/4` (with a tunable
    sign/offset constant so "north art" lines up with orient 0);
  - `PRIM_COLOR` → owner tint (`COLOR_RED`/`COLOR_GREEN`/`COLOR_NEUTRAL`) + alpha;
  - `PRIM_GLOW` → keep the existing highlight glow;
  - `PRIM_TEXT` → keep the supplemental label (type/facing/`~STUN~`) via existing
    `pieceLabel`/`dirStr`.
- **Empty cells:** transparent/blank texture (SL's built-in transparent UUID) at low alpha — keeps
  the dark grid look.
- **Highlight:** unchanged logic — glow stays (it sits over the texture, so a capture target still
  shows the enemy sprite); empty highlighted squares can keep the yellow tint or a highlight glow.
- Keep the recent `setHighlight` no-op guard and single batched SLPPF call (perf).

### Textures (user-provided, one-time)
- Upload one sprite per piece type (≈10 movable + Hole + Hyper Hole). Recommended: **white/greyscale
  icons designed to be tinted** red/green by owner (1 texture per type). Paste the UUIDs into the
  `TEX` list. *(Option: upload red and green variants and index `TEX` by `type` + `owner`, setting
  tint to white — more textures, exact colors.)*
- The laserchess.org piece icons are a good visual reference for the sprites.

### Docs
- `SETUP.md`: add a short "Piece textures" section (upload sprites → paste UUIDs into `TEX`),
  and note the owner-tint vs per-owner-texture choice.
- `TESTING.md`: add a check that each piece shows the right sprite, rotates with facing, and tints
  by owner.

## Notable details / risks

- **Facing direction:** texture rotation is around the face center; tune a single `TEX_ROT_SIGN`/
  offset constant so orient N/E/S/W/diagonals read correctly (SL texture rotation is CCW-positive).
- **Which face:** using `ALL_SIDES` avoids per-shape face-index guessing; only the top is seen from
  above. (If edges look wrong, switch to the specific top face.)
- **Square tiles only:** the 1×1 cells keep the sprite undistorted under rotation; fine as built.
- **Message size:** appending a 36-char UUID to each `LM_CELL_UPDATE` is negligible.
- **Tinting colored art** muddies it — design sprites for tinting, or use per-owner textures.
- Rules engine, touch, dialog, capture, beam, AI are all **unchanged**.

## Implementation phases

1. **Render:** add `TEX` + appended UUID in `game_controller.lsl`; texture-render in `piece.lsl`
   with rotation + tint; keep labels and glow. Test with placeholder UUIDs.
2. **Tune:** dial in `TEX_ROT_SIGN`/offset so all 8 facings read right; settle owner tint vs
   per-owner textures.
3. **Docs:** `SETUP.md` + `TESTING.md` texture sections.

## Verification (in-world)

- Drop updated `game_controller.lsl` (with real `TEX` UUIDs) and `piece.lsl` into the existing
  board; Reset Scripts.
- Confirm each occupied cell shows its piece **sprite**, **rotated** to its facing, **tinted** by
  owner; empty cells stay blank; the `~STUN~`/facing label still appears.
- Rotate a piece → sprite turns 45°. Move/capture → sprite moves/clears. Fire → beam unaffected.
- Highlight a capture target → enemy sprite still visible under the glow.
- No prim-count change; no rebuild required.
