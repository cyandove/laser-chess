// ============================================================
// Advanced Laser Chess — AI Controller (separate, swappable)
// Drop into any child prim of the board linkset. Enable via the CONFIG
// channel ("AI_ON" / "AI_GREEN" etc. — see game_controller.lsl).
//
// Protocol (one action per request):
//   Receives LM_AI_REQUEST (num 20):
//     "boardCSV | player | actionsLeft | firedCSV | capturedCSV"
//   Replies LM_AI_RESPONSE (num 21) with ONE of:
//     "FIRE:x,y" | "MOVE:fx,fy,tx,ty" | "ROTATE_CW:x,y"
//     "ROTATE_CCW:x,y" | "PASS"
//   The controller applies it (spending actions) and re-requests until
//   the AI's turn ends.
//
// This is a greedy baseline: take a winning shot, else the best
// destroying/stunning shot, else a capture, else advance toward the
// enemy King, else rotate. Replace this script to drop in a stronger AI
// that speaks the same protocol.
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;

// types
integer T_EMPTY=0; integer T_KING=1; integer T_LASER=2; integer T_STUNNER=3;
integer T_ONEWAY=4; integer T_TRIMIR=5; integer T_BOMB=6; integer T_HYPERGON=7;
integer T_SPLITTER=8; integer T_POCT=9; integer T_FOCT=10; integer T_HOLE=11;
integer T_HYPERHOLE=12;

integer LM_AI_REQUEST  = 20;
integer LM_AI_RESPONSE = 21;
integer LM_CONFIG      = 100;

integer P_RED   = 1;
integer P_GREEN = 2;

// mode acknowledgement (floating text over this prim)
integer gEnabled = FALSE;
integer gSide    = 2;   // P_GREEN by default

showMode() {
    if (!gEnabled) { llSetText("AI: OFF (2-player)", <0.65,0.65,0.65>, 1.0); return; }
    if (gSide == P_RED) llSetText("AI: ON — playing Red", <1.0,0.35,0.35>, 1.0);
    else                llSetText("AI: ON — playing Green", <0.35,1.0,0.4>, 1.0);
}

list DDX = [ 0, 1, 1, 1, 0,-1,-1,-1];
list DDY = [-1,-1, 0, 1, 1, 1, 0,-1];

integer WIN_SCORE  =  1000000;
integer LOSE_SCORE = -1000000;

// ---- decode (must match game_controller.lsl) ----
integer cType(integer c)   { return c % 100; }
integer cOwner(integer c)  { return (c / 100) % 10; }
integer cOrient(integer c) { return (c / 1000) % 10; }
integer cStun(integer c)   { return (c / 10000) % 10; }

integer bOk(integer x, integer y) { return x>=0 && x<BOARD_W && y>=0 && y<BOARD_H; }
integer dirDX(integer o) { return llList2Integer(DDX, o); }
integer dirDY(integer o) { return llList2Integer(DDY, o); }
integer iabs(integer a) { if (a<0) return -a; return a; }

integer bGetL(list b, integer x, integer y) { return llList2Integer(b, y*BOARD_W + x); }
list    bSetL(list b, integer x, integer y, integer v) {
    integer i = y*BOARD_W + x;
    return llListReplaceList(b, [v], i, i);
}

integer pieceValue(integer t) {
    if (t==T_KING)     return 1000;
    if (t==T_LASER)    return 50;
    if (t==T_STUNNER)  return 40;
    if (t==T_BOMB)     return 35;
    if (t==T_FOCT)     return 30;
    if (t==T_POCT)     return 28;
    if (t==T_HYPERGON) return 25;
    if (t==T_SPLITTER) return 20;
    if (t==T_ONEWAY)   return 12;
    if (t==T_TRIMIR)   return 10;
    return 0;
}

// ---- beam math (ported, deterministic subset) ----
integer dirFromVec(integer dx, integer dy) {
    integer i;
    for (i=0; i<8; ++i)
        if (llList2Integer(DDX,i)==dx && llList2Integer(DDY,i)==dy) return i;
    return -1;
}
integer reflectOff(integer d, integer nrm) {
    integer vx=dirDX(d); integer vy=dirDY(d);
    integer nx=dirDX(nrm); integer ny=dirDY(nrm);
    integer dot = vx*nx + vy*ny;
    integer nn  = nx*nx + ny*ny;
    integer f   = (2*dot) / nn;
    return dirFromVec(vx - f*nx, vy - f*ny);
}
integer dotDir(integer d, integer nrm) {
    return dirDX(d)*dirDX(nrm) + dirDY(d)*dirDY(nrm);
}

// What a beam travelling 'd' does at (x,y) of board b. Hypergon/bomb are
// treated conservatively (absorb / plain hit) since the AI can't predict them.
string interact(list b, integer x, integer y, integer d) {
    integer cell = bGetL(b,x,y);
    integer t = cType(cell);
    integer o = cOrient(cell);
    if (t==T_EMPTY)                       return "pass";
    if (t==T_HOLE || t==T_HYPERHOLE)      return "absorb";
    if (t==T_HYPERGON)                    return "absorb";
    if (t==T_KING)                        return "king";
    if (t==T_LASER || t==T_STUNNER)       return "hit";
    if (t==T_BOMB)                        return "hit";
    if (t==T_FOCT)                        return "reflect:" + (string)((d+4)%8);
    if (t==T_POCT) {
        integer face=(d+4)%8;
        if (face==o || face==(o+1)%8 || face==(o+7)%8) return "reflect:" + (string)((d+4)%8);
        return "hit";
    }
    if (t==T_ONEWAY) {
        integer dt=dotDir(d,o);
        if (dt>0) return "pass";
        if (dt<0) return "reflect:" + (string)reflectOff(d,o);
        return "hit";
    }
    if (t==T_SPLITTER) {
        if (d==(o+4)%8) return "split:" + (string)((d+2)%8) + ":" + (string)((d+6)%8);
        if (d==o) return "hit";
        return "pass";
    }
    if (t==T_TRIMIR) {
        integer dt=dotDir(d,o);
        if (dt==0) return "pass";
        if (dt>0)  return "hit";
        return "reflect:" + (string)reflectOff(d,o);
    }
    return "absorb";
}

// Score firing the weapon at (wx,wy). WIN_SCORE if it kills the enemy King,
// LOSE_SCORE if it would kill our own King; otherwise net value of enemy
// pieces affected minus our own.
integer simShot(list board, integer wx, integer wy, integer isStun, integer player) {
    integer opp = 3 - player;
    integer score = 0;
    list b = board;
    list queue = [wx, wy, cOrient(bGetL(b,wx,wy))];
    list visited = [];
    integer steps = 300;

    while (llGetListLength(queue) >= 3 && steps > 0) {
        --steps;
        integer cx = llList2Integer(queue,0);
        integer cy = llList2Integer(queue,1);
        integer cd = llList2Integer(queue,2);
        queue = llDeleteSubList(queue,0,2);
        integer nx = cx + dirDX(cd);
        integer ny = cy + dirDY(cd);
        if (!bOk(nx,ny)) jump cont;
        string vkey = (string)nx+","+(string)ny+","+(string)cd;
        if (llListFindList(visited,[vkey])>=0) jump cont;
        visited += [vkey];

        string res = interact(b, nx, ny, cd);
        if (res == "pass") {
            queue = [nx,ny,cd] + queue;
        } else if (llGetSubString(res,0,6) == "reflect") {
            queue = [nx,ny,(integer)llGetSubString(res,8,-1)] + queue;
        } else if (llGetSubString(res,0,4) == "split") {
            list pp = llParseString2List(res,[":"],[]);
            queue = [nx,ny,(integer)llList2String(pp,1), nx,ny,(integer)llList2String(pp,2)] + queue;
        } else if (res == "king") {
            integer ko = cOwner(bGetL(b,nx,ny));
            if (!isStun) { if (ko==opp) return WIN_SCORE; return LOSE_SCORE; }
            score += 5;     // stunning a King is mild
        } else if (res == "hit") {
            integer pc = bGetL(b,nx,ny);
            integer pt = cType(pc);
            integer po = cOwner(pc);
            integer v  = pieceValue(pt);
            if (isStun) {
                if (pt==T_LASER || pt==T_STUNNER) { if (po==opp) score += v; else score -= v; }
                else { if (po==opp) score += 2; else score -= 2; }
            } else {
                if (po==opp) score += v; else score -= v;
            }
            b = bSetL(b, nx, ny, 0);   // beam stops; remove for any later forks
        }
        // absorb -> branch ends
        @cont;
    }
    return score;
}

// ---- choose one action ----
string chooseMove(list board, integer player, integer actionsLeft, list fired, list captured) {
    integer opp = 3 - player;
    integer i;
    integer N = BOARD_W * BOARD_H;

    // 1. Best shot (winning shot returns immediately).
    string  bestFire = "";
    integer bestFireScore = 0;
    for (i=0; i<N; ++i) {
        integer c = llList2Integer(board, i);
        if (cOwner(c)==player && !cStun(c)) {
            integer t = cType(c);
            if ((t==T_LASER || t==T_STUNNER) && llListFindList(fired,[i])<0) {
                integer x = i % BOARD_W;
                integer y = i / BOARD_W;
                integer s = simShot(board, x, y, (t==T_STUNNER), player);
                if (s >= WIN_SCORE) return "FIRE:" + (string)x + "," + (string)y;
                if (s > bestFireScore) {
                    bestFireScore = s;
                    bestFire = "FIRE:" + (string)x + "," + (string)y;
                }
            }
        }
    }
    if (bestFire != "" && bestFireScore > 0) return bestFire;

    // 2. Capture: a King/Octagon adjacent to an enemy piece (not capped).
    string  bestCap = "";
    integer bestCapVal = 0;
    for (i=0; i<N; ++i) {
        integer c = llList2Integer(board, i);
        integer t = cType(c);
        if (cOwner(c)==player && !cStun(c)
            && (t==T_KING || t==T_POCT || t==T_FOCT)
            && llListFindList(captured,[i])<0) {
            integer x = i % BOARD_W;
            integer y = i / BOARD_W;
            integer o;
            for (o=0; o<8; ++o) {
                integer cost = 1; if (o % 2) cost = 2;
                if (cost <= actionsLeft) {
                    integer nx = x + dirDX(o);
                    integer ny = y + dirDY(o);
                    if (bOk(nx,ny)) {
                        integer d = bGetL(board, nx, ny);
                        integer dt = cType(d);
                        if (dt!=T_EMPTY && dt!=T_HOLE && dt!=T_HYPERHOLE && cOwner(d)==opp) {
                            integer v = pieceValue(dt);
                            if (v > bestCapVal) {
                                bestCapVal = v;
                                bestCap = "MOVE:" + (string)x + "," + (string)y
                                        + "," + (string)nx + "," + (string)ny;
                            }
                        }
                    }
                }
            }
        }
    }
    if (bestCap != "") return bestCap;

    // 3. Advance an orthogonal step toward the enemy King.
    integer kx = -1; integer ky = -1;
    for (i=0; i<N && kx<0; ++i) {
        integer c = llList2Integer(board, i);
        if (cType(c)==T_KING && cOwner(c)==opp) { kx = i % BOARD_W; ky = i / BOARD_W; }
    }
    string  bestAdv = "";
    integer bestGain = 0;
    if (kx >= 0 && actionsLeft >= 1) {
        for (i=0; i<N; ++i) {
            integer c = llList2Integer(board, i);
            if (cOwner(c)==player && !cStun(c) && cType(c)!=T_EMPTY) {
                integer x = i % BOARD_W;
                integer y = i / BOARD_W;
                integer curD = iabs(x-kx) + iabs(y-ky);
                integer o;
                for (o=0; o<8; o+=2) {       // cardinal steps only (cost 1)
                    integer nx = x + dirDX(o);
                    integer ny = y + dirDY(o);
                    if (bOk(nx,ny) && bGetL(board,nx,ny)==0) {
                        integer gain = curD - (iabs(nx-kx) + iabs(ny-ky));
                        if (gain > bestGain) {
                            bestGain = gain;
                            bestAdv = "MOVE:" + (string)x + "," + (string)y
                                    + "," + (string)nx + "," + (string)ny;
                        }
                    }
                }
            }
        }
    }
    if (bestAdv != "") return bestAdv;

    // 4. Rotate a random non-stunned piece (always legal).
    list rotables;
    for (i=0; i<N; ++i) {
        integer c = llList2Integer(board, i);
        if (cOwner(c)==player && !cStun(c) && cType(c)!=T_EMPTY) rotables += [i];
    }
    if (llGetListLength(rotables) > 0) {
        integer pick = llList2Integer(rotables, (integer)llFrand(llGetListLength(rotables)));
        integer px = pick % BOARD_W;
        integer py = pick / BOARD_W;
        if (llFrand(1.0) < 0.5) return "ROTATE_CW:"  + (string)px + "," + (string)py;
        return "ROTATE_CCW:" + (string)px + "," + (string)py;
    }

    return "PASS";   // every piece stunned / no legal action
}

list csvToInts(string s) {
    if (s == "") return [];
    list p = llParseString2List(s, [","], []);
    list r = [];
    integer i;
    for (i=0; i<llGetListLength(p); ++i) r += [(integer)llList2String(p,i)];
    return r;
}

default {
    state_entry() { showMode(); }

    link_message(integer sender, integer num, string str, key id) {
        // Track the controller's config so this prim can show its mode.
        if (num == LM_CONFIG) {
            if (str == "AI_ON")         gEnabled = TRUE;
            else if (str == "AI_OFF")   gEnabled = FALSE;
            else if (str == "AI_RED")   gSide    = P_RED;
            else if (str == "AI_GREEN") gSide    = P_GREEN;
            else return;            // RESET etc. — not ours to display
            showMode();
            return;
        }

        if (num != LM_AI_REQUEST) return;

        list parts = llParseString2List(str, ["|"], []);
        list board = csvToInts(llList2String(parts, 0));
        integer player      = (integer)llList2String(parts, 1);
        integer actionsLeft = (integer)llList2String(parts, 2);
        list fired    = csvToInts(llList2String(parts, 3));
        list captured = csvToInts(llList2String(parts, 4));

        llSetText("AI: thinking…", <1.0,1.0,0.4>, 1.0);
        llSleep(0.6 + llFrand(0.6));   // brief "thinking" pause
        string mv = chooseMove(board, player, actionsLeft, fired, captured);
        llMessageLinked(LINK_ROOT, LM_AI_RESPONSE, mv, NULL_KEY);
        showMode();
    }
}
