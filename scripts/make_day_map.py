"""Day map of the home live map (owner's design picture).

Usage (from the repo root): python3 scripts/make_day_map.py <picture.png>
Writes:
* assets/images/world_map_day.jpg — the picture framed by soft white
  cumulus clouds (extra room around it, so no country / hub is covered);
* assets/images/clouds_day_top.jpg / clouds_day_bottom.jpg — clouds behind
  the home title and the counters (they fade to white where they meet the
  map and the page);
* lib/features/cargo/presentation/widgets/live_map_day_geo.dart — the
  live-map hubs (live_map.dart, same order) and city lights placed on the
  picture, via a smooth warp fitted to landmarks marked on it below.
Deterministic (fixed seeds). Needs numpy + Pillow."""
import re, sys
import numpy as np
from PIL import Image
SRC = sys.argv[1]

def fbm(w, h, seed, base=5, octaves=5, persist=0.55):
    rng = np.random.default_rng(seed); out = np.zeros((h, w)); amp = 1; tot = 0
    for o in range(octaves):
        gw = int(base * 2**o * max(1, w / h)) + 2; gh = int(base * 2**o) + 2
        g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += amp * np.asarray(g, float) / 255; tot += amp; amp *= persist
    out /= tot
    return (out - out.min()) / (out.max() - out.min())
def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

def cumulus(w, h, clusters, seed, scale=0.5):
    """clusters: (cx, cy, size) in px. Returns alpha, rgb (h, w)."""
    rng = np.random.default_rng(seed)
    W, H = int(w * scale), int(h * scale)
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    dens = np.zeros((H, W)); lum = np.zeros((H, W))
    for cx, cy, size in clusters:
        n = int(10 + size / 12)
        for _ in range(n):
            # puffs: wider than tall, bigger on top of the cluster
            ox = rng.normal(0, size * 0.55); oy = rng.normal(0, size * 0.22)
            r = size * rng.uniform(0.22, 0.5) * (1.15 if oy < 0 else 0.9)
            bx, by, br = (cx + ox) * scale, (cy + oy) * scale, r * scale
            x0, x1 = int(max(0, bx - 2 * br)), int(min(W, bx + 2 * br)); y0, y1 = int(max(0, by - 2 * br)), int(min(H, by + 2 * br))
            if x0 >= x1 or y0 >= y1: continue
            sx = xx[y0:y1, x0:x1]; sy = yy[y0:y1, x0:x1]
            q = ((sx - bx) ** 2 + (sy - by) ** 2) / (br * br)
            g = np.clip(1 - q, 0, 1) ** 1.6
            # lit from the top: each puff bright on top, a bit grey underneath
            l = ss(0.9, -0.6, (sy - by) / br)
            dens[y0:y1, x0:x1] += g
            lum[y0:y1, x0:x1] += g * l
    lum = np.where(dens > 1e-6, lum / np.maximum(dens, 1e-6), 1)
    n = fbm(W, H, seed + 3, base=8)
    a = ss(0.10, 0.55, dens * (0.8 + 0.4 * n))
    br = np.clip(0.55 + 0.45 * lum, 0, 1) * (0.94 + 0.06 * n)
    top = np.array([255, 255, 255.]); low = np.array([206, 222, 240.])
    rgb = low + (top - low) * br[..., None]
    up = lambda arr: np.asarray(Image.fromarray(arr.astype(np.float32)).resize((w, h), Image.BICUBIC))
    A = np.clip(up(a), 0, 1); RGB = np.stack([up(rgb[..., i]) for i in range(3)], -1)
    return A, np.clip(RGB, 0, 255)

def edge_clusters(w, h, rng, step, inset, size, sides='tblr'):
    cl = []
    if 't' in sides:
        for x in np.arange(-step / 2, w + step, step): cl.append((x + rng.uniform(-step / 3, step / 3), -inset * 0.2 + rng.uniform(0, inset), size * rng.uniform(0.8, 1.25)))
    if 'b' in sides:
        for x in np.arange(-step / 2, w + step, step): cl.append((x + rng.uniform(-step / 3, step / 3), h + inset * 0.2 - rng.uniform(0, inset), size * rng.uniform(0.8, 1.25)))
    if 'l' in sides:
        for y in np.arange(0, h + step, step * 0.8): cl.append((rng.uniform(-inset * 0.3, inset * 0.6), y, size * rng.uniform(0.8, 1.2)))
    if 'r' in sides:
        for y in np.arange(0, h + step, step * 0.8): cl.append((w - rng.uniform(-inset * 0.3, inset * 0.6), y, size * rng.uniform(0.8, 1.2)))
    return cl

PAD = (40, 70, 40, 80)  # left, top, right, bottom: room for the clouds around the map

def map_with_clouds(src, dst, seed=11):
    pic = Image.open(src).convert('RGB'); pw, ph = pic.size
    L, T, R, B = PAD; w, h = pw + L + R, ph + T + B
    canvas = Image.new('RGB', (w, h), (255, 255, 255)); canvas.paste(pic, (L, T))
    im = np.asarray(canvas, float)
    # soften the picture's own rectangle into the sky colour
    yy, xx = np.mgrid[0:h, 0:w]
    din = np.minimum(np.minimum(xx - L, L + pw - 1 - xx), np.minimum(yy - T, T + ph - 1 - yy))
    k = ss(-4, 26, din)[..., None]
    sky = np.array([255, 255, 255.])
    im = im * k + sky * (1 - k)
    rng = np.random.default_rng(seed)
    cl = []
    cl += [(x + rng.uniform(-50, 50), rng.uniform(0, T * 0.7), rng.uniform(60, 95)) for x in np.arange(-40, w + 130, 130)]
    cl += [(x + rng.uniform(-50, 50), h - rng.uniform(0, B * 0.55), rng.uniform(55, 85)) for x in np.arange(-40, w + 120, 120)]
    cl += [(rng.uniform(-30, L + 30), y + rng.uniform(-30, 30), rng.uniform(60, 100)) for y in np.arange(40, h, 120)]
    cl += [(w - rng.uniform(-30, R + 30), y + rng.uniform(-30, 30), rng.uniform(60, 100)) for y in np.arange(40, h, 120)]
    A, RGB = cumulus(w, h, cl, seed)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx) / 30.0, np.minimum(yy, h - 1 - yy) / 40.0)
    A = np.maximum(A, ss(1.0, 0.0, d))           # the very border is all cloud / white
    out = im * (1 - A[..., None]) + RGB * A[..., None]
    edge = ss(0.35, 0.0, d)[..., None]           # outermost pixels pure white
    out = out * (1 - edge) + 255 * edge
    Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(dst, quality=84, optimize=True, progressive=True)

def backdrop(dst, w, h, top, seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]; y = yy / h
    if top:
        sky = ss(0.75, 0.0, y)
        base = np.stack([255 - 34 * sky, 255 - 16 * sky, 255 - 3 * sky], -1)
        cl = [(x + rng.uniform(-60, 60), h * rng.uniform(0.55, 0.95), rng.uniform(90, 150)) for x in np.arange(0, w + 150, 150)]
        cl += [(x + rng.uniform(-80, 80), h * rng.uniform(0.05, 0.35), rng.uniform(50, 90)) for x in np.arange(80, w, 320)]
        fade = ss(0.86, 1.0, y)
    else:
        base = np.full((h, w, 3), 255.0)
        cl = [(x + rng.uniform(-60, 60), h * rng.uniform(0.05, 0.30), rng.uniform(60, 100)) for x in np.arange(0, w + 150, 150)]
        fade = np.maximum(ss(0.10, 0.0, y), ss(0.65, 1.0, y))
    A, RGB = cumulus(w, h, cl, seed)
    out = base * (1 - A[..., None]) + RGB * A[..., None]
    out = out * (1 - fade[..., None]) + 255 * fade[..., None]
    Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(dst, quality=84, optimize=True, progressive=True)


# landmarks on the owner's picture: (img x, y) : (lat, lon)
LM = {
 (133,308):(34.05,-118.24),   # Los Angeles dot
 (408,518):(-15.8,-47.9),     # Brasília dot
 (307,629):(-33.45,-70.67),   # Santiago dot
 (1241,313):(35.68,139.69),   # Tokyo dot
 (1119,333):(39.9,116.4),     # Beijing dot
 (979,337):(28.61,77.21),     # Delhi dot
 (852,270):(40.41,49.87),     # Baku dot
 (640,193):(51.5,-0.13),      # London dot
 (827,177):(55.75,37.62),     # Moscow dot
 (735,640):(-34.6,19.5),      # Cape Agulhas
 (870,427):(11.8,51.3),       # Cape Guardafui
 (993,440):(8.1,77.5),        # India south tip
 (1270,507):(-10.7,142.5),    # Cape York
 (1137,587):(-26.1,113.2),    # Steep Point
 (850,597):(-25.6,45.1),      # Madagascar south
 (623,297):(36.0,-5.6),       # Gibraltar
 (485,517):(-7.1,-34.8),      # Brazil east tip
 (280,443):(9.0,-79.5),       # Panama
}
P=np.array(list(LM.keys()),float); L=np.array(list(LM.values()),float)
X=np.stack([L[:,1]/180,L[:,0]/90],1)
def tps(src,dst,lam):
    n=len(src)
    U=lambda r2: np.where(r2>0,r2*np.log(r2+1e-12),0.0)
    K=U(((src[:,None]-src[None])**2).sum(-1)); Pm=np.hstack([np.ones((n,1)),src])
    A=np.zeros((n+3,n+3)); A[:n,:n]=K+lam*np.eye(n); A[:n,n:]=Pm; A[n:,:n]=Pm.T
    W=np.linalg.solve(A,np.vstack([dst,np.zeros((3,2))]))
    def f(q):
        q=np.atleast_2d(q); k=U(((q[:,None]-src[None])**2).sum(-1))
        return k@W[:n]+W[n]+q@W[n+1:]
    return f
f=tps(X,P,0.01)
src=open('lib/features/cargo/presentation/widgets/live_map.dart').read()
hub_block=src[src.index('const List<Offset> _hubs = ['):src.index('];',src.index('const List<Offset> _hubs = ['))]
names=re.findall(r'Offset\((\d+), (\d+)\), // (.+)',hub_block)
CITY={'New York':(40.71,-74.0),'Los Angeles':(34.05,-118.24),'Chicago':(41.88,-87.63),'Mexico City':(19.43,-99.13),'Bogotá':(4.71,-74.07),
 'São Paulo':(-23.55,-46.63),'Buenos Aires':(-34.6,-58.38),'London':(51.5,-0.13),'Central Europe':(50.1,8.7),'Madrid':(40.42,-3.7),
 'Moscow':(55.75,37.62),'Istanbul':(41.01,28.98),'Cairo':(30.04,31.24),'Lagos':(6.52,3.38),'Nairobi':(-1.29,36.82),'Johannesburg':(-26.2,28.05),
 'Baku':(40.41,49.87),'Dubai':(25.2,55.27),'Tehran':(35.69,51.39),'Almaty':(43.24,76.89),'Delhi':(28.61,77.21),'Mumbai':(19.08,72.88),
 'Novosibirsk':(55.03,82.92),'Beijing':(39.9,116.4),'Shanghai':(31.23,121.47),'Tokyo':(35.68,139.69),'Hong Kong':(22.32,114.17),
 'Singapore':(1.35,103.82),'Jakarta':(-6.2,106.85),'Sydney':(-33.87,151.21),'Perth':(-31.95,115.86),'Tbilisi':(41.72,44.79),'Yerevan':(40.18,44.51),
 'Ankara':(39.93,32.86),'Kyiv':(50.45,30.52),'Warsaw':(52.23,21.01),'Aktau':(43.65,51.17),'Ashgabat':(37.96,58.33),'Tashkent':(41.3,69.24),'Bishkek':(42.87,74.59)}
night=np.array([(int(x)-80,int(y)-40) for x,y,_ in names],float)
ll=np.array([CITY[n.strip()] for _,_,n in names])
day=f(np.stack([ll[:,1]/180,ll[:,0]/90],1))
im=Image.open(SRC).convert('RGB')

# night image px -> day image px through the hubs (for the twinkling city lights)
sb=src[src.index('const List<Offset> _sparks = ['):]
sb=sb[:sb.index('];')]
sparks=np.array([(int(a),int(b)) for a,b in re.findall(r'Offset\((\d+), (\d+)\)',sb)],float)
g=tps(night/1000,day,0.001)
dsp=g(sparks/1000)
# the picture sits inside the cloud frame at (PAD left, PAD top)
day = day + np.array([PAD[0], PAD[1]]); dsp = dsp + np.array([PAD[0], PAD[1]])
W, H = im.size[0] + PAD[0] + PAD[2], im.size[1] + PAD[1] + PAD[3]
def fmt(arr):
    out=[]
    for i in range(0,len(arr),5):
        out.append('  '+' '.join(f'Offset({x:.0f}, {y:.0f}),' for x,y in arr[i:i+5]))
    return '\n'.join(out)
dart=f'''import 'dart:ui' show Offset;

// GENERATED by scripts/make_day_map.py — do not edit by hand.
//
// Day-mode geometry of the home live map: the same hubs (same order as
// _hubs in live_map.dart) and city lights, placed on the day picture
// (assets/images/world_map_day.jpg, {W}×{H}: the owner's design framed by
// clouds).

const double kDayImgW = {W}, kDayImgH = {H};

const List<Offset> kDayHubs = [
{fmt(day)}
];

const List<Offset> kDaySparks = [
{fmt(dsp)}
];
'''
open('lib/features/cargo/presentation/widgets/live_map_day_geo.dart','w').write(dart)
map_with_clouds(SRC, 'assets/images/world_map_day.jpg')
backdrop('assets/images/clouds_day_top.jpg', 1170, 420, True, 3)
backdrop('assets/images/clouds_day_bottom.jpg', 1170, 360, False, 5)
print('hubs',len(day),'sparks',len(dsp), 'outside', int(((dsp[:,0]<0)|(dsp[:,0]>W)|(dsp[:,1]<0)|(dsp[:,1]>H)).sum()))
