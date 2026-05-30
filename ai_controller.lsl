// ============================================================
// Advanced Laser Chess — AI Controller (separate, swappable)
// Place this script in any child prim of the board linkset.
// Enable/disable via LM_CONFIG "AI_ON" / "AI_OFF".
//
// This is a basic greedy AI:
//   1. If firing wins the game, fire.
//   2. If a rotation or move sets up an immediate win next action, do it.
//   3. Otherwise pick a random legal action (move or rotation).
//
// To replace this AI: remove this script and drop in a replacement
// that listens for LM_AI_REQUEST and sends LM_AI_RESPONSE.
// ============================================================

// Match game_controller.lsl
integer T_EMPTY   = 0;
integer T_LASER   = 1;
integer T_DEFLECT = 2;
integer T_DEFEND  = 3;
integer T_SWITCH  = 4;
integer T_KING    = 5;
integer T_SPLIT   = 6;
integer T_TELE    = 7;

integer BOARD_W = 15;
integer BOARD_H = 11;

integer LM_AI_REQUEST  = 20;
integer LM_AI_RESPONSE = 21;

// ---- Board helpers (local copy) ----
integer mkCell(integer t, integer o, integer r) { return t + o*10 + r*100; }
integer cType(integer c)   { return c % 10; }
integer cOwner(integer c)  { return (c/10) % 10; }
integer cOrient(integer c) { return (c/100) % 10; }

integer bIdx(integer x, integer y) { return y * BOARD_W + x; }
integer bGet(list board, integer x, integer y) { return llList2Integer(board, bIdx(x,y)); }
list bSet(list board, integer x, integer y, integer v) {
    return llListReplaceList(board, [v], bIdx(x,y), bIdx(x,y));
}
integer bOk(integer x, integer y) { return x>=0 && x<BOARD_W && y>=0 && y<BOARD_H; }

// ---- Direction utilities ----
integer dirDX(integer d) {
    if (d==1) return  1;
    if (d==3) return -1;
    return 0;
}
integer dirDY(integer d) {
    if (d==0) return -1;
    if (d==2) return  1;
    return 0;
}
integer oppDir(integer d) { return (d+2)%4; }

integer reflectDeflect(integer fromDir, integer orient) {
    if (orient==0 || orient==2) {
        if (fromDir==0) return 1;
        if (fromDir==1) return 0;
        if (fromDir==2) return 3;
        return 2;
    }
    if (fromDir==0) return 3;
    if (fromDir==3) return 0;
    if (fromDir==2) return 1;
    return 2;
}

// ---- Simulate laser, return "king:P" or "" ----
string simLaser(list board, integer player) {
    integer lx=-1; integer ly=-1;
    integer x; integer y;
    for (y=0; y<BOARD_H && lx<0; ++y)
        for (x=0; x<BOARD_W && lx<0; ++x) {
            integer c = bGet(board,x,y);
            if (cType(c)==T_LASER && cOwner(c)==player) { lx=x; ly=y; }
        }
    if (lx<0) return "";

    list queue = [lx, ly, cOrient(bGet(board,lx,ly))];
    list visited = [];
    integer maxSteps = 150;

    while (llGetListLength(queue)>=3 && maxSteps>0) {
        --maxSteps;
        integer cx   = llList2Integer(queue,0);
        integer cy   = llList2Integer(queue,1);
        integer cdir = llList2Integer(queue,2);
        queue = llDeleteSubList(queue,0,2);

        integer nx = cx + dirDX(cdir);
        integer ny = cy + dirDY(cdir);
        if (!bOk(nx,ny)) jump simskip;

        string key_ = (string)nx+","+(string)ny+","+(string)cdir;
        if (llListFindList(visited,[key_])>=0) jump simskip;
        visited += [key_];

        integer cell = bGet(board,nx,ny);
        integer t = cType(cell);
        integer o = cOrient(cell);

        if (t==T_EMPTY) { queue += [nx,ny,cdir]; jump simskip; }
        if (t==T_KING)  return "king:" + (string)cOwner(cell);
        if (t==T_LASER || t==T_TELE) jump simskip; // absorbed
        if (t==T_DEFLECT) {
            queue += [nx, ny, reflectDeflect(cdir, o)];
            jump simskip;
        }
        if (t==T_DEFEND) {
            integer mirrorFace = oppDir(o);
            if (cdir==mirrorFace) { queue += [nx,ny,reflectDeflect(cdir,o)]; jump simskip; }
            jump simskip; // destroyed or absorbed — either way beam stops
        }
        if (t==T_SWITCH) {
            integer nd;
            if (cdir==0||cdir==2) nd=reflectDeflect(cdir,0);
            else nd=reflectDeflect(cdir,1);
            queue += [nx,ny,nd];
            jump simskip;
        }
        if (t==T_SPLIT) {
            queue += [nx,ny,cdir, nx,ny,(cdir+1)%4];
            jump simskip;
        }
        @simskip;
    }
    return "";
}

// ---- Collect all pieces belonging to player ----
list playerPieces(list board, integer player) {
    list pieces = [];
    integer x; integer y;
    for (y=0; y<BOARD_H; ++y)
        for (x=0; x<BOARD_W; ++x) {
            integer c = bGet(board,x,y);
            if (cType(c)!=T_EMPTY && cOwner(c)==player) pieces += [x,y];
        }
    return pieces;
}

// ---- Build a list of all legal moves for player ----
// Each entry is a string "CMD:params" ready to send as AI_RESPONSE
list allMoves(list board, integer player) {
    list moves = [];
    list pieces = playerPieces(board, player);
    list dd = [0,-1,1,0,0,1,-1,0];
    integer i;
    for (i=0; i<llGetListLength(pieces); i+=2) {
        integer px = llList2Integer(pieces,i);
        integer py = llList2Integer(pieces,i+1);
        // Rotations are always legal
        moves += ["ROTATE_CW:"+(string)px+","+(string)py];
        moves += ["ROTATE_CCW:"+(string)px+","+(string)py];
        // Moves to adjacent empty cells
        integer j;
        for (j=0; j<8; j+=2) {
            integer nx = px+llList2Integer(dd,j);
            integer ny = py+llList2Integer(dd,j+1);
            if (bOk(nx,ny) && bGet(board,nx,ny)==T_EMPTY)
                moves += ["MOVE:"+(string)px+","+(string)py+","+(string)nx+","+(string)ny];
        }
    }
    // Fire is always an option
    moves += ["FIRE"];
    return moves;
}

// ---- Apply a move to a board copy, return modified board ----
list applyMove(list board, string move, integer player) {
    list p = llParseString2List(move,[":"],[]);
    string cmd = llList2String(p,0);
    if (cmd=="FIRE") return board; // fire doesn't change board for simulation

    list xy = llParseString2List(llList2String(p,1),[","],[]);
    integer ax = llList2Integer(xy,0);
    integer ay = llList2Integer(xy,1);

    if (cmd=="MOVE") {
        integer tx=llList2Integer(xy,2); integer ty=llList2Integer(xy,3);
        integer cv=bGet(board,ax,ay);
        board = bSet(board,tx,ty,cv);
        board = bSet(board,ax,ay,0);
    } else if (cmd=="ROTATE_CW") {
        integer c=bGet(board,ax,ay);
        board = bSet(board,ax,ay, mkCell(cType(c),cOwner(c),(cOrient(c)+1)%4));
    } else if (cmd=="ROTATE_CCW") {
        integer c=bGet(board,ax,ay);
        board = bSet(board,ax,ay, mkCell(cType(c),cOwner(c),(cOrient(c)+3)%4));
    }
    return board;
}

// ---- Choose AI move ----
// Returns an encoded move string ("FIRE", "MOVE:…", "ROTATE_CW:…", "ROTATE_CCW:…")
string chooseMove(list board, integer player, integer actionsLeft) {
    integer opponent = 1 - player;

    // Priority 1: if firing wins right now, fire.
    string fireRes = simLaser(board, player);
    if (llGetSubString(fireRes,0,3)=="king") {
        integer loser = (integer)llGetSubString(fireRes,5,-1);
        if (loser==opponent) return "FIRE";
    }

    // Priority 2: try every move; if it leads to a winning fire, do it.
    list moves = allMoves(board, player);
    integer i;
    for (i=0; i<llGetListLength(moves); ++i) {
        string mv = llList2String(moves,i);
        if (mv == "FIRE") jump skipFire;
        list sim = applyMove(board, mv, player);
        string res = simLaser(sim, player);
        if (llGetSubString(res,0,3)=="king") {
            integer loser = (integer)llGetSubString(res,5,-1);
            if (loser==opponent) return mv;
        }
        @skipFire;
    }

    // Priority 3: avoid moves that let opponent win on their fire.
    // Check current position first — if opponent can already fire-win, that's a
    // pre-existing threat we can't escape without more analysis; skip for now.

    // Priority 4: prefer moves; rotations are weaker positionally.
    // Pick a random non-FIRE move with preference for MOVE over ROTATE.
    list movesOnly = [];
    list rotatesOnly = [];
    for (i=0; i<llGetListLength(moves); ++i) {
        string mv = llList2String(moves,i);
        if (llGetSubString(mv,0,3)=="MOVE") movesOnly += [mv];
        else if (llGetSubString(mv,0,5)=="ROTATE") rotatesOnly += [mv];
    }

    if (llGetListLength(movesOnly) > 0)
        return llList2String(movesOnly, (integer)llFrand(llGetListLength(movesOnly)));
    if (llGetListLength(rotatesOnly) > 0)
        return llList2String(rotatesOnly, (integer)llFrand(llGetListLength(rotatesOnly)));

    return "FIRE"; // last resort
}

// ============================================================
// MAIN
// ============================================================
default {
    state_entry() {
        // Nothing to do until game controller sends a request
    }

    link_message(integer sender_num, integer num, string str, key id) {
        if (num != LM_AI_REQUEST) return;

        // Parse: "boardCSV|player|actionsLeft"
        list parts = llParseString2List(str, ["|"], []);
        list board  = llParseString2List(llList2String(parts,0), [","], []);
        integer player      = (integer)llList2String(parts,1);
        integer actionsLeft = (integer)llList2String(parts,2);

        // Convert string list to integer list
        list iBoard = [];
        integer i;
        for (i=0; i<llGetListLength(board); ++i)
            iBoard += [(integer)llList2String(board,i)];

        // Small delay so it doesn't feel instant
        llSleep(0.8 + llFrand(0.7));

        string move = chooseMove(iBoard, player, actionsLeft);
        llMessageLinked(LINK_ROOT, LM_AI_RESPONSE, move, NULL_KEY);

        // If the AI still has a second action and it just used its first,
        // the controller will call us again via a new LM_AI_REQUEST after endAction().
    }
}
