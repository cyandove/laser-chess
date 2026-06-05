// ============================================================
// Advanced Laser Chess — Laser Beam FX (particle ribbon)
// Drop into a SINGLE dedicated child prim named "fxbeam".
// Works alongside the cell-flash already done by board_renderer.lsl —
// this adds a glowing ribbon that traces the beam's actual path,
// bends and all.
//
// HOW IT WORKS:
//   1. At start-up it scans the linkset for prims named cell_X_Y and
//      caches each one's LOCAL position (relative to root). Reset this
//      script AFTER the board cells are named/positioned so the cache fills.
//   2. On LM_LASER_PATH it converts the path's cell coords to world
//      points and sweeps this prim through them with a ribbon particle
//      system running, leaving a connected beam. Then it parks itself
//      back at its home position and stops emitting.
//
// SWAPPABLE: delete this prim (or just this script) to disable the
// ribbon FX; the game and the cell-flash keep working unchanged.
// ============================================================

integer LM_LASER_PATH = 4;   // must match game_controller.lsl

// ---- Beam look ----
vector  BEAM_COL_START = <1.0, 0.25, 0.0>; // hot orange at the core
vector  BEAM_COL_END   = <1.0, 0.85, 0.2>; // fading to yellow
float   BEAM_SCALE     = 0.35;             // ribbon width (m) — wider, easier to see
float   BEAM_AGE       = 1.4;              // particle lifetime (s) — lingers
float   STEP_TIME      = 0.08;             // seconds per path point (matches BEAM_STEP)
float   HOLD_TIME      = 0.60;             // linger after last point

// ---- Cached geometry: strided ["x,y", <pos>, "x,y", <pos>, ...] ----
list    gCellPos;

// ---- Sweep state ----
list    gBeamPts;        // list of world-space vectors for current shot
integer gStep;           // index into gBeamPts
vector  gHome;           // this prim's resting local position (rel. to root)
float   gCellSpacing = 1.0; // world distance between adjacent cells

// ============================================================
// Build the cell -> world-position cache
// ============================================================
buildCellCache() {
    gCellPos = [];
    integer n = llGetNumberOfPrims();
    integer i;
    for (i = 1; i <= n; ++i) {
        string nm = llGetLinkName(i);
        if (llGetSubString(nm, 0, 4) == "cell_") {
            list parts = llParseString2List(nm, ["_"], []);
            if (llGetListLength(parts) >= 3) {
                string xy = llList2String(parts, 1) + "," + llList2String(parts, 2);
                // LOCAL position (relative to root) — reliable for child prims,
                // unlike PRIM_POSITION which can't be set on a child via SLPPF.
                vector p = llList2Vector(
                    llGetLinkPrimitiveParams(i, [PRIM_POS_LOCAL]), 0);
                gCellPos += [xy, p];
            }
        }
    }
}

vector cellWorld(string xy) {
    integer idx = llListFindList(gCellPos, [xy]);
    if (idx < 0) return ZERO_VECTOR;
    return llList2Vector(gCellPos, idx + 1);
}

// Distance between two horizontally-adjacent cells, used to tell a normal
// one-cell beam step from a fork jump (where the DFS path leaps from the end
// of one branch back to a splitter to start the other).
measureSpacing() {
    vector a = cellWorld("0,0");
    vector b = cellWorld("1,0");
    if (a != ZERO_VECTOR && b != ZERO_VECTOR) gCellSpacing = llVecDist(a, b);
}

// ============================================================
// Particle ribbon control
// ============================================================
startRibbon() {
    llParticleSystem([
        PSYS_PART_FLAGS,  PSYS_PART_RIBBON_MASK
                        | PSYS_PART_EMISSIVE_MASK
                        | PSYS_PART_INTERP_COLOR_MASK
                        | PSYS_PART_INTERP_SCALE_MASK,
        PSYS_SRC_PATTERN,        PSYS_SRC_PATTERN_DROP,
        PSYS_PART_START_COLOR,   BEAM_COL_START,
        PSYS_PART_END_COLOR,     BEAM_COL_END,
        PSYS_PART_START_ALPHA,   1.0,
        PSYS_PART_END_ALPHA,     0.0,
        PSYS_PART_START_SCALE,   <BEAM_SCALE, BEAM_SCALE, 0.0>,
        PSYS_PART_END_SCALE,     <BEAM_SCALE * 0.4, BEAM_SCALE * 0.4, 0.0>,
        PSYS_PART_MAX_AGE,       BEAM_AGE,
        PSYS_SRC_BURST_RATE,     0.0,   // continuous emission while moving
        PSYS_SRC_BURST_PART_COUNT, 1,
        PSYS_SRC_BURST_RADIUS,   0.0,
        PSYS_SRC_BURST_SPEED_MIN, 0.0,  // ribbon trails the emitter, no fling
        PSYS_SRC_BURST_SPEED_MAX, 0.0
    ]);
}

stopRibbon() {
    llParticleSystem([]);
}

// Move this prim to a LOCAL point (relative to root). PRIM_POS_LOCAL is the
// reliable child-prim positioner; PRIM_POSITION can't be set on a child here.
moveTo(vector localPos) {
    llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_POS_LOCAL, localPos]);
}

default {
    state_entry() {
        llSetObjectName("fxbeam");
        // Hide the emitter prim itself — only the particles should show.
        llSetLinkAlpha(LINK_THIS, 0.0, ALL_SIDES);
        gHome = llList2Vector(
            llGetLinkPrimitiveParams(LINK_THIS, [PRIM_POS_LOCAL]), 0);
        buildCellCache();
        measureSpacing();
    }

    // Rebuild the cache if the build changes (prims added/moved/renamed).
    changed(integer c) {
        if (c & (CHANGED_LINK | CHANGED_SCALE)) {
            gHome = llList2Vector(
                llGetLinkPrimitiveParams(LINK_THIS, [PRIM_POS_LOCAL]), 0);
            buildCellCache();
            measureSpacing();
        }
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num != LM_LASER_PATH) return;

        // Build world-space point list from "x0,y0;x1,y1;..."
        list segs = llParseString2List(str, [";"], []);
        gBeamPts = [];
        integer i;
        for (i = 0; i < llGetListLength(segs); ++i) {
            vector w = cellWorld(llList2String(segs, i));
            if (w != ZERO_VECTOR) gBeamPts += [w];
        }

        // Need at least two points to draw a ribbon.
        if (llGetListLength(gBeamPts) < 2) {
            gBeamPts = [];
            return;
        }

        // Seed the emitter at the source, then sweep.
        gStep = 0;
        moveTo(llList2Vector(gBeamPts, 0));
        startRibbon();
        llSetTimerEvent(STEP_TIME);
    }

    timer() {
        ++gStep;

        if (gStep < llGetListLength(gBeamPts)) {
            vector cur  = llList2Vector(gBeamPts, gStep);
            vector prev = llList2Vector(gBeamPts, gStep - 1);
            // A jump bigger than one cell means the DFS path crossed from one
            // split fork to another. Break the ribbon so it doesn't draw a
            // line across the board: stop emitting, teleport, start fresh.
            if (llVecDist(prev, cur) > gCellSpacing * 1.5) {
                stopRibbon();
                moveTo(cur);
                startRibbon();
            } else {
                moveTo(cur);
            }
            return;
        }

        // Past the end: linger so the ribbon is visible, then clean up.
        if (gStep == llGetListLength(gBeamPts)) {
            llSetTimerEvent(HOLD_TIME); // one longer tick to hold the beam
            return;
        }

        // Final tick: stop emitting and park the emitter back home.
        llSetTimerEvent(0.0);
        stopRibbon();
        moveTo(gHome);
        gBeamPts = [];
        gStep = 0;
    }
}
