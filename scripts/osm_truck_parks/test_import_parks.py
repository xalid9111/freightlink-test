"""Unit tests for the OSM truck parking import (no network)."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_parks as ip  # noqa: E402

# A square around Baku and one around Nakhchivan, in the Osmosis .poly format.
AZ_POLY = """azerbaijan
1
   49.0   40.0
   50.5   40.0
   50.5   41.0
   49.0   41.0
   49.0   40.0
END
2
   45.0   39.0
   46.0   39.0
   46.0   39.6
   45.0   39.6
   45.0   39.0
END
!3
   49.5   40.3
   49.6   40.3
   49.6   40.4
END
END
"""


def feat(fid, tags, geom):
    return {'type': 'Feature', 'id': fid, 'properties': tags, 'geometry': geom}


def pt(lat, lng):
    return {'type': 'Point', 'coordinates': [lng, lat]}


class ImportTest(unittest.TestCase):
    def setUp(self):
        self.az = ip.parse_poly(AZ_POLY)

    def test_only_objects_marked_for_lorries(self):
        self.assertEqual(ip.park_kind({'amenity': 'parking', 'hgv': 'designated'}), 'parking')
        self.assertEqual(ip.park_kind({'amenity': 'parking', 'hgv': 'yes'}), 'parking')
        self.assertEqual(ip.park_kind({'highway': 'rest_area', 'hgv': 'yes'}), 'rest_area')
        self.assertEqual(ip.park_kind({'highway': 'services', 'hgv': 'only'}), 'services')
        self.assertIsNone(ip.park_kind({'amenity': 'parking'}), 'no hgv tag = not a truck park')
        self.assertIsNone(ip.park_kind({'amenity': 'parking', 'hgv': 'no'}))
        self.assertIsNone(ip.park_kind({'amenity': 'parking', 'hgv': 'yes', 'access': 'private'}))
        self.assertIsNone(ip.park_kind({'amenity': 'fuel', 'hgv': 'yes'}))
        self.assertIsNone(ip.park_kind({'amenity': 'parking', 'hgv': 'yes', 'disused:amenity': 'parking'}))

    def test_points_of_shapes(self):
        self.assertEqual(ip.feature_point(pt(41.7, 44.8)), (41.7, 44.8))
        sq = {'type': 'Polygon', 'coordinates': [[[44.0, 41.0], [44.2, 41.0], [44.2, 41.2], [44.0, 41.2]]]}
        lat, lng = ip.feature_point(sq)
        self.assertAlmostEqual(lat, 41.1)
        self.assertAlmostEqual(lng, 44.1)
        self.assertIsNone(ip.feature_point({'type': 'Polygon', 'coordinates': []}))
        self.assertEqual(ip.osm_id({'id': 'n12'}), 'node/12')
        self.assertEqual(ip.osm_id({'id': 'w7'}), 'way/7')
        self.assertEqual(ip.osm_id({'id': 'r3'}), 'relation/3')
        self.assertEqual(ip.osm_id({'id': 'a10'}), 'way/5', 'an area from a closed way')
        self.assertEqual(ip.osm_id({'id': 'a11'}), 'relation/5', 'an area from a multipolygon')
        self.assertIsNone(ip.osm_id({'id': 'x3'}))
        closed = {'type': 'Polygon', 'coordinates': [[[0, 0], [2, 0], [2, 2], [0, 2], [0, 0]]]}
        self.assertEqual(ip.feature_point(closed), (1.0, 1.0), 'the repeated first point does not pull the pin')

    def test_azerbaijan_border_read_with_nakhchivan(self):
        self.assertEqual(len(self.az), 2, 'two outer rings, the hole skipped')
        self.assertTrue(ip.in_rings(40.4, 49.8, self.az), 'Baku')
        self.assertTrue(ip.in_rings(39.2, 45.4, self.az), 'Nakhchivan')
        self.assertFalse(ip.in_rings(41.7, 44.8, self.az), 'Tbilisi')

    def test_select_drops_azerbaijan_keeps_source_facts_only(self):
        rows, dropped = ip.select_parks([
            feat('n1', {'amenity': 'parking', 'hgv': 'designated', 'name': 'TIR Park Tbilisi',
                        'fee': 'yes', 'phone': '+995', 'capacity:hgv': '40'}, pt(41.7, 44.8)),
            feat('n2', {'amenity': 'parking', 'hgv': 'yes', 'name': 'Bakı'}, pt(40.4, 49.8)),
            feat('n3', {'amenity': 'parking', 'hgv': 'yes'}, pt(39.2, 45.4)),
            feat('n4', {'amenity': 'parking'}, pt(42.0, 45.0)),
        ], self.az)
        self.assertEqual(dropped, 2, 'Baku and Nakhchivan never come from OSM')
        self.assertEqual([r['id'] for r in rows], ['node/1'])
        self.assertEqual(rows[0]['tags'], {'fee': 'yes', 'capacity:hgv': '40', 'hgv': 'designated', 'kind': 'parking'})
        self.assertEqual(rows[0]['name'], 'TIR Park Tbilisi')

    def test_one_row_per_object_and_rest_area_next_to_its_parking(self):
        rows, _ = ip.select_parks([
            feat('w10', {'highway': 'rest_area', 'hgv': 'yes'}, pt(48.0, 11.0)),
            feat('n11', {'amenity': 'parking', 'hgv': 'designated'}, pt(48.001, 11.001)),
            feat('n11', {'amenity': 'parking', 'hgv': 'designated'}, pt(48.001, 11.001)),
            feat('w12', {'highway': 'services', 'hgv': 'yes'}, pt(49.0, 12.0)),
        ], [])
        self.assertEqual([r['id'] for r in rows], ['node/11', 'way/12'])
        self.assertEqual(rows[0]['name'], None, 'no name in the source = no name')

    def test_sql_is_quoted_safely(self):
        rows = [{'id': 'node/1', 'lat': 1.0, 'lng': 2.0, 'name': "O'Brien $osm$ park", 'tags': {'kind': 'parking'}}]
        sql = ip.upsert_sql('GE', rows, "Tue, 10 Nov 2026")
        self.assertTrue(sql.startswith("select public.osm_truck_parks_upsert('GE', $osm"))
        tag = sql.split("'GE', ")[1].split('[')[0]
        self.assertNotEqual(tag, '$osm$', 'a name holding the quote tag changes the tag')
        body = sql.split(tag)[1]
        self.assertEqual(json.loads(body)[0]['name'], "O'Brien $osm$ park")

    def test_groups_never_hold_azerbaijan_and_phase_one_is_the_owners_list(self):
        codes = [cc for lst in ip.GROUPS.values() for cc, _ in lst]
        self.assertNotIn('AZ', codes)
        self.assertEqual(len(codes), len(set(codes)), 'every country once')
        phase1 = {cc for g in ip.PHASE_1 for cc, _ in ip.GROUPS[g]}
        for cc in ('DE', 'FR', 'PL', 'TR', 'GE', 'RU', 'KZ', 'UZ', 'KG', 'TJ', 'TM', 'IR'):
            self.assertIn(cc, phase1)
        self.assertNotIn('asia-rest', ip.PHASE_1)
        self.assertTrue(all(not p.startswith('asia/azerbaijan') for lst in ip.GROUPS.values() for _, p in lst))


if __name__ == '__main__':
    unittest.main()
