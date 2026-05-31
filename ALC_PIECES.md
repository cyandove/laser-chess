# Advanced Laser Chess — Piece Roster (for review)

> **Purpose:** This is a working spec for you to evaluate and correct before we
> rewrite the game logic. The current code in `master` actually implements the
> simpler **Laser Chess (1987)**, not **Advanced Laser Chess (1989)** — this
> document captures what ALC *should* be, sourced from the official rules at
> <https://www.laserchess.org/instructions_alc.html>.
>
> Please mark each row: ✅ correct / ✏️ fix / ❓ unsure, and add notes. Where the
> rules text was silent (e.g. exact starting squares), I've flagged **[NEEDS
> CONFIRMATION]** — those come from the board image / your knowledge.

---

## Core rules (corrected vs. current code)

| Rule | Current code (Laser Chess) | Advanced Laser Chess | Status |
|------|----------------------------|----------------------|--------|
| Board | 15 × 11 | 15 × 11 | ✅ same |
| Players | Red / Blue | **Red / Green** (Red moves first) | ✏️ rename Blue→Green |
| Actions per turn | 2 | **Up to 3** | ✏️ |
| Rotation | 4 directions, 90° steps | **8 directions, 45° steps** | ✏️ major |
| Movement | 1 square orthogonal | 1 square orthogonal; **diagonal = 2 actions** if path clear | ✏️ |
| Capture by moving | none | **King & both Octagons** capture by "stomping" onto a piece, once/turn | ✏️ new |
| Setup | sparse 2-row custom | **3 rows per side: 2 full rows + a front row of 5** | ✏️ **[NEEDS CONFIRMATION]** on exact squares |
| Win | laser hits a King | **King destroyed** (by beam, capture, bomb, etc.) | ✏️ broaden |
| Fire | once (laser only) | each beam-firing piece may fire **once per turn** | ✏️ |

---

## Pieces

Orientation matters in **8 directions** (N, NE, E, SE, S, SW, W, NW) for any piece
with a directional mirror/shield/arrow.

### 1. King
- **Role:** Must be protected. **If your King is destroyed, you lose.**
- **Mirrors:** None — a beam from *any* direction destroys it.
- **Special:** Can **capture** by moving onto an enemy piece (once per turn).
- _Current code:_ have a King, but it can't capture and only "loses if laser hits it."

### 2. Laser
- **Role:** Your main weapon. Rotate to aim, then **fire** the beam.
- **Mirrors:** None. **Immune to its own beam.**
- **Special:** No capture.
- _Current code:_ have it, but it's destructible by any beam (should be immune to own beam at least) and rotates only 4 ways.

### 3. Stunner
- **Role:** Fires a **non-destructive** beam that **stuns** any non-reflective
  surface it hits. A stunned piece **cannot act** until it thaws; each turn a
  stunned piece has a **fixed random chance to thaw** on its own.
- **Mirrors/shield:** **Shielded on three sides** — a **135° arc opposite the
  firing direction**.
- _Current code:_ **missing entirely.**

### 4. One-Way Mirror
- **Role:** Directional mirror. Beams travelling **with the arrow pass through**;
  beams travelling **against it are reflected back**.
- **Vulnerable:** A **perpendicular** beam **destroys** it.
- _Current code:_ **missing.** (My "Deflector" is not this.)

### 5. Bomb
- **Role:** Area weapon. A **direct centre hit destroys the bomb plus all 8
  surrounding pieces.** A **side hit destroys only the bomb.** A **stun to the
  centre stuns all 8 surrounding pieces.**
- **Configs:** has **orthogonal and diagonal** configurations (orientation matters).
- _Current code:_ **missing.**

### 6. Hypergon
- **Role:** **Immune to both Laser and Stunner** — an incoming beam **emerges in a
  random direction.**
- **Special:** **Displaces** pieces it steps on (once per turn, random direction).
- _Current code:_ **missing.** (My central "Teleporter" is roughly this idea but wrong.)

### 7. Beam Splitter
- **Role:** A beam striking the splitter **at its vertex splits into two
  perpendicular beams.**
- **Vulnerable:** Exposed **back face destroys** it.
- _Current code:_ have a "Splitter" but it does passthrough+90°CW and is
  indestructible — should be **vertex-split into two perpendicular** + **back face
  destroys it**.

### 8. Fully Mirrored Octagon
- **Role:** **Eight-sided, fully mirrored**, **indestructible by laser fire.**
- **Special:** **Captures** once per turn; can only be taken by a **King, another
  Octagon, Bomb, or Hypergon.**
- _Current code:_ my "Switch" is the nearest analogue but wrong (4-dir, no capture).

### 9. Partially Mirrored Octagon
- **Role:** Eight-sided with a **135° reflective shield arc on 3 of its 8 faces**;
  the other **5 faces are exposed.**
- **Special:** **Captures** once per turn.
- _Current code:_ my "Defender" is the nearest analogue but wrong (4-dir, simpler).

### 10. Triangular Mirror
- **Role:** One **reflective** face and one **exposed back** face.
  - At a **cardinal** orientation → acts as a **flat mirror (180° return).**
  - At a **diagonal** orientation → acts as a **45° deflector.**
- **Vulnerable:** **Back-face hit destroys** it.
- _Current code:_ my "Deflector" is the nearest analogue but only does 45° and is indestructible.

### 11. Hyper Hole
- **Role:** Board feature. **Absorbs** laser beams and **displaces pieces to
  random locations in random orientations.**
- _Current code:_ **missing.**

### 12. Hole
- **Role:** Board feature. **Impassable.** A piece that **ends its movement on it
  is removed.**
- _Current code:_ **missing.**

---

## Open questions for you

1. **Exact starting setup** — the rules text doesn't list squares. You said **3
   rows: 2 full + front row of 5**. Can you confirm *which* pieces sit where (from
   the board image), or should I infer a layout from the image for you to check?
2. **Counts** — how many of each piece per side (e.g. how many Deflectors/Triangular
   Mirrors, Octagons, Stunners)?
3. **Beam termination** — the rules page didn't state it explicitly; I'll assume a
   beam ends at the **board edge** and on **absorption** (Hole/Hyper Hole, exposed
   non-mirror faces). OK?
4. **Stun thaw chance** — is there a canonical probability, or do we pick one?
5. **Scope** — do you want the **full** roster (incl. Bomb, Hypergon, Holes,
   Stunner) in v1, or a phased build (mirrors + laser + king first, then the rest)?

Once you've marked this up, I'll rewrite `game_controller.lsl` (8-direction
rotation, 3 actions, capture, new beam interactions), update `piece.lsl`, and
rewrite `INSTRUCTIONS.md` to match.
