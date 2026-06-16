#!/usr/bin/env python3
"""CPU renderer for the fractal pyramid shader variants.

Ports the GLSL raymarcher to vectorized numpy so a still frame can be produced
without a GPU. Writes PNGs (via zlib, no Pillow needed). This is for previews /
sanity-checking only -- the real shaders run on the GPU via Shadertoy or the
WebGL page. Original shader by bradjamesgrant (shadertoy.com/view/tsXBzS).
"""
import struct, zlib, sys
import numpy as np

W, H = 480, 270          # preview resolution
STEPS = 64
TIME = 12.0              # fixed iTime for a representative frame


def rotate(x, y, a):
    c, s = np.cos(a), np.sin(a)
    return x * c + y * s, x * (-s) + y * c   # p * mat2(c,s,-s,c)


def make_map(folds, spin):
    def mp(px, py, pz):
        for _ in range(folds):
            t = TIME * spin
            px, pz = rotate(px, pz, t)
            px, py = rotate(px, py, t * 1.89)
            px, pz = np.abs(px), np.abs(pz)
            px -= 0.5
            pz -= 0.5
        return (np.sign(px) * px + np.sign(py) * py + np.sign(pz) * pz) / 5.0
    return mp


def render(folds, spin, orbit, spread, glow, colA, colB):
    mp = make_map(folds, spin)
    # pixel grid -> uv (centered, aspect-correct by width), matching GLSL
    xs = np.arange(W) + 0.5
    ys = np.arange(H) + 0.5
    gx, gy = np.meshgrid(xs, ys)
    uvx = (gx - W / 2.0) / W
    uvy = (gy - H / 2.0) / W

    # camera orbiting the origin
    rox, roz = rotate(np.float64(0.0), np.float64(-50.0), TIME * orbit)
    roy = 0.0
    cf = np.array([-rox, -roy, -roz]); cf /= np.linalg.norm(cf)
    cs = np.cross(cf, [0.0, 1.0, 0.0]); cs /= np.linalg.norm(cs)
    cu = np.cross(cf, cs); cu /= np.linalg.norm(cu)

    uux = rox + cf[0] * 3.0 + uvx * cs[0] + uvy * cu[0]
    uuy = roy + cf[1] * 3.0 + uvx * cs[1] + uvy * cu[1]
    uuz = roz + cf[2] * 3.0 + uvx * cs[2] + uvy * cu[2]
    rdx, rdy, rdz = uux - rox, uuy - roy, uuz - roz
    rlen = np.sqrt(rdx * rdx + rdy * rdy + rdz * rdz)
    rdx, rdy, rdz = rdx / rlen, rdy / rlen, rdz / rlen

    t = np.zeros((H, W))
    col = np.zeros((H, W, 3))
    active = np.ones((H, W), dtype=bool)
    cA = np.array(colA); cB = np.array(colB)

    for _ in range(STEPS):
        px = rox + rdx * t
        py = roy + rdy * t
        pz = roz + rdz * t
        d = mp(px, py, pz) * 0.5
        active &= (d >= 0.02) & (d <= 100.0)
        if not active.any():
            break
        plen = np.sqrt(px * px + py * py + pz * pz)
        dd = (plen * spread)[..., None]
        pal = cA * (1.0 - dd) + cB * dd
        contrib = pal / (glow * np.maximum(np.abs(d), 1e-6))[..., None]
        col += np.where(active[..., None], contrib, 0.0)
        t = np.where(active, t + d, t)

    img = np.clip(col, 0.0, 1.0)
    return (img * 255).astype(np.uint8)


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


# folds, spin, orbit, spread, glow, colA, colB
VARIANTS = {
    "original": (8,  0.20, 1.0, 0.10, 400, (0.2, 0.7, 0.9),     (1.0, 0.0, 1.0)),
    "dense":    (12, 0.12, 0.4, 0.10, 400, (0.2, 0.7, 0.9),     (1.0, 0.0, 1.0)),
    "ember":    (9,  0.25, 0.8, 0.13, 300, (1.0, 0.667, 0.2),   (0.8, 0.067, 0.2)),
    "ice":      (10, 0.15, 0.6, 0.09, 450, (0.682, 0.914, 1.0), (0.133, 0.333, 0.8)),
    "acid":     (7,  0.30, 1.2, 0.15, 280, (0.8, 1.0, 0.2),     (1.0, 0.0, 0.4)),
    "mono":     (8,  0.18, 0.7, 0.10, 380, (1.0, 1.0, 1.0),     (0.333, 0.4, 0.667)),
}

if __name__ == "__main__":
    names = sys.argv[1:] or list(VARIANTS)
    for name in names:
        params = VARIANTS[name]
        rgb = render(*params)
        out = f"/tmp/preview_{name}.png"
        write_png(out, rgb)
        print(f"wrote {out}  (nonzero pixels: {(rgb.sum(2) > 0).mean()*100:.1f}%)")
