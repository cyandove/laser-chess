// ============================================================
// Advanced Laser Chess — AI Toggle Button
// Drop into a SMALL dedicated prim that you LINK into the board
// (not a cell, not the board face). Touch it for a menu to enable/
// disable the AI, pick which side it plays, or reset the game.
//
// It just sends the controller's config messages on link channel 100
// (see game_controller.lsl). Picking a side both selects it and turns
// the AI on. The AI prim (ai_controller.lsl) shows the live mode.
//
// llMessageLinked only travels within a linkset, so this prim MUST be
// part of the board's linkset.
// ============================================================

integer LM_CONFIG = 100;
integer MENU_CH   = -918273;   // private dialog channel
integer gListen;

showLabel() { llSetText("Touch: AI menu", <1,1,1>, 1.0); }

cfg(string msg) { llMessageLinked(LINK_SET, LM_CONFIG, msg, NULL_KEY); }

default {
    state_entry() { showLabel(); }

    touch_start(integer n) {
        key who = llDetectedKey(0);
        if (gListen) llListenRemove(gListen);
        gListen = llListen(MENU_CH, "", who, "");
        llSetTimerEvent(30.0);   // auto-close the listen
        llDialog(who, "AI control:",
            ["Plays Green", "Plays Red", "AI Off", "Reset", "Close"], MENU_CH);
    }

    listen(integer ch, string nm, key id, string msg) {
        if (msg == "Plays Green") { cfg("AI_GREEN"); cfg("AI_ON"); llSetText("AI: Green", <0.35,1,0.4>, 1.0); }
        else if (msg == "Plays Red") { cfg("AI_RED"); cfg("AI_ON"); llSetText("AI: Red", <1,0.35,0.35>, 1.0); }
        else if (msg == "AI Off")  { cfg("AI_OFF"); llSetText("AI: Off", <1,1,1>, 1.0); }
        else if (msg == "Reset")   { cfg("RESET");  llSetText("Game reset", <1,1,0.4>, 1.0); }
        // "Close" / anything else: just dismiss

        llSetTimerEvent(0.0);
        if (gListen) { llListenRemove(gListen); gListen = 0; }
    }

    timer() {
        llSetTimerEvent(0.0);
        if (gListen) { llListenRemove(gListen); gListen = 0; }
    }
}
