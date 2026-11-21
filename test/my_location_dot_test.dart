// Owner, 21.11.2026: "xəritədə konum olduğum yer göy rəngdədir, işıq kimi
// yanıb sönsün, diqqət çəksin" (mockup approved: "Konum nöqtəsi yaxşıdır").
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/my_location_dot.dart';

void main() {
  testWidgets('the dot pulses: the wave grows and fades, then starts again', (t) async {
    await t.pumpWidget(const MaterialApp(home: Center(child: MyLocationDot())));
    MyLocationPainter painter() =>
        t.widget<CustomPaint>(find.descendant(of: find.byType(MyLocationDot), matching: find.byType(CustomPaint)).first).painter!
            as MyLocationPainter;
    final a = painter().t;
    await t.pump(kMyLocationPulse * 0.4);
    final b = painter().t;
    expect(b, greaterThan(a));
    await t.pump(kMyLocationPulse * 0.7);
    expect(painter().t, lessThan(b), reason: 'repeats');
    expect(t.getSize(find.byKey(const ValueKey('my-location-dot'))), const Size(kMyLocationBox, kMyLocationBox));
    expect(painter().color, isNot(Colors.transparent));
  });

  testWidgets('less motion: a still dot with a steady halo', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: MediaQuery(data: MediaQueryData(disableAnimations: true), child: Center(child: MyLocationDot())),
    ));
    final p = t.widget<CustomPaint>(find.descendant(of: find.byType(MyLocationDot), matching: find.byType(CustomPaint)).first).painter!
        as MyLocationPainter;
    expect(p.t, -1);
    await t.pump(const Duration(seconds: 1));
    expect(t.binding.hasScheduledFrame, isFalse, reason: 'nothing animates');
  });

  test('wired on Parklar and on Servislər / Mağazalar, never the old still dot', () {
    final park = File('lib/features/tirpark/presentation/tir_park_screen.dart').readAsStringSync();
    expect(park, contains('child: const IgnorePointer(child: MyLocationDot(dot: 22)),'));
    final svc = File('lib/features/services/presentation/services_map_screen.dart').readAsStringSync();
    expect(svc, contains('child: const IgnorePointer(child: MyLocationDot()),'));
    expect(File('lib/core/widgets/my_location_dot.dart').readAsStringSync(), contains('RepaintBoundary('));
  });
}
