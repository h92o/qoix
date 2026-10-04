#!/usr/bin/env python3
"""CPU preview of octagram_pyramid.glsl (mashup). Renders each blend mode.
Faithful numpy port for previews only; the shader runs on GPU in Shadertoy.
Sources: bradjamesgrant (tsXBzS) + whisky_shusuky (tlVGDt), both CC BY-NC-SA 3.0.
"""
import struct, zlib, sys
import numpy as np

W, H = 420, 236
TIME = 19.0

def rot(x, y, a):
    c, s = np.cos(a), np.sin(a)
    return x * c + y * s, -x * s + y * c

def sdBox(px, py, pz, bx, by, bz):
    qx, qy, qz = np.abs(px) - bx, np.abs(py) - by, np.abs(pz) - bz
    mx = np.maximum(qx, 0.0); my = np.maximum(qy, 0.0); mz = np.maximum(qz, 0.0)
    outside = np.sqrt(mx*mx + my*my + mz*mz)
    inside = np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0.0)
    return outside + inside

def box(px, py, pz, scale):
    return -sdBox(px*scale, py*scale, pz*scale, 0.4, 0.4, 0.1) / 1.5

def box_set(px, py, pz, gTime):
    s = np.sin(gTime * 0.4)
    sc = 2.0 - np.abs(s) * 1.5
    def b(ox, oy, oz):
        x, y = rot(ox, oy, 0.8)
        return box(x, y, oz, sc)
    b1 = b(px, py + s*2.5, pz)
    b2 = b(px, py - s*2.5, pz)
    b3 = b(px + s*2.5, py, pz)
    b4 = b(px - s*2.5, py, pz)
    x5, y5 = rot(px, py, 0.8); b5 = box(x5, y5, pz, 0.5) * 6.0
    b6 = box(px, py, pz, 0.5) * 6.0
    return np.maximum.reduce([b1, b2, b3, b4, b5, b6])

def pyramid(px, py, pz):
    px, py, pz = px.copy(), py.copy(), pz.copy()
    for _ in range(8):
        t = TIME * 0.2
        px, pz = rot(px, pz, t)
        px, py = rot(px, py, t * 1.89)
        px, pz = np.abs(px), np.abs(pz)
        px -= 0.5; pz -= 0.5
    return (np.sign(px)*px + np.sign(py)*py + np.sign(pz)*pz) / 5.0

def combine(dO, dP, mode):
    if mode == 0: return np.minimum(dO, dP)
    if mode == 1: return np.maximum(dO, dP)
    if mode == 2: return np.maximum(dO, -dP)
    return (dO + dP) * 0.5

def palette(d):
    d = d[..., None]
    return np.array([0.2,0.7,0.9])*(1-d) + np.array([1.0,0.0,1.0])*d

def render(mode):
    gx, gy = np.meshgrid(np.arange(W)+0.5, np.arange(H)+0.5)
    m = min(W, H)
    px = (gx*2 - W) / m
    py = (gy*2 - H) / m
    # ray = normalize(vec3(p,1.5)); note GLSL y is up, fragCoord y from bottom
    rx, ry, rz = px, -py, np.full_like(px, 1.5)
    n = np.sqrt(rx*rx+ry*ry+rz*rz); rx, ry, rz = rx/n, ry/n, rz/n
    rx, ry = rot(rx, ry, np.sin(TIME*0.03)*5.0)
    ry, rz = rot(ry, rz, np.sin(TIME*0.05)*0.2)
    rox, roy, roz = 0.0, -0.2, TIME*4.0
    t = np.full((H, W), 0.1)
    ac = np.zeros((H, W))
    for i in range(99):
        posx = rox + rx*t; posy = roy + ry*t; posz = roz + rz*t
        posx = np.mod(posx-2.0,4.0)-2.0
        posy = np.mod(posy-2.0,4.0)-2.0
        posz = np.mod(posz-2.0,4.0)-2.0
        gTime = TIME - i*0.01
        dO = box_set(posx, posy, posz, gTime)
        dP = pyramid(posx, posy, posz)
        d = combine(dO, dP, mode)
        d = np.maximum(np.abs(d), 0.01)
        ac += np.exp(-d*23.0)
        t += d*0.55
    col = palette(np.clip(ac*0.03,0,1)) * (ac*0.02)[...,None]
    pulse = np.array([0.0, 0.15*abs(np.sin(TIME)), 0.4+0.2*np.sin(TIME)])
    col += pulse * (ac*0.015)[...,None]
    return (np.clip(col,0,1)*255).astype(np.uint8)

def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00"+rgb[y].tobytes() for y in range(h))
    def chunk(tag, data):
        c = tag+data
        return struct.pack(">I",len(data))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(png)

if __name__ == "__main__":
    names = {0:"union",1:"intersect",2:"subtract",3:"mix"}
    for mode, name in names.items():
        rgb = render(mode)
        out = f"/tmp/mashup_{mode}_{name}.png"
        write_png(out, rgb)
        print(f"wrote {out}")
