// Catalog photo order (drag & drop) — pure logic.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/ads/presentation/catalog_order.dart';

void main() {
  group('moveItem', () {
    test('moves forward and backward, keeps the rest in order', () {
      expect(moveItem(['a', 'b', 'c', 'd'], 0, 2), ['b', 'c', 'a', 'd']);
      expect(moveItem(['a', 'b', 'c', 'd'], 3, 0), ['d', 'a', 'b', 'c']);
      expect(moveItem(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
    });
    test('never loses or duplicates a photo', () {
      final list = [for (var i = 0; i < 60; i++) 'p$i'];
      for (final (from, to) in [(0, 59), (59, 0), (12, 40), (40, 12), (5, 99)]) {
        final out = moveItem(list, from, to);
        expect(samePhotos(out, list), isTrue, reason: '$from → $to');
      }
    });
  });

  group('reconcileOrder (photos added / deleted while arranging)', () {
    test('keeps the arrangement, drops deleted, new uploads first', () {
      expect(reconcileOrder(['c', 'a', 'b'], ['new', 'a', 'b', 'c']), ['new', 'c', 'a', 'b']);
      expect(reconcileOrder(['c', 'a', 'b'], ['a', 'c']), ['c', 'a']);
    });
    test('result is always exactly the server photos, each once', () {
      final out = reconcileOrder(['x', 'a', 'a', 'b'], ['b', 'a', 'z']);
      expect(samePhotos(out, ['a', 'b', 'z']), isTrue);
      expect(out.length, 3);
    });
  });

  group('GridGeometry (3 columns)', () {
    const g = GridGeometry(width: 358); // 390 px phone minus 2 × 16 padding
    test('square tiles fill the width', () {
      expect(g.tile * 3 + g.gap * 2, closeTo(358, 0.001));
      expect(g.heightFor(7), closeTo(3 * g.tile + 2 * g.gap, 0.001));
      expect(g.heightFor(0), 0);
    });
    test('slots go left→right, then the next row', () {
      expect(g.slotOffset(0), Offset.zero);
      expect(g.slotOffset(4), Offset(g.tile + g.gap, g.tile + g.gap));
    });
    test('a point finds its slot across rows; outside snaps to the ends', () {
      final mid = Offset(g.tile / 2, g.tile / 2);
      expect(g.slotAt(g.slotOffset(5) + mid, first: 1, last: 9), 5);
      expect(g.slotAt(const Offset(-50, -50), first: 1, last: 9), 1); // "add" tile stays put
      expect(g.slotAt(const Offset(9999, 9999), first: 1, last: 9), 9);
    });
  });
}
