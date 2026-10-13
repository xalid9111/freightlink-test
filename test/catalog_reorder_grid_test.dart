// Drag & drop in the owner's catalog grid on iPhone, small phone, desktop.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/ads/presentation/catalog_reorder_grid.dart';
import 'package:freightlink/repositories/profile_page_repository.dart';

CatalogItem _item(int i) => CatalogItem(
      id: 'p$i',
      userId: 'u',
      imagePath: 'u/catalog/$i.jpg',
      imageUrl: 'https://example.invalid/$i.jpg',
      createdAt: DateTime(2026, 10, 1).add(Duration(minutes: i)),
    );

void main() {
  const sizes = {'iphone390': Size(390, 844), 'small320': Size(320, 568), 'desktop1280': Size(1280, 800)};
  for (final e in sizes.entries) {
    testWidgets('${e.key}: hold + drag across rows reorders; page does not scroll', (tester) async {
      tester.view.physicalSize = e.value * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final items = [for (var i = 0; i < 20; i++) _item(i)];
      List<String>? reported;
      CatalogItem? opened;
      final scroll = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
            CatalogReorderGrid(
              items: items,
              leading: const ColoredBox(color: Colors.grey, child: Text('add')),
              tileBuilder: (it) => ColoredBox(color: Colors.blue, child: Center(child: Text(it.id))),
              onOpen: (it) => opened = it,
              onOrderChanged: (ids) => reported = ids,
            ),
          ]),
        ),
      ));

      // Tap opens the photo (no drag).
      await tester.tap(find.text('p0'));
      await tester.pump();
      expect(opened?.id, 'p0');

      // Hold p0 (slot 1, first row), drag it down to p4's place (second row).
      final start = tester.getCenter(find.text('p0'));
      final target = tester.getCenter(find.text('p4'));
      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600)); // long press
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(start, target, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, 0, reason: 'the page must not scroll while a photo is dragged');
      await g.up();
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.indexOf('p0'), 4);
      expect(reported!.toSet().length, 20, reason: 'no photo lost or duplicated');
      expect(reported!.take(4), ['p1', 'p2', 'p3', 'p4']);
      // The others slid: p1 now sits where p0 was.
      expect(tester.getCenter(find.text('p1')), start);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('photos added / deleted elsewhere keep the arrangement, nothing lost', (tester) async {
    List<String>? reported;
    Widget grid(List<CatalogItem> items) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CatalogReorderGrid(
                items: items,
                tileBuilder: (it) => Text(it.id),
                onOpen: (_) {},
                onOrderChanged: (ids) => reported = ids,
              ),
            ),
          ),
        );
    await tester.pumpWidget(grid([_item(1), _item(2), _item(3)]));
    await tester.pumpWidget(grid([_item(9), _item(1), _item(3)])); // 2 deleted, 9 added
    await tester.pump();
    expect(reported, ['p9', 'p1', 'p3']);
  });
}
