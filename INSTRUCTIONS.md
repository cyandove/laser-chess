# Advanced Laser Chess — How to Play

A two-player game of mirrors and light, after *Advanced Laser Chess* (Amiga, 1989).
You and your opponent take turns nudging, rotating, and firing — the goal is to bounce a
laser through the board until it destroys the enemy **King**.

This describes how **this LSL implementation** behaves.

---

## The board

- **15 × 11** squares. **Red** starts on the **west** side (columns 0–2), **Green** on the
  **east** (columns 12–14). Red moves first.
- Each side has 27 pieces: two full back ranks plus a front rank of five octagons.
- The centre column has four **Holes** and, at the very centre, one **Hyper Hole**.
- Coordinates here are `(x,y)` with x = 0–14 west→east, y = 0–10 north→south.

Every piece **faces** one of **8 directions** (N, NE, E, SE, S, SW, W, NW), shown after its
label (e.g. `TRI\nSE`). Facing decides how mirrors bend the beam and which side is exposed.

---

## A turn

You get **3 actions** per turn. An action is one of:

| Action | Cost | What it does |
|--------|------|--------------|
| **Move** (orthogonal) | 1 | Slide a piece one square N/E/S/W. |
| **Move** (diagonal) | 2 | Slide a piece one square diagonally (needs 2 actions). |
| **Rotate** (CW / CCW) | 1 | Turn a piece 45°. |
| **Fire** | 1 | A Laser or Stunner shoots; resolves instantly. |

Rules of thumb:
- **Capture by stomping:** a **King** or either **Octagon** may move onto an enemy piece to
  destroy it — **once per turn** each.
- A **Laser/Stunner** may fire **once per turn** each (you have several, so you can fire more
  than one weapon in a turn).
- **Rotation is refundable:** rotating a piece back to the orientation it had at the start of
  your turn refunds the actions you spent rotating it.

### Controls in-world

Touch one of **your** pieces → a dialog appears: **Move / Rotate CW / Rotate CCW /
[Fire] / Cancel**. *Move* glows the legal destinations (an occupied capture target keeps the
enemy piece visible underneath); touch one to go there. After the game ends, touch the board
to restart. A **stunned** piece can't be selected until it recovers.

---

## Firing

A beam leaves the weapon in the direction it faces and travels in a straight line —
**in any of the 8 directions** — until something happens to it:

- **Empty square** → passes through.
- **Mirror** → bends (see each piece). Both players' mirrors are fair game for your shot.
- **Splitter vertex** → forks into two beams.
- **Board edge / Hole / Hyper Hole** → absorbed (beam ends).
- **An exposed (non-mirror) face** → that piece is **destroyed** (Laser) or **stunned**
  (Stunner), and the beam stops.
- **A King** → Laser: that King's owner **loses**. Stunner: the King is merely stunned.

> ⚠️ **Friendly fire is real**, and there's no immunity for the piece that fired. A beam that
> bounces back can destroy/stun your own pieces — and routing it into your **own King** loses
> the game. Trace the whole path before you shoot.

---

## The pieces

Orientation matters in **8 directions**.

### ♦ King — `KING`
Protect it. If **either** King is destroyed (beam, capture, or bomb blast), that owner loses.
The King can **capture by stomping** (once per turn). It has no mirror — a beam from any side
destroys it.

### ▼ Laser — `LASR`
Your main weapon. Rotate to aim, then **Fire**. Has no mirror; a beam striking it destroys it.
Fires once per turn.

### ♣ Stunner — `STUN`
Fires a **non-destructive** beam that **stuns** an exposed piece instead of destroying it. A
stunned piece can't act; each turn it has a fixed chance to recover. The Stunner itself is
shielded over a 135° arc opposite its firing direction. Fires once per turn.

### ▮ One-Way Mirror — `1WAY`
A beam travelling **with** its arrow passes straight through; a beam **against** it is
reflected; a beam hitting it **perpendicular** destroys it.

### ◣ Triangular Mirror — `TRI`
A single mirror with an exposed back.
- Facing a **cardinal** direction → flat mirror (reflects a head-on beam 180°).
- Facing a **diagonal** direction → 45° deflector (turns the beam 90°).
A beam hitting its **back** destroys it; a beam grazing the edge passes.

### ✚ Bomb — `BOMB` (`+` orthogonal / `X` diagonal)
A beam striking it **along an arm** is a **center hit**; otherwise a **side hit**. Arms point
cardinally for a `+` bomb, diagonally for an `X` bomb.
- **Center + Laser:** destroys the bomb **and all 8 surrounding pieces** (a neighbouring King
  dies → that owner loses).
- **Center + Stunner:** stuns all 8 neighbours.
- **Side hit:** only the bomb is destroyed/stunned.

### ✺ Hypergon — `HYPR`
**Immune** to Laser and Stunner — a beam entering it **comes out in a random direction**.
Indestructible by fire.

### ◤ Beam Splitter — `SPLT`
A beam hitting its **vertex** head-on **splits into two** perpendicular beams. A beam into its
**back** destroys it. A beam that isn't a head-on vertex hit (including any diagonal) **misses**
and passes through.

### ⬡ Fully-Mirrored Octagon — `OCT`
Eight mirrored faces: reflects any beam **180°** straight back. **Indestructible** by fire. Can
**capture by stomping** (once per turn).

### ⬢ Partially-Mirrored Octagon — `oct`
A 135° mirrored shield over three of its eight faces. A beam striking the **shielded** side
reflects 180°; a beam on an **exposed** face destroys it. Can **capture by stomping**.

### ✱ Hyper Hole — `HOLE *`
Board feature at the centre. Absorbs beams. A piece that **moves onto it is displaced** to a
random empty square with a random orientation.

### ✖ Hole — `HOLE`
Board feature. **Impassable** (you can't move onto it) and absorbs beams.

---

## Winning

Destroy the enemy **King** — by laser beam, by stomping it with your King/Octagon, or by a bomb
blast. Because of friendly fire you can also *lose* on your own turn by hitting your own King.
When a King falls the game announces the winner and freezes; **touch the board to restart.**

---

## Strategy notes

- **Think in paths, not squares.** One 45° rotation can swing your beam across the board.
- **Mirrors are shared.** Every mirror, splitter, and octagon bends *both* players' beams.
- **Triangular mirrors and the partial octagon are directional** — hit them on the exposed side
  to destroy them; keep your own protected face toward the threat.
- **Stunners buy tempo** — freeze an enemy Laser before it can fire.
- **Bombs are area threats** — a center hit clears a whole neighbourhood (including, sometimes,
  a King). Keep your King away from your own bombs.
- **Mind the centre** — the Hyper Hole scatters anything that steps on it.

---

## Playing against the AI

An optional AI opponent ships in a separate, swappable script (`ai_controller.lsl`), playing
**Green** by default. Toggle it via the config messages in [SETUP.md](SETUP.md). The bundled AI
is a greedy baseline — it takes a winning shot when one exists, otherwise the best
destroying/stunning shot, a capture, an advance toward your King, or a rotation. It's designed
to be replaced by a stronger AI that speaks the same one-action-per-request protocol.
