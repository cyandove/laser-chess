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
//      (cell 0,0 will appear at the rezzer's location).
//   4. Touch the rezzer → it rezzes all 165 cell prims in a grid.
//   5. Select all 165 rezzed prims + your board root prim, link them
//      (root prim selected LAST), then run builder_layout.lsl.
//
// The rezzer itself is NOT part of the final board — delete it after linking.
// ============================================================

string CELL_ITEM  = "lc_cell";  // inventory name of the cell prim template
float  CELL_SIZE  = 1.0;        // must match builder_layout.lsl
float  CELL_ZOFF  = 0.025;      // small lift so prims don't z-fight

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

        // Compute rez position: origin is NW corner (col=0, row=0)
        // Each step goes east (local +X) for col, south (local -Y) for row
        vector localOffset = <
            (float)gCol * CELL_SIZE,
            -((float)gRow * CELL_SIZE),
            CELL_ZOFF
        >;
        vector rezPos = gOrigin + (localOffset * gRot);

        // Rez with a temporary name containing coords so builder_layout.lsl
        // can also verify positions independently if needed.
        // The rezzed prim's start param encodes col + row*100 for identification.
        llRezObject(CELL_ITEM, rezPos, ZERO_VECTOR, gRot,
                    gCol + gRow * 100);

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
