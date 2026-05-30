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

        integer col = param % 100;
        integer row = param / 100;
        llSetObjectName("cell_" + (string)col + "_" + (string)row);
        llSetObjectDesc((string)col + "," + (string)row);

        // Self-destruct: this script is only needed for the rez step.
        llRemoveInventory(llGetScriptName());
    }
}
