#!/usr/bin/env python3
"""
Advanced Laser Chess — piece texture generator (pure standard library).

Draws each piece as a white, anti-aliased icon on a transparent background,
facing NORTH (the game rotates the texture for the 8 facings) and tinted
red/green per owner in-world via PRIM_COLOR. Writes 256x256 RGBA PNGs with
no third-party dependencies (uses zlib/struct from the stdlib).

Run:  python3 tools/gen_textures.py
Out:  textures/tex_<piece>.png
"""
import zlib, struct, math, os

SIZE = 256
OUT  = os.path.join(os.path.dirname(__file__), "..", "textures")
FEATHER = 3.0 / SIZE * 2.0   # ~1.5px edge softness, in [-1,1] units

# ---------- tiny vector / SDF helpers (coords in [-1,1], y up) ----------
def clamp(v, a, b): return a if v < a else (b if v > b else v)
def dot(a, b): return a[0]*b[0] + a[1]*b[1]
def sub(a, b): return (a[0]-b[0], a[1]-b[1])

def sd_circle(p, c, r):
    d = sub(p, c)
    return math.sqrt(dot(d, d)) - r

def sd_segment(p, a, b):
    pa = sub(p, a); ba = sub(b, a)
    h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)
    d = (pa[0] - ba[0]*h, pa[1] - ba[1]*h)
    return math.sqrt(dot(d, d))

def sd_poly(p, v):
    """Signed distance to a polygon (negative inside). Inigo Quilez's method."""
    N = len(v)
    d = dot(sub(p, v[0]), sub(p, v[0]))
    s = 1.0
    j = N - 1
    for i in range(N):
        e = sub(v[j], v[i]); w = sub(p, v[i])
        t = clamp(dot(w, e) / dot(e, e), 0.0, 1.0)
        b = (w[0] - e[0]*t, w[1] - e[1]*t)
        d = min(d, dot(b, b))
        c1 = p[1] >= v[i][1]
        c2 = p[1] <  v[j][1]
        c3 = (e[0]*w[1] - e[1]*w[0]) > 0.0
        if (c1 and c2 and c3) or ((not c1) and (not c2) and (not c3)):
            s = -s
        j = i
    return s * math.sqrt(d)

# coverage from a signed distance: filled if d<0
def fill(d):   return clamp(0.5 - d / FEATHER, 0.0, 1.0)
def stroke(d, hw): return clamp(0.5 - (abs(d) - hw) / FEATHER, 0.0, 1.0)

def regular_poly(n, R, rot=0.0):
    return [(R*math.cos(rot + i*2*math.pi/n), R*math.sin(rot + i*2*math.pi/n))
            for i in range(n)]

# octagon with a flat top/bottom/sides (vertices offset by 22.5°)
def octagon(R): return regular_poly(8, R, math.radians(22.5))

# ---------------------------- piece icons -------------------------------
# Each returns coverage alpha 0..1 for point p=(x,y). Union via max().

def king(p):
    dia = [(0,0.82),(0.82,0),(0,-0.82),(-0.82,0)]
    inner = [(0,0.34),(0.34,0),(0,-0.34),(-0.34,0)]
    a = stroke(sd_poly(p, dia), 0.07)         # diamond outline
    a = max(a, fill(sd_poly(p, inner)))       # solid core
    return a

def laser(p):
    a = fill(sd_circle(p, (0,-0.35), 0.36))   # base
    barrel = [(-0.14,-0.35),(0.14,-0.35),(0.14,0.45),(-0.14,0.45)]
    a = max(a, fill(sd_poly(p, barrel)))      # barrel pointing north
    muzzle = [(-0.14,0.45),(0.14,0.45),(0.34,0.84),(-0.34,0.84)]  # flared emitter
    a = max(a, fill(sd_poly(p, muzzle)))
    return a

def stunner(p):
    # Directional: solid body at the back (south), a two-prong emitter "fork"
    # at the front (north) so it's clear which end is the gun.
    a = fill(sd_circle(p, (0,-0.4), 0.34))            # body
    a = max(a, fill(sd_poly(p, [(-0.13,-0.4),(0.13,-0.4),(0.13,0.05),(-0.13,0.05)])))  # neck
    a = max(a, stroke(sd_segment(p, (-0.22,0.0), (0.22,0.0)), 0.07))  # yoke
    a = max(a, stroke(sd_segment(p, (-0.22,0.0), (-0.22,0.78)), 0.07)) # left prong
    a = max(a, stroke(sd_segment(p, ( 0.22,0.0), ( 0.22,0.78)), 0.07)) # right prong
    return a

def oneway(p):
    bar = [(-0.78,-0.1),(0.78,-0.1),(0.78,0.1),(-0.78,0.1)]
    a = fill(sd_poly(p, bar))                 # the mirror bar
    a = max(a, stroke(sd_segment(p, (0,-0.6), (0,0.6)), 0.06))      # arrow shaft
    a = max(a, stroke(sd_segment(p, (0,0.6), (-0.22,0.34)), 0.06))  # arrowhead
    a = max(a, stroke(sd_segment(p, (0,0.6), (0.22,0.34)), 0.06))   # arrowhead
    return a

def trimir(p):
    # Reflective edge faces the way the piece faces. At orient 0 (N) that edge
    # is the flat TOP (facing up); the body/apex points the opposite way. The
    # game rotates the texture for the other 7 facings.
    tri = [(-0.78, 0.42), (0.78, 0.42), (0.78, -0.74)]  # right triangle, flat top
    a = fill(sd_poly(p, tri))
    a = max(a, stroke(sd_segment(p, (-0.78,0.42), (0.78,0.42)), 0.08))  # bright mirror edge (N)
    return a

def bomb(p):
    a = fill(sd_circle(p, (0,0), 0.46))
    for ang in (0, 90, 180, 270):            # 4 spikes (orthogonal config)
        r = math.radians(ang)
        a = max(a, stroke(sd_segment(p, (0.4*math.cos(r),0.4*math.sin(r)),
                                         (0.72*math.cos(r),0.72*math.sin(r))), 0.06))
    return a

def hypergon(p):
    oct = octagon(0.72)
    a = stroke(sd_poly(p, oct), 0.05)        # rim
    for v in oct:                            # spokes to each vertex
        a = max(a, stroke(sd_segment(p, (0,0), v), 0.045))
    a = max(a, fill(sd_circle(p, (0,0), 0.1)))
    return a

def splitter(p):
    tri = [(0,0.78),(-0.68,-0.55),(0.68,-0.55)]   # apex (vertex) points north
    return fill(sd_poly(p, tri))

def poct(p):
    oct = octagon(0.72)
    a = stroke(sd_poly(p, oct), 0.05)        # thin outline
    # thick "shield" over the top three faces (edges between the upper verts)
    top = [v for v in oct if v[1] > 0.2]
    top.sort(key=lambda v: v[0])
    for i in range(len(top)-1):
        a = max(a, stroke(sd_segment(p, top[i], top[i+1]), 0.13))
    return a

def foct(p):
    a = stroke(sd_poly(p, octagon(0.74)), 0.06)   # double-walled ring =
    a = max(a, stroke(sd_poly(p, octagon(0.50)), 0.06))  #  fully mirrored
    a = max(a, fill(sd_circle(p, (0,0), 0.12)))
    return a

def hole(p):
    a = stroke(sd_segment(p, (-0.62,-0.62), (0.62,0.62)), 0.11)
    a = max(a, stroke(sd_segment(p, (-0.62,0.62), (0.62,-0.62)), 0.11))
    return a

def hyperhole(p):
    a = 0.0
    for ang in (0, 45, 90, 135):             # 8-point asterisk
        r = math.radians(ang)
        a = max(a, stroke(sd_segment(p, (-0.72*math.cos(r),-0.72*math.sin(r)),
                                        (0.72*math.cos(r), 0.72*math.sin(r))), 0.06))
    a = max(a, fill(sd_circle(p, (0,0), 0.14)))
    return a

ICONS = [
    ("king", king), ("laser", laser), ("stunner", stunner), ("oneway", oneway),
    ("trimir", trimir), ("bomb", bomb), ("hypergon", hypergon),
    ("splitter", splitter), ("poct", poct), ("foct", foct),
    ("hole", hole), ("hyperhole", hyperhole),
]

# ------------------------------ PNG output ------------------------------
def write_png(path, size, fn):
    raw = bytearray()
    for py in range(size):
        raw.append(0)                                  # filter: none
        y = 1.0 - (py + 0.5) / size * 2.0
        for px in range(size):
            x = (px + 0.5) / size * 2.0 - 1.0
            a = int(clamp(fn((x, y)), 0.0, 1.0) * 255 + 0.5)
            raw += bytes((255, 255, 255, a))           # white, alpha = coverage
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))

def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ICONS:
        path = os.path.join(OUT, "tex_%s.png" % name)
        write_png(path, SIZE, fn)
        print("wrote", os.path.relpath(path))

if __name__ == "__main__":
    main()
