// ============================================================
// Advanced Laser Chess — Piece / Board-Square Script  (ALC, Phase 1)
// Goes in every child cell prim, named "cell_X_Y".
// Renders the cell, forwards touches, shows the action dialog.
// Encoding must match game_controller.lsl:
//   cell = type + owner*100 + orient*1000 + stun*10000 + bombDiag*100000
// ============================================================

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

integer LM_CELL_UPDATE = 1;
integer LM_HIGHLIGHT   = 2;
integer LM_CLEAR_HL    = 3;
integer LM_LASER_PATH  = 4;
integer LM_GAME_OVER   = 5;
integer LM_STATUS      = 6;
integer LM_BEAM        = 7;
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

integer gMyX = -1;
integer gMyY = -1;
integer gHighlighted = FALSE;
integer gCurrentCell = 0;
key     gLastToucher = NULL_KEY;

// Texture rotation per facing step. Flip the sign if pieces face the wrong way.
float   TEX_ROT_SIGN = -1.0;
// Which prim face is the top of your cell tiles (a default box's top = 0).
// If the sprite shows on a side instead of the top, change this.
integer TOP_FACE = 0;

// Piece textures by type (index 0 = empty/blank). Paste your uploaded UUIDs
// here; re-drop this script into the cells after changing them.
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
// Upload sculpties/*_sculptmap.png with LOSSLESS compression, set the Stitching
// from sculpties/README.md, then paste the map UUIDs here and re-drop this script.
list SCULPT = [
    "",  //  0 empty
    "310259e5-e6f2-ccab-a55c-c7c7f03e25c5", //  1 King   (king_sculptmap, Cylinder)
    "",  //  2 Laser
    "",  //  3 Stunner
    "",  //  4 One-Way
    "",  //  5 Triangular
    "",  //  6 Bomb
    "",  //  7 Hypergon
    "",  //  8 Splitter
    "",  //  9 Part. Oct
    "0b2e2e7a-943c-fa25-2afb-c8073e7e4b17", // 10 Full Oct (foct_sculptmap, Cylinder)
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

integer SCULPT_STITCH  = PRIM_SCULPT_TYPE_CYLINDER; // both maps; add a per-type list if needed
float   SCULPT_ROT_SIGN = -1.0;     // facing-rotation direction (flip if pieces face wrong way)
vector  TILE_SIZE       = <1.0, 1.0, 0.05>;  // the flat cell tile (empty / textured pieces)
float   CELL_ZOFF       = 0.20;     // local Z of the cell tiles above the root (match game_controller)
float   SCULPT_BASE_Z   = 0.0;      // extra lift of tokens above the tile top (fine-tune)

// Per-type 180-degree upright flip (1 = that sculpt map is itself upside down).
// None needed with a correctly-oriented root; set an entry to 1 if a map renders
// inverted.
list SCULPT_FLIP = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
//  0  1  2  3  4  5  6  7  8  9 10 11 12
];

// ---- decode ----
integer cType(integer c)   { return c % 100; }
integer cOwner(integer c)  { return (c / 100) % 10; }
integer cOrient(integer c) { return (c / 1000) % 10; }
integer cStun(integer c)   { return (c / 10000) % 10; }
integer cBombDiag(integer c){ return (c / 100000) % 10; }

parsePosition() {
    string name = llGetLinkName(llGetLinkNumber());
    if (llGetSubString(name, 0, 4) != "cell_") return;
    list parts = llParseString2List(name, ["_"], []);
    if (llGetListLength(parts) < 3) return;
    gMyX = (integer)llList2String(parts, 1);
    gMyY = (integer)llList2String(parts, 2);
}

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
// board features cannot be selected/acted on
integer isFeature(integer t) { return (t == T_HOLE || t == T_HYPERHOLE); }

updateVisuals(integer cell) {
    // Only render once we're a placed, linked board cell. On a standalone prim
    // (e.g. the unlinked lc_cell template) PRIM_POS_LOCAL is the *region*
    // position, so setting it here would fling the prim underground.
    if (gMyX < 0) return;
    gCurrentCell = cell;
    integer t = cType(cell);
    integer owner = cOwner(cell);

    // Base appearance for the piece (or empty cell).
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

    // Highlight a legal destination with glow (so an occupied capture target
    // still shows the enemy piece's colour + label underneath). Empty targets
    // turn yellow so they're visible on the dark board.
    float glow = 0.0;
    if (gHighlighted) {
        glow = 0.25;
        if (t == T_EMPTY) { col = COLOR_HIGHLIGHT; a = 1.0; }
    }

    // Keep the cell's grid XY (owned by the controller's layoutCells); we only
    // adjust Z / size / type / rotation here.
    vector lp = llList2Vector(llGetLinkPrimitiveParams(LINK_THIS, [PRIM_POS_LOCAL]), 0);

    string sc = "";
    if (t != T_EMPTY) sc = llList2String(SCULPT, t);

    if (sc != "") {
        // 3D sculptie piece: morph the prim and rotate it to face its orientation.
        vector sz = llList2Vector(SCULPT_SIZE, t);
        rotation rot = llAxisAngle2Rot(<0.0,0.0,1.0>,
            (float)cOrient(cell) * PI * 0.25 * SCULPT_ROT_SIGN);
        if (llList2Integer(SCULPT_FLIP, t))            // upside-down map: flip upright first
            rot = llAxisAngle2Rot(<1.0,0.0,0.0>, PI) * rot;
        // Stand the token's base on the top of the tile: prim centre = tile top
        // + half the token height. Nudge SCULPT_BASE_Z if a token floats/sinks.
        float tileTopZ = CELL_ZOFF + TILE_SIZE.z * 0.5;
        llSetLinkPrimitiveParamsFast(LINK_THIS, [
            PRIM_TYPE, PRIM_TYPE_SCULPT, sc, SCULPT_STITCH,
            PRIM_SIZE, sz,
            PRIM_POS_LOCAL, <lp.x, lp.y, tileTopZ + SCULPT_BASE_Z + sz.z * 0.5>,
            PRIM_ROT_LOCAL, rot,
            PRIM_COLOR, ALL_SIDES, col, a,
            PRIM_GLOW,  ALL_SIDES, glow,
            PRIM_TEXT,  label, <1,1,1>, 1.0 ]);
    } else {
        // Flat box tile: empty cell, or a piece without a sculpt map yet. The
        // sprite goes on the top face only (blank the rest), rotated for facing.
        float texRot = (float)cOrient(cell) * PI * 0.25 * TEX_ROT_SIGN;
        llSetLinkPrimitiveParamsFast(LINK_THIS, [
            PRIM_TYPE, PRIM_TYPE_BOX, PRIM_HOLE_DEFAULT, <0.0,1.0,0.0>, 0.0,
                <0.0,0.0,0.0>, <1.0,1.0,0.0>, <0.0,0.0,0.0>,
            PRIM_SIZE, TILE_SIZE,
            PRIM_POS_LOCAL, <lp.x, lp.y, CELL_ZOFF>,
            PRIM_ROT_LOCAL, ZERO_ROTATION,
            PRIM_TEXTURE, ALL_SIDES, llList2String(TEX, 0), <1.0,1.0,0.0>, <0.0,0.0,0.0>, 0.0,
            PRIM_TEXTURE, TOP_FACE,  llList2String(TEX, t), <1.0,1.0,0.0>, <0.0,0.0,0.0>, texRot,
            PRIM_COLOR, ALL_SIDES, col, a,
            PRIM_GLOW,  ALL_SIDES, glow,
            PRIM_TEXT,  label, <1,1,1>, 1.0 ]);
    }
}

setHighlight(integer on) {
    if (gHighlighted == on) return;   // skip redundant updates (most cells)
    gHighlighted = on;
    updateVisuals(gCurrentCell);
}

// Light this cell as part of the beam (no sleep — stays lit until the
// controller pushes a normal cell update to clear it).
beamLight(vector c) {
    llSetLinkPrimitiveParamsFast(LINK_THIS, [
        PRIM_COLOR, ALL_SIDES, c, 1.0,
        PRIM_GLOW,  ALL_SIDES, 0.45 ]);
}

showActionDialog() {
    if (gLastToucher == NULL_KEY) return;
    integer t = cType(gCurrentCell);
    list buttons;
    if (canFire(t)) buttons = ["Move", "Fire", "Cancel", "Rot CW", "Rot CCW"];
    else            buttons = ["Move", "Rot CW", "Rot CCW", "Cancel"];
    llDialog(gLastToucher, "Action for " + pieceLabel(gCurrentCell)
        + "  (45° turns):", buttons, DIALOG_CH);
    llListen(DIALOG_CH, "", gLastToucher, "");
}

default {
    state_entry() {
        parsePosition();
        if (gMyX >= 0) updateVisuals(0);   // render the blank empty cell
        else llSetText("laser-chess cell\nlink into the board, then Reset Scripts",
                       <1,1,0>, 1.0);       // unlinked template: leave it where it is
    }

    touch_start(integer n) {
        if (gMyX < 0) return;
        gLastToucher = llDetectedKey(0);
        llMessageLinked(LINK_ROOT, LM_PIECE_TOUCH,
            (string)gMyX + "," + (string)gMyY, NULL_KEY);
    }

    listen(integer channel, string name, key id, string msg) {
        if (channel != DIALOG_CH) return;
        string action = "CANCEL";
        if (msg == "Move")    action = "MOVE";
        if (msg == "Rot CW")  action = "ROTATE_CW";
        if (msg == "Rot CCW") action = "ROTATE_CCW";
        if (msg == "Fire")    action = "FIRE";
        if (msg == "Cancel")  action = "CANCEL";
        llMessageLinked(LINK_ROOT, LM_ACTION, action, NULL_KEY);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        // If we never resolved our cell name (e.g. named/linked after this
        // script's state_entry ran), try again now that the game is talking.
        if (gMyX < 0) parsePosition();

        if (num == LM_CELL_UPDATE) {
            list p = llParseString2List(str, [","], []);
            if (llList2Integer(p,0)==gMyX && llList2Integer(p,1)==gMyY)
                updateVisuals(llList2Integer(p,2));
            return;
        }
        if (num == LM_HIGHLIGHT) {
            list p = llParseString2List(str, [","], []);
            if (llList2Integer(p,0)==gMyX && llList2Integer(p,1)==gMyY)
                setHighlight(llList2Integer(p,2));
            return;
        }
        if (num == LM_CLEAR_HL) { setHighlight(FALSE); return; }
        if (num == LM_BEAM) {
            list p = llParseString2List(str, [","], []);
            if (llList2Integer(p,0)==gMyX && llList2Integer(p,1)==gMyY) {
                if (llGetListLength(p) >= 3) beamLight(<1.0, 0.12, 0.05>); // HIT
                else                         beamLight(COLOR_LASER_HIT);    // travel
            }
            return;
        }
        if (num == LM_ACTION) {
            if (llGetSubString(str,0,4) == "MENU:") {
                list xy = llParseString2List(llGetSubString(str,5,-1), [","], []);
                if (llList2Integer(xy,0)==gMyX && llList2Integer(xy,1)==gMyY)
                    showActionDialog();
            }
            return;
        }
        if (num == LM_GAME_OVER) {
            llSetColor(<1,1,0>, ALL_SIDES);
            llSleep(1.0);
            updateVisuals(gCurrentCell);
            return;
        }
    }
}
