"""Renders assets/images/world_map_day.jpg: Natural Earth countries (public
domain) in soft bright colours, warped onto the night map's layout so the
live-map hubs (live_map.dart) sit on their cities."""
import json, sys
import numpy as np
from PIL import Image, ImageDraw

# Usage: python3 scripts/make_day_map.py ne_50m_admin_0_countries.geojson assets/images/world_map_day.jpg
# (geojson: github.com/nvkelso/natural-earth-vector, geojson/). Needs numpy + Pillow.
H = {  # hub pixel on the 1400x700 map : (lat, lon)
 (254,224):(40.71,-74.0),(104,256):(34.05,-118.24),(220,214):(41.88,-87.63),(142,309):(19.43,-99.13),(206,373):(4.71,-74.07),
 (321,490):(-23.55,-46.63),(282,536):(-34.6,-58.38),(558,174):(51.5,-0.13),(599,186):(50.1,8.7),(539,223):(40.42,-3.7),
 (698,153):(55.75,37.62),(693,231):(41.01,28.98),(718,264):(30.04,31.24),(558,371):(6.52,3.38),(773,426):(-1.29,36.82),
 (693,528):(-26.2,28.05),(795,228):(40.41,49.87),(832,295):(25.2,55.27),(820,244):(35.69,51.39),(947,215):(43.24,76.89),
 (936,281):(28.61,77.21),(924,327):(19.08,72.88),(937,151):(55.03,82.92),(1135,223):(39.9,116.4),(1159,269):(31.23,121.47),
 (1225,253):(35.68,139.69),(1133,312):(22.32,114.17),(1082,412):(1.35,103.82),(1103,448):(-6.2,106.85),(1247,570):(-33.87,151.21),
 (1125,557):(-31.95,115.86),(778,218):(41.72,44.79),(782,234):(40.18,44.51),(705,238):(39.93,32.86),(672,168):(50.45,30.52),
 (628,163):(52.23,21.01),(832,212):(43.65,51.17),(862,242):(37.96,58.33),(905,222):(41.3,69.24),(938,208):(42.87,74.59)}
P=np.array([k for k in H],float)-np.array([80,40]); L=np.array([H[k] for k in H],float)
lat,lon=L[:,0],L[:,1]
W, Hh, SS = 1220, 580, 3
# Thin-plate spline lon/lat -> image px, exact through the hubs (light smoothing).
X = np.stack([lon/180, lat/90], 1)
def U(r2): return np.where(r2 > 0, r2*np.log(r2+1e-12), 0.0)
n = len(X)
K = U(((X[:, None, :]-X[None, :, :])**2).sum(-1))
Pm = np.hstack([np.ones((n, 1)), X])
lam = 0.002
A = np.zeros((n+3, n+3)); A[:n, :n] = K + lam*np.eye(n); A[:n, n:] = Pm; A[n:, :n] = Pm.T
bx = np.concatenate([P[:, 0], [0, 0, 0]]); by = np.concatenate([P[:, 1], [0, 0, 0]])
wx = np.linalg.solve(A, bx); wy = np.linalg.solve(A, by)
def warp(lo, la):
    q = np.stack([np.asarray(lo)/180, np.asarray(la)/90], -1)
    k = U(((q[..., None, :]-X)**2).sum(-1))
    x = k@wx[:n] + wx[n] + q[..., 0]*wx[n+1] + q[..., 1]*wx[n+2]
    y = k@wy[:n] + wy[n] + q[..., 0]*wy[n+1] + q[..., 1]*wy[n+2]
    return x, y
res = [np.hypot(*(np.array(warp(lon[i], lat[i]))-P[i])) for i in range(n)]
print('max hub error px', round(max(res), 2))

PAL = {1: (134, 197, 120), 2: (246, 205, 92), 3: (244, 152, 98), 4: (238, 128, 150), 5: (158, 136, 214), 6: (104, 176, 222), 7: (96, 196, 180)}
img = Image.new('RGB', (W*SS, Hh*SS), (205, 232, 250))
# Ocean: light blue, a little deeper towards the middle.
yy, xx = np.mgrid[0:Hh*SS, 0:W*SS]
d = np.hypot((xx/(W*SS)-0.5)*1.6, (yy/(Hh*SS)-0.5)*1.6)
sea = np.stack([206+20*d, 233+12*d, 250+3*d], -1).clip(0, 255).astype(np.uint8)
img = Image.fromarray(sea)
dr = ImageDraw.Draw(img)
gj = json.load(open(sys.argv[1]))
def rings(geom):
    t = geom['type']; cs = geom['coordinates']
    polys = [cs] if t == 'Polygon' else cs
    for poly in polys:
        for i, ring in enumerate(poly): yield i, ring
outlines = []
for f in gj['features']:
    pr = f['properties']
    if pr.get('ADMIN') == 'Antarctica': continue
    col = PAL.get(pr.get('MAPCOLOR7') or 1, PAL[1])
    for i, ring in rings(f['geometry']):
        a = np.array(ring)
        # densify long edges so the warp bends them smoothly
        pts = [a[0]]
        for p0, p1 in zip(a[:-1], a[1:]):
            seg = max(1, int(np.hypot(*(p1-p0))/1.5))
            for t in range(1, seg+1): pts.append(p0+(p1-p0)*t/seg)
        a = np.array(pts)
        x, y = warp(a[:, 0], a[:, 1])
        xy = list(zip((x*SS).tolist(), (y*SS).tolist()))
        if len(xy) < 3: continue
        dr.polygon(xy, fill=col if i == 0 else (206, 233, 250))
        outlines.append(xy)
for xy in outlines:
    dr.line(xy + [xy[0]], fill=(255, 255, 255), width=SS)
img = img.resize((W, Hh), Image.LANCZOS)
# Soft white fade at the edges (blends into the white page).
m = np.ones((Hh, W))
f = 0.07
for ax, size in ((1, W), (0, Hh)):
    r = np.minimum(np.arange(size), np.arange(size)[::-1]) / (size*f)
    r = np.clip(r, 0, 1); r = r*r*(3-2*r)
    m = m * (r[None, :] if ax == 1 else r[:, None])
arr = np.asarray(img).astype(float)
arr = arr*m[..., None] + 255*(1-m[..., None])
out = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
out.save(sys.argv[2], quality=86, optimize=True, progressive=True)
print('saved', out.size)
