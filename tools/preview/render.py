import numpy as np
from PIL import Image, ImageDraw, ImageFont
from r4core import GL, Audio
from scenes import SCENES, SOLID_BG

def warm_and_render(name, w, h, ss=2, t_end=2.05, dt=1/60):
    """Advance scene state cheaply, then render the final frame at full res."""
    if name in SOLID_BG:
        r,g,b,fn = SOLID_BG[name]; bg=(r,g,b)
    else:
        fn = SCENES[name]; bg=None
    st = {}
    warm = GL(48, 36, 1)
    t = 0.0
    while t < t_end - dt:
        t += dt; a = Audio(t, dt)
        warm.buf[:] = bg if bg else 0
        fn(warm, a, st)
    final = GL(w, h, ss)
    a = Audio(t_end, dt)
    final.buf[:] = bg if bg else 0
    fn(final, a, st)
    return final.image()

def rgb_split(img, off=6):
    arr = np.asarray(img).astype(np.int16)
    r = np.roll(arr[...,0], -off, axis=1)
    b = np.roll(arr[...,2],  off, axis=1)
    out = np.stack([r, arr[...,1], b], -1)
    return Image.fromarray(np.clip(out,0,255).astype(np.uint8))

def label(img, text):
    d = ImageDraw.Draw(img)
    try: font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    except Exception: font = ImageFont.load_default()
    d.rectangle([0,0,len(text)*9+12,24], fill=(0,0,0))
    d.text((6,3), text, fill=(255,255,255), font=font)
    return img

def montage():
    cells = [
        ("Spinner",   warm_and_render("spinner", 360, 270)),
        ("Thumper",   warm_and_render("thumper", 360, 270)),
        ("Cube Field",warm_and_render("cubefield", 360, 270)),
        ("Spectrum",  warm_and_render("spectrum", 360, 270)),
        ("Medusa",    warm_and_render("medusa", 360, 270)),
        ("Medusa + RGB Split overlay", rgb_split(warm_and_render("medusa", 360, 270), 7)),
    ]
    cols, rows = 3, 2
    cw, ch = 360, 270; pad = 6
    W = cols*cw + (cols+1)*pad; H = rows*ch + (rows+1)*pad
    sheet = Image.new('RGB', (W, H), (18,18,20))
    for i,(name,img) in enumerate(cells):
        img = label(img.copy(), name)
        x = pad + (i%cols)*(cw+pad); y = pad + (i//cols)*(ch+pad)
        sheet.paste(img, (x,y))
    sheet.save("/tmp/r4preview/montage.png")
    print("wrote montage.png", sheet.size)

def gif(name="medusa", w=320, h=240, seconds=2.6, fps=20):
    fn = SCENES[name]; st={}; dt=1/fps; frames=[]
    t=0.0; n=int(seconds*fps)
    for _ in range(n):
        t+=dt; a=Audio(t,dt)
        gl=GL(w,h,1); gl.buf[:]=0; fn(gl,a,st)
        frames.append(gl.image())
    frames[0].save(f"/tmp/r4preview/{name}.gif", save_all=True,
                   append_images=frames[1:], duration=int(1000/fps), loop=0)
    print(f"wrote {name}.gif", len(frames), "frames")

if __name__ == "__main__":
    montage()
    gif("medusa")
    gif("spinner")
