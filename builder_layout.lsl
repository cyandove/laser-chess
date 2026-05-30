// ============================================================
// Advanced Laser Chess — Builder Layout Helper
// Drop into the ROOT PRIM of the board linkset.
// Requires exactly 165 child prims already linked to the root.
//
// USAGE:
//   1. Build or duplicate a single flat prim 164 more times (165 total).
//   2. Select all 165 cell prims + the root board prim (root last),
//      then link (Ctrl+L / Build > Link).
//   3. Drop this script into the root prim.
//   4. Touch the root prim → it names and positions every child prim.
//   5. Remove this script when done; drop game_controller.lsl in instead.
//
// CONFIGURATION: edit the constants below to match your build scale.
// ============================================================

float CELL_SIZE   = 1.0;   // metres per cell (board will be 15m × 11m at 1.0)
float CELL_HEIGHT = 0.05;  // thickness of each cell prim
float CELL_ZOFF   = 0.03;  // how far above the board surface the cells sit

integer BOARD_W = 15;
integer BOARD_H = 11;

// Layout state
integer gRow = 0;     // current row being processed (0–10)
integer gRunning = FALSE;

updateProgress(string msg) {
    llSetText(msg, <1,1,0>, 1.0);
    llOwnerSay(msg);
}

processRow(integer row) {
    // Link numbers: 1 = root, 2..166 = children in link order.
    // We map: link (2 + row*BOARD_W + col) → cell_col_row

    vector rootPos = llGetRootPosition();
    rotation rootRot = llGetRootRotation();

    // Board centre is at root prim position.
    // cell (0,0) is northwest: local (-7, +5, CELL_ZOFF) at CELL_SIZE=1
    float halfW = (float)(BOARD_W - 1) * 0.5 * CELL_SIZE;
    float halfH = (float)(BOARD_H - 1) * 0.5 * CELL_SIZE;

    integer col;
    for (col = 0; col < BOARD_W; col++) {
        integer linkNum = 2 + row * BOARD_W + col;

        if (linkNum > llGetNumberOfPrims()) {
            updateProgress("ERROR: not enough prims (need 165 children). "
                + "Found " + (string)(llGetNumberOfPrims()-1) + ".");
            llSetTimerEvent(0.0);
            gRunning = FALSE;
            return;
        }

        // Local offset: X increases eastward, Y decreases southward
        // (SL Y+ = north, so row 0 is north = positive local Y)
        float lx = ((float)col * CELL_SIZE) - halfW;
        float ly = halfH - ((float)row * CELL_SIZE);
        float lz = CELL_ZOFF;

        vector localOffset = <lx, ly, lz>;
        vector globalPos   = rootPos + (localOffset * rootRot);

        string cellName = "cell_" + (string)col + "_" + (string)row;

        llSetLinkPrimitiveParamsFast(linkNum, [
            PRIM_NAME,     cellName,
            PRIM_DESC,     (string)col + "," + (string)row,
            PRIM_POSITION, globalPos,
            PRIM_ROTATION, rootRot,
            PRIM_SIZE,     <CELL_SIZE, CELL_SIZE, CELL_HEIGHT>,
            PRIM_COLOR,    ALL_SIDES, <0.2, 0.2, 0.2>, 0.5,
            PRIM_TEXT,     "", <1,1,1>, 0.0
        ]);
    }
}

default {
    state_entry() {
        llSetText("Touch to lay out board cells.", <1,1,1>, 1.0);
    }

    touch_start(integer n) {
        if (llDetectedKey(0) != llGetOwner()) {
            llInstantMessage(llDetectedKey(0), "Only the owner can run the layout.");
            return;
        }

        integer totalPrims = llGetNumberOfPrims();
        integer numChildren = totalPrims - 1;

        if (numChildren != BOARD_W * BOARD_H) {
            updateProgress("Need exactly " + (string)(BOARD_W*BOARD_H)
                + " child prims. Currently have: " + (string)numChildren
                + ". Link more prims and try again.");
            return;
        }

        updateProgress("Starting layout — 165 cells across 11 rows…");
        gRow = 0;
        gRunning = TRUE;
        llSetTimerEvent(0.1); // process one row per tick to avoid script timeout
    }

    timer() {
        if (!gRunning) { llSetTimerEvent(0.0); return; }

        processRow(gRow);
        updateProgress("Layout: row " + (string)gRow + " / " + (string)(BOARD_H-1)
            + " done…");
        gRow++;

        if (gRow >= BOARD_H) {
            llSetTimerEvent(0.0);
            gRunning = FALSE;
            updateProgress("Layout complete! All 165 cells named and positioned.\n"
                + "Remove this script, then drop game_controller.lsl here.");
        }
    }
}
