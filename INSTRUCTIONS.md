# Advanced Laser Chess — How to Play

A two-player game of mirrors and light, inspired by *Advanced Laser Chess*
(Amiga, 1989). You and your opponent take turns nudging, rotating, and firing —
the goal is to bounce your laser through the board until it strikes the enemy
**King**.

This document describes how **this LSL implementation** actually behaves. Where it
simplifies the original game, that's noted.

---

## The board

- **15 columns × 11 rows** (X = 0–14 west→east, Y = 0–10 north→south).
- **Red** starts on the south edge (rows 9–10). **Blue** starts on the north edge
  (rows 0–1).
- A neutral **Teleporter** sits at the centre, cell (7, 5).
- Red moves first.

Every piece "faces" one of four directions — **N, E, S, W** — shown after its label
(e.g. `DFL\nE` is a deflector facing east). Facing matters for mirrors: it decides
which way they bend the beam, and which side is vulnerable.

---

## A turn

On your turn you take **2 actions**. An action is one of:

| Action | What it does |
|--------|--------------|
| **Move** | Slide one piece to an orthogonally adjacent **empty** square (N/E/S/W). |
| **Rotate CW** | Turn one piece 90° clockwise. |
| **Rotate CCW** | Turn one piece 90° counter-clockwise. |
| **Fire** | Only the **Laser** can do this. Emits the beam and resolves it instantly. |

You may split your two actions across two pieces, spend both on one piece (e.g. rotate
then fire), or move twice to reach a diagonal square. Firing ends that action; the beam
is traced and any hits resolve immediately, then it's your second action (or the
opponent's turn).

### Controls in-world

Touch one of **your** pieces → a dialog appears with **Move / Rotate CW / Rotate CCW /
Fire / Cancel**. Choosing **Move** highlights the legal destination squares; touch one
to complete the move. After the game ends, touch the board to restart.

---

## Firing the laser

When you fire, a beam leaves your Laser in the direction it faces and travels in a
straight line until something happens to it:

- **Empty square** → passes straight through.
- **Mirror piece** → bends 90° (see each piece below). Both your mirrors *and* the
  opponent's are fair game for setting up a shot.
- **Splitter** → the beam forks into two.
- **Edge of the board** → absorbed (beam ends).
- **A vulnerable face** → that piece is **destroyed** and removed from the board.
- **A King** → the game ends. (See *Winning* below.)

> ⚠️ **Friendly fire is real.** The beam doesn't care who owns a piece. You can
> destroy your own pieces, and if your beam loops back into your *own* King, **you
> lose**. Plan the whole path, not just the first bounce.

---

## The pieces

### ♦ King — `KING`
The piece you must protect. It has no mirror. If the laser beam reaches **either**
King, that King's owner **loses** immediately. It can move and rotate (rotation has no
mechanical effect). Keep it shielded behind mirrors and out of beam lines.

### ▣ Laser — `LZR`
Your beam source — one per side. Move and rotate it to aim; **Fire** to shoot. The beam
exits the face it points toward. A Laser struck by a beam is **destroyed**, so don't
aim a shot that bounces back into it.

### ◤ Deflector — `DFL`
A single 45° mirror that **bends the beam 90°**. Its facing sets the diagonal:

- Facing **N or S** → acts as a `/` mirror: a beam going **N→E**, **E→N**, **S→W**,
  **W→S**.
- Facing **E or W** → acts as a `\` mirror: a beam going **N→W**, **W→N**, **S→E**,
  **E→S**.

In this implementation the Deflector reflects a beam arriving from **any** direction
(both faces mirror). Rotating it is how you re-aim a bounce.

### ◬ Defender — `DEF`
An **armoured, one-way** mirror. The side it **faces is mirrored** and deflects the
beam (same 90° rule as the Deflector). A hit on its **back** (the opposite side)
**destroys it**. Hits on its two **sides** are harmlessly **absorbed**. Use it as a
shield that only protects from the front — and watch your opponent trying to get a beam
around to its back.

### ◇ Switch — `SWT`
A **double mirror that cannot be destroyed** by the beam. It always bends an incoming
beam **90° clockwise**, from any direction (N→E→S→W→N). Reliable, indestructible
plumbing for your beam — but it bends *either* player's shots, so it cuts both ways.

### ⤜ Splitter — `SPL`
**Splits the beam into two.** One copy continues straight through; the other is
deflected **90° clockwise**. Both resulting beams are traced fully (each can bounce,
split again, destroy pieces, or hit a King). The Splitter itself is not destroyed.
A well-placed Splitter lets one shot threaten two lines at once.

### ✦ Teleporter — `TELE`
Neutral piece fixed at the board centre (7, 5). In this implementation it **absorbs**
the beam — the laser stops there.

> In the original *Advanced Laser Chess*, the central device also displaces pieces that
> land on it. That displacement mechanic is **not** implemented here; the Teleporter
> currently only blocks the beam.

---

## Winning

You win when the laser beam — yours on your turn — reaches the **opponent's King**. The
beam may take any path: straight, bounced off any number of mirrors, or arriving via a
splitter fork. Because of friendly fire, you can also *lose* on your own turn by
routing the beam into your own King.

When a King is hit, the game announces the winner and freezes. **Touch the board to
start a new game.**

---

## Quick strategy notes

- **Think in paths, not squares.** A single rotation can swing your beam across the
  whole board. Trace it to the end before you fire.
- **Mirrors are shared.** Every Deflector, Switch, and Splitter bends *both* players'
  beams. Position yours so they help your shot and hinder the reply.
- **Defenders are directional.** They only shield from the front. Manoeuvre to hit the
  back, or rotate yours to keep the armoured face toward the threat.
- **Mind your own Laser and King.** A beam that loops home destroys your cannon or ends
  the game in your opponent's favour.
- **Two actions = setup + payoff.** A common turn is *rotate a mirror, then fire* —
  arrange the bounce and take the shot in one turn.

---

## Playing against the AI

This build ships with an optional AI opponent in a separate, swappable script. By
default it plays **Blue**. To toggle it, see *Turning the AI on/off* in
[SETUP.md](SETUP.md). The bundled AI is a basic greedy player (it takes a winning shot
when one exists, otherwise sets up or moves); it's designed to be replaced with a
stronger one without touching the game rules.
