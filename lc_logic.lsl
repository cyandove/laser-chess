// ============================================================
// Advanced Laser Chess — Logic Helper  (root script)
// Lives in the ROOT prim with game_controller.lsl + board_renderer.lsl.
//
// game_controller.lsl is near the 64 KB Mono limit, so the two heaviest pure
// computations live here instead, each a request/response over link messages:
//   * LM_BUILD_BOARD -> LM_BOARD_DATA  : build the starting position (CSV)
//   * LM_TRACE       -> LM_TRACE_RESULT: trace a laser/stunner shot
// Neither mutates game state; the controller applies the results.
//
// Encoding must match game_controller.lsl:
//   cell = type + owner*100 + orient*1000 + stun*10000 + bombDiag*100000
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;

integer T_EMPTY     = 0;
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

list DDX = [ 0, 1, 1, 1, 0,-1,-1,-1];
list DDY = [-1,-1, 0, 1, 1, 1, 0,-1];

integer LM_BUILD_BOARD  = 16;  // -> build the starting board (reply LM_BOARD_DATA)
integer LM_BOARD_DATA   = 17;  // reply: the board CSV
integer LM_TRACE        = 18;  // -> trace a shot "boardCSV|ox|oy|isStun"
integer LM_TRACE_RESULT = 19;  // reply: "beamCells|pendingFx|pendingKing"

list gB;                 // working board (ints when building; strings when tracing — bGet casts)
list gBeamCells;
list gPendingFx;
string gPendingKing;
integer gFireIsStun;

integer mkCell(integer t, integer ownr, integer o, integer stun, integer bombDiag) {
    return t + ownr*100 + o*1000 + stun*10000 + bombDiag*100000;
}
integer bGet(integer x, integer y) { return llList2Integer(gB, y*BOARD_W + x); }
bSet(integer x, integer y, integer v) {
    integer i = y * BOARD_W + x;
    gB = llListReplaceList(gB, [v], i, i);
}
integer bOk(integer x, integer y) { return x>=0 && x<BOARD_W && y>=0 && y<BOARD_H; }

integer cType(integer c)   { return c % 100; }
integer cOwner(integer c)  { return (c / 100) % 10; }
integer cOrient(integer c) { return (c / 1000) % 10; }
integer cBombDiag(integer c){ return (c / 100000) % 10; }

integer dirDX(integer o) { return llList2Integer(DDX, o); }
integer dirDY(integer o) { return llList2Integer(DDY, o); }

// ---- beam geometry ----
integer dirFromVec(integer dx, integer dy) {
    integer i;
    for (i=0; i<8; ++i)
        if (llList2Integer(DDX,i)==dx && llList2Integer(DDY,i)==dy) return i;
    return -1;
}
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
list perpDirs(integer d) { return [(d+2)%8, (d+6)%8]; }
integer inShieldArc(integer face, integer o) {
    return (face==o || face==(o+1)%8 || face==(o+7)%8);
}

// What happens when a beam travelling 'd' enters cell (x,y)?
// pass | absorb | random | hit | king | reflect:D | split:D1:D2 | bomb:C
string laserInteract(integer x, integer y, integer d) {
    integer cell = bGet(x,y);
    integer t = cType(cell);
    integer o = cOrient(cell);

    if (t == T_EMPTY)                       return "pass";
    if (t == T_HOLE || t == T_HYPERHOLE)    return "absorb";
    if (t == T_HYPERGON)                    return "random";
    if (t == T_KING)                        return "king";
    if (t == T_LASER || t == T_STUNNER) return "hit";
    if (t == T_BOMB) {
        integer dDiag = (d % 2);            // 1 if the beam travels diagonally
        integer detonate;
        if (cBombDiag(cell)) detonate = dDiag;
        else                 detonate = (1 - dDiag);
        if (detonate) return "bomb:1";
        return "bomb:0";
    }
    if (t == T_FOCT)                        return "reflect:" + (string)((d+4)%8);

    if (t == T_POCT) {
        integer face = (d+4)%8;
        if (inShieldArc(face, o)) return "reflect:" + (string)((d+4)%8);
        return "hit";
    }
    if (t == T_ONEWAY) {
        integer dt = dotDir(d, o);
        if (dt > 0) return "pass";
        if (dt < 0) return "reflect:" + (string)reflectOff(d, o);
        return "hit";
    }
    if (t == T_SPLITTER) {
        if (d == (o+4)%8) {
            list pc = perpDirs(d);
            return "split:" + (string)llList2Integer(pc,0)
                       + ":" + (string)llList2Integer(pc,1);
        }
        if (d == o) return "hit";
        return "pass";
    }
    if (t == T_TRIMIR) {
        integer dt = dotDir(d, o);
        if (dt == 0) return "pass";
        if (dt > 0)  return "hit";
        return "reflect:" + (string)reflectOff(d, o);
    }
    return "absorb";
}

addFx(integer x, integer y) {
    string cellKey = (string)x + "," + (string)y;
    if (llListFindList(gPendingFx, [cellKey]) < 0) gPendingFx += [cellKey];
}
queueBomb(integer x, integer y, integer center) {
    if (center) {
        integer o;
        for (o=0; o<8; ++o) {
            integer nx = x + dirDX(o);
            integer ny = y + dirDY(o);
            if (bOk(nx,ny)) {
                integer nt = cType(bGet(nx,ny));
                if (nt != T_EMPTY && nt != T_HOLE && nt != T_HYPERHOLE) {
                    if (!gFireIsStun && nt == T_KING)
                        gPendingKing = "king:" + (string)cOwner(bGet(nx,ny));
                    addFx(nx, ny);
                }
            }
        }
        if (!gFireIsStun) addFx(x, y);
    } else {
        addFx(x, y);
    }
}

// Trace a beam from weapon at (ox,oy); fills gBeamCells / gPendingFx / gPendingKing.
traceBeam(integer ox, integer oy, integer isStun) {
    gBeamCells   = [(string)ox + "," + (string)oy];
    gPendingFx   = [];
    gPendingKing = "";
    gFireIsStun  = isStun;

    integer startDir = cOrient(bGet(ox,oy));
    list queue = [ox, oy, startDir];
    list visited = [];
    integer maxSteps = 256;

    while (llGetListLength(queue) >= 3 && maxSteps > 0) {
        --maxSteps;
        integer cx = llList2Integer(queue,0);
        integer cy = llList2Integer(queue,1);
        integer cd = llList2Integer(queue,2);
        queue = llDeleteSubList(queue, 0, 2);

        integer nx = cx + dirDX(cd);
        integer ny = cy + dirDY(cd);
        if (!bOk(nx,ny)) jump nxt;

        integer vkey = (ny*BOARD_W + nx)*8 + cd;
        if (llListFindList(visited,[vkey]) >= 0) jump nxt;
        visited += [vkey];

        gBeamCells += [(string)nx + "," + (string)ny];
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
            addFx(nx, ny);
        } else if (llGetSubString(res,0,3) == "bomb") {
            queueBomb(nx, ny, (integer)llGetSubString(res,5,-1));
        } else if (res == "king") {
            addFx(nx, ny);
            if (!isStun) gPendingKing = "king:" + (string)cOwner(bGet(nx,ny));
        }
        @nxt;
    }
}

// ---- starting position ----
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

    placePair(0, 0,  T_ONEWAY,   2, 0);
    placePair(0, 1,  T_TRIMIR,   2, 0);
    placePair(0, 2,  T_BOMB,     0, 0);
    placePair(0, 3,  T_STUNNER,  6, 0);
    placePair(0, 4,  T_LASER,    2, 0);
    placePair(0, 5,  T_KING,     0, 0);
    placePair(0, 6,  T_LASER,    2, 0);
    placePair(0, 7,  T_STUNNER,  6, 0);
    placePair(0, 8,  T_BOMB,     0, 0);
    placePair(0, 9,  T_TRIMIR,   2, 0);
    placePair(0, 10, T_ONEWAY,   2, 0);

    placePair(1, 0,  T_TRIMIR,   3, 0);
    placePair(1, 1,  T_TRIMIR,   0, 0);
    placePair(1, 2,  T_ONEWAY,   2, 0);
    placePair(1, 3,  T_HYPERGON, 0, 0);
    placePair(1, 4,  T_SPLITTER, 6, 0);
    placePair(1, 5,  T_STUNNER,  6, 0);
    placePair(1, 6,  T_SPLITTER, 6, 0);
    placePair(1, 7,  T_HYPERGON, 0, 0);
    placePair(1, 8,  T_ONEWAY,   2, 0);
    placePair(1, 9,  T_TRIMIR,   4, 0);
    placePair(1, 10, T_TRIMIR,   1, 0);

    placePair(2, 3,  T_POCT,     2, 0);
    placePair(2, 4,  T_POCT,     2, 0);
    placePair(2, 5,  T_FOCT,     0, 0);
    placePair(2, 6,  T_POCT,     2, 0);
    placePair(2, 7,  T_POCT,     2, 0);

    neutral(7, 1, T_HOLE);
    neutral(7, 3, T_HOLE);
    neutral(7, 5, T_HYPERHOLE);
    neutral(7, 7, T_HOLE);
    neutral(7, 9, T_HOLE);
}

default {
    link_message(integer sender, integer num, string str, key id) {
        if (num == LM_BUILD_BOARD) {
            buildBoard();
            llMessageLinked(LINK_ROOT, LM_BOARD_DATA, llDumpList2String(gB, ","), NULL_KEY);
            gB = [];
            return;
        }
        if (num == LM_TRACE) {
            list p = llParseStringKeepNulls(str, ["|"], []);
            gB = llParseString2List(llList2String(p,0), [","], []);  // board (strings; bGet casts)
            traceBeam(llList2Integer(p,1), llList2Integer(p,2), llList2Integer(p,3));
            llMessageLinked(LINK_ROOT, LM_TRACE_RESULT,
                llDumpList2String(gBeamCells, ";") + "|"
                + llDumpList2String(gPendingFx, ";") + "|"
                + gPendingKing, NULL_KEY);
            gB = []; gBeamCells = []; gPendingFx = [];
            return;
        }
    }
}
