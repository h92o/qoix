import math
from r4core import hsb

def spinner(gl, a, st):
    st['bt'] = st.get('bt',0) + a.timepass*(1.0+max(a.sounda,0))
    bt = st['bt']
    gl.addBlend(); gl.push(); gl.translate(0,0,-3.5)
    s = 1.0+math.sin(bt)+math.cos(bt*1.245); s = s*0.05+0.95
    r = (a.sounda+math.sin(bt))*10
    hue = bt*0.05
    for i in range(8):
        c = hsb(hue,0.8,0.42);       gl.color(*c,0.16); gl.quad()
        c = hsb(hue+0.5,0.9,0.38);   gl.color(*c,0.08+0.10*i/8); gl.quad()
        gl.rotate(r,0,0,1); gl.scale(s,s,1)
    gl.pop(); gl.normBlend()

def thumper(gl, a, st):
    bass = a.band(0,0.12)
    th = st.get('th',0)
    if a.beat: th = 1
    th = max(th - a.timepass*3.5, bass); st['th']=th
    st['spin'] = st.get('spin',0) + a.timepass*(20+40*bass)
    gl.push(); gl.translate(0,0,-4.5); gl.rotate(st['spin'],0.3,1,0.15)
    sc = 1.0+0.6*th; gl.scale(sc,sc,sc)
    c = hsb(a.time*0.04,0.55,0.55+0.45*th); gl.color(*c,1); gl.cube(); gl.pop()

def _cf_reset(st):
    cubes=[]; cols=5; depth=14; sp=2.2
    for d in range(depth):
        for c in range(cols):
            x=(c-(cols-1)/2)*sp; y=math.sin(d*0.7+c)*0.6
            cubes.append((x,y,d/depth))
    st['cubes']=cubes; st['travel']=0; st['totalDepth']=depth*sp

def cubefield(gl, a, st):
    if 'cubes' not in st: _cf_reset(st)
    bass=a.band(0,0.15); st['travel']+=a.timepass*4.0*(1+bass)
    td=st['totalDepth']
    for (x,y,phase) in st['cubes']:
        z=-td+((phase*td+st['travel'])%td)
        if z>0: z-=td
        gl.push(); gl.translate(x,y,z); s=0.5+0.5*bass; gl.scale(s,s,s)
        near=max(0,min(1,(z+td)/td)); c=hsb(x*0.08+a.time*0.03,0.6,0.25+0.75*near)
        gl.color(*c,1); gl.cube(); gl.pop()

def spectrum(gl, a, st):
    bars=48; radius=2.6
    sm=st.get('sm',[0]*bars)
    st['rot']=st.get('rot',0)+a.timepass*(12+30*a.band(0,0.15))
    gl.push(); gl.translate(0,-0.2,-6.0); gl.rotate(-18,1,0,0); gl.rotate(st['rot'],0,1,0)
    for i in range(bars):
        f=i/bars; target=a.band(f*0.9,f*0.9+0.05)
        sm[i]=max(sm[i]-a.timepass*1.5,target)
        angle=i/bars*360; h=0.1+2.4*sm[i]
        gl.push(); gl.rotate(angle,0,1,0); gl.translate(0,h-1,-radius); gl.scale(0.12,h,0.12)
        c=hsb(f*0.8,0.85,0.4+0.6*sm[i]); gl.color(*c,1); gl.cube(); gl.pop()
    gl.pop(); st['sm']=sm

def _fib(n):
    g=math.pi*(3-math.sqrt(5)); out=[]
    for i in range(n):
        y=1-(i/(n-1))*2; r=math.sqrt(max(0,1-y*y)); th=g*i
        out.append((math.cos(th)*r, y, math.sin(th)*r))
    return out

def medusa(gl, a, st):
    if 'dirs' not in st: st['dirs']=_fib(420)
    bass=a.band(0,0.15)
    st['kick']=max(st.get('kick',0)-a.timepass*2.2, max(a.sounda,bass))
    st['spin']=st.get('spin',0)+a.timepass*(18+40*bass)
    kick=st['kick']; t=a.time
    gl.addBlend(); gl.push(); gl.translate(0,0,-4.5); gl.rotate(st['spin'],0,1,0); gl.rotate(st['spin']*0.4,1,0,0)
    for i,d in enumerate(st['dirs']):
        n=math.sin(d[0]*4+t*2)+math.cos(d[1]*5+t*1.7)+math.sin(d[2]*3+t*2.3)
        tent=0.5+0.5*math.sin(i*0.7+t*3); r=1.3+0.22*n+1.4*kick*tent
        p=(d[0]*r,d[1]*r,d[2]*r); c=hsb(i/420+t*0.03,0.7,0.5+0.5*kick)
        gl.color(*c,0.5); gl.point(p,0.16+0.20*kick)
    gl.pop(); gl.normBlend()

SCENES = {'spinner':spinner,'thumper':thumper,'cubefield':cubefield,'spectrum':spectrum,'medusa':medusa}
SOLID_BG = {'graph-medusa':(0.03,0,0.07,medusa),'graph-cubefield':(0.0,0.02,0.06,cubefield)}
