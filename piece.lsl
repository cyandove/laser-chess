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

    // One batched call is cheaper than separate color/alpha/glow/text calls.
    llSetLinkPrimitiveParamsFast(LINK_THIS, [
        PRIM_COLOR, ALL_SIDES, col, a,
        PRIM_GLOW,  ALL_SIDES, glow,
        PRIM_TEXT,  label, <1,1,1>, 1.0 ]);
}

setHighlight(integer on) {
    if (gHighlighted == on) return;   // skip redundant updates (most cells)
    gHighlighted = on;
    updateVisuals(gCurrentCell);
}

flashLaserHit() {
    llSetColor(COLOR_LASER_HIT, ALL_SIDES);
    llSleep(0.3);
    updateVisuals(gCurrentCell);
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
        llSetColor(COLOR_EMPTY, ALL_SIDES);
        llSetAlpha(0.3, ALL_SIDES);
        llSetText("", <1,1,1>, 0.0);
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
        if (num == LM_LASER_PATH) {
            list segs = llParseString2List(str, [";"], []);
            integer i;
            for (i=0; i<llGetListLength(segs); ++i) {
                list xy = llParseString2List(llList2String(segs,i), [","], []);
                if (llList2Integer(xy,0)==gMyX && llList2Integer(xy,1)==gMyY)
                    flashLaserHit();
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
