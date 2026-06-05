// ============================================================
// Advanced Laser Chess — Game Controller  (ALC rewrite, Phase 3)
// Root prim of the board linkset. Rendering is done by board_renderer.lsl
// (also a root script); the cell prims hold no scripts.
//
// Done: cell model (12 types, 8 orientations), full ALC starting board,
// rendering + auto-layout, 3 actions/turn, orthogonal move (diagonal costs 2),
// 45-degree rotation w/ refund-on-return, capture-by-moving (King + Octagons),
// 8-direction beam physics (Laser destroys / Stunner stuns), Bomb blast
// (center vs side), stun enforcement + per-turn thaw, Hyper Hole displacement,
// and once-per-turn caps on firing and capturing.
// Hole is impassable; "removal on entry" only via displacement (avoided here).
//
// Board: 15 wide (x 0-14, W->E) x 11 tall (y 0-10, N->S).
// Red = cols 0-2 (west), Green = cols 12-14 (east). See ALC_DESIGN.md.
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;

// Cell layout (sizing, lift, the grid arrangement) now lives in
// board_renderer.lsl, which positions each cell as it renders it.

// ---- Piece types ----
integer T_EMPTY     = 0;
integer T_KING      = 1;
integer T_LASER     = 2;
integer T_STUNNER   = 3;
integer T_ONEWAY    = 4;
integer T_TRIMIR    = 5;
integer T_BOMB      = 6;
integer T_HYPERGON  = 7;
integer T_SPLITTER  = 8;
integer T_POCT      = 9;   // partially-mirrored octagon
integer T_FOCT      = 10;  // fully-mirrored octagon
integer T_HOLE      = 11;
integer T_HYPERHOLE = 12;

// ---- Owners ----
integer O_NONE = 0;
integer P_RED  = 1;
integer P_GREEN= 2;

// ---- Orientations (0..7 CW from north): N NE E SE S SW W NW ----
// dx/dy lookup
list DDX = [ 0, 1, 1, 1, 0,-1,-1,-1];
list DDY = [-1,-1, 0, 1, 1, 1, 0,-1];

// ---- link-message nums ----
integer LM_CELL_UPDATE = 1;
integer LM_HIGHLIGHT   = 2;
integer LM_CLEAR_HL    = 3;
integer LM_LASER_PATH  = 4;
integer LM_GAME_OVER   = 5;
integer LM_BEAM        = 7;   // "x,y" -> light a beam cell; "x,y,HIT" -> emphasized
integer LM_BOARD_FULL  = 8;   // whole board as one CSV -> board_renderer.lsl
integer LM_RENDER_READY = 9;  // board_renderer.lsl -> us: it (re)started, wants the board
integer LM_PIECE_TOUCH = 10;
integer LM_ACTION      = 11;
integer LM_SELECT      = 12;  // -> board_renderer.lsl: which cell is selected ("x,y" / "-1,-1")
integer LM_RENDER_MODE = 13;  // -> renderer: "3D" / "FLAT"
integer LM_SETUP       = 14;  // -> renderer: show setup screen "flat,ai,side"
integer LM_CONFIRM     = 15;  // -> renderer: show reset-confirm prompt
integer LM_BUILD_BOARD = 16;  // -> lc_logic.lsl: build the starting board
integer LM_BOARD_DATA  = 17;  // lc_logic.lsl -> us: the starting board CSV
integer LM_TRACE       = 18;  // -> lc_logic.lsl: trace a shot "boardCSV|ox|oy|isStun"
integer LM_TRACE_RESULT= 19;  // lc_logic.lsl -> us: "beamCells|pendingFx|pendingKing"
integer LM_AI_REQUEST  = 20;
integer LM_AI_RESPONSE = 21;
integer LM_CONFIG      = 100;

// ---- FSM ----
integer GS_IDLE     = 0;
integer GS_SELECTED = 1;
integer GS_AWAIT_DST= 2;
integer GS_GAMEOVER = 3;
integer GS_FIRING   = 4;   // beam animation playing; input ignored
integer GS_SETUP    = 5;   // pre-game menu drawn on the tiles
integer GS_CONFIRM_RESET = 6;  // modal "reset the game?" prompt

integer ACTIONS_PER_TURN = 3;

// Beam animation tunables
float   BEAM_STEP = 0.08;   // seconds per cell as the beam travels
float   HIT_HOLD  = 0.55;   // emphasis hold on the struck cell(s)

// ---- state ----
list    gBoard;
integer gCurPlayer;
integer gActionsLeft;
integer gState;
integer gSelX;
integer gSelY;
integer gAIEnabled;
integer gAIPlayer;
integer gFlatMode;      // TRUE = force flat textured pieces (set on the setup screen)

// Rotation-refund tracking (per turn): for each rotated piece, its board
// index, its orientation when first rotated this turn, and how many rotation
// actions have been charged. Returning a piece to its start orientation
// refunds those actions. Cleared on any move and at end of turn.
list    gRotIdx;
list    gRotStart;
list    gRotSpent;

// Beam animation state (a shot is traced up front, then played back).
list    gBeamCells;     // ordered "x,y" cells the beam passes through
list    gPendingFx;     // "x,y" cells to destroy/stun when the beam arrives
string  gPendingKing;   // "king:owner" if a laser beam reaches a King, else ""
integer gFireIsStun;    // current shot is a stunner
integer gBeamStep;      // reveal index into gBeamCells

// Per-turn caps: board indices of pieces that have fired / captured this turn.
list    gFired;
list    gCaptured;

float   THAW_CHANCE = 0.34;   // per-turn chance a stunned piece recovers

// ============================================================
// ENCODING  cell = type + owner*100 + orient*1000 + stun*10000 + bombDiag*100000
// ============================================================
integer mkCell(integer t, integer ownr, integer o, integer stun, integer bombDiag) {
    return t + ownr*100 + o*1000 + stun*10000 + bombDiag*100000;
}
integer cType(integer c)   { return c % 100; }
integer cOwner(integer c)  { return (c / 100) % 10; }
integer cOrient(integer c) { return (c / 1000) % 10; }
integer cStun(integer c)   { return (c / 10000) % 10; }
integer cBombDiag(integer c){ return (c / 100000) % 10; }

// ============================================================
// BOARD ACCESS
// ============================================================
integer bIdx(integer x, integer y) { return y * BOARD_W + x; }
integer bGet(integer x, integer y) { return llList2Integer(gBoard, bIdx(x,y)); }
bSet(integer x, integer y, integer v) {
    gBoard = llListReplaceList(gBoard, [v], bIdx(x,y), bIdx(x,y));
}
integer bOk(integer x, integer y) { return x>=0 && x<BOARD_W && y>=0 && y<BOARD_H; }

integer dirDX(integer o) { return llList2Integer(DDX, o); }
integer dirDY(integer o) { return llList2Integer(DDY, o); }

// ============================================================
// MESSAGING
// ============================================================
// (Piece-texture/sculpt UUIDs live in board_renderer.lsl's TEX/SCULPT lists —
// it has the spare memory, and it decodes the piece type for rendering.)
// Renderer messages go to LINK_THIS — board_renderer.lsl is a root script, so
// this reaches it without fanning out to the (script-less) cell prims.
pushCell(integer x, integer y) {
    llMessageLinked(LINK_THIS, LM_CELL_UPDATE,
        (string)x+","+(string)y+","+(string)bGet(x,y), NULL_KEY);
}
setStatus(string s) {
    llSetText(s, <1,1,1>, 1.0);
}
clearHL() { llMessageLinked(LINK_THIS, LM_CLEAR_HL, "", NULL_KEY); }
hlCell(integer x, integer y, integer on) {
    llMessageLinked(LINK_THIS, LM_HIGHLIGHT,
        (string)x+","+(string)y+","+(string)on, NULL_KEY);
}
broadcastBoard() {
    // Hand the whole board to the renderer in ONE message (it loops and morphs
    // every square, clearing cells that became empty). Pushing all 165 cells
    // individually risked overflowing the renderer's event queue.
    llMessageLinked(LINK_THIS, LM_BOARD_FULL, llDumpList2String(gBoard, ","), NULL_KEY);
}

// ============================================================
// SETUP — place a Red piece and its 180-degree Green counterpart.
// ============================================================
// The starting position is built by board_init.lsl (a separate root script) and
// streamed back as a CSV — see startGame() / the LM_BOARD_DATA handler.

// ============================================================
// CAPTURE / MOVEMENT RULES
// ============================================================
integer canCapture(integer t) {
    return (t == T_KING || t == T_POCT || t == T_FOCT);
}
// Pieces that can never be moved/rotated (board features)
integer isFeature(integer t) {
    return (t == T_HOLE || t == T_HYPERHOLE);
}
string playerName(integer p) { if (p==P_RED) return "Red"; return "Green"; }

// cost of a step to (nx,ny) from selected piece; -1 if illegal given actionsLeft
integer moveCost(integer fx, integer fy, integer nx, integer ny, integer actionsLeft) {
    if (!bOk(nx,ny)) return -1;
    integer adx = nx - fx; if (adx<0) adx = -adx;
    integer ady = ny - fy; if (ady<0) ady = -ady;
    integer cost;
    if (adx+ady == 1) cost = 1;          // orthogonal
    else if (adx==1 && ady==1) cost = 2; // diagonal
    else return -1;                      // not a single step
    if (cost > actionsLeft) return -1;

    integer dst = bGet(nx,ny);
    integer dt = cType(dst);
    if (dt == T_EMPTY) return cost;
    if (dt == T_HYPERHOLE) return cost;  // enterable: displaces the mover
    if (isFeature(dt)) return -1;        // Hole is impassable
    // occupied: only a capture by an enemy-capturing mover, once per turn
    integer mover = bGet(fx,fy);
    if (cOwner(dst) != cOwner(mover) && canCapture(cType(mover))) {
        if (llListFindList(gCaptured, [bIdx(fx,fy)]) >= 0) return -1; // already captured
        return cost;
    }
    return -1;
}

// highlight every legal destination for the selected piece
showDestinations() {
    integer o;
    for (o=0; o<8; ++o) {
        integer nx = gSelX + dirDX(o);
        integer ny = gSelY + dirDY(o);
        if (moveCost(gSelX, gSelY, nx, ny, gActionsLeft) > 0) hlCell(nx, ny, 1);
    }
}

// ============================================================
// TURN MANAGEMENT
// ============================================================
announceTurn() {
    setStatus(playerName(gCurPlayer) + "'s turn — "
        + (string)gActionsLeft + " action(s) left.");
    if (gAIEnabled && gCurPlayer == gAIPlayer && gState != GS_GAMEOVER) {
        string boardEnc = llDumpList2String(gBoard, ",");
        string firedEnc = llDumpList2String(gFired, ",");
        string capEnc   = llDumpList2String(gCaptured, ",");
        llMessageLinked(LINK_ALL_CHILDREN, LM_AI_REQUEST,
            boardEnc + "|" + (string)gCurPlayer + "|" + (string)gActionsLeft
            + "|" + firedEnc + "|" + capEnc, NULL_KEY);
    }
}

// ---- Phase 3 helpers ----

// At the start of a player's turn, each of their stunned pieces has a fixed
// chance to recover (thaw).
thawStunned(integer player) {
    integer x; integer y;
    for (y=0; y<BOARD_H; ++y)
        for (x=0; x<BOARD_W; ++x) {
            integer c = bGet(x,y);
            if (cOwner(c)==player && cStun(c) && llFrand(1.0) < THAW_CHANCE) {
                bSet(x,y, mkCell(cType(c), cOwner(c), cOrient(c), 0, cBombDiag(c)));
                pushCell(x,y);
            }
        }
}

// Move a displaced piece to a random empty cell with a random orientation.
displacePiece(integer cell) {
    list empties;
    integer x; integer y;
    for (y=0; y<BOARD_H; ++y)
        for (x=0; x<BOARD_W; ++x)
            if (bGet(x,y)==0) empties += [y*BOARD_W + x];
    if (llGetListLength(empties)==0) return;   // nowhere to go
    integer pick = llList2Integer(empties, (integer)llFrand(llGetListLength(empties)));
    integer rx = pick % BOARD_W;
    integer ry = pick / BOARD_W;
    integer no = (integer)llFrand(8.0);
    bSet(rx,ry, mkCell(cType(cell), cOwner(cell), no, cStun(cell), cBombDiag(cell)));
    pushCell(rx,ry);
}

// Follow per-turn caps when a piece moves (to = -1 drops the tracking).
remapTracking(integer from, integer to) {
    integer p = llListFindList(gFired, [from]);
    if (p >= 0) {
        if (to < 0) gFired = llDeleteSubList(gFired, p, p);
        else gFired = llListReplaceList(gFired, [to], p, p);
    }
    p = llListFindList(gCaptured, [from]);
    if (p >= 0) {
        if (to < 0) gCaptured = llDeleteSubList(gCaptured, p, p);
        else gCaptured = llListReplaceList(gCaptured, [to], p, p);
    }
}

resetTurnState() {
    gRotIdx = []; gRotStart = []; gRotSpent = [];
    gFired = []; gCaptured = [];
}

spendActions(integer cost) {
    gActionsLeft -= cost;
    clearHL();
    gState = GS_IDLE;
    gSelX = -1; gSelY = -1;
    llMessageLinked(LINK_THIS, LM_SELECT, "-1,-1", NULL_KEY);  // selection ended
    if (gActionsLeft <= 0) {
        if (gCurPlayer == P_RED) gCurPlayer = P_GREEN;
        else gCurPlayer = P_RED;
        gActionsLeft = ACTIONS_PER_TURN;
        resetTurnState();
        thawStunned(gCurPlayer);
    }
    announceTurn();
}

// Rotate the piece at (x,y) by 'step' (+1 = CW, +7 = CCW). Returning a piece to
// its start-of-turn orientation refunds the rotation actions spent on it.
doRotate(integer x, integer y, integer step) {
    integer cell = bGet(x, y);
    integer startO = cOrient(cell);
    integer newO = (startO + step) % 8;
    bSet(x, y, mkCell(cType(cell), cOwner(cell), newO, cStun(cell), cBombDiag(cell)));
    pushCell(x, y);

    integer idx = bIdx(x, y);
    integer p = llListFindList(gRotIdx, [idx]);
    if (p < 0) {
        gRotIdx   += [idx];
        gRotStart += [startO];          // orientation before the first rotation
        gRotSpent += [0];
        p = llGetListLength(gRotIdx) - 1;
    }
    integer spent = llList2Integer(gRotSpent, p);
    if (newO == llList2Integer(gRotStart, p)) {
        gRotSpent = llListReplaceList(gRotSpent, [0], p, p);
        spendActions(-spent);           // refund prior charges; this one is free
    } else {
        gRotSpent = llListReplaceList(gRotSpent, [spent + 1], p, p);
        spendActions(1);
    }
}

// ============================================================
// BEAM  — tracing lives in lc_logic.lsl (LM_TRACE/LM_TRACE_RESULT); the
// controller fires the request, then plays back + applies the result.
// ============================================================

// apply weapon effect to the piece at (x,y)
applyHit(integer x, integer y, integer isStun) {
    integer c = bGet(x,y);
    if (isStun)
        bSet(x, y, mkCell(cType(c), cOwner(c), cOrient(c), 1, cBombDiag(c)));
    else
        bSet(x, y, 0);
    pushCell(x, y);
}

// Apply the queued effects (called when the beam reaches its target).
applyPendingFx() {
    integer i;
    for (i=0; i<llGetListLength(gPendingFx); ++i) {
        list xy = llParseString2List(llList2String(gPendingFx,i), [","], []);
        applyHit(llList2Integer(xy,0), llList2Integer(xy,1), gFireIsStun);
    }
}

// Revert every cell the beam lit back to its normal render.
clearTrail() {
    integer i;
    for (i=0; i<llGetListLength(gBeamCells); ++i) {
        list xy = llParseString2List(llList2String(gBeamCells,i), [","], []);
        pushCell(llList2Integer(xy,0), llList2Integer(xy,1));
    }
}

// Fire the selected weapon: trace the shot, then PLAY IT BACK over time.
// The board isn't touched until the beam reaches its target (see beamTick).
doFire() {
    integer t = cType(bGet(gSelX, gSelY));
    if (t != T_LASER && t != T_STUNNER) {
        setStatus("Only a Laser or Stunner can fire.");
        return;
    }
    integer idx = bIdx(gSelX, gSelY);
    if (llListFindList(gFired, [idx]) >= 0) {
        setStatus("That weapon already fired this turn.");
        return;
    }
    gFireIsStun = (t == T_STUNNER);
    gFired += [idx];        // this weapon has fired this turn
    clearHL();
    gState = GS_FIRING;     // ignore input until the trace comes back + plays
    setStatus(playerName(gCurPlayer) + " fires…");
    // ask lc_logic.lsl to trace the shot; playback starts on LM_TRACE_RESULT.
    llMessageLinked(LINK_THIS, LM_TRACE,
        llDumpList2String(gBoard, ",") + "|" + (string)gSelX + "|"
        + (string)gSelY + "|" + (string)gFireIsStun, NULL_KEY);
}

// The trace came back: stash it and start the beam playback.
startBeam(string result) {
    list parts = llParseStringKeepNulls(result, ["|"], []);
    gBeamCells   = llParseString2List(llList2String(parts,0), [";"], []);
    gPendingFx   = llParseString2List(llList2String(parts,1), [";"], []);
    gPendingKing = llList2String(parts, 2);
    gBeamStep = 0;
    llMessageLinked(LINK_ALL_CHILDREN, LM_LASER_PATH,
        llDumpList2String(gBeamCells, ";"), NULL_KEY);   // ribbon FX
    llSetTimerEvent(BEAM_STEP);
}

// One step of the beam playback (driven by the controller timer).
beamTick() {
    integer n = llGetListLength(gBeamCells);

    if (gBeamStep < n) {                 // travel: light the next cell
        llMessageLinked(LINK_THIS, LM_BEAM,
            llList2String(gBeamCells, gBeamStep), NULL_KEY);
        ++gBeamStep;
        return;
    }
    if (gBeamStep == n) {                // arrived: emphasize the struck cell(s)
        integer i;
        for (i=0; i<llGetListLength(gPendingFx); ++i)
            llMessageLinked(LINK_THIS, LM_BEAM,
                llList2String(gPendingFx,i) + ",HIT", NULL_KEY);
        ++gBeamStep;
        llSetTimerEvent(HIT_HOLD);
        return;
    }

    // finish: stop the timer, land the effects, clear the trail, advance.
    llSetTimerEvent(0.0);
    applyPendingFx();
    clearTrail();
    gBeamCells = []; gPendingFx = [];   // free the trace memory

    if (!gFireIsStun && gPendingKing != "") {
        integer loser  = (integer)llGetSubString(gPendingKing,5,-1);
        integer winner = P_RED;
        if (loser == P_RED) winner = P_GREEN;
        setStatus(playerName(winner) + " WINS! Touch the board to restart.");
        llMessageLinked(LINK_THIS, LM_GAME_OVER, (string)winner, NULL_KEY);
        gState = GS_GAMEOVER;
        return;
    }
    spendActions(1);       // firing costs one action; advances the turn
}

// ============================================================
// INPUT
// ============================================================

// Execute a (possibly capturing) move. Stomping the enemy King wins.
doMove(integer fx, integer fy, integer tx, integer ty, integer cost) {
    integer captured = bGet(tx, ty);
    integer mv = bGet(fx, fy);
    integer fromIdx = bIdx(fx, fy);
    integer toIdx = bIdx(tx, ty);
    gRotIdx = []; gRotStart = []; gRotSpent = [];   // a move resets rotation refunds

    // Moving onto the Hyper Hole displaces the mover to a random empty cell.
    if (cType(captured) == T_HYPERHOLE) {
        bSet(fx, fy, 0);
        pushCell(fx, fy);
        remapTracking(fromIdx, -1);
        displacePiece(mv);
        spendActions(cost);
        return;
    }

    bSet(tx, ty, mv);
    bSet(fx, fy, 0);
    pushCell(fx, fy);
    pushCell(tx, ty);
    remapTracking(fromIdx, toIdx);

    if (cType(captured) == T_KING) {
        integer winner = cOwner(mv);
        setStatus(playerName(winner) + " WINS by capture! Touch the board to restart.");
        llMessageLinked(LINK_THIS, LM_GAME_OVER, (string)winner, NULL_KEY);
        gState = GS_GAMEOVER;
        return;
    }
    if (cType(captured) != T_EMPTY) gCaptured += [toIdx];  // used its capture this turn
    spendActions(cost);
}

// ---- Pre-game setup screen ----
// All setup/confirm RENDERING lives in board_renderer.lsl (it has the spare
// memory); the controller just sends the current settings.
sendRenderMode() {
    string m = "3D"; if (gFlatMode) m = "FLAT";
    llMessageLinked(LINK_THIS, LM_RENDER_MODE, m, NULL_KEY);
}
showSetup() {
    llMessageLinked(LINK_THIS, LM_SETUP,
        (string)gFlatMode + "," + (string)gAIEnabled + "," + (string)gAIPlayer, NULL_KEY);
}
// Ask board_init.lsl for a fresh starting board; play begins on LM_BOARD_DATA.
startGame() {
    llSetTimerEvent(0.0);   // cancel any beam in flight
    llMessageLinked(LINK_THIS, LM_BUILD_BOARD, "", NULL_KEY);
}
// Load the streamed board (CSV; elements stay strings — bGet casts) and start.
beginGame(string boardCSV) {
    gBoard = llParseString2List(boardCSV, [","], []);
    gCurPlayer = P_RED; gActionsLeft = ACTIONS_PER_TURN;
    gState = GS_IDLE; gSelX = -1; gSelY = -1;
    resetTurnState();
    llMessageLinked(LINK_THIS, LM_SELECT, "-1,-1", NULL_KEY);
    broadcastBoard();
    announceTurn();        // kicks the AI if it happens to play Red
}
handleSetupTouch(integer x, integer y) {
    if (y != 1) return;
    if (x == 3)      { gFlatMode = !gFlatMode; sendRenderMode(); showSetup(); }
    else if (x == 5) { gAIEnabled = !gAIEnabled; showSetup(); }
    else if (x == 9) {
        if (gAIEnabled) {
            if (gAIPlayer == P_RED) gAIPlayer = P_GREEN; else gAIPlayer = P_RED;
            showSetup();
        }
    }
    else if (x == 11) startGame();
}
// Paint whatever the current state should show (used on the renderer handshake).
repaint() {
    if (gState == GS_SETUP) showSetup();
    else broadcastBoard();
}

// Reset control -> confirm before wiping the game.
requestReset() {
    if (gState == GS_SETUP || gState == GS_CONFIRM_RESET || gState == GS_FIRING) return;
    gState = GS_CONFIRM_RESET;
    gSelX = -1; gSelY = -1;
    clearHL();
    llMessageLinked(LINK_THIS, LM_SELECT, "-1,-1", NULL_KEY);
    llMessageLinked(LINK_THIS, LM_CONFIRM, "", NULL_KEY);
    setStatus("Reset the game?");
}

// True if (x,y) holds a piece the current player can pick up this turn.
integer canSelect(integer x, integer y) {
    integer cell = bGet(x, y);
    integer t = cType(cell);
    return (t != T_EMPTY && !isFeature(t) && cOwner(cell) == gCurPlayer && !cStun(cell));
}

// Select (x,y): highlight its destinations and tell the renderer (drives the
// floating hint + which clicks become rotate/fire zones).
selectPiece(integer x, integer y) {
    gSelX = x; gSelY = y;
    gState = GS_SELECTED;
    clearHL();
    showDestinations();
    llMessageLinked(LINK_THIS, LM_SELECT, (string)x + "," + (string)y, NULL_KEY);
}
deselect() {
    gState = GS_IDLE;
    gSelX = -1; gSelY = -1;
    clearHL();
    llMessageLinked(LINK_THIS, LM_SELECT, "-1,-1", NULL_KEY);
    announceTurn();
}
// After a rotate, keep the piece selected (if it's still actionable this turn)
// so the player can keep turning it; otherwise the turn/selection has ended.
reselectAfter(integer x, integer y) {
    if (gState == GS_IDLE && gActionsLeft > 0 && canSelect(x, y)) selectPiece(x, y);
}

handleTouch(integer x, integer y) {
    if (gState == GS_SETUP) { handleSetupTouch(x, y); return; }
    if (gState == GS_CONFIRM_RESET) {
        if (x == 6 && y == 5) {                 // confirm -> back to setup
            llSetTimerEvent(0.0);
            gState = GS_SETUP; gSelX = -1; gSelY = -1;
            resetTurnState();
            showSetup();
        } else if (x == 8 && y == 5) {          // cancel -> resume play
            gState = GS_IDLE; gSelX = -1; gSelY = -1;
            pushCell(6, 5); pushCell(8, 5);     // restore the two overlaid cells
            announceTurn();
        }
        return;
    }
    if (gState == GS_FIRING) return;            // ignore touches while a beam plays
    if (gState == GS_GAMEOVER) {
        startGame();   // touch to restart -> fresh board, begins on LM_BOARD_DATA
        return;
    }
    if (gAIEnabled && gCurPlayer == gAIPlayer) return;

    if (gState == GS_IDLE) {
        if (canSelect(x, y)) selectPiece(x, y);
        else if (cOwner(bGet(x,y)) == gCurPlayer && cStun(bGet(x,y)))
            setStatus("That piece is stunned — it can't act this turn.");
        return;
    }

    // GS_SELECTED. Clicks on the selected piece itself arrive as zone actions
    // (ROTATE_*/FIRE) from the renderer, not here — so this is a move target,
    // a different piece to pick up, or a click that cancels the selection.
    integer cost = moveCost(gSelX, gSelY, x, y, gActionsLeft);
    if (cost > 0)        doMove(gSelX, gSelY, x, y, cost);   // direct move (spendActions clears selection)
    else if (canSelect(x, y)) selectPiece(x, y);             // pick up a different piece
    else                 deselect();                         // empty / illegal -> cancel
}

handleAction(string action) {
    if (action == "RESET") { requestReset(); return; }   // reset button, any time
    // Need a selected piece; ignore while a beam plays or the game is over
    // (control buttons + click-zones are always live, unlike the old menu).
    if (gSelX < 0 || gState == GS_GAMEOVER || gState == GS_FIRING) return;
    integer sx = gSelX; integer sy = gSelY;

    if (action == "ROTATE_CW") {
        doRotate(sx, sy, 1);
        reselectAfter(sx, sy);

    } else if (action == "ROTATE_CCW") {
        doRotate(sx, sy, 7);
        reselectAfter(sx, sy);

    } else if (action == "FIRE") {
        doFire();
        if (gState == GS_FIRING)            // fire actually started -> drop selection UI
            llMessageLinked(LINK_THIS, LM_SELECT, "-1,-1", NULL_KEY);
    }
}

// Apply a move from the AI (Phase 1 subset; FIRE deferred)
applyAIMove(string move) {
    list p = llParseString2List(move, [":"], []);
    string cmd = llList2String(p, 0);
    if (cmd == "PASS") { spendActions(gActionsLeft); return; }  // skip remaining turn

    list xy = llParseString2List(llList2String(p,1), [","], []);
    integer ax = llList2Integer(xy,0);
    integer ay = llList2Integer(xy,1);

    if (cmd == "FIRE") {
        gSelX = ax; gSelY = ay;
        doFire();
    } else if (cmd == "MOVE") {
        integer tx = llList2Integer(xy,2);
        integer ty = llList2Integer(xy,3);
        integer cost = moveCost(ax, ay, tx, ty, gActionsLeft);
        if (cost < 1) cost = 1;
        doMove(ax, ay, tx, ty, cost);
    } else if (cmd == "ROTATE_CW") {
        doRotate(ax, ay, 1);
    } else if (cmd == "ROTATE_CCW") {
        doRotate(ax, ay, 7);
    }
}

// ============================================================
default {
    state_entry() {
        gAIEnabled = FALSE;
        gAIPlayer  = P_GREEN;
        gFlatMode  = FALSE;
        gCurPlayer = P_RED;
        gActionsLeft = ACTIONS_PER_TURN;
        gState = GS_SETUP;
        gSelX = -1; gSelY = -1;
        llSleep(1.0);       // let links settle after a reset
        sendRenderMode();
        showSetup();        // boot into the pre-game menu
    }

    // Touches arrive via LM_PIECE_TOUCH from board_renderer.lsl (it maps the
    // touched child link to a board square), so no touch_start here.

    timer() { beamTick(); }   // drives the laser beam playback

    link_message(integer sender_num, integer num, string str, key id) {
        if (num == LM_RENDER_READY) {
            sendRenderMode();   // renderer just (re)started — resync mode + screen
            repaint();
            return;
        }
        if (num == LM_BOARD_DATA) {   // lc_logic streamed a fresh starting board
            beginGame(str);
            return;
        }
        if (num == LM_TRACE_RESULT) { // lc_logic traced the shot — play it back
            startBeam(str);
            return;
        }
        if (num == LM_PIECE_TOUCH) {
            list xy = llParseString2List(str, [","], []);
            handleTouch(llList2Integer(xy,0), llList2Integer(xy,1));
        } else if (num == LM_ACTION) {
            handleAction(str);
        } else if (num == LM_AI_RESPONSE) {
            if (gAIEnabled && gCurPlayer == gAIPlayer) applyAIMove(str);
        } else if (num == LM_CONFIG) {
            if (str == "AI_ON") {
                gAIEnabled = TRUE;
                // kick off immediately if it's already the AI's turn
                if (gCurPlayer == gAIPlayer && gState != GS_GAMEOVER) announceTurn();
            }
            else if (str == "AI_OFF")  gAIEnabled = FALSE;
            else if (str == "AI_RED")  gAIPlayer  = P_RED;
            else if (str == "AI_GREEN")gAIPlayer  = P_GREEN;
            else if (str == "RESET") {
                llSetTimerEvent(0.0);   // cancel any beam in flight
                gState = GS_SETUP; gSelX = -1; gSelY = -1;
                resetTurnState();
                llMessageLinked(LINK_THIS, LM_SELECT, "-1,-1", NULL_KEY);
                showSetup();            // back to the pre-game menu
            }
        }
    }
}
