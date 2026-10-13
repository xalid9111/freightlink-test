// Catalog photo order — pure logic (no Flutter widgets, no Supabase), so it
// is unit-tested in test/catalog_order_test.dart.
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// [list] with the element at [from] moved to [to]; everything else keeps
/// its relative order. Nothing is added or removed.
List<T> moveItem<T>(List<T> list, int from, int to) {
  if (from == to || from < 0 || from >= list.length) return List<T>.of(list);
  final out = List<T>.of(list);
  final item = out.removeAt(from);
  out.insert(to.clamp(0, out.length), item);
  return out;
}

/// The order being edited, brought up to date with the photos the server
/// has now: deleted photos drop out, new ones come first (as uploads do),
/// the user's arrangement of the rest is kept. Never loses or repeats one.
List<String> reconcileOrder(List<String> working, List<String> fresh) {
  final freshSet = fresh.toSet();
  final kept = <String>[];
  final seen = <String>{};
  for (final id in working) {
    if (freshSet.contains(id) && seen.add(id)) kept.add(id);
  }
  final added = [for (final id in fresh) if (!seen.contains(id)) id];
  return [...added.toSet(), ...kept];
}

/// True when [a] and [b] are the same photos (each once), in any order.
bool samePhotos(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().length == a.length && a.toSet().containsAll(b);

/// Grid geometry: square tiles, [columns] per row, [gap] between them.
class GridGeometry {
  final double width;
  final int columns;
  final double gap;

  /// Fixed tile size (e.g. 84 px thumbnails); null = tiles fill the width.
  final double? tileSize;
  const GridGeometry({required this.width, this.columns = 3, this.gap = 8, this.tileSize});

  /// As many fixed-size tiles per row as fit into [width] (at least 1).
  factory GridGeometry.fixed({required double width, required double tileSize, double gap = 8}) => GridGeometry(
        width: width,
        tileSize: tileSize,
        gap: gap,
        columns: math.max(1, ((width + gap) / (tileSize + gap)).floor()),
      );

  double get tile => tileSize ?? math.max(0, (width - gap * (columns - 1)) / columns);

  /// Top-left corner of slot [i] (row by row).
  Offset slotOffset(int i) => Offset((i % columns) * (tile + gap), (i ~/ columns) * (tile + gap));

  double heightFor(int slots) {
    if (slots <= 0) return 0;
    final rows = (slots + columns - 1) ~/ columns;
    return rows * tile + (rows - 1) * gap;
  }

  /// Slot under [point] (grid coordinates), limited to [first]..[last] —
  /// rows above / below and the gaps snap to the nearest slot.
  int slotAt(Offset point, {required int first, required int last}) {
    final step = tile + gap;
    if (step <= 0) return first;
    final col = (point.dx / step).floor().clamp(0, columns - 1);
    final row = math.max(0, (point.dy / step).floor());
    return (row * columns + col).clamp(first, last);
  }
}
