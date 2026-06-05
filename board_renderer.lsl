// ============================================================
// Advanced Laser Chess — Board Renderer  (root prim, drives all cells)
// Lives in the ROOT prim alongside game_controller.lsl. Replaces the old
// per-cell piece.lsl: one script renders all 165 `cell_X_Y` child prims,
// positions them, forwards touches, and shows the action dialog.
//
// It builds an (x,y) -> link-number map from the cell names, then on the
// controller's broadcasts it morphs the right child link between a flat tile
// (empty / textured piece) and a 3D sculptie. Nothing renders from inside the
// cells, so the cell prims hold NO scripts.
//
// Encoding must match game_controller.lsl:
//   cell = type + owner*100 + orient*1000 + stun*10000 + bombDiag*100000
// ============================================================

integer BOARD_W = 15;
integer BOARD_H = 11;
float   CELL_SIZE = 1.0;   // metres per cell — match your build

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

integer P_RED   = 1;
integer P_GREEN = 2;

// ---- link-message nums (must match game_controller.lsl) ----
integer LM_CELL_UPDATE = 1;
integer LM_HIGHLIGHT   = 2;
integer LM_CLEAR_HL    = 3;
integer LM_GAME_OVER   = 5;
integer LM_BEAM        = 7;
integer LM_BOARD_FULL  = 8;   // whole-board CSV (one message, we loop)
integer LM_RENDER_READY = 9;  // renderer -> controller: "I'm up, send the board"
integer LM_PIECE_TOUCH = 10;
integer LM_ACTION      = 11;

integer DIALOG_CH = -987654;

// ---- appearance ----
vector COLOR_RED       = <0.85, 0.12, 0.12>;
vector COLOR_GREEN     = <0.12, 0.70, 0.18>;
vector COLOR_NEUTRAL   = <0.45, 0.45, 0.50>;
vector COLOR_EMPTY     = <0.20, 0.20, 0.20>;
vector COLOR_HIGHLIGHT = <0.90, 0.90, 0.20>;
vector COLOR_LASER_HIT = <1.0, 0.5, 0.0>;

// Texture rotation per facing step. Flip the sign if pieces face the wrong way.
float   TEX_ROT_SIGN = -1.0;
// Which prim face is the top of your cell tiles (a default box's top = 0).
integer TOP_FACE = 0;

// Piece textures by type (index 0 = empty/blank). Used for any piece whose
// SCULPT entry is "" (so you can mix flat and 3D pieces).
list TEX = [
    "5748decc-f629-461c-9a36-a35a221fe21f", //  0 empty (blank)
    "b1b31d44-39a8-05a0-3a18-66c672980228", //  1 King       (tex_king)
    "b7d6a241-2427-8c71-460e-581d82cbbbd4", //  2 Laser      (tex_laser)
    "60387018-dfe7-f04f-075b-a902207bcbf9", //  3 Stunner    (tex_stunner)
    "f0aaca44-e8de-a032-7ebd-e33bd6c21918", //  4 One-Way    (tex_oneway)
    "702f8ffa-4f49-b9d8-30d1-c160b5925bae", //  5 Triangular (tex_trimir)
    "f536281c-f7d4-bb44-a296-f286d1178027", //  6 Bomb       (tex_bomb)
    "7bd2294c-94aa-c365-27af-09ac6e8373e9", //  7 Hypergon   (tex_hypergon)
    "7b979c02-7673-2539-04ab-20eb397465b8", //  8 Splitter   (tex_splitter)
    "fe692b3b-01cc-52f2-023c-19d7faa4c465", //  9 Part. Oct  (tex_poct)
    "b27697b1-5f64-533d-bffb-a5769de4003b", // 10 Full Oct   (tex_foct)
    "b287b832-b2ac-344e-2e03-cb8455941117", // 11 Hole       (tex_hole)
    "00139b4e-5d9d-b007-7bb7-c2ba560e0f80"  // 12 Hyper Hole (tex_hyperhole)
];

// 3D sculptie maps by type ("" = none -> the piece uses the flat texture above).
list SCULPT = [
    "",  //  0 empty
    "310259e5-e6f2-ccab-a55c-c7c7f03e25c5", //  1 King
    "bdd73307-42f2-f659-7b13-5cbc450e9dab", //  2 Laser
    "012f2161-df39-b9ce-ca54-7ffa54d9528d", //  3 Stunner
    "424b4fd1-cb28-3b2e-616c-77be64f0c8c0", //  4 One-Way
    "4ce24d3a-acb8-c5f7-5f25-fc7a21ae7905", //  5 Triangular
    "5211a05d-3554-5dc9-d06c-ca4a4836fa74", //  6 Bomb
    "1781631d-8a8c-2d34-5f4a-c90d52ea2ba9", //  7 Hypergon
    "4ca24f9f-0d2a-eaa2-322a-708c60f069df", //  8 Splitter
    "7e95cafd-b0e4-9e0c-c273-c3e9d45873f9", //  9 Part. Oct
    "0b2e2e7a-943c-fa25-2afb-c8073e7e4b17", // 10 Full Oct
    "",  // 11 Hole
    ""   // 12 Hyper Hole
];

// Per-type sculptie prim size <x,y,z> (the maps fill [-1,1]; tune per piece).
list SCULPT_SIZE = [
    <0.80,0.80,0.50>,  //  0 (unused)
    <0.70,0.70,1.00>,  //  1 King (taller)
    <0.80,0.80,0.70>,  //  2 Laser
    <0.80,0.80,0.70>,  //  3 Stunner
    <0.80,0.80,0.60>,  //  4 One-Way
    <0.80,0.80,0.60>,  //  5 Triangular
    <0.80,0.80,0.70>,  //  6 Bomb
    <0.80,0.80,0.70>,  //  7 Hypergon
    <0.80,0.80,0.60>,  //  8 Splitter
    <0.85,0.85,0.70>,  //  9 Part. Oct
    <0.85,0.85,0.80>,  // 10 Full Oct
    <0.80,0.80,0.40>,  // 11 Hole
    <0.80,0.80,0.40>   // 12 Hyper Hole
];

// Per-type sculpt stitching. Most maps are Cylinder; the Hypergon gem is Sphere.
list SCULPT_STITCH = [
    PRIM_SCULPT_TYPE_CYLINDER,  //  0 (unused)
    PRIM_SCULPT_TYPE_CYLINDER,  //  1 King
    PRIM_SCULPT_TYPE_CYLINDER,  //  2 Laser
    PRIM_SCULPT_TYPE_CYLINDER,  //  3 Stunner
    PRIM_SCULPT_TYPE_CYLINDER,  //  4 One-Way
    PRIM_SCULPT_TYPE_CYLINDER,  //  5 Triangular
    PRIM_SCULPT_TYPE_CYLINDER,  //  6 Bomb
    PRIM_SCULPT_TYPE_SPHERE,    //  7 Hypergon
    PRIM_SCULPT_TYPE_CYLINDER,  //  8 Splitter
    PRIM_SCULPT_TYPE_CYLINDER,  //  9 Part. Oct
    PRIM_SCULPT_TYPE_CYLINDER,  // 10 Full Oct
    PRIM_SCULPT_TYPE_CYLINDER,  // 11 Hole
    PRIM_SCULPT_TYPE_CYLINDER   // 12 Hyper Hole
];
float   SCULPT_ROT_SIGN = -1.0;     // facing-rotation direction (flip if pieces face wrong way)
vector  TILE_SIZE       = <1.0, 1.0, 0.05>;  // the flat cell tile (empty / textured pieces)
float   CELL_ZOFF       = 0.20;     // local Z of the cell tiles above the root
float   SCULPT_BASE_Z   = 0.0;      // extra lift of tokens above the tile top (fine-tune)

// Per-type 180-degree upright flip (1 = that sculpt map is itself upside down).
list SCULPT_FLIP = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
//  0  1  2  3  4  5  6  7  8  9 10 11 12
];

// ---- state ----
list    gLink;          // index = y*BOARD_W+x  ->  child link number (-1 = missing)
list    gCell;          // last cell value pushed for each square
list    gHL;            // highlight flag (0/1) for each square
key     gLastToucher = NULL_KEY;
integer gListen = 0;

// Side control buttons (named ctl_*_ccw / _cw / _fire). Parallel lists:
// gCtlLink[i] is a child link, gCtlAction[i] the action it fires on the
// currently-selected piece.
list    gCtlLink;
list    gCtlAction;

// ---- decode ----
integer cType(integer c)   { return c % 100; }
integer cOwner(integer c)  { return (c / 100) % 10; }
integer cOrient(integer c) { return (c / 1000) % 10; }
integer cStun(integer c)   { return (c / 10000) % 10; }
integer cBombDiag(integer c){ return (c / 100000) % 10; }

integer cellIdx(integer x, integer y) { return y * BOARD_W + x; }

string dirStr(integer o) {
    return llList2String(["N","NE","E","SE","S","SW","W","NW"], o);
}

string pieceLabel(integer cell) {
    integer t = cType(cell);
    integer o = cOrient(cell);
    if (t == T_KING)      return "KING";
    if (t == T_LASER)     return "LASR\n" + dirStr(o);
    if (t == T_STUNNER)   return "STUN\n" + dirStr(o);
    if (t == T_ONEWAY)    return "1WAY\n" + dirStr(o);
    if (t == T_TRIMIR)    return "TRI\n"  + dirStr(o);
    if (t == T_BOMB)      { if (cBombDiag(cell)) return "BOMB\nX"; return "BOMB\n+"; }
    if (t == T_HYPERGON)  return "HYPR";
    if (t == T_SPLITTER)  return "SPLT\n" + dirStr(o);
    if (t == T_POCT)      return "oct\n"  + dirStr(o);
    if (t == T_FOCT)      return "OCT";
    if (t == T_HOLE)      return "HOLE";
    if (t == T_HYPERHOLE) return "HOLE\n*";
    return "";
}

integer canFire(integer t) { return (t == T_LASER || t == T_STUNNER); }

// Zero the per-cell value / highlight caches (board starts empty until the
// controller broadcasts). Only done at start-up, not on every re-link.
initCaches() {
    gCell = []; gHL = [];
    integer total = BOARD_W * BOARD_H;
    integer i;
    for (i = 0; i < total; ++i) { gCell += [0]; gHL += [0]; }
}

// (Re)build the (x,y) -> link map by scanning every cell_X_Y child name.
// Map a control prim's name suffix to the action it fires ("" = not a control).
string ctlAction(string nm) {
    list p = llParseString2List(nm, ["_"], []);
    string suf = llList2String(p, llGetListLength(p) - 1);
    if (suf == "ccw")  return "ROTATE_CCW";
    if (suf == "cw")   return "ROTATE_CW";
    if (suf == "fire") return "FIRE";
    return "";
}

scanLinks() {
    integer total = BOARD_W * BOARD_H;
    gLink = [];
    gCtlLink = []; gCtlAction = [];
    integer i;
    for (i = 0; i < total; ++i) gLink += [-1];
    integer n = llGetNumberOfPrims();
    for (i = 1; i <= n; ++i) {
        string nm = llGetLinkName(i);
        if (llGetSubString(nm, 0, 4) == "cell_") {
            list p = llParseString2List(nm, ["_"], []);
            if (llGetListLength(p) >= 3) {
                integer x = (integer)llList2String(p, 1);
                integer y = (integer)llList2String(p, 2);
                if (x >= 0 && x < BOARD_W && y >= 0 && y < BOARD_H) {
                    integer idx = cellIdx(x, y);
                    gLink = llListReplaceList(gLink, [i], idx, idx);
                }
            }
        } else if (llGetSubString(nm, 0, 3) == "ctl_") {
            string act = ctlAction(nm);
            if (act != "") { gCtlLink += [i]; gCtlAction += [act]; }
        }
    }
}

// Render one square from its cached value + highlight state. Computes the grid
// XY itself (so no separate layout pass is needed) and morphs the child link.
renderIdx(integer idx) {
    integer link = llList2Integer(gLink, idx);
    if (link < 1) return;                 // no such cell linked
    integer cell  = llList2Integer(gCell, idx);
    integer hl    = llList2Integer(gHL, idx);
    integer t     = cType(cell);
    integer owner = cOwner(cell);

    vector col = COLOR_EMPTY;
    float  a   = 0.3;
    string label = "";
    if (t != T_EMPTY) {
        a = 1.0;
        if (owner == P_RED)        col = COLOR_RED;
        else if (owner == P_GREEN) col = COLOR_GREEN;
        else                       col = COLOR_NEUTRAL;
        label = pieceLabel(cell);
        if (cStun(cell)) label += "\n~STUN~";
    }

    float glow = 0.0;
    if (hl) {
        glow = 0.25;
        if (t == T_EMPTY) { col = COLOR_HIGHLIGHT; a = 1.0; }
    }

    // grid XY relative to the root (centered), matching the old layoutCells.
    integer x = idx % BOARD_W;
    integer y = idx / BOARD_W;
    float halfW = (float)(BOARD_W - 1) * 0.5 * CELL_SIZE;
    float halfH = (float)(BOARD_H - 1) * 0.5 * CELL_SIZE;
    float lx = (float)x * CELL_SIZE - halfW;
    float ly = halfH - (float)y * CELL_SIZE;

    string sc = "";
    if (t != T_EMPTY) sc = llList2String(SCULPT, t);

    if (sc != "") {
        // 3D sculptie piece: morph the prim and rotate it to face its orientation.
        vector sz = llList2Vector(SCULPT_SIZE, t);
        float facing = (float)cOrient(cell) * PI * 0.25;
        // Bomb: spikes sit on the orthogonal faces (+ config). In the diagonal
        // config (bombDiag==1) turn it an extra 45° so they point at the X.
        if (t == T_BOMB && cBombDiag(cell)) facing += PI * 0.25;
        rotation rot = llAxisAngle2Rot(<0.0,0.0,1.0>, facing * SCULPT_ROT_SIGN);
        if (llList2Integer(SCULPT_FLIP, t))            // upside-down map: flip upright first
            rot = llAxisAngle2Rot(<1.0,0.0,0.0>, PI) * rot;
        // Stand the token's base on the top of the tile: prim centre = tile top
        // + half the token height. Nudge SCULPT_BASE_Z if a token floats/sinks.
        float tileTopZ = CELL_ZOFF + TILE_SIZE.z * 0.5;
        llSetLinkPrimitiveParamsFast(link, [
            PRIM_TYPE, PRIM_TYPE_SCULPT, sc, llList2Integer(SCULPT_STITCH, t),
            PRIM_SIZE, sz,
            PRIM_POS_LOCAL, <lx, ly, tileTopZ + SCULPT_BASE_Z + sz.z * 0.5>,
            PRIM_ROT_LOCAL, rot,
            PRIM_COLOR, ALL_SIDES, col, a,
            PRIM_GLOW,  ALL_SIDES, glow,
            PRIM_TEXT,  label, <1,1,1>, 1.0 ]);
    } else {
        // Flat box tile: empty cell, or a piece without a sculpt map yet. The
        // sprite goes on the top face only (blank the rest), rotated for facing.
        float texRot = (float)cOrient(cell) * PI * 0.25 * TEX_ROT_SIGN;
        llSetLinkPrimitiveParamsFast(link, [
            PRIM_TYPE, PRIM_TYPE_BOX, PRIM_HOLE_DEFAULT, <0.0,1.0,0.0>, 0.0,
                <0.0,0.0,0.0>, <1.0,1.0,0.0>, <0.0,0.0,0.0>,
            PRIM_SIZE, TILE_SIZE,
            PRIM_POS_LOCAL, <lx, ly, CELL_ZOFF>,
            PRIM_ROT_LOCAL, ZERO_ROTATION,
            PRIM_TEXTURE, ALL_SIDES, llList2String(TEX, 0), <1.0,1.0,0.0>, <0.0,0.0,0.0>, 0.0,
            PRIM_TEXTURE, TOP_FACE,  llList2String(TEX, t), <1.0,1.0,0.0>, <0.0,0.0,0.0>, texRot,
            PRIM_COLOR, ALL_SIDES, col, a,
            PRIM_GLOW,  ALL_SIDES, glow,
            PRIM_TEXT,  label, <1,1,1>, 1.0 ]);
    }
}

renderAll() {
    integer total = BOARD_W * BOARD_H;
    integer i;
    for (i = 0; i < total; ++i) renderIdx(i);
}

// Light a square as part of the beam (no sleep — restored when the controller
// pushes a normal cell update afterward).
beamLight(integer idx, vector c) {
    integer link = llList2Integer(gLink, idx);
    if (link < 1) return;
    llSetLinkPrimitiveParamsFast(link, [
        PRIM_COLOR, ALL_SIDES, c, 1.0,
        PRIM_GLOW,  ALL_SIDES, 0.45 ]);
}

showActionDialog(integer x, integer y) {
    if (gLastToucher == NULL_KEY) return;
    integer cell = llList2Integer(gCell, cellIdx(x, y));
    integer t = cType(cell);
    list buttons;
    if (canFire(t)) buttons = ["Move", "Fire", "Cancel", "Rot CW", "Rot CCW"];
    else            buttons = ["Move", "Rot CW", "Rot CCW", "Cancel"];
    if (gListen) llListenRemove(gListen);
    gListen = llListen(DIALOG_CH, "", gLastToucher, "");
    llDialog(gLastToucher, "Action for " + pieceLabel(cell)
        + "  (45° turns):", buttons, DIALOG_CH);
}

default {
    state_entry() {
        initCaches();   // empty board until the controller sends one
        scanLinks();
        // Ask the controller for the current board so EVERY cell renders now
        // (positions empties too) — don't rely on catching its one-shot
        // start-up broadcast, which a deploy/reset-order race can miss.
        llMessageLinked(LINK_ROOT, LM_RENDER_READY, "", NULL_KEY);
    }

    changed(integer c) {
        // On a re-link, remap link numbers but KEEP the cached board, then
        // repaint so cells stay correct instead of blanking out.
        if (c & CHANGED_LINK) { scanLinks(); renderAll(); }
    }

    touch_start(integer n) {
        integer link = llDetectedLinkNumber(0);
        // Side control button: fire its action at the current selection.
        integer ci = llListFindList(gCtlLink, [link]);
        if (ci >= 0) {
            llMessageLinked(LINK_ROOT, LM_ACTION, llList2String(gCtlAction, ci), NULL_KEY);
            return;
        }
        integer idx = llListFindList(gLink, [link]);
        if (idx < 0) return;              // not a board cell or a control
        gLastToucher = llDetectedKey(0);
        llMessageLinked(LINK_ROOT, LM_PIECE_TOUCH,
            (string)(idx % BOARD_W) + "," + (string)(idx / BOARD_W), NULL_KEY);
    }

    listen(integer channel, string name, key id, string msg) {
        if (channel != DIALOG_CH) return;
        string action = "CANCEL";
        if (msg == "Move")    action = "MOVE";
        if (msg == "Rot CW")  action = "ROTATE_CW";
        if (msg == "Rot CCW") action = "ROTATE_CCW";
        if (msg == "Fire")    action = "FIRE";
        if (msg == "Cancel")  action = "CANCEL";
        if (gListen) { llListenRemove(gListen); gListen = 0; }
        llMessageLinked(LINK_ROOT, LM_ACTION, action, NULL_KEY);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        if (num == LM_BOARD_FULL) {
            // whole board as one CSV: update caches and render every square.
            list vals = llParseString2List(str, [","], []);
            integer total = BOARD_W * BOARD_H;
            integer cnt = llGetListLength(vals);
            integer i;
            for (i = 0; i < total && i < cnt; ++i) {
                gCell = llListReplaceList(gCell, [(integer)llList2String(vals, i)], i, i);
                renderIdx(i);
            }
            return;
        }
        if (num == LM_CELL_UPDATE) {
            list p = llParseString2List(str, [","], []);
            integer idx = cellIdx(llList2Integer(p,0), llList2Integer(p,1));
            gCell = llListReplaceList(gCell, [llList2Integer(p,2)], idx, idx);
            renderIdx(idx);
            return;
        }
        if (num == LM_HIGHLIGHT) {
            list p = llParseString2List(str, [","], []);
            integer idx = cellIdx(llList2Integer(p,0), llList2Integer(p,1));
            integer on = llList2Integer(p,2);
            if (llList2Integer(gHL, idx) != on) {
                gHL = llListReplaceList(gHL, [on], idx, idx);
                renderIdx(idx);
            }
            return;
        }
        if (num == LM_CLEAR_HL) {
            integer total = BOARD_W * BOARD_H;
            integer i;
            for (i = 0; i < total; ++i) {
                if (llList2Integer(gHL, i)) {
                    gHL = llListReplaceList(gHL, [0], i, i);
                    renderIdx(i);
                }
            }
            return;
        }
        if (num == LM_BEAM) {
            list p = llParseString2List(str, [","], []);
            integer idx = cellIdx(llList2Integer(p,0), llList2Integer(p,1));
            if (llGetListLength(p) >= 3) beamLight(idx, <1.0, 0.12, 0.05>); // HIT
            else                         beamLight(idx, COLOR_LASER_HIT);    // travel
            return;
        }
        if (num == LM_ACTION) {
            if (llGetSubString(str,0,4) == "MENU:") {
                list xy = llParseString2List(llGetSubString(str,5,-1), [","], []);
                showActionDialog(llList2Integer(xy,0), llList2Integer(xy,1));
            }
            return;
        }
        if (num == LM_GAME_OVER) {
            integer total = BOARD_W * BOARD_H;
            integer i;
            for (i = 0; i < total; ++i) {
                integer link = llList2Integer(gLink, i);
                if (link >= 1) llSetLinkPrimitiveParamsFast(link,
                    [PRIM_COLOR, ALL_SIDES, <1,1,0>, 1.0]);
            }
            llSleep(1.0);
            renderAll();
            return;
        }
    }
}
