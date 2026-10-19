"""Cloud-scene maps of the home live map (the owner's pictures).

Usage (from the repo root):
  python3 scripts/make_cloud_map.py night <picture.png>   (owner, 19.10.2026)
  python3 scripts/make_cloud_map.py day <picture.png>     (owner, 19.10.2026)
Writes, for the mode:
* assets/images/world_map_<mode>_vN.jpg — the map part of the picture (the
  animated layer is drawn on it);
* assets/images/world_map_<mode>_vN_top.jpg / ..._bottom.jpg — the clouds
  above and below it: one cloud scene behind the home title, map and
  counters. Its outer edges fade to exactly the page colour (night
  #02050C, day #FFFFFF), so no line shows where the picture ends;
* lib/features/cargo/presentation/widgets/live_map_<mode>_geo.dart — the
  live-map hubs (live_map.dart, same order) and city lights placed on the
  picture, via a smooth warp fitted to the landmarks marked on it below.
Needs numpy + Pillow."""
import re, sys
import numpy as np
from PIL import Image

MODE, SRC = sys.argv[1], sys.argv[2]
# Per mode: map part of the picture (left, top, right, bottom), page colour,
# title backing (night darker / day lighter, for readable text), output
# version, and landmarks on the picture: (x, y) : (lat, lon).
MODES = {
 'night': dict(crop=(180, 210, 1600, 690), bg=(2, 5, 12), title='darken', version='v3', lm={

 (316,360):(25.1,-80.9),     # Florida tip
 (219,374):(22.9,-109.9),    # Baja California tip
 (190,335):(34.05,-118.24),  # Los Angeles coast
 (275,382):(21.5,-87.0),     # Yucatán
 (310,430):(9.0,-79.5),      # Panama
 (360,295):(40.7,-74.0),     # New York
 (507,502):(-7.1,-34.8),     # Brazil east tip
 (452,565):(-22.9,-43.2),    # Rio de Janeiro
 (312,500):(-12.0,-77.0),    # Lima
 (297,480):(-2.0,-81.0),     # Ecuador west
 (405,605):(-34.6,-58.4),    # Buenos Aires
 (675,335):(36.0,-5.6),      # Gibraltar
 (702,265):(51.5,-0.1),      # London
 (842,313):(41.0,29.0),      # Istanbul
 (880,352):(30.0,32.5),      # Suez
 (1000,390):(26.5,56.3),     # Hormuz
 (960,318):(40.4,49.9),      # Baku
 (600,427):(14.7,-17.4),     # Dakar
 (800,662):(-34.8,20.0),     # Cape Agulhas
 (975,457):(11.8,51.3),      # Cape Guardafui
 (1152,475):(8.1,77.5),      # India south tip
 (940,630):(-25.6,45.1),     # Madagascar south
 (702,470):(6.5,3.4),        # Lagos
 (1472,357):(35.7,139.7),    # Tokyo
 (1410,362):(34.8,126.5),    # Korea south
 (1380,370):(31.2,121.5),    # Shanghai
 (1345,410):(22.3,114.2),    # Hong Kong
 (1297,520):(1.35,103.8),    # Singapore
 (1500,565):(-10.7,142.5),   # Cape York
 (1347,620):(-26.1,113.2),   # Steep Point
 (1542,655):(-33.9,151.2),   # Sydney
 (1617,680):(-36.8,174.8),   # Auckland
 }),
 'day': dict(crop=(160, 240, 1600, 720), bg=(255, 255, 255), title='lighten', version='v2', lm={
 (356,390):(25.1,-80.9),     # Florida tip
 (215,397):(22.9,-109.9),    # Baja California tip
 (190,357):(34.05,-118.24),  # Los Angeles coast
 (177,297):(47.6,-122.3),    # Seattle
 (315,415):(21.5,-87.0),     # Yucatán
 (355,467):(9.0,-79.5),      # Panama
 (420,310):(40.7,-74.0),     # New York
 (570,540):(-7.1,-34.8),     # Brazil east tip
 (510,605):(-22.9,-43.2),    # Rio de Janeiro
 (450,650):(-34.6,-58.4),    # Buenos Aires
 (370,550):(-12.0,-77.0),    # Lima
 (350,520):(-2.0,-81.0),     # Ecuador west
 (732,352):(36.0,-5.6),      # Gibraltar
 (765,277):(51.5,-0.1),      # London
 (905,335):(41.0,29.0),      # Istanbul
 (925,390):(30.0,32.5),      # Suez
 (1050,417):(26.5,56.3),     # Hormuz
 (1005,330):(40.4,49.9),     # Baku
 (802,500):(6.5,3.4),        # Lagos
 (845,675):(-34.8,20.0),     # Cape Agulhas
 (1012,465):(11.8,51.3),     # Cape Guardafui
 (980,637):(-25.6,45.1),     # Madagascar south
 (1151,494):(8.1,77.5),      # India south tip
 (1295,490):(1.35,103.8),    # Singapore
 (1335,415):(22.3,114.2),    # Hong Kong
 (1372,390):(31.2,121.5),    # Shanghai
 (1400,372):(34.8,126.5),    # Korea south
 (1457,365):(35.7,139.7),    # Tokyo
 (1515,300):(51.0,156.7),    # Kamchatka tip
 (1487,595):(-10.7,142.5),   # Cape York
 (1335,645):(-26.1,113.2),   # Steep Point
 (1530,695):(-33.9,151.2),   # Sydney
 (1500,735):(-42.0,147.0),   # Tasmania
 (1625,710):(-36.8,174.8),   # Auckland
 }),
}
M = MODES[MODE]
CROP = M['crop']
BG = np.array(M['bg'], float)
LM = M['lm']
NAME = f"world_map_{MODE}_{M['version']}"

CITY={'New York':(40.71,-74.0),'Los Angeles':(34.05,-118.24),'Chicago':(41.88,-87.63),'Mexico City':(19.43,-99.13),'Bogotá':(4.71,-74.07),
 'São Paulo':(-23.55,-46.63),'Buenos Aires':(-34.6,-58.38),'London':(51.5,-0.13),'Central Europe':(50.1,8.7),'Madrid':(40.42,-3.7),
 'Moscow':(55.75,37.62),'Istanbul':(41.01,28.98),'Cairo':(30.04,31.24),'Lagos':(6.52,3.38),'Nairobi':(-1.29,36.82),'Johannesburg':(-26.2,28.05),
 'Baku':(40.41,49.87),'Dubai':(25.2,55.27),'Tehran':(35.69,51.39),'Almaty':(43.24,76.89),'Delhi':(28.61,77.21),'Mumbai':(19.08,72.88),
 'Novosibirsk':(55.03,82.92),'Beijing':(39.9,116.4),'Shanghai':(31.23,121.47),'Tokyo':(35.68,139.69),'Hong Kong':(22.32,114.17),
 'Singapore':(1.35,103.82),'Jakarta':(-6.2,106.85),'Sydney':(-33.87,151.21),'Perth':(-31.95,115.86),'Tbilisi':(41.72,44.79),'Yerevan':(40.18,44.51),
 'Ankara':(39.93,32.86),'Kyiv':(50.45,30.52),'Warsaw':(52.23,21.01),'Aktau':(43.65,51.17),'Ashgabat':(37.96,58.33),'Tashkent':(41.3,69.24),'Bishkek':(42.87,74.59)}


def tps(src, dst, lam):
    """Thin-plate spline src -> dst (smooth, exact up to lam)."""
    n = len(src)
    U = lambda r2: np.where(r2 > 0, r2 * np.log(r2 + 1e-12), 0.0)
    K = U(((src[:, None] - src[None]) ** 2).sum(-1))
    Pm = np.hstack([np.ones((n, 1)), src])
    A = np.zeros((n + 3, n + 3)); A[:n, :n] = K + lam * np.eye(n); A[:n, n:] = Pm; A[n:, :n] = Pm.T
    W = np.linalg.solve(A, np.vstack([dst, np.zeros((3, 2))]))
    def f(q):
        q = np.atleast_2d(q); k = U(((q[:, None] - src[None]) ** 2).sum(-1))
        return k @ W[:n] + W[n] + q @ W[n + 1:]
    return f


def lonlat(ll):
    return np.stack([ll[:, 1] / 180, ll[:, 0] / 90], 1)


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


P = np.array(list(LM.keys()), float)
to_pic = tps(lonlat(np.array(list(LM.values()), float)), P, 0.01)

src = open('lib/features/cargo/presentation/widgets/live_map.dart').read()
hb = src[src.index('const List<Offset> _hubs = ['):]; hb = hb[:hb.index('];')]
hubs = re.findall(r'Offset\((\d+), (\d+)\), // (.+)', hb)
old = np.array([(int(x) - 80, int(y) - 40) for x, y, _ in hubs], float)  # old night picture px (crop 80, 40)
new = to_pic(lonlat(np.array([CITY[n.strip()] for _, _, n in hubs])))
sb = src[src.index('const List<Offset> _sparks = ['):]; sb = sb[:sb.index('];')]
sparks = np.array(re.findall(r'Offset\((\d+), (\d+)\)', sb), float)
new_sparks = tps(old / 1000, new, 0.001)(sparks / 1000)  # old px -> new px through the hubs

a = np.asarray(Image.open(SRC).convert('RGB'), float)
X0, Y0, X1, Y1 = CROP
W, H = X1 - X0, Y1 - Y0
pic = a[:, X0:X1]


def vjoin(top, bottom, n):
    w = ss(0, 1, np.linspace(0, 1, n))[:, None, None]
    return np.concatenate([top[:-n], top[-n:] * (1 - w) + bottom[:n] * w, bottom[n:]], 0)


# One cloud scene, top to bottom: clouds behind the title, the map, clouds
# behind the counters — all from the picture itself; a mirrored cloud strip
# gives the title / counters a little more cloud. Cut into three pictures
# that join seamlessly when all are shown at the screen width.
above, below = pic[:Y0], pic[Y1:]
# Only cloud rows go into the mirrored strips (no land edges).
top = vjoin(below[50:][::-1, ::-1], above, 60)
bottom = vjoin(below, above[:150][::-1, ::-1], 60)
scene = np.concatenate([top, pic[Y0:Y1], bottom], 0)
T = top.shape[0]
y = np.arange(scene.shape[0])[:, None, None]
if M['title'] == 'darken':
    scene = scene * (1 - 0.45 * ss(T - 40, 0, y))           # darker behind the title (readable white text)
else:
    scene = scene + (255 - scene) * (0.62 * ss(T, T - 70, y))  # light mist behind the title (readable dark text)
# Keep only as much cloud above / below the map as is always on screen (the
# title / counters area at every text size, Kiçik included), and fade it to
# the page colour slowly and completely inside that part: no edge of
# the picture is ever visible, so no horizontal line at the top or bottom.
KEEP_TOP, KEEP_BOTTOM = 270, 200
scene = scene[T - KEEP_TOP:T + H + KEEP_BOTTOM]
T, n = KEEP_TOP, scene.shape[0]
y = np.arange(n)[:, None, None]
scene = scene + (BG - scene) * ss(150, 0, y)             # top: gradually into the page colour
scene = scene + (BG - scene) * ss(T + H + 10, n - 3, y)  # bottom: the same, below the counters
scene = scene.clip(0, 255).round().astype(np.uint8)
for name, part in ((f'{NAME}_top', scene[:T]), (NAME, scene[T:T + H]), (f'{NAME}_bottom', scene[T + H:])):
    Image.fromarray(part).save(f'assets/images/{name}.jpg', quality=88, optimize=True, progressive=True)
new = new - np.array(CROP[:2])
new_sparks = new_sparks - np.array(CROP[:2])
keep = (new_sparks[:, 0] > 4) & (new_sparks[:, 0] < W - 4) & (new_sparks[:, 1] > 4) & (new_sparks[:, 1] < H - 4)
new_sparks = new_sparks[keep]


def fmt(arr):
    return '\n'.join('  ' + ' '.join(f'Offset({x:.0f}, {y:.0f}),' for x, y in arr[i:i + 5]) for i in range(0, len(arr), 5))


P = 'Night' if MODE == 'night' else 'Day'
open(f'lib/features/cargo/presentation/widgets/live_map_{MODE}_geo.dart', 'w').write(f'''import 'dart:ui' show Offset;

// GENERATED by scripts/make_cloud_map.py ({MODE}) — do not edit by hand.
//
// {P}-mode geometry of the home live map: the same hubs (same order as
// _hubs in live_map.dart) and city lights, placed on the {MODE} picture
// (assets/images/{NAME}.jpg, {W}×{H}, the owner's cloud design).

const double k{P}ImgW = {W}, k{P}ImgH = {H};

const List<Offset> k{P}Hubs = [
{fmt(new)}
];

const List<Offset> k{P}Sparks = [
{fmt(new_sparks)}
];
''')

out = ((new[:, 0] < 0) | (new[:, 0] > W) | (new[:, 1] < 0) | (new[:, 1] > H)).sum()
print('hubs', len(new), 'outside', int(out), 'lights', len(new_sparks), 'of', len(sparks), 'top', T, 'bottom', n - T - H)
