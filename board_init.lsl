// ============================================================
// Advanced Laser Chess — Board Builder  (3rd root script)
// Lives in the ROOT prim alongside game_controller.lsl + board_renderer.lsl.
//
// game_controller.lsl is near the 64 KB Mono limit, and building the starting
// position there (50+ list-replace calls churning the 165-element board) tipped
// it into a stack-heap collision on Start. So that work moves here: on
// LM_BUILD_BOARD this script constructs the position in its OWN memory and
// streams the finished board back as one CSV (LM_BOARD_DATA). The controller
// just loads that string in a single parse — no churn, and the setup code/data
// no longer take up room in the controller.
//
// Encoding must match game_controller.lsl:
//   cell = type + owner*100 + orient*1000 + stun*10000 + bombDiag*100000
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;

integer T_KING      = 1;
integer T_LASER     = 2;
integer T_STUNNER   = 3;
integer T_ONEWAY    = 4;
integer T_TRIMIR    = 5;
integer T_BOMB      = 6;
integer T_HYPERGON  = 7;
integer T_SPLITTER  = 8;
integer T_POCT      = 9;
integer T_FOCT      = 10;
integer T_HOLE      = 11;
integer T_HYPERHOLE = 12;

integer O_NONE  = 0;
integer P_RED   = 1;
integer P_GREEN = 2;

integer LM_BUILD_BOARD = 16;  // controller -> us: build the starting board
integer LM_BOARD_DATA  = 17;  // us -> controller: the board as one CSV

list gB;

integer mkCell(integer t, integer ownr, integer o, integer stun, integer bombDiag) {
    return t + ownr*100 + o*1000 + stun*10000 + bombDiag*100000;
}
bSet(integer x, integer y, integer v) {
    integer i = y * BOARD_W + x;
    gB = llListReplaceList(gB, [v], i, i);
}
// Place a Red piece and its 180-degree Green counterpart.
placePair(integer x, integer y, integer t, integer o, integer bombDiag) {
    bSet(x, y, mkCell(t, P_RED, o, 0, bombDiag));
    bSet((BOARD_W-1) - x, (BOARD_H-1) - y, mkCell(t, P_GREEN, (o + 4) % 8, 0, bombDiag));
}
neutral(integer x, integer y, integer t) {
    bSet(x, y, mkCell(t, O_NONE, 0, 0, 0));
}

buildBoard() {
    gB = [];
    integer i;
    for (i = 0; i < BOARD_W * BOARD_H; ++i) gB += [0];

    // --- Red back column (x=0) ---
    placePair(0, 0,  T_ONEWAY,   2, 0);   // Oe
    placePair(0, 1,  T_TRIMIR,   2, 0);   // Te  (cardinal -> flat mirror)
    placePair(0, 2,  T_BOMB,     0, 0);   // Bo  (orthogonal)
    placePair(0, 3,  T_STUNNER,  6, 0);   // Sw
    placePair(0, 4,  T_LASER,    2, 0);   // Le
    placePair(0, 5,  T_KING,     0, 0);   // K
    placePair(0, 6,  T_LASER,    2, 0);   // Le
    placePair(0, 7,  T_STUNNER,  6, 0);   // Sw
    placePair(0, 8,  T_BOMB,     0, 0);   // Bo
    placePair(0, 9,  T_TRIMIR,   2, 0);   // Te
    placePair(0, 10, T_ONEWAY,   2, 0);   // Oe

    // --- Red middle column (x=1) ---
    placePair(1, 0,  T_TRIMIR,   3, 0);   // Tse (diagonal -> deflector)
    placePair(1, 1,  T_TRIMIR,   0, 0);   // Tn
    placePair(1, 2,  T_ONEWAY,   2, 0);   // Oe
    placePair(1, 3,  T_HYPERGON, 0, 0);   // H
    placePair(1, 4,  T_SPLITTER, 6, 0);   // Pw
    placePair(1, 5,  T_STUNNER,  6, 0);   // Sw
    placePair(1, 6,  T_SPLITTER, 6, 0);   // Pw
    placePair(1, 7,  T_HYPERGON, 0, 0);   // H
    placePair(1, 8,  T_ONEWAY,   2, 0);   // Oe
    placePair(1, 9,  T_TRIMIR,   4, 0);   // Ts
    placePair(1, 10, T_TRIMIR,   1, 0);   // Tne

    // --- Red front column (x=2): 4 partial octagons + 1 full (centre) ---
    placePair(2, 3,  T_POCT,     2, 0);   // me (shield ne/e/se)
    placePair(2, 4,  T_POCT,     2, 0);
    placePair(2, 5,  T_FOCT,     0, 0);   // M  (fully mirrored)
    placePair(2, 6,  T_POCT,     2, 0);
    placePair(2, 7,  T_POCT,     2, 0);

    // --- Neutral centre features (column x=7) ---
    neutral(7, 1, T_HOLE);
    neutral(7, 3, T_HOLE);
    neutral(7, 5, T_HYPERHOLE);
    neutral(7, 7, T_HOLE);
    neutral(7, 9, T_HOLE);
}

default {
    link_message(integer sender, integer num, string str, key id) {
        if (num != LM_BUILD_BOARD) return;
        buildBoard();
        llMessageLinked(LINK_ROOT, LM_BOARD_DATA, llDumpList2String(gB, ","), NULL_KEY);
        gB = [];   // free the working board
    }
}
