// ============================================================
// Advanced Laser Chess — Cell Prim On-Rez Self-Placer
// Drop this into the "lc_cell" template prim alongside piece.lsl.
//
// builder_rezzer.lsl rezzes every cell AT the rezzer (because llRezObject
// can't reach the far side of the board). On rez this script:
//   1. decodes its (col,row) from the start parameter,
//   2. names itself cell_X_Y,
//   3. moves itself from the rez point (the board's NW corner) to its grid
//      slot using llSetRegionPos — which, unlike llSetPos, can move any
//      distance within the region.
// It then deletes itself so it doesn't sit in the final build.
//
// CELL_SIZE must match the spacing builder_layout.lsl will use later.
// ============================================================

float CELL_SIZE = 1.0;    // metres per cell (match builder_layout.lsl)
float CELL_ZOFF = 0.025;  // small lift so cells don't z-fight the board

default {
    on_rez(integer param) {
        if (param == 0) return; // rezzed manually, not by the rezzer

        // Rezzer passes (1 + col + row*100); subtract the +1 offset back out.
        integer enc = param - 1;
        integer col = enc % 100;
        integer row = enc / 100;

        llSetObjectName("cell_" + (string)col + "_" + (string)row);
        llSetObjectDesc((string)col + "," + (string)row);

        // The rez point is the board's NW corner (cell 0,0). From here:
        //   col -> east (local +X),  row -> south (local -Y).
        // Compute in the rezzer's rotation frame (we were rezzed with it).
        vector localOffset = < (float)col * CELL_SIZE,
                              -((float)row * CELL_SIZE),
                               CELL_ZOFF >;
        vector target = llGetPos() + (localOffset * llGetRot());

        llSleep(0.1);               // let the rez settle before moving
        llSetRegionPos(target);     // no 10 m limit within the region

        // Self-destruct: only needed for the rez/placement step.
        llRemoveInventory(llGetScriptName());
    }
}
