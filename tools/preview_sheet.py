#!/usr/bin/env python3
"""Composite all piece icons (white on dark cells) into one PNG for review."""
import zlib, struct, os, gen_textures as G

COLS, ROWS, CELL, ICON = 4, 3, 150, 132
W, H = COLS*CELL, ROWS*CELL
BG = (40, 42, 48)
LINE = (70, 73, 82)

def main():
    px = bytearray()
    for y in range(H):
        px.append(0)
        cyr = y // CELL
        for x in range(W):
            cxr = x // CELL
            idx = cyr*COLS + cxr
            r, g, b = BG
            # cell grid lines
            if x % CELL < 1 or y % CELL < 1:
                r, g, b = LINE
            if idx < len(G.ICONS):
                fn = G.ICONS[idx][1]
                # local icon coords in [-1,1]
                lx = ((x % CELL) - CELL/2) / (ICON/2)
                ly = -(((y % CELL) - CELL/2) / (ICON/2))
                if -1.1 < lx < 1.1 and -1.1 < ly < 1.1:
                    a = G.clamp(fn((lx, ly)), 0.0, 1.0)
                    r = int(r + (255 - r)*a)
                    g = int(g + (255 - g)*a)
                    b = int(b + (255 - b)*a)
            px += bytes((r, g, b))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t+d) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8-bit RGB
    out = os.path.join(os.path.dirname(__file__), "..", "textures", "_preview.png")
    with open(out, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(px), 9)))
        f.write(chunk(b"IEND", b""))
    print("wrote", out)

if __name__ == "__main__":
    main()
