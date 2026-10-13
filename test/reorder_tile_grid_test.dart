// Drag & drop of the service-profile photos (fixed 84 px tiles + ✕ button).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/reorder_tile_grid.dart';
import 'package:freightlink/features/ads/presentation/catalog_order.dart';

class _Host extends StatefulWidget {
  final ScrollController scroll;
  final double top;
  const _Host(this.scroll, {this.top = 100});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<String> ids = [for (var i = 0; i < 7; i++) 'p$i'];
  List<String> removed = [];

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: ListView(controller: widget.scroll, padding: const EdgeInsets.all(16), children: [
            SizedBox(height: widget.top),
            ReorderTileGrid(
              ids: ids,
              onReorder: (next) => setState(() => ids = next),
              tileBuilder: (id) => Stack(fit: StackFit.expand, children: [
                ColoredBox(color: Colors.blue, child: Center(child: Text(id))),
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    key: ValueKey('x-$id'),
                    onTap: () => setState(() {
                      ids = [...ids]..remove(id);
                      removed.add(id);
                    }),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ),
              ]),
              trailing: const ColoredBox(color: Colors.grey, child: Text('add')),
            ),
            const SizedBox(height: 900),
          ]),
        ),
      );
}

void main() {
  test('fixed 84 px tiles: as many per row as fit', () {
    expect(GridGeometry.fixed(width: 358, tileSize: 84).columns, 3); // 390 phone, 16 padding
    expect(GridGeometry.fixed(width: 390 - 32 - 8, tileSize: 84).columns, 3);
    expect(GridGeometry.fixed(width: 380, tileSize: 84).columns, 4);
    expect(GridGeometry.fixed(width: 50, tileSize: 84).columns, 1);
    expect(GridGeometry.fixed(width: 380, tileSize: 84).tile, 84);
  });

  const sizes = {'iphone390': Size(390, 844), 'small320': Size(320, 568), 'desktop1280': Size(1280, 800)};
  for (final e in sizes.entries) {
    testWidgets('${e.key}: hold + drag reorders across rows, page does not scroll', (tester) async {
      tester.view.physicalSize = e.value * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      await tester.pumpWidget(_Host(scroll));
      final state = tester.state<_HostState>(find.byType(_Host));

      // Move p0 to the last photo's place (another row on phones).
      final start = tester.getCenter(find.text('p0'));
      final target = tester.getCenter(find.text('p6'));
      final addBefore = tester.getTopLeft(find.text('add'));
      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(start, target, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, 0, reason: 'page must not scroll while dragging');
      await g.up();
      await tester.pumpAndSettle();

      expect(state.ids, ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p0']);
      expect(state.ids.toSet().length, 7, reason: 'nothing lost or duplicated');
      expect(tester.getTopLeft(find.text('add')), addBefore, reason: '"add" tile stays after the photos');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('✕ still deletes a photo; a short tap never starts a drag', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(_Host(scroll));
    final state = tester.state<_HostState>(find.byType(_Host));
    await tester.tap(find.byKey(const ValueKey('x-p3')));
    await tester.pumpAndSettle();
    expect(state.removed, ['p3']);
    expect(state.ids, ['p0', 'p1', 'p2', 'p4', 'p5', 'p6']);
    expect(find.text('p3'), findsNothing);
  });

  testWidgets('holding a photo near the bottom edge scrolls the page on purpose', (tester) async {
    tester.view.physicalSize = const Size(320, 568) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    await tester.pumpWidget(_Host(scroll, top: 330));
    final start = tester.getCenter(find.text('p0'));
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveTo(Offset(start.dx, 560)); // inside the bottom edge zone
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, greaterThan(0));
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.state<_HostState>(find.byType(_Host)).ids.toSet().length, 7);
  });
}
