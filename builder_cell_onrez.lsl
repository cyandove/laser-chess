// ============================================================
// Advanced Laser Chess — Cell Prim On-Rez Self-Namer  (OPTIONAL)
// Drop this into the "lc_cell" template prim alongside piece.lsl.
// When the rezzer rezzes it, it reads the start param and names
// itself cell_X_Y immediately — useful for debugging placement
// before running builder_layout.lsl.
// This script deletes itself after naming so it doesn't waste
// script memory in the final build.
// ============================================================

default {
    on_rez(integer param) {
        if (param == 0) return; // rezzed manually, not by rezzer

        // Rezzer passes (1 + col + row*100); subtract the +1 offset back out.
        integer enc = param - 1;
        integer col = enc % 100;
        integer row = enc / 100;
        llSetObjectName("cell_" + (string)col + "_" + (string)row);
        llSetObjectDesc((string)col + "," + (string)row);

        // Self-destruct: this script is only needed for the rez step.
        llRemoveInventory(llGetScriptName());
    }
}
