// ============================================================
// Advanced Laser Chess — Piece / Board-Square Script
// Goes in every child prim of the board linkset.
// Each prim corresponds to one board cell (x,y encoded in prim name
// as "cell_X_Y", e.g. "cell_3_7").
// The script handles: visual state, highlight, touch forwarding,
// and showing the action dialog when this prim's cell is selected.
// ============================================================

// Must match game_controller.lsl constants
integer T_EMPTY   = 0;
integer T_LASER   = 1;
integer T_DEFLECT = 2;
integer T_DEFEND  = 3;
integer T_SWITCH  = 4;
integer T_KING    = 5;
integer T_SPLIT   = 6;
integer T_TELE    = 7;

integer P_RED  = 0;
integer P_BLUE = 1;

integer LM_CELL_UPDATE = 1;
integer LM_HIGHLIGHT   = 2;
integer LM_CLEAR_HL    = 3;
integer LM_LASER_PATH  = 4;
integer LM_GAME_OVER   = 5;
integer LM_STATUS      = 6;
integer LM_PIECE_TOUCH = 10;
integer LM_ACTION      = 11;

// ---- Piece appearance ----
// Colors per player (adjust to taste)
vector COLOR_RED       = <0.9, 0.1, 0.1>;
vector COLOR_BLUE      = <0.1, 0.3, 0.9>;
vector COLOR_EMPTY     = <0.2, 0.2, 0.2>;
vector COLOR_HIGHLIGHT = <0.9, 0.9, 0.2>;
vector COLOR_LASER_HIT = <1.0, 0.5, 0.0>;

// ---- Cell position for this prim ----
integer gMyX = -1;
integer gMyY = -1;
integer gHighlighted = FALSE;
integer gCurrentCell = 0;

// Parse "cell_X_Y" from prim name
parsePosition() {
    string name = llGetLinkName(llGetLinkNumber());
    if (llGetSubString(name, 0, 4) != "cell_") return;
    list parts = llParseString2List(name, ["_"], []);
    if (llGetListLength(parts) < 3) return;
    gMyX = (integer)llList2String(parts, 1);
    gMyY = (integer)llList2String(parts, 2);
}

// ---- Piece label text ----
string pieceLabel(integer cell) {
    integer t = cell % 10;
    integer o = (cell / 100) % 10;
    string dir = llList2String(["N","E","S","W"], o);
    if (t == T_LASER)   return "LZR\n" + dir;
    if (t == T_DEFLECT) return "DFL\n" + dir;
    if (t == T_DEFEND)  return "DEF\n" + dir;
    if (t == T_SWITCH)  return "SWT\n" + dir;
    if (t == T_KING)    return "KING\n" + dir;
    if (t == T_SPLIT)   return "SPL\n" + dir;
    if (t == T_TELE)    return "TELE";
    return "";
}

// ---- Visual update ----
updateVisuals(integer cell) {
    gCurrentCell = cell;
    integer t = cell % 10;
    integer owner = (cell / 10) % 10;

    if (gHighlighted) {
        llSetColor(COLOR_HIGHLIGHT, ALL_SIDES);
        llSetText("", <1,1,1>, 0.0);
        return;
    }

    if (t == T_EMPTY) {
        llSetColor(COLOR_EMPTY, ALL_SIDES);
        llSetText("", <1,1,1>, 0.0);
        llSetAlpha(0.3, ALL_SIDES);
        return;
    }

    llSetAlpha(1.0, ALL_SIDES);
    if (owner == P_RED)
        llSetColor(COLOR_RED, ALL_SIDES);
    else
        llSetColor(COLOR_BLUE, ALL_SIDES);

    llSetText(pieceLabel(cell), <1,1,1>, 1.0);
}

setHighlight(integer on) {
    gHighlighted = on;
    updateVisuals(gCurrentCell);
}

// ---- Flash effect for laser beam ----
flashLaserHit() {
    llSetColor(COLOR_LASER_HIT, ALL_SIDES);
    llSleep(0.3);
    updateVisuals(gCurrentCell);
}

// ---- Action dialog ----
// Shown to the last agent who touched this prim's cell.
key gLastToucher = NULL_KEY;

showActionDialog() {
    if (gLastToucher == NULL_KEY) return;
    integer t = gCurrentCell % 10;
    list buttons = ["Move", "Rotate CW", "Rotate CCW"];
    if (t == T_LASER) buttons = ["Fire", "Rotate CW", "Rotate CCW"];
    buttons += ["Cancel"];
    llDialog(gLastToucher, "Select action for " + pieceLabel(gCurrentCell) + ":",
             buttons, -987654); // private channel
    llListen(-987654, "", gLastToucher, "");
}

default {
    state_entry() {
        parsePosition();
        llSetColor(COLOR_EMPTY, ALL_SIDES);
        llSetAlpha(0.3, ALL_SIDES);
        llSetText("", <1,1,1>, 0.0);
    }

    touch_start(integer n) {
        if (gMyX < 0) return; // prim not yet named correctly
        gLastToucher = llDetectedKey(0);
        // Forward touch to game controller (root prim = link 1)
        llMessageLinked(LINK_ROOT, LM_PIECE_TOUCH,
            (string)gMyX + "," + (string)gMyY, NULL_KEY);
    }

    listen(integer channel, string name, key id, string msg) {
        if (channel != -987654) return;
        // Map dialog button to action string
        string action = "CANCEL";
        if (msg == "Move")       action = "MOVE";
        if (msg == "Rotate CW")  action = "ROTATE_CW";
        if (msg == "Rotate CCW") action = "ROTATE_CCW";
        if (msg == "Fire")       action = "FIRE";
        if (msg == "Cancel")     action = "CANCEL";
        llMessageLinked(LINK_ROOT, LM_ACTION, action, NULL_KEY);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        // ---- Cell update ----
        if (num == LM_CELL_UPDATE) {
            list p = llParseString2List(str, [","], []);
            if (llList2Integer(p,0)==gMyX && llList2Integer(p,1)==gMyY)
                updateVisuals(llList2Integer(p,2));
            return;
        }

        // ---- Highlight ----
        if (num == LM_HIGHLIGHT) {
            list p = llParseString2List(str, [","], []);
            if (llList2Integer(p,0)==gMyX && llList2Integer(p,1)==gMyY)
                setHighlight(llList2Integer(p,2));
            return;
        }

        // ---- Clear highlights ----
        if (num == LM_CLEAR_HL) {
            setHighlight(FALSE);
            return;
        }

        // ---- Laser path — flash cells the beam passes through ----
        if (num == LM_LASER_PATH) {
            list segments = llParseString2List(str, [";"], []);
            integer i;
            for (i=0; i<llGetListLength(segments); ++i) {
                list xy = llParseString2List(llList2String(segments,i),[","],[]);
                if (llList2Integer(xy,0)==gMyX && llList2Integer(xy,1)==gMyY)
                    flashLaserHit();
            }
            return;
        }

        // ---- Action menu request (controller asks piece to show dialog) ----
        if (num == LM_ACTION) {
            if (llGetSubString(str,0,4) == "MENU:") {
                list xy = llParseString2List(llGetSubString(str,5,-1),[","],[]);
                if (llList2Integer(xy,0)==gMyX && llList2Integer(xy,1)==gMyY)
                    showActionDialog();
            }
            return;
        }

        // ---- Game over ----
        if (num == LM_GAME_OVER) {
            // Visual flash for all pieces (simple celebration / signal)
            llSetColor(<1,1,0>, ALL_SIDES);
            llSleep(1.0);
            updateVisuals(gCurrentCell);
            return;
        }

        // ---- Status text (only root prim should display this,
        //      but if a HUD prim wants to forward it that's fine) ----
        if (num == LM_STATUS) {
            // Individual piece prims ignore status; root prim handles it.
            return;
        }
    }
}
