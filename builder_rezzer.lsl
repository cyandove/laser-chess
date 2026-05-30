// ============================================================
// Advanced Laser Chess — Cell Prim Rezzer
// Drop into a SEPARATE prim (the "rezzer" object, not the board).
// Put a single small flat box prim named "lc_cell" in its inventory.
//
// USAGE:
//   1. Create a small flat box prim (e.g. 1m × 1m × 0.05m).
//      Name it exactly: lc_cell
//   2. Create a second prim — this is your rezzer controller.
//      Drop THIS script + the lc_cell prim into the rezzer's inventory.
//   3. Position the rezzer where you want the NORTHWEST corner of the board
//      (cell 0,0 ends up at the rezzer's location). Keep the whole 15x11 m
//      board inside the region (board extends east +X and south -Y from here).
//   4. Touch the rezzer → it rezzes 165 cells AT the rezzer; each cell then
//      moves itself to its grid slot (see builder_cell_onrez.lsl).
//   5. Select all 165 rezzed prims + your board root prim, link them
//      (root prim selected LAST), then run builder_layout.lsl.
//
// Why self-positioning: llRezObject can only rez within ~10 m of the rezzer,
// but the board's far corner is ~18 m away — so cells can't be rezzed in
// place. They are rezzed at the rezzer and relocate themselves via
// llSetRegionPos (which, unlike llSetPos, has no 10 m move limit in-region).
//
// The rezzer itself is NOT part of the final board — delete it after linking.
// ============================================================

string CELL_ITEM = "lc_cell";   // inventory name of the cell prim template
// (cell SIZE and Z-offset live in builder_cell_onrez.lsl, which positions cells)

integer BOARD_W = 15;
integer BOARD_H = 11;

integer gCol = 0;
integer gRow = 0;
integer gTotal = 0;

vector gOrigin;    // position of rezzer = NW corner of board
rotation gRot;

default {
    state_entry() {
        llSetText("Touch to rez 165 board cell prims.", <1,1,1>, 1.0);
        if (llGetInventoryType(CELL_ITEM) != INVENTORY_OBJECT) {
            llSetText("ERROR: put prim named '" + CELL_ITEM + "' in inventory first.",
                      <1,0,0>, 1.0);
        }
    }

    touch_start(integer n) {
        if (llDetectedKey(0) != llGetOwner()) return;

        if (llGetInventoryType(CELL_ITEM) != INVENTORY_OBJECT) {
            llOwnerSay("Place a prim named '" + CELL_ITEM + "' in this object's inventory.");
            return;
        }

        gOrigin = llGetPos();
        gRot    = llGetRot();
        gCol    = 0;
        gRow    = 0;
        gTotal  = 0;

        llOwnerSay("Rezzing 165 cell prims — this will take about 20 seconds…");
        llSetTimerEvent(0.12); // ~8 prims/sec; llRezObject has ~10/sec limit
    }

    timer() {
        if (gRow >= BOARD_H) {
            llSetTimerEvent(0.0);
            llSetText("Done! " + (string)gTotal + " prims rezzed.\n"
                + "Select all + board root, link, then run builder_layout.lsl.",
                <0,1,0>, 1.0);
            llOwnerSay("All " + (string)gTotal + " cell prims rezzed.");
            return;
        }

        // Rez every cell AT the rezzer (distance 0, well within rez range);
        // the cell relocates itself to (col,row) from this same origin point.
        // gOrigin is the NW corner; the cell uses its own rez pos + rotation
        // to compute its slot, so all cells must share this origin/rotation.
        // Start param encodes (1 + col + row*100); the +1 keeps cell (0,0)
        // from colliding with on_rez's "param == 0 = rezzed manually" sentinel.
        llRezObject(CELL_ITEM, gOrigin, ZERO_VECTOR, gRot,
                    1 + gCol + gRow * 100);

        ++gTotal;
        ++gCol;
        if (gCol >= BOARD_W) {
            gCol = 0;
            ++gRow;
            llSetText("Rezzing row " + (string)gRow + " / " + (string)BOARD_H + "…",
                      <1,1,0>, 1.0);
        }
    }

    // Optional: the rezzed cell prim can read on_rez(integer param) to pre-name itself.
    // See builder_cell_onrez.lsl for that optional helper.
}
