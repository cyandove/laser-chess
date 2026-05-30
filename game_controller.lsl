// ============================================================
// Advanced Laser Chess — Game Controller  (ALC rewrite, Phase 2)
// Root prim of the board linkset. Children run piece.lsl.
//
// Done: cell model (12 types, 8 orientations), full ALC starting board,
// rendering, 3 actions/turn, orthogonal move (diagonal costs 2),
// 45-degree rotation, capture-by-moving (King + Octagons), and 8-direction
// beam physics for Laser (destroys) and Stunner (stuns).
// Deferred to Phase 3: Bomb area effect, stun/thaw enforcement, Hyper Hole
// displacement, Hole removal-on-entry, once-per-turn caps.
//
// Board: 15 wide (x 0-14, W->E) x 11 tall (y 0-10, N->S).
// Red = cols 0-2 (west), Green = cols 12-14 (east). See ALC_DESIGN.md.
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;

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
integer LM_STATUS      = 6;
integer LM_PIECE_TOUCH = 10;
integer LM_ACTION      = 11;
integer LM_AI_REQUEST  = 20;
integer LM_AI_RESPONSE = 21;
integer LM_CONFIG      = 100;

// ---- FSM ----
integer GS_IDLE     = 0;
integer GS_SELECTED = 1;
integer GS_AWAIT_DST= 2;
integer GS_GAMEOVER = 3;

integer ACTIONS_PER_TURN = 3;

// ---- state ----
list    gBoard;
integer gCurPlayer;
integer gActionsLeft;
integer gState;
integer gSelX;
integer gSelY;
integer gAIEnabled;
integer gAIPlayer;

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
pushCell(integer x, integer y) {
    llMessageLinked(LINK_ALL_CHILDREN, LM_CELL_UPDATE,
        (string)x+","+(string)y+","+(string)bGet(x,y), NULL_KEY);
}
setStatus(string s) {
    llMessageLinked(LINK_ALL_CHILDREN, LM_STATUS, s, NULL_KEY);
    llSetText(s, <1,1,1>, 1.0);
}
clearHL() { llMessageLinked(LINK_ALL_CHILDREN, LM_CLEAR_HL, "", NULL_KEY); }
hlCell(integer x, integer y, integer on) {
    llMessageLinked(LINK_ALL_CHILDREN, LM_HIGHLIGHT,
        (string)x+","+(string)y+","+(string)on, NULL_KEY);
}
broadcastBoard() {
    integer x; integer y;
    for (y=0; y<BOARD_H; ++y)
        for (x=0; x<BOARD_W; ++x)
            if (bGet(x,y)) pushCell(x, y);
}

// ============================================================
// SETUP — place a Red piece and its 180-degree Green counterpart.
// ============================================================
placePair(integer x, integer y, integer t, integer o, integer bombDiag) {
    bSet(x, y, mkCell(t, P_RED, o, 0, bombDiag));
    integer gx = (BOARD_W-1) - x;
    integer gy = (BOARD_H-1) - y;
    integer go = (o + 4) % 8;
    bSet(gx, gy, mkCell(t, P_GREEN, go, 0, bombDiag));
}
neutral(integer x, integer y, integer t) {
    bSet(x, y, mkCell(t, O_NONE, 0, 0, 0));
}

initBoard() {
    gBoard = [];
    integer i;
    for (i=0; i<BOARD_W*BOARD_H; ++i) gBoard += [0];

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
    if (isFeature(dt)) return -1;        // Holes handled in Phase 3
    // occupied: only a capture by an enemy-capturing mover
    integer mover = bGet(fx,fy);
    if (cOwner(dst) != cOwner(mover) && canCapture(cType(mover))) return cost;
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
    if (gAIEnabled && gCurPlayer == gAIPlayer) {
        string boardEnc = llDumpList2String(gBoard, ",");
        llMessageLinked(LINK_ALL_CHILDREN, LM_AI_REQUEST,
            boardEnc + "|" + (string)gCurPlayer + "|" + (string)gActionsLeft, NULL_KEY);
    }
}

spendActions(integer cost) {
    gActionsLeft -= cost;
    clearHL();
    gState = GS_IDLE;
    gSelX = -1; gSelY = -1;
    if (gActionsLeft <= 0) {
        gCurPlayer = (gCurPlayer == P_RED) ? P_GREEN : P_RED;
        gActionsLeft = ACTIONS_PER_TURN;
    }
    announceTurn();
}

// ============================================================
// BEAM PHYSICS (Phase 2)
// Beams travel in any of the 8 directions. Mirror interactions use a
// single vector-reflection rule:  v' = v - 2(v·n)/(n·n) n , where n is
// the reflective face's outward normal. sign(v·n): <0 front (reflect),
// >0 back (destroy), ==0 graze (pass). Same rule covers flat mirrors
// (cardinal normal) and 45° deflectors (diagonal normal).
// ============================================================

// direction index <- vector
integer dirFromVec(integer dx, integer dy) {
    integer i;
    for (i=0; i<8; ++i)
        if (llList2Integer(DDX,i)==dx && llList2Integer(DDY,i)==dy) return i;
    return -1;
}
// reflect travel-dir d off a face whose outward normal points 'nrm'
integer reflectOff(integer d, integer nrm) {
    integer vx = dirDX(d);  integer vy = dirDY(d);
    integer nx = dirDX(nrm); integer ny = dirDY(nrm);
    integer dot = vx*nx + vy*ny;
    integer nn  = nx*nx + ny*ny;          // 1 cardinal, 2 diagonal
    integer f   = (2*dot) / nn;
    return dirFromVec(vx - f*nx, vy - f*ny);
}
integer dotDir(integer d, integer nrm) {
    return dirDX(d)*dirDX(nrm) + dirDY(d)*dirDY(nrm);
}
// the two directions perpendicular (±90°) to d
list perpDirs(integer d) {
    return [(d+2)%8, (d+6)%8];
}
integer inShieldArc(integer face, integer o) {
    return (face==o || face==(o+1)%8 || face==(o+7)%8);
}

// What happens when a beam travelling 'd' enters cell (x,y)?
// Returns: pass | absorb | random | hit | king | reflect:D | split:D1:D2
string laserInteract(integer x, integer y, integer d) {
    integer cell = bGet(x,y);
    integer t = cType(cell);
    integer o = cOrient(cell);

    if (t == T_EMPTY)                       return "pass";
    if (t == T_HOLE || t == T_HYPERHOLE)    return "absorb";
    if (t == T_HYPERGON)                    return "random";
    if (t == T_KING)                        return "king";
    if (t == T_LASER || t == T_STUNNER || t == T_BOMB) return "hit"; // bomb area: Phase 3
    if (t == T_FOCT)                        return "reflect:" + (string)((d+4)%8);

    if (t == T_POCT) {
        integer face = (d+4)%8;             // face the beam strikes
        if (inShieldArc(face, o)) return "reflect:" + (string)((d+4)%8);
        return "hit";
    }

    if (t == T_ONEWAY) {                    // arrow points cardinal o
        integer dt = dotDir(d, o);
        if (dt > 0) return "pass";                      // with the arrow
        if (dt < 0) return "reflect:" + (string)reflectOff(d, o); // against
        return "hit";                                   // perpendicular destroys
    }

    if (t == T_SPLITTER) {                  // vertex points cardinal o
        if (d == (o+4)%8) {                 // head-on into the vertex
            list pc = perpDirs(d);
            return "split:" + (string)llList2Integer(pc,0)
                       + ":" + (string)llList2Integer(pc,1);
        }
        if (d == o) return "hit";           // back face exposed
        return "pass";                      // off-axis / diagonal: misses
    }

    if (t == T_TRIMIR) {                    // normal = orient (flat or 45°)
        integer dt = dotDir(d, o);
        if (dt == 0) return "pass";         // graze
        if (dt > 0)  return "hit";          // back face -> destroy
        return "reflect:" + (string)reflectOff(d, o);
    }

    return "absorb";
}

// apply weapon effect to the piece at (x,y)
applyHit(integer x, integer y, integer isStun) {
    integer c = bGet(x,y);
    if (isStun)
        bSet(x, y, mkCell(cType(c), cOwner(c), cOrient(c), 1, cBombDiag(c)));
    else
        bSet(x, y, 0);
    pushCell(x, y);
}

// Trace a beam from weapon at (ox,oy). isStun => non-destructive (stun).
// Returns "king:owner" if a King was struck by a (non-stun) beam, else "".
string fireBeam(integer ox, integer oy, integer isStun) {
    integer startDir = cOrient(bGet(ox,oy));
    string path = (string)ox + "," + (string)oy;
    string result = "";
    list queue = [ox, oy, startDir];        // DFS: pop front, prepend
    list visited = [];
    integer maxSteps = 400;

    while (llGetListLength(queue) >= 3 && maxSteps > 0) {
        --maxSteps;
        integer cx = llList2Integer(queue,0);
        integer cy = llList2Integer(queue,1);
        integer cd = llList2Integer(queue,2);
        queue = llDeleteSubList(queue, 0, 2);

        integer nx = cx + dirDX(cd);
        integer ny = cy + dirDY(cd);
        if (!bOk(nx,ny)) jump nxt;

        string vkey = (string)nx+","+(string)ny+","+(string)cd;
        if (llListFindList(visited,[vkey]) >= 0) jump nxt;
        visited += [vkey];

        path += ";" + (string)nx + "," + (string)ny;
        string res = laserInteract(nx, ny, cd);

        if (res == "pass") {
            queue = [nx, ny, cd] + queue;
        } else if (llGetSubString(res,0,6) == "reflect") {
            integer rd = (integer)llGetSubString(res,8,-1);
            queue = [nx, ny, rd] + queue;
        } else if (llGetSubString(res,0,4) == "split") {
            list pp = llParseString2List(res,[":"],[]);
            integer d1 = (integer)llList2String(pp,1);
            integer d2 = (integer)llList2String(pp,2);
            queue = [nx, ny, d1, nx, ny, d2] + queue;
        } else if (res == "random") {
            integer rr = (integer)llFrand(8.0);
            queue = [nx, ny, rr] + queue;
        } else if (res == "hit") {
            applyHit(nx, ny, isStun);
        } else if (res == "king") {
            if (isStun) applyHit(nx, ny, 1);
            else result = "king:" + (string)cOwner(bGet(nx,ny));
        }
        // "absorb" -> beam ends here

        @nxt;
    }

    llMessageLinked(LINK_ALL_CHILDREN, LM_LASER_PATH, path, NULL_KEY);
    return result;
}

doFire() {
    integer t = cType(bGet(gSelX, gSelY));
    if (t != T_LASER && t != T_STUNNER) {
        setStatus("Only a Laser or Stunner can fire.");
        return;
    }
    integer isStun = (t == T_STUNNER);
    string res = fireBeam(gSelX, gSelY, isStun);

    if (!isStun && llGetSubString(res,0,3) == "king") {
        integer loser  = (integer)llGetSubString(res,5,-1);
        integer winner = (loser == P_RED) ? P_GREEN : P_RED;
        setStatus(playerName(winner) + " WINS! Touch the board to restart.");
        llMessageLinked(LINK_ALL_CHILDREN, LM_GAME_OVER, (string)winner, NULL_KEY);
        gState = GS_GAMEOVER;
        return;
    }
    spendActions(1);    // firing costs one action
}

// ============================================================
// INPUT
// ============================================================

// Execute a (possibly capturing) move. Stomping the enemy King wins.
doMove(integer fx, integer fy, integer tx, integer ty, integer cost) {
    integer captured = bGet(tx, ty);
    integer mv = bGet(fx, fy);
    bSet(tx, ty, mv);
    bSet(fx, fy, 0);
    pushCell(fx, fy);
    pushCell(tx, ty);
    if (cType(captured) == T_KING) {
        integer winner = cOwner(mv);
        setStatus(playerName(winner) + " WINS by capture! Touch the board to restart.");
        llMessageLinked(LINK_ALL_CHILDREN, LM_GAME_OVER, (string)winner, NULL_KEY);
        gState = GS_GAMEOVER;
        return;
    }
    spendActions(cost);
}

handleTouch(integer x, integer y) {
    if (gState == GS_GAMEOVER) {
        initBoard();
        gCurPlayer = P_RED; gActionsLeft = ACTIONS_PER_TURN;
        gState = GS_IDLE; gSelX = -1; gSelY = -1;
        clearHL(); broadcastBoard();
        announceTurn();
        return;
    }
    if (gAIEnabled && gCurPlayer == gAIPlayer) return;

    integer cell  = bGet(x, y);
    integer t     = cType(cell);
    integer owner = cOwner(cell);

    if (gState == GS_IDLE || gState == GS_SELECTED) {
        if (t != T_EMPTY && !isFeature(t) && owner == gCurPlayer) {
            gSelX = x; gSelY = y;
            gState = GS_SELECTED;
            clearHL();
            showDestinations();
            llMessageLinked(LINK_ALL_CHILDREN, LM_ACTION,
                "MENU:" + (string)x + "," + (string)y, NULL_KEY);
        }
    } else if (gState == GS_AWAIT_DST) {
        integer cost = moveCost(gSelX, gSelY, x, y, gActionsLeft);
        if (cost > 0) {
            doMove(gSelX, gSelY, x, y, cost);
        } else {
            gState = GS_SELECTED;
            clearHL();
            showDestinations();
        }
    }
}

handleAction(string action) {
    if (gSelX < 0 || gState == GS_GAMEOVER) return;
    integer c = bGet(gSelX, gSelY);

    if (action == "MOVE") {
        gState = GS_AWAIT_DST;
        clearHL();
        showDestinations();
        setStatus("Click a highlighted square. (diagonal = 2 actions)");

    } else if (action == "ROTATE_CW") {
        bSet(gSelX, gSelY,
            mkCell(cType(c), cOwner(c), (cOrient(c)+1)%8, cStun(c), cBombDiag(c)));
        pushCell(gSelX, gSelY);
        spendActions(1);

    } else if (action == "ROTATE_CCW") {
        bSet(gSelX, gSelY,
            mkCell(cType(c), cOwner(c), (cOrient(c)+7)%8, cStun(c), cBombDiag(c)));
        pushCell(gSelX, gSelY);
        spendActions(1);

    } else if (action == "FIRE") {
        doFire();

    } else if (action == "CANCEL") {
        gState = GS_IDLE;
        gSelX = -1; gSelY = -1;
        clearHL();
        announceTurn();
    }
}

// Apply a move from the AI (Phase 1 subset; FIRE deferred)
applyAIMove(string move) {
    list p = llParseString2List(move, [":"], []);
    string cmd = llList2String(p, 0);
    if (cmd == "FIRE") { return; } // Phase 2

    list xy = llParseString2List(llList2String(p,1), [","], []);
    integer ax = llList2Integer(xy,0);
    integer ay = llList2Integer(xy,1);
    integer c = bGet(ax, ay);

    if (cmd == "MOVE") {
        integer tx = llList2Integer(xy,2);
        integer ty = llList2Integer(xy,3);
        integer cost = moveCost(ax, ay, tx, ty, gActionsLeft);
        if (cost < 1) cost = 1;
        doMove(ax, ay, tx, ty, cost);
    } else if (cmd == "ROTATE_CW") {
        bSet(ax, ay, mkCell(cType(c),cOwner(c),(cOrient(c)+1)%8,cStun(c),cBombDiag(c)));
        pushCell(ax, ay);
        gSelX = ax; gSelY = ay;
        spendActions(1);
    } else if (cmd == "ROTATE_CCW") {
        bSet(ax, ay, mkCell(cType(c),cOwner(c),(cOrient(c)+7)%8,cStun(c),cBombDiag(c)));
        pushCell(ax, ay);
        gSelX = ax; gSelY = ay;
        spendActions(1);
    }
}

// ============================================================
default {
    state_entry() {
        gAIEnabled = FALSE;
        gAIPlayer  = P_GREEN;
        gCurPlayer = P_RED;
        gActionsLeft = ACTIONS_PER_TURN;
        gState = GS_IDLE;
        gSelX = -1; gSelY = -1;
        initBoard();
        llSleep(1.0);
        broadcastBoard();
        announceTurn();
    }

    touch_start(integer n) {
        vector st = llDetectedTouchST(0);
        integer bx = (integer)(st.x  * (float)BOARD_W);
        integer by = (integer)((1.0 - st.y) * (float)BOARD_H);
        if (bOk(bx, by)) handleTouch(bx, by);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        if (num == LM_PIECE_TOUCH) {
            list xy = llParseString2List(str, [","], []);
            handleTouch(llList2Integer(xy,0), llList2Integer(xy,1));
        } else if (num == LM_ACTION) {
            handleAction(str);
        } else if (num == LM_AI_RESPONSE) {
            if (gAIEnabled && gCurPlayer == gAIPlayer) applyAIMove(str);
        } else if (num == LM_CONFIG) {
            if (str == "AI_ON")        gAIEnabled = TRUE;
            else if (str == "AI_OFF")  gAIEnabled = FALSE;
            else if (str == "AI_RED")  gAIPlayer  = P_RED;
            else if (str == "AI_GREEN")gAIPlayer  = P_GREEN;
            else if (str == "RESET") {
                initBoard();
                gCurPlayer = P_RED; gActionsLeft = ACTIONS_PER_TURN;
                gState = GS_IDLE; gSelX = -1; gSelY = -1;
                clearHL(); broadcastBoard();
                announceTurn();
            }
        }
    }
}
