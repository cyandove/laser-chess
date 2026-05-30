// ============================================================
// Advanced Laser Chess — Game Controller
// Root prim of the board linkset.
// Child prims run piece.lsl; communicate via llMessageLinked.
// Board: 15 wide (x) × 11 tall (y), y=0 = north (Blue), y=10 = south (Red).
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;

// Piece types
integer T_EMPTY   = 0;
integer T_LASER   = 1;
integer T_DEFLECT = 2;
integer T_DEFEND  = 3;
integer T_SWITCH  = 4;
integer T_KING    = 5;
integer T_SPLIT   = 6;
integer T_TELE    = 7;

// Players
integer P_RED  = 0;
integer P_BLUE = 1;

// Orientations — direction piece's active/mirror face points
integer O_NORTH = 0;
integer O_EAST  = 1;
integer O_SOUTH = 2;
integer O_WEST  = 3;

// llMessageLinked num codes
integer LM_CELL_UPDATE = 1;  // str "x,y,cell"
integer LM_HIGHLIGHT   = 2;  // str "x,y,1" or "x,y,0"
integer LM_CLEAR_HL    = 3;
integer LM_LASER_PATH  = 4;  // str "x0,y0;x1,y1;…"
integer LM_GAME_OVER   = 5;  // str "0" or "1" (winner)
integer LM_STATUS      = 6;  // str status text
integer LM_PIECE_TOUCH = 10; // from child: str "x,y"
integer LM_ACTION      = 11; // from child: str action name
integer LM_AI_REQUEST  = 20; // to AI script: str board|player|actionsLeft
integer LM_AI_RESPONSE = 21; // from AI: str move encoding
integer LM_CONFIG      = 100;// str "RESET","AI_ON","AI_OFF","AI_PLAYER:0/1"

// Game FSM
integer GS_IDLE      = 0;
integer GS_SELECTED  = 1;
integer GS_AWAIT_DST = 2;
integer GS_GAMEOVER  = 3;

// ---- Global state ----
list    gBoard;
integer gCurPlayer;
integer gActionsLeft;
integer gState;
integer gSelX;
integer gSelY;
integer gAIEnabled;
integer gAIPlayer;

// ============================================================
// ENCODING  cell = type + owner*10 + orient*100
// ============================================================
integer mkCell(integer t, integer o, integer r) { return t + o*10 + r*100; }
integer cType(integer c)   { return c % 10; }
integer cOwner(integer c)  { return (c / 10) % 10; }
integer cOrient(integer c) { return (c / 100) % 10; }

// ============================================================
// BOARD ACCESS
// ============================================================
integer bIdx(integer x, integer y) { return y * BOARD_W + x; }
integer bGet(integer x, integer y) { return llList2Integer(gBoard, bIdx(x,y)); }
bSet(integer x, integer y, integer v) {
    gBoard = llListReplaceList(gBoard, [v], bIdx(x,y), bIdx(x,y));
}
integer bOk(integer x, integer y) { return x>=0 && x<BOARD_W && y>=0 && y<BOARD_H; }

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
// INITIAL BOARD LAYOUT
// Red  (P_RED=0)  — south, rows 9-10
// Blue (P_BLUE=1) — north, rows 0-1
// Symmetric across horizontal midline (y=5)
// Teleporter at centre (7,5)
// ============================================================
initBoard() {
    gBoard = [];
    integer i;
    for (i=0; i<BOARD_W*BOARD_H; ++i) gBoard += [0];

    // Red — south
    bSet( 0,10, mkCell(T_LASER,  P_RED, O_NORTH));
    bSet( 7,10, mkCell(T_KING,   P_RED, O_NORTH));
    bSet( 2,10, mkCell(T_DEFLECT,P_RED, O_NORTH));
    bSet( 4,10, mkCell(T_DEFLECT,P_RED, O_EAST ));
    bSet(10,10, mkCell(T_DEFLECT,P_RED, O_NORTH));
    bSet(12,10, mkCell(T_DEFLECT,P_RED, O_WEST ));
    bSet( 5,10, mkCell(T_DEFEND, P_RED, O_NORTH));
    bSet( 9,10, mkCell(T_DEFEND, P_RED, O_NORTH));
    bSet( 3, 9, mkCell(T_DEFLECT,P_RED, O_EAST ));
    bSet(11, 9, mkCell(T_DEFLECT,P_RED, O_WEST ));
    bSet( 6, 9, mkCell(T_SWITCH, P_RED, O_NORTH));
    bSet( 8, 9, mkCell(T_SWITCH, P_RED, O_NORTH));
    bSet( 7, 9, mkCell(T_SPLIT,  P_RED, O_NORTH));

    // Blue — north (mirrored)
    bSet(14, 0, mkCell(T_LASER,  P_BLUE, O_SOUTH));
    bSet( 7, 0, mkCell(T_KING,   P_BLUE, O_SOUTH));
    bSet(12, 0, mkCell(T_DEFLECT,P_BLUE, O_SOUTH));
    bSet(10, 0, mkCell(T_DEFLECT,P_BLUE, O_WEST ));
    bSet( 4, 0, mkCell(T_DEFLECT,P_BLUE, O_SOUTH));
    bSet( 2, 0, mkCell(T_DEFLECT,P_BLUE, O_EAST ));
    bSet( 5, 0, mkCell(T_DEFEND, P_BLUE, O_SOUTH));
    bSet( 9, 0, mkCell(T_DEFEND, P_BLUE, O_SOUTH));
    bSet(11, 1, mkCell(T_DEFLECT,P_BLUE, O_WEST ));
    bSet( 3, 1, mkCell(T_DEFLECT,P_BLUE, O_EAST ));
    bSet( 6, 1, mkCell(T_SWITCH, P_BLUE, O_SOUTH));
    bSet( 8, 1, mkCell(T_SWITCH, P_BLUE, O_SOUTH));
    bSet( 7, 1, mkCell(T_SPLIT,  P_BLUE, O_SOUTH));

    // Neutral teleporter at centre
    bSet(7, 5, mkCell(T_TELE, P_RED, O_NORTH));
}

// ============================================================
// DIRECTION UTILITIES
// ============================================================
integer dirDX(integer d) {
    if (d==O_EAST)  return  1;
    if (d==O_WEST)  return -1;
    return 0;
}
integer dirDY(integer d) {
    if (d==O_NORTH) return -1;
    if (d==O_SOUTH) return  1;
    return 0;
}
integer oppDir(integer d) { return (d+2)%4; }

// Deflector "/" reflection (orient N or S) or "\" (orient E or W)
integer reflectDeflect(integer fromDir, integer orient) {
    if (orient==O_NORTH || orient==O_SOUTH) {
        // "/" mirror: N↔E, S↔W
        if (fromDir==O_NORTH) return O_EAST;
        if (fromDir==O_EAST)  return O_NORTH;
        if (fromDir==O_SOUTH) return O_WEST;
        return O_SOUTH;
    }
    // "\" mirror: N↔W, S↔E
    if (fromDir==O_NORTH) return O_WEST;
    if (fromDir==O_WEST)  return O_NORTH;
    if (fromDir==O_SOUTH) return O_EAST;
    return O_SOUTH;
}

// ============================================================
// LASER INTERACTION
// Returns encoded result string:
//   "pass"            — empty cell (beam continues same dir)
//   "reflect:D"       — beam turns to direction D
//   "split:D1:D2"     — beam forks into D1 and D2
//   "absorb"          — beam stops, piece survives
//   "destroy:x,y"     — piece removed, beam stops
//   "king:P"          — king of player P hit → game over
// ============================================================
string laserInteract(integer x, integer y, integer fromDir) {
    integer cell = bGet(x, y);
    integer t = cType(cell);
    integer o = cOrient(cell);

    if (t == T_EMPTY) return "pass";

    if (t == T_KING)   return "king:" + (string)cOwner(cell);
    if (t == T_LASER)  return "destroy:" + (string)x + "," + (string)y;
    if (t == T_TELE)   return "absorb"; // beam absorbed by teleporter

    if (t == T_DEFLECT) return "reflect:" + (string)reflectDeflect(fromDir, o);

    if (t == T_DEFEND) {
        // Mirror face on side opposite to orient (the "back").
        // Hit back face → reflect. Hit front face → destroy. Sides → absorb.
        integer mirrorFace = oppDir(o);
        if (fromDir == mirrorFace) return "reflect:" + (string)reflectDeflect(fromDir, o);
        if (fromDir == o)          return "destroy:" + (string)x + "," + (string)y;
        return "absorb";
    }

    if (t == T_SWITCH) {
        // Double mirror: always reflects. Uses "/" when fromDir is N or S, "\" otherwise.
        integer newDir;
        if (fromDir==O_NORTH || fromDir==O_SOUTH)
            newDir = reflectDeflect(fromDir, O_NORTH); // "/"
        else
            newDir = reflectDeflect(fromDir, O_EAST);  // "\"
        return "reflect:" + (string)newDir;
    }

    if (t == T_SPLIT) {
        // Passes straight through AND deflects 90° CW
        integer deflected = (fromDir+1)%4;
        return "split:" + (string)fromDir + ":" + (string)deflected;
    }

    return "absorb";
}

// ============================================================
// LASER TRACE
// Fires the current player's laser, handles all interactions.
// Returns "" on no capture, "king:P" on king hit.
// ============================================================
string fireLaser(integer player) {
    // Locate laser
    integer lx = -1; integer ly = -1;
    integer x; integer y;
    for (y=0; y<BOARD_H && lx<0; ++y)
        for (x=0; x<BOARD_W && lx<0; ++x) {
            integer c = bGet(x,y);
            if (cType(c)==T_LASER && cOwner(c)==player) { lx=x; ly=y; }
        }
    if (lx < 0) return "";

    string path = (string)lx+","+(string)ly;
    string gameResult = "";

    // Queue: groups of 3 ints [x, y, dir, …]
    // Seeded with the laser's initial shot direction
    list queue = [lx, ly, cOrient(bGet(lx,ly))];
    list visited = [];
    integer maxSteps = 200; // guard against infinite loops

    while (llGetListLength(queue) >= 3 && maxSteps > 0) {
        --maxSteps;
        integer cx   = llList2Integer(queue, 0);
        integer cy   = llList2Integer(queue, 1);
        integer cdir = llList2Integer(queue, 2);
        queue = llDeleteSubList(queue, 0, 2);

        integer nx = cx + dirDX(cdir);
        integer ny = cy + dirDY(cdir);

        if (!bOk(nx, ny)) jump skip; // exits board

        // Cycle guard
        string key_ = (string)nx+","+(string)ny+","+(string)cdir;
        if (llListFindList(visited, [key_]) >= 0) jump skip;
        visited += [key_];

        path = path + ";" + (string)nx + "," + (string)ny;
        string res = laserInteract(nx, ny, cdir);

        if (res == "pass") {
            queue += [nx, ny, cdir];
        } else if (llGetSubString(res,0,6) == "reflect") {
            integer nd = (integer)llGetSubString(res,8,-1);
            queue += [nx, ny, nd];
        } else if (llGetSubString(res,0,4) == "split") {
            list p = llParseString2List(res,[":"],[]);
            integer d1 = (integer)llList2String(p,1);
            integer d2 = (integer)llList2String(p,2);
            queue += [nx, ny, d1, nx, ny, d2];
        } else if (llGetSubString(res,0,6) == "destroy") {
            list p = llParseString2List(res,[":"],[]);
            list xy = llParseString2List(llList2String(p,1),[","],[]);
            integer dx_ = llList2Integer(xy,0);
            integer dy_ = llList2Integer(xy,1);
            bSet(dx_, dy_, 0);
            pushCell(dx_, dy_);
        } else if (llGetSubString(res,0,3) == "king") {
            gameResult = res; // "king:P"
        }
        // "absorb" → beam ends here, do nothing

        @skip;
    }

    llMessageLinked(LINK_ALL_CHILDREN, LM_LASER_PATH, path, NULL_KEY);
    return gameResult;
}

// ============================================================
// VALID MOVES  (orthogonal adjacency, must land on empty cell)
// ============================================================
list validMoves(integer x, integer y) {
    list moves = [];
    list dd = [0,-1, 1,0, 0,1, -1,0];
    integer i;
    for (i=0; i<8; i+=2) {
        integer nx = x + llList2Integer(dd,i);
        integer ny = y + llList2Integer(dd,i+1);
        if (bOk(nx,ny) && bGet(nx,ny)==0) moves += [nx,ny];
    }
    return moves;
}

// ============================================================
// TURN MANAGEMENT
// ============================================================
string playerName(integer p) { if (p==P_RED) return "Red"; return "Blue"; }

endAction() {
    --gActionsLeft;
    clearHL();
    gState = GS_IDLE;
    gSelX = -1; gSelY = -1;
    if (gActionsLeft <= 0) {
        gCurPlayer = 1 - gCurPlayer;
        gActionsLeft = 2;
        setStatus(playerName(gCurPlayer) + "'s turn — 2 actions left.");
        if (gAIEnabled && gCurPlayer == gAIPlayer) {
            // Encode board state and send to AI
            string boardEnc = llDumpList2String(gBoard, ",");
            llMessageLinked(LINK_ALL_CHILDREN, LM_AI_REQUEST,
                boardEnc + "|" + (string)gCurPlayer + "|" + (string)gActionsLeft, NULL_KEY);
        }
    } else {
        setStatus(playerName(gCurPlayer) + "'s turn — "
            + (string)gActionsLeft + " action left.");
    }
}

doFire() {
    string res = fireLaser(gCurPlayer);
    if (llGetSubString(res,0,3) == "king") {
        integer loser = (integer)llGetSubString(res,5,-1);
        integer winner = 1 - loser;
        setStatus(playerName(winner) + " WINS! Touch board to restart.");
        llMessageLinked(LINK_ALL_CHILDREN, LM_GAME_OVER, (string)winner, NULL_KEY);
        gState = GS_GAMEOVER;
    } else {
        endAction();
    }
}

// ============================================================
// INPUT HANDLING
// ============================================================
handleTouch(integer x, integer y) {
    if (gState == GS_GAMEOVER) {
        // Any touch restarts
        initBoard();
        gCurPlayer = P_RED; gActionsLeft = 2; gState = GS_IDLE;
        gSelX = -1; gSelY = -1;
        clearHL(); broadcastBoard();
        setStatus("Red's turn — 2 actions left.");
        return;
    }
    if (gAIEnabled && gCurPlayer == gAIPlayer) return;

    integer cell  = bGet(x, y);
    integer t     = cType(cell);
    integer owner = cOwner(cell);

    if (gState == GS_IDLE || gState == GS_SELECTED) {
        if (t != T_EMPTY && owner == gCurPlayer) {
            gSelX = x; gSelY = y;
            gState = GS_SELECTED;
            clearHL();
            // Highlight valid move destinations
            list moves = validMoves(x, y);
            integer i;
            for (i=0; i<llGetListLength(moves); i+=2)
                hlCell(llList2Integer(moves,i), llList2Integer(moves,i+1), 1);
            // Show action dialog via child prims (they'll llDialog to nearest agent)
            llMessageLinked(LINK_ALL_CHILDREN, LM_ACTION,
                "MENU:" + (string)x + "," + (string)y, NULL_KEY);
        }

    } else if (gState == GS_AWAIT_DST) {
        if (t == T_EMPTY && llAbs(x-gSelX)+llAbs(y-gSelY)==1) {
            integer mv = bGet(gSelX, gSelY);
            bSet(x, y, mv);  bSet(gSelX, gSelY, 0);
            pushCell(gSelX, gSelY); pushCell(x, y);
            endAction();
        } else {
            // Cancel move, return to selected state
            gState = GS_SELECTED;
            clearHL();
        }
    }
}

handleAction(string action) {
    if (gSelX < 0 || gState == GS_GAMEOVER) return;

    if (action == "MOVE") {
        gState = GS_AWAIT_DST;
        list moves = validMoves(gSelX, gSelY);
        integer i;
        for (i=0; i<llGetListLength(moves); i+=2)
            hlCell(llList2Integer(moves,i), llList2Integer(moves,i+1), 1);
        setStatus("Click destination square.");

    } else if (action == "ROTATE_CW") {
        integer c = bGet(gSelX, gSelY);
        bSet(gSelX, gSelY, mkCell(cType(c), cOwner(c), (cOrient(c)+1)%4));
        pushCell(gSelX, gSelY);
        endAction();

    } else if (action == "ROTATE_CCW") {
        integer c = bGet(gSelX, gSelY);
        bSet(gSelX, gSelY, mkCell(cType(c), cOwner(c), (cOrient(c)+3)%4));
        pushCell(gSelX, gSelY);
        endAction();

    } else if (action == "FIRE") {
        doFire();

    } else if (action == "CANCEL") {
        gState = GS_IDLE;
        gSelX = -1; gSelY = -1;
        clearHL();
        setStatus(playerName(gCurPlayer) + "'s turn — "
            + (string)gActionsLeft + " actions left.");
    }
}

// Apply a move sent by the AI script
applyAIMove(string move) {
    // Format: "MOVE:fx,fy,tx,ty" | "ROTATE_CW:x,y" | "ROTATE_CCW:x,y" | "FIRE"
    list p = llParseString2List(move,[":"],[]);
    string cmd = llList2String(p,0);

    if (cmd == "FIRE") { doFire(); return; }

    list xy = llParseString2List(llList2String(p,1),[","],[]);
    integer ax = llList2Integer(xy,0);
    integer ay = llList2Integer(xy,1);

    if (cmd == "MOVE") {
        integer tx = llList2Integer(xy,2);
        integer ty = llList2Integer(xy,3);
        integer cv = bGet(ax,ay);
        bSet(tx,ty,cv); bSet(ax,ay,0);
        pushCell(ax,ay); pushCell(tx,ty);
    } else if (cmd == "ROTATE_CW") {
        integer c = bGet(ax,ay);
        bSet(ax,ay, mkCell(cType(c),cOwner(c),(cOrient(c)+1)%4));
        pushCell(ax,ay);
    } else if (cmd == "ROTATE_CCW") {
        integer c = bGet(ax,ay);
        bSet(ax,ay, mkCell(cType(c),cOwner(c),(cOrient(c)+3)%4));
        pushCell(ax,ay);
    }
    endAction();
}

// ============================================================
// ENTRY POINT
// ============================================================
default {
    state_entry() {
        gAIEnabled = FALSE;
        gAIPlayer  = P_BLUE;
        gCurPlayer = P_RED;
        gActionsLeft = 2;
        gState = GS_IDLE;
        gSelX = -1; gSelY = -1;
        initBoard();
        llSleep(1.0); // allow child prims to initialise
        broadcastBoard();
        setStatus("Red's turn — 2 actions left. Touch a piece to select.");
    }

    touch_start(integer n) {
        // Map touch UV → board cell
        vector st = llDetectedTouchST(0);
        integer bx = (integer)(st.x  * (float)BOARD_W);
        integer by = (integer)((1.0 - st.y) * (float)BOARD_H);
        if (bOk(bx, by)) handleTouch(bx, by);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        if (num == LM_PIECE_TOUCH) {
            list xy = llParseString2List(str,[","],[]);
            handleTouch(llList2Integer(xy,0), llList2Integer(xy,1));

        } else if (num == LM_ACTION) {
            handleAction(str);

        } else if (num == LM_AI_RESPONSE) {
            if (gAIEnabled && gCurPlayer == gAIPlayer)
                applyAIMove(str);

        } else if (num == LM_CONFIG) {
            if (str == "AI_ON")         gAIEnabled = TRUE;
            else if (str == "AI_OFF")   gAIEnabled = FALSE;
            else if (str == "AI_RED")   gAIPlayer  = P_RED;
            else if (str == "AI_BLUE")  gAIPlayer  = P_BLUE;
            else if (str == "RESET") {
                initBoard();
                gCurPlayer = P_RED; gActionsLeft = 2;
                gState = GS_IDLE; gSelX = -1; gSelY = -1;
                clearHL(); broadcastBoard();
                setStatus("Red's turn — 2 actions left.");
            }
        }
    }
}
