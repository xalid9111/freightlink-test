#!/usr/bin/env python3
"""TIRPark map data: truck parking from OpenStreetMap (owner, 11.11.2026, SQL 0117).

Bulk import, never a live API: for each country the Geofabrik regional
extract (.osm.pbf, rebuilt daily from OpenStreetMap) is downloaded ONCE,
filtered locally with osmium-tool, and the matching objects are written to
public.osm_truck_parks through public.osm_truck_parks_upsert() (Supabase SQL
API, the repository secret SUPABASE_ACCESS_TOKEN). The app only reads that
table. The public Overpass servers are not used.

  * Kept: amenity=parking, highway=rest_area or highway=services with
    hgv=yes|designated|only, not access=private|no. A rest area / services
    within 300 m of such a parking is left out (the parking is the place).
  * Azerbaijan never: AZ is not imported, and points inside Azerbaijan's
    border (Geofabrik's azerbaijan.poly, Nakhchivan included) are dropped from
    neighbouring extracts too. AZ parks come only from the platform.
  * Only the source's own facts go in (name + a few tags); the database keeps
    only its allow-list (operator, fee, opening_hours, capacity:hgv, ...).
  * One row per OSM object (node/way/relation id): a later run updates it.

Data © OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright);
extracts by Geofabrik GmbH (https://download.geofabrik.de).

Usage (GitHub workflow "OSM truck parks"):
  python3 scripts/osm_truck_parks/import_parks.py --group europe-a
  python3 scripts/osm_truck_parks/import_parks.py --country GE --dry-run
"""
from __future__ import annotations

import argparse
import json
import math
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

GEOFABRIK = 'https://download.geofabrik.de'
AZ_POLY = f'{GEOFABRIK}/asia/azerbaijan.poly'
PROJECT_REF = os.environ.get('SUPABASE_PROJECT_REF', 'jqdqtfmxnqezlsetelpi')
USER_AGENT = 'FreightLink-osm-truck-parks/1.0 (monthly bulk import)'
BATCH = 2000

# (ISO code, Geofabrik path). Phase 1 (owner, 11.11.2026): Europe, Türkiyə,
# Gürcüstan, Rusiya, Qazaxıstan, Özbəkistan, the rest of Central Asia, İran.
# Phase 2: the rest of Asia (group 'asia-rest', started by hand for now).
# Azerbaijan is NEVER in any group.
GROUPS: dict[str, list[tuple[str, str]]] = {
    'europe-a': [
        ('DE', 'europe/germany'), ('NL', 'europe/netherlands'), ('BE', 'europe/belgium'),
        ('LU', 'europe/luxembourg'), ('AT', 'europe/austria'), ('CH', 'europe/switzerland'),
        ('LI', 'europe/liechtenstein'), ('DK', 'europe/denmark'),
    ],
    'europe-b': [
        ('FR', 'europe/france'), ('ES', 'europe/spain'), ('PT', 'europe/portugal'),
        ('AD', 'europe/andorra'), ('MC', 'europe/monaco'), ('IT', 'europe/italy'),
        ('MT', 'europe/malta'), ('GB', 'europe/great-britain'),
        ('IE', 'europe/ireland-and-northern-ireland'), ('IS', 'europe/iceland'),
    ],
    'europe-c': [
        ('PL', 'europe/poland'), ('CZ', 'europe/czech-republic'), ('SK', 'europe/slovakia'),
        ('HU', 'europe/hungary'), ('SI', 'europe/slovenia'), ('HR', 'europe/croatia'),
        ('BA', 'europe/bosnia-herzegovina'), ('RS', 'europe/serbia'), ('ME', 'europe/montenegro'),
        ('XK', 'europe/kosovo'), ('MK', 'europe/macedonia'), ('AL', 'europe/albania'),
        ('GR', 'europe/greece'), ('BG', 'europe/bulgaria'), ('RO', 'europe/romania'),
        ('CY', 'europe/cyprus'),
    ],
    'europe-d': [
        ('SE', 'europe/sweden'), ('NO', 'europe/norway'), ('FI', 'europe/finland'),
        ('EE', 'europe/estonia'), ('LV', 'europe/latvia'), ('LT', 'europe/lithuania'),
        ('BY', 'europe/belarus'), ('UA', 'europe/ukraine'), ('MD', 'europe/moldova'),
    ],
    'eurasia': [
        ('TR', 'europe/turkey'), ('GE', 'europe/georgia'), ('RU', 'russia'),
        ('KZ', 'asia/kazakhstan'), ('UZ', 'asia/uzbekistan'), ('KG', 'asia/kyrgyzstan'),
        ('TJ', 'asia/tajikistan'), ('TM', 'asia/turkmenistan'), ('IR', 'asia/iran'),
    ],
    'asia-rest': [
        ('AM', 'asia/armenia'), ('AF', 'asia/afghanistan'), ('PK', 'asia/pakistan'),
        ('IN', 'asia/india'), ('CN', 'asia/china'), ('MN', 'asia/mongolia'),
        ('IQ', 'asia/iraq'), ('SY', 'asia/syria'), ('LB', 'asia/lebanon'),
        ('JO', 'asia/jordan'), ('IL', 'asia/israel-and-palestine'), ('GC', 'asia/gcc-states'),
        ('YE', 'asia/yemen'), ('NP', 'asia/nepal'), ('BD', 'asia/bangladesh'),
        ('BT', 'asia/bhutan'), ('LK', 'asia/sri-lanka'), ('MM', 'asia/myanmar'),
        ('TH', 'asia/thailand'), ('LA', 'asia/laos'), ('KH', 'asia/cambodia'),
        ('VN', 'asia/vietnam'), ('MY', 'asia/malaysia-singapore-brunei'),
        ('ID', 'asia/indonesia'), ('PH', 'asia/philippines'), ('TW', 'asia/taiwan'),
        ('KR', 'asia/south-korea'), ('KP', 'asia/north-korea'), ('JP', 'asia/japan'),
        ('TL', 'asia/east-timor'),
    ],
}
PHASE_1 = ['europe-a', 'europe-b', 'europe-c', 'europe-d', 'eurasia']

HGV_OK = {'yes', 'designated', 'only'}
ACCESS_NO = {'private', 'no'}
KEEP_TAGS = ('operator', 'fee', 'opening_hours', 'capacity:hgv', 'toilets', 'shower',
             'supervised', 'lit', 'maxstay', 'hgv')


# ---------------------------------------------------------------- pure parts

def park_kind(tags: dict) -> str | None:
    """'parking' / 'rest_area' / 'services' for an object marked for lorries, else None."""
    if (tags.get('hgv') or '').strip().lower() not in HGV_OK:
        return None
    if (tags.get('access') or '').strip().lower() in ACCESS_NO:
        return None
    if any(k.startswith(('disused:', 'abandoned:', 'construction')) for k in tags):
        return None
    if tags.get('amenity') == 'parking':
        return 'parking'
    if tags.get('highway') in ('rest_area', 'services'):
        return tags['highway']
    return None


def _ring_centroid(ring: list) -> tuple[float, float] | None:
    pts = [p for p in ring if isinstance(p, (list, tuple)) and len(p) >= 2]
    if len(pts) > 1 and list(pts[0][:2]) == list(pts[-1][:2]):
        pts = pts[:-1]  # a closed ring repeats its first point
    if not pts:
        return None
    return (sum(p[1] for p in pts) / len(pts), sum(p[0] for p in pts) / len(pts))


def feature_point(geom: dict | None) -> tuple[float, float] | None:
    """(lat, lng) of a GeoJSON geometry: the point itself, or the middle of
    the outer ring / line (good enough to put a pin on a car park)."""
    if not geom:
        return None
    t, c = geom.get('type'), geom.get('coordinates')
    try:
        if t == 'Point':
            return (float(c[1]), float(c[0]))
        if t == 'LineString':
            return _ring_centroid(c)
        if t == 'Polygon':
            return _ring_centroid(c[0])
        if t == 'MultiPolygon':
            biggest = max(c, key=lambda poly: len(poly[0]))
            return _ring_centroid(biggest[0])
    except (TypeError, ValueError, IndexError):
        return None
    return None


def osm_id(feature: dict) -> str | None:
    """'n123' / 'w123' / 'r123' (osmium export -u type_id) → 'node/123' …;
    an area 'a<n>' is way n/2 (even n) or relation (n-1)/2 (odd n)."""
    raw = str(feature.get('id') or '')
    if len(raw) < 2 or not raw[1:].isdigit():
        return None
    k, n = raw[0], int(raw[1:])
    if k == 'a':
        return f'way/{n // 2}' if n % 2 == 0 else f'relation/{(n - 1) // 2}'
    kinds = {'n': 'node', 'w': 'way', 'r': 'relation'}
    return f'{kinds[k]}/{n}' if k in kinds else None


def parse_poly(text: str) -> list[list[tuple[float, float]]]:
    """Osmosis .poly → outer rings as (lat, lng) lists (holes are skipped:
    a hole in Azerbaijan's border does not exist in practice)."""
    rings: list[list[tuple[float, float]]] = []
    lines = [ln.strip() for ln in text.splitlines()]
    i = 1  # the first line is the file's name
    while i < len(lines):
        name = lines[i]
        i += 1
        if not name or name == 'END':
            continue
        ring: list[tuple[float, float]] = []
        while i < len(lines) and lines[i] != 'END':
            parts = lines[i].split()
            if len(parts) >= 2:
                ring.append((float(parts[1]), float(parts[0])))
            i += 1
        i += 1
        if not name.startswith('!') and len(ring) >= 3:
            rings.append(ring)
    return rings


def in_rings(lat: float, lng: float, rings: list[list[tuple[float, float]]]) -> bool:
    for ring in rings:
        lats = [p[0] for p in ring]
        lngs = [p[1] for p in ring]
        if not (min(lats) <= lat <= max(lats) and min(lngs) <= lng <= max(lngs)):
            continue
        inside = False
        j = len(ring) - 1
        for k in range(len(ring)):
            yk, xk = ring[k]
            yj, xj = ring[j]
            if (yk > lat) != (yj > lat) and lng < (xj - xk) * (lat - yk) / ((yj - yk) or 1e-12) + xk:
                inside = not inside
            j = k
        if inside:
            return True
    return False


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def select_parks(features, az_rings) -> tuple[list[dict], int]:
    """Rows for osm_truck_parks_upsert from GeoJSON features; also the number
    dropped because they lie inside Azerbaijan."""
    rows: dict[str, dict] = {}
    dropped_az = 0
    for f in features:
        tags = {str(k): str(v) for k, v in (f.get('properties') or {}).items()}
        kind = park_kind(tags)
        sid = osm_id(f)
        pt = feature_point(f.get('geometry'))
        if not kind or not sid or not pt:
            continue
        if in_rings(pt[0], pt[1], az_rings):
            dropped_az += 1
            continue
        keep = {k: tags[k].strip()[:120] for k in KEEP_TAGS if tags.get(k, '').strip()}
        keep['kind'] = kind
        name = (tags.get('name') or '').strip()[:120] or None
        rows[sid] = {'id': sid, 'lat': round(pt[0], 7), 'lng': round(pt[1], 7), 'name': name, 'tags': keep}
    # A rest area / services with its own lorry parking: the parking is the place.
    parkings = [r for r in rows.values() if r['tags']['kind'] == 'parking']
    cell = {}
    for p in parkings:
        cell.setdefault((round(p['lat'], 2), round(p['lng'], 2)), []).append(p)
    out = []
    for r in rows.values():
        if r['tags']['kind'] != 'parking':
            near = [p for dl in (-0.01, 0, 0.01) for dn in (-0.01, 0, 0.01)
                    for p in cell.get((round(r['lat'] + dl, 2), round(r['lng'] + dn, 2)), [])]
            if any(distance_m((r['lat'], r['lng']), (p['lat'], p['lng'])) < 300 for p in near):
                continue
        out.append(r)
    out.sort(key=lambda r: r['id'])
    return out, dropped_az


def upsert_sql(country: str, rows: list[dict], data_date: str | None) -> str:
    payload = json.dumps(rows, ensure_ascii=False, separators=(',', ':'))
    tag = 'osm'
    while f'${tag}$' in payload or f'${tag}$' in (data_date or ''):
        tag = 'osm' + secrets.token_hex(4)
    date = 'null' if not data_date else "'" + data_date.replace("'", "''") + "'"
    return (f"select public.osm_truck_parks_upsert('{country}', ${tag}${payload}${tag}$::jsonb, "
            f"'geofabrik', {date});")


# ---------------------------------------------------------------- I/O parts

def _http(url: str, data: bytes | None = None, headers: dict | None = None, method: str | None = None):
    req = urllib.request.Request(url, data=data, method=method, headers={'User-Agent': USER_AGENT, **(headers or {})})
    return urllib.request.urlopen(req, timeout=600)


def download(url: str, dest: Path) -> str | None:
    """Downloads [url] once (with 3 tries); returns its Last-Modified date."""
    for attempt in range(3):
        try:
            with _http(url) as r, open(dest, 'wb') as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
                return r.headers.get('Last-Modified')
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == 2:
                raise
            print(f'  retry {url}: {e}', flush=True)
            time.sleep(30 * (attempt + 1))
    return None


def extract_features(pbf: Path, work: Path):
    """GeoJSON-like features of the parking / rest area objects in [pbf]:
    osmium-tool when installed, else pyosmium (pip) — the same output."""
    if shutil.which('osmium'):
        yield from _extract_cli(pbf, work)
    else:
        yield from extract_features_py(pbf, work)


def extract_features_py(pbf: Path, work: Path):
    """pyosmium: pass 1 keeps the matching objects + the nodes they use
    (like osmium tags-filter), pass 2 builds points / rings / areas."""
    import osmium  # pip install osmium

    filtered = work / 'filtered_py.osm.pbf'
    tag_filter = osmium.filter.KeyFilter('amenity', 'highway')
    with osmium.BackReferenceWriter(str(filtered), ref_src=str(pbf), overwrite=True) as writer:
        for obj in osmium.FileProcessor(str(pbf)).with_filter(tag_filter):
            tags = obj.tags
            if tags.get('amenity') == 'parking' or tags.get('highway') in ('rest_area', 'services'):
                writer.add(obj)

    def ring(nodes):
        out = []
        for n in nodes:
            try:
                out.append([n.lon, n.lat])
            except Exception:  # a node missing from the extract
                pass
        return out

    proc = osmium.FileProcessor(str(filtered)).with_locations().with_areas()
    for obj in proc:
        tags = {t.k: t.v for t in obj.tags}
        if not (tags.get('amenity') == 'parking' or tags.get('highway') in ('rest_area', 'services')):
            continue
        if obj.is_node():
            try:
                yield {'id': f'n{obj.id}', 'properties': tags, 'geometry': {'type': 'Point', 'coordinates': [obj.location.lon, obj.location.lat]}}
            except Exception:
                continue
        elif obj.is_way():
            coords = ring(obj.nodes)
            if coords:
                yield {'id': f'w{obj.id}', 'properties': tags, 'geometry': {'type': 'LineString', 'coordinates': coords}}
        elif obj.is_area():
            polys = [[ring(outer)] for outer in obj.outer_rings()]
            polys = [p for p in polys if p[0]]
            if polys:
                yield {'id': f'a{obj.id}', 'properties': tags, 'geometry': {'type': 'MultiPolygon', 'coordinates': polys}}


def _extract_cli(pbf: Path, work: Path):
    filtered = work / 'filtered.osm.pbf'
    seq = work / 'parks.geojsonseq'
    subprocess.run(['osmium', 'tags-filter', '--overwrite', '-o', str(filtered), str(pbf),
                    'nwr/amenity=parking', 'nwr/highway=rest_area,services'], check=True)
    subprocess.run(['osmium', 'export', '--overwrite', '-f', 'geojsonseq', '-u', 'type_id',
                    '-x', 'print_record_separator=false', '-o', str(seq), str(filtered)], check=True)
    with open(seq, encoding='utf-8') as f:
        for line in f:
            line = line.strip().lstrip('\x1e')
            if line:
                yield json.loads(line)


def run_sql(sql: str, token: str) -> object:
    url = f'https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query'
    body = json.dumps({'query': sql}).encode()
    for attempt in range(4):
        try:
            with _http(url, body, {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}, 'POST') as r:
                return json.loads(r.read() or b'null')
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(10 * (attempt + 1))
                continue
            raise SystemExit(f'SQL API error {e.code}: {e.read()[:300]!r}')
    return None


def import_country(cc: str, path: str, az_rings, token: str | None, out: Path | None) -> int:
    assert cc != 'AZ', 'Azerbaijan is never imported from OSM'
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        pbf = work / 'extract.osm.pbf'
        url = f'{GEOFABRIK}/{path}-latest.osm.pbf'
        print(f'{cc}: {url}', flush=True)
        data_date = download(url, pbf)
        rows, dropped = select_parks(extract_features(pbf, work), az_rings)
    print(f'{cc}: {len(rows)} truck parking objects ({dropped} inside Azerbaijan left out); data {data_date}', flush=True)
    if out is not None:
        (out / f'{cc}.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding='utf-8')
    if token:
        for i in range(0, len(rows), BATCH):
            run_sql(upsert_sql(cc, rows[i:i + BATCH], data_date), token)
        if not rows:
            run_sql(upsert_sql(cc, [], data_date), token)  # recorded: the country was checked
    return len(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--group', action='append', default=[], help=f'one of {", ".join(GROUPS)} or "phase-1"')
    ap.add_argument('--country', action='append', default=[], help='ISO code from the groups, e.g. GE')
    ap.add_argument('--dry-run', action='store_true', help='do not write to Supabase')
    ap.add_argument('--out', type=Path, help='also write <CC>.json files here')
    a = ap.parse_args()

    groups = [g for name in a.group for g in (PHASE_1 if name == 'phase-1' else [name])]
    todo: list[tuple[str, str]] = []
    for g in groups:
        if g not in GROUPS:
            ap.error(f'unknown group {g}')
        todo += GROUPS[g]
    known = {cc: p for lst in GROUPS.values() for cc, p in lst}
    for cc in a.country:
        cc = cc.upper()
        if cc == 'AZ':
            ap.error('Azerbaijan is never imported from OSM (platform parks only)')
        if cc not in known:
            ap.error(f'unknown country {cc}')
        todo.append((cc, known[cc]))
    if not todo:
        ap.error('nothing to do: give --group or --country')

    token = None if a.dry_run else os.environ.get('SUPABASE_ACCESS_TOKEN')
    if not a.dry_run and not token:
        print('::error::SUPABASE_ACCESS_TOKEN is not set', file=sys.stderr)
        return 1
    if a.out:
        a.out.mkdir(parents=True, exist_ok=True)

    with _http(AZ_POLY) as r:
        az_rings = parse_poly(r.read().decode())
    if not az_rings:
        print('::error::Azerbaijan border not read — stopping (nothing written)', file=sys.stderr)
        return 1

    total = 0
    for i, (cc, path) in enumerate(dict(todo).items()):
        if i:
            time.sleep(5)  # polite: one download after another
        total += import_country(cc, path, az_rings, token, a.out)
    print(f'done: {total} objects in {len(dict(todo))} countries', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
