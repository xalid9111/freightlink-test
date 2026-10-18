"""Day map of the home live map (the owner's design picture).

Usage (from the repo root):
  python3 scripts/make_day_map.py <picture.png> <ne_50m_admin_0_countries.geojson>
(geojson: github.com/nvkelso/natural-earth-vector, geojson/)
Writes:
* assets/images/world_map_day.jpg — the picture, zoomed in (owner's choice
  "Variant 3": most of the cloud margin cut, edges fade to pure white
  #FFFFFF = the day page colour) with a slightly paler sea (saturation
  -35 % outside the land, land colours untouched);
* lib/features/cargo/presentation/widgets/live_map_day_geo.dart — the
  live-map hubs (live_map.dart, same order) and city lights placed on the
  picture, via a smooth warp fitted to the landmarks marked on it below.
Needs numpy + Pillow."""
import json, re, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1]
COUNTRIES = sys.argv[2]
CROP = (240, 165, 1470, 800)  # left, top, right, bottom on the picture
SEA_KEEP = 0.65               # sea keeps 65 % of its colour saturation

# Landmarks on the picture: (x, y) : (lat, lon)
LM = {
 (425,452):(25.1,-80.9),     # Florida tip
 (305,457):(22.9,-109.9),    # Baja California tip
 (280,410):(34.05,-118.24),  # Los Angeles coast
 (390,477):(21.5,-87.0),     # Yucatán
 (420,522):(9.0,-79.5),      # Panama
 (282,355):(47.6,-122.3),    # Seattle
 (614,584):(-7.1,-34.8),     # Brazil east tip
 (570,655):(-22.9,-43.2),    # Rio de Janeiro
 (420,600):(-12.0,-77.0),    # Lima
 (415,567):(-2.0,-81.0),     # Ecuador west
 (515,705):(-34.6,-58.4),    # Buenos Aires
 (745,405):(36.0,-5.6),      # Gibraltar
 (765,335):(51.5,-0.1),      # London
 (862,385):(41.0,29.0),      # Istanbul
 (900,435):(30.0,32.5),      # Suez
 (975,460):(26.5,56.3),      # Hormuz
 (945,382):(40.4,49.9),      # Baku
 (697,505):(14.7,-17.4),     # Dakar
 (840,705):(-34.8,20.0),     # Cape Agulhas
 (957,516):(11.8,51.3),      # Cape Guardafui
 (1060,527):(8.1,77.5),      # India south tip
 (935,665):(-25.6,45.1),     # Madagascar south
 (777,540):(6.5,3.4),        # Lagos
 (1295,412):(35.7,139.7),    # Tokyo
 (1252,420):(34.8,126.5),    # Korea south
 (1227,435):(31.2,121.5),    # Shanghai
 (1212,470):(22.3,114.2),    # Hong Kong
 (1360,340):(51.0,156.7),    # Kamchatka tip
 (1162,550):(1.35,103.8),    # Singapore
 (1307,612):(-10.7,142.5),   # Cape York
 (1189,672):(-26.1,113.2),   # Steep Point
 (1332,710):(-33.9,151.2),   # Sydney
 (1302,745):(-42.0,147.0),   # Tasmania
 (1415,720):(-36.8,174.8),   # Auckland
}

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


P = np.array(list(LM.keys()), float)
to_pic = tps(lonlat(np.array(list(LM.values()), float)), P, 0.01)

src = open('lib/features/cargo/presentation/widgets/live_map.dart').read()
hb = src[src.index('const List<Offset> _hubs = ['):]; hb = hb[:hb.index('];')]
hubs = re.findall(r'Offset\((\d+), (\d+)\), // (.+)', hb)
night = np.array([(int(x) - 80, int(y) - 40) for x, y, _ in hubs], float)  # night picture px (crop 80, 40)
day = to_pic(lonlat(np.array([CITY[n.strip()] for _, _, n in hubs])))

sb = src[src.index('const List<Offset> _sparks = ['):]; sb = sb[:sb.index('];')]
sparks = np.array(re.findall(r'Offset\((\d+), (\d+)\)', sb), float)
day_sparks = tps(night / 1000, day, 0.001)(sparks / 1000)  # night px -> day px through the hubs

def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


im = Image.open(SRC).convert('RGB')
# Land mask from the countries, drawn through the same warp, a little wider
# than the coast so no country colour is touched.
mask = Image.new('L', im.size, 0)
draw = ImageDraw.Draw(mask)
for f in json.load(open(COUNTRIES))['features']:
    if f['properties'].get('ADMIN') == 'Antarctica':
        continue
    g = f['geometry']
    for poly in ([g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']):
        ring = np.array(poly[0])
        if len(ring) < 3 or not -169 < ring[:, 0].mean() < 178:  # pieces across the date line
            continue
        draw.polygon([tuple(p) for p in to_pic(lonlat(ring[:, ::-1].copy()))], fill=255)
land = np.asarray(mask.filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(10)), float) / 255
a = np.asarray(im, float) / 255
a = a + (a.max(-1)[..., None] - a) * ((1 - SEA_KEEP) * (1 - land))[..., None]  # paler sea
a = a[CROP[1]:CROP[3], CROP[0]:CROP[2]] * 255
H, W = a.shape[:2]
yy, xx = np.mgrid[0:H, 0:W]
edge = ss(0, 60, np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy, H - 1 - yy)))[..., None]
a = a * edge + 255 * (1 - edge)  # soft fade to the white page
lift = np.clip((a.min(-1) - 244) / 8, 0, 1)[..., None]  # near-white -> pure white
a = a + (255 - a) * lift * lift * (3 - 2 * lift)
Image.fromarray(a.clip(0, 255).astype(np.uint8)).save('assets/images/world_map_day.jpg', quality=84, optimize=True, progressive=True)
day = day - np.array(CROP[:2])
day_sparks = day_sparks - np.array(CROP[:2])


def fmt(arr):
    return '\n'.join('  ' + ' '.join(f'Offset({x:.0f}, {y:.0f}),' for x, y in arr[i:i + 5]) for i in range(0, len(arr), 5))


open('lib/features/cargo/presentation/widgets/live_map_day_geo.dart', 'w').write(f'''import 'dart:ui' show Offset;

// GENERATED by scripts/make_day_map.py — do not edit by hand.
//
// Day-mode geometry of the home live map: the same hubs (same order as
// _hubs in live_map.dart) and city lights, placed on the day picture
// (assets/images/world_map_day.jpg, {W}×{H}, the owner's design, zoomed in).

const double kDayImgW = {W}, kDayImgH = {H};

const List<Offset> kDayHubs = [
{fmt(day)}
];

const List<Offset> kDaySparks = [
{fmt(day_sparks)}
];
''')
out = ((day_sparks[:, 0] < 0) | (day_sparks[:, 0] > W) | (day_sparks[:, 1] < 0) | (day_sparks[:, 1] > H)).sum()
print('hubs', len(day), 'lights', len(day_sparks), 'outside', int(out))
