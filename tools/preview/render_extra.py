import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from r4core import Audio, hsb
from render import warm_and_render, label

# ---------------------------------------------------------------- overlays (post-process a rendered frame)
def ov_blur(img, a):       return img.filter(ImageFilter.GaussianBlur(6))
def ov_scanlines(img, a):
    arr = np.asarray(img).astype(np.float32)
    arr[1::3] *= 0.45
    return Image.fromarray(arr.astype(np.uint8))
def ov_rgb_split(img, a):
    arr = np.asarray(img).astype(np.int16)
    off = int(2 + 12*a.band(0,0.15))
    r = np.roll(arr[...,0], -off, axis=1); b = np.roll(arr[...,2], off, axis=1)
    return Image.fromarray(np.clip(np.stack([r,arr[...,1],b],-1),0,255).astype(np.uint8))
def ov_strobe(img, a):
    return Image.blend(img, Image.new('RGB', img.size, (255,255,255)), 0.45)
def ov_spectrum(img, a):
    img = img.copy(); d = ImageDraw.Draw(img, 'RGBA'); W,H = img.size
    bins = a.spectrum; bw = W/len(bins)
    for i,m in enumerate(bins):
        h = max(1, m*H*0.3); c = hsb(i/len(bins)*0.8, 0.85, 0.95)
        d.rectangle([i*bw, H-h, i*bw+bw*0.85, H],
                    fill=(int(c[0]*255),int(c[1]*255),int(c[2]*255),190))
    return img

OVERLAYS = [("None", lambda i,a: i), ("Blur", ov_blur), ("Scanlines", ov_scanlines),
            ("Spectrum", ov_spectrum), ("Strobe", ov_strobe), ("RGB Split", ov_rgb_split)]

# ---------------------------------------------------------------- fades (composite two frames by progress t)
def scale_center(img, factor):
    W,H = img.size; nw,nh = max(1,int(W*factor)), max(1,int(H*factor))
    s = img.resize((nw,nh), Image.LANCZOS); out = Image.new('RGB',(W,H),(0,0,0))
    out.paste(s, ((W-nw)//2,(H-nh)//2)); return out

def fade_cross(a,b,t): return Image.blend(a,b,t)
def fade_slide(a,b,t):
    W,H = a.size; out = Image.new('RGB',(W,H),(0,0,0))
    out.paste(a,(int(-t*W),0)); out.paste(b,(int((1-t)*W),0)); return out
def fade_zoom(a,b,t):
    fa = scale_center(a, 1+0.6*t); fb = scale_center(b, 0.5+0.5*t)
    return Image.blend(fa, fb, t)

FADES = [("Cross", fade_cross), ("Slide", fade_slide), ("Zoom", fade_zoom)]

# ---------------------------------------------------------------- sheets
def grid(cells, cols, cw, ch, pad=6):
    rows = (len(cells)+cols-1)//cols
    W = cols*cw+(cols+1)*pad; H = rows*ch+(rows+1)*pad
    sheet = Image.new('RGB',(W,H),(18,18,20))
    for i,(name,img) in enumerate(cells):
        im = label(img.copy().resize((cw,ch)), name) if name else img.resize((cw,ch))
        sheet.paste(im, (pad+(i%cols)*(cw+pad), pad+(i//cols)*(ch+pad)))
    return sheet

def graphs_sheet():
    cells = [("Medusa ∘ Solid (graph)", warm_and_render("graph-medusa", 360,270)),
             ("Cube Field ∘ Solid (graph)", warm_and_render("graph-cubefield", 360,270))]
    grid(cells, 2, 360, 270).save("/tmp/r4preview/graphs.png"); print("graphs.png")

def overlays_sheet():
    base = warm_and_render("medusa", 360, 270); a = Audio(2.05, 1/60)
    cells = [(name, fn(base, a)) for name,fn in OVERLAYS]
    grid(cells, 3, 360, 270).save("/tmp/r4preview/overlays.png"); print("overlays.png")

def fades_sheet():
    frm = warm_and_render("cubefield", 320, 240)
    to  = warm_and_render("medusa", 320, 240)
    ts = [0.0, 0.33, 0.66, 1.0]
    cells = []
    for name, fn in FADES:
        for t in ts:
            cells.append((f"{name} t={t:.2f}", fn(frm, to, t)))
    grid(cells, 4, 320, 240).save("/tmp/r4preview/fades.png"); print("fades.png")

if __name__ == "__main__":
    graphs_sheet(); overlays_sheet(); fades_sheet()
