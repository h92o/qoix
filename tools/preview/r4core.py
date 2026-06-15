"""
R4Viz preview renderer.

A faithful CPU port of the Swift R4VizKit math (Matrix4, GL projection, the
synthetic audio source, and each scene's render()) so we can render actual
frames headlessly and confirm the visuals — the SwiftUI app itself can't run in
this Linux container. Kept deliberately 1:1 with the Swift so the preview is
representative.
"""
import math, numpy as np
from PIL import Image, ImageDraw

# ---------------------------------------------------------------- Matrix4 (column-major, mirrors Matrix4.swift)
def m_identity():
    return [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]  # columns

def m_mul(a, b):  # a*b, columns
    out = []
    for k in range(4):
        col = b[k]
        out.append([sum(a[j][i]*col[j] for j in range(4)) for i in range(4)])
    return out

def m_translate(x,y,z):
    m = m_identity(); m[3] = [x,y,z,1]; return m

def m_scale(x,y,z):
    return [[x,0,0,0],[0,y,0,0],[0,0,z,0],[0,0,0,1]]

def m_rotate(deg,x,y,z):
    ln = math.sqrt(x*x+y*y+z*z)
    if ln == 0: return m_identity()
    a = deg*math.pi/180; x,y,z = x/ln,y/ln,z/ln
    c,s,t = math.cos(a), math.sin(a), 1-math.cos(a)
    col0 = [t*x*x+c,   t*x*y+s*z, t*x*z-s*y, 0]
    col1 = [t*x*y-s*z, t*y*y+c,   t*y*z+s*x, 0]
    col2 = [t*x*z+s*y, t*y*z-s*x, t*z*z+c,   0]
    return [col0,col1,col2,[0,0,0,1]]

def m_perspective(fovy,aspect,near,far):
    f = 1/math.tan(fovy*math.pi/360)
    return [[f/aspect,0,0,0],[0,f,0,0],
            [0,0,(far+near)/(near-far),-1],
            [0,0,(2*far*near)/(near-far),0]]

def matvec(m,v):
    return [sum(m[k][i]*v[k] for k in range(4)) for i in range(4)]

# ---------------------------------------------------------------- color (mirrors ColorUtil.swift)
def hsb(h,s,b):
    if s<=0: return (b,b,b)
    h = (h%1)*6; i=int(h); f=h-i
    p=b*(1-s); q=b*(1-s*f); t=b*(1-s*(1-f))
    return [(b,t,p),(q,b,p),(p,b,t),(p,q,b),(t,p,b),(b,p,q)][i%6]

# ---------------------------------------------------------------- GL (mirrors GL.swift)
class GL:
    def __init__(self, w, h, ss=2):
        self.W, self.H = w*ss, h*ss
        self.ss = ss
        self.buf = np.zeros((self.H, self.W, 3), np.float32)
        self.proj = m_perspective(60, self.W/self.H, 0.1, 100)
        self.stack = [m_identity()]
        self.rgba = (1,1,1,1)
        self.additive = False

    @property
    def cur(self): return self.stack[-1]
    @cur.setter
    def cur(self, v): self.stack[-1] = v

    def push(self): self.stack.append([c[:] for c in self.cur])
    def pop(self):
        if len(self.stack) > 1: self.stack.pop()
    def translate(self,x,y,z): self.cur = m_mul(self.cur, m_translate(x,y,z))
    def rotate(self,d,x,y,z):  self.cur = m_mul(self.cur, m_rotate(d,x,y,z))
    def scale(self,x,y,z):     self.cur = m_mul(self.cur, m_scale(x,y,z))
    def color(self,r,g,b,a=1): self.rgba = (r,g,b,a)
    def addBlend(self): self.additive = True
    def normBlend(self): self.additive = False

    def fillBackground(self, r,g,b,a=1):
        self.buf[:] = (r,g,b)

    def _project(self, p):
        eye = matvec(self.cur, [p[0],p[1],p[2],1])
        clip = matvec(self.proj, eye)
        if clip[3] <= 1e-4: return None
        w = clip[3]
        return ((clip[0]/w*0.5+0.5)*self.W, (1-(clip[1]/w*0.5+0.5))*self.H, w)

    def _composite(self, mask_img, x0, y0, shade=1.0):
        r,g,b,a = self.rgba
        col = np.array([r*shade, g*shade, b*shade], np.float32)
        m = (np.asarray(mask_img, np.float32)/255.0) * a
        if m.max() <= 0: return
        h,w = m.shape
        region = self.buf[y0:y0+h, x0:x0+w]
        m3 = m[...,None]
        if self.additive:
            region += col*m3
        else:
            region[:] = region*(1-m3) + col*m3

    def _poly(self, pts3, shade=1.0):
        scr = []
        for p in pts3:
            s = self._project(p)
            if s is None: return
            scr.append((s[0], s[1]))
        xs = [s[0] for s in scr]; ys = [s[1] for s in scr]
        x0,y0 = int(math.floor(min(xs))), int(math.floor(min(ys)))
        x1,y1 = int(math.ceil(max(xs))), int(math.ceil(max(ys)))
        x0 = max(0,x0); y0 = max(0,y0); x1 = min(self.W,x1); y1 = min(self.H,y1)
        if x1<=x0 or y1<=y0: return
        mask = Image.new('L', (x1-x0, y1-y0), 0)
        ImageDraw.Draw(mask).polygon([(s[0]-x0, s[1]-y0) for s in scr], fill=255)
        self._composite(mask, x0, y0, shade)

    def quad(self):
        self._poly([(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0)])

    def cube(self):
        v=[(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
        faces=[([0,1,2,3],0.55),([5,4,7,6],1.0),([4,0,3,7],0.70),([1,5,6,2],0.85),([3,2,6,7],0.95),([4,5,1,0],0.65)]
        def depth(idx):
            avg=[sum(v[i][k] for i in idx)/len(idx) for k in range(3)]
            return matvec(self.cur,[avg[0],avg[1],avg[2],1])[2]
        for idx,shade in sorted(faces, key=lambda fs: depth(fs[0])):
            self._poly([v[i] for i in idx], shade)

    def point(self, p, size):
        s = self._project(p)
        if s is None: return
        cx,cy,w = s
        rad = size/w*self.H*0.5
        if rad < 0.2: return
        x0,y0 = int(math.floor(cx-rad)), int(math.floor(cy-rad))
        x1,y1 = int(math.ceil(cx+rad)), int(math.ceil(cy+rad))
        x0=max(0,x0);y0=max(0,y0);x1=min(self.W,x1);y1=min(self.H,y1)
        if x1<=x0 or y1<=y0: return
        mask=Image.new('L',(x1-x0,y1-y0),0)
        ImageDraw.Draw(mask).ellipse([cx-rad-x0,cy-rad-y0,cx+rad-x0,cy+rad-y0], fill=255)
        self._composite(mask, x0, y0)

    def image(self):
        arr = np.clip(self.buf,0,1)
        img = Image.fromarray((arr*255).astype(np.uint8), 'RGB')
        if self.ss != 1:
            img = img.resize((self.W//self.ss, self.H//self.ss), Image.LANCZOS)
        return img

# ---------------------------------------------------------------- synthetic audio (mirrors SignalSource.swift)
class Audio:
    def __init__(self, time, timepass, bins=64, bpm=120):
        t=time; period=60/bpm; phase=(time%period)/period
        kick=max(0,1-phase)**3
        self.time=time; self.timepass=timepass
        self.beat = (int((time)/period) != int((time-timepass)/period)) if timepass>0 else False
        env=0.45+0.55*kick
        self.sounda=max(-1,min(1,(math.sin(t*2.3)*0.4+kick*0.9)-0.15))
        self.spectrum=[]
        for bn in range(bins):
            f=bn/bins; tilt=(1-f)**1.8; sweep=0.5+0.5*math.sin(t*1.3+f*6)
            self.spectrum.append(max(0,min(1,tilt*sweep*env+kick*tilt*0.6)))
    def band(self,lo,hi):
        sp=self.spectrum; n=len(sp)
        a=int(lo*n); b=max(int(hi*n),a+1)
        a=min(a,n-1); b=min(b,n)
        sl=sp[a:b]
        return sum(sl)/len(sl) if sl else 0
