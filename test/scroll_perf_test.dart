// Scroll smoothness (owner, 16.11.2026): every vertical scroll is measured;
// a poor one goes to AutoFix; admins get a live meter and test switches.
import 'dart:io';

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/perf/scroll_perf.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

List<double> frames(int n, double every) => [for (var i = 0; i < n; i++) i * every];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a smooth scroll: 60 fps, nothing missed, not poor', () {
    final s = ScrollPerfStats.fromFrameTimes(frames(61, 1000 / 60))!;
    expect(s.fps.round(), 60);
    expect(s.missed, 0);
    expect(s.poor, isFalse);
  });

  test('a steady 30 fps (battery saving / the 30 FPS choice) is not a problem', () {
    final s = ScrollPerfStats.fromFrameTimes(frames(31, 1000 / 30))!;
    expect(s.fps.round(), 30);
    expect(s.poor, isFalse);
  });

  test('a stuttering scroll: 20 fps and missed frames = poor', () {
    final s = ScrollPerfStats.fromFrameTimes(frames(21, 50))!;
    expect(s.fps.round(), 20);
    expect(s.missed, 40, reason: '20 gaps of 50 ms = 2 missed frames each');
    expect(s.poor, isTrue);
  });

  test('one long hitch makes a smooth scroll poor', () {
    final t = frames(60, 1000 / 60)..add(1000 + 180);
    expect(ScrollPerfStats.fromFrameTimes(t)!.poor, isTrue);
  });

  test('too short to judge = nothing reported', () {
    expect(ScrollPerfStats.fromFrameTimes(frames(2, 300)), isNull);
    expect(ScrollPerfStats.fromFrameTimes(frames(5, 10)), isNull, reason: 'under 100 ms');
  });

  test('a 300 ms scroll drawn in only 4 frames is caught (seen in the browser)', () {
    final s = ScrollPerfStats.fromFrameTimes([12349.5, 12449.5, 12549.5, 12649.5])!;
    expect(s.fps.round(), 10);
    expect(s.poor, isTrue);
  });

  test('phones smooth the finger by default, a computer does not (owner, 23.11.2026)', () {
    expect(PerfFlags.resampleByDefault(TargetPlatform.iOS), isTrue);
    expect(PerfFlags.resampleByDefault(TargetPlatform.android), isTrue);
    expect(PerfFlags.resampleByDefault(TargetPlatform.windows), isFalse);
    expect(PerfFlags.resampleByDefault(TargetPlatform.macOS), isFalse);
  });

  testWidgets('a phone with nothing saved starts with resampling on; a saved "off" stays off', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues({});
      await PerfFlags.load();
      expect(PerfFlags.resample.value, isTrue);
      expect(GestureBinding.instance.resamplingEnabled, isFalse, reason: 'never for a tap');
      PerfFlags.fingerScroll(true);
      expect(GestureBinding.instance.resamplingEnabled, isTrue, reason: 'while a finger scrolls');
      PerfFlags.fingerScroll(false);
      expect(GestureBinding.instance.resamplingEnabled, isFalse);
      SharedPreferences.setMockInitialValues({'perf_resample': false});
      await PerfFlags.load();
      PerfFlags.fingerScroll(true);
      expect(GestureBinding.instance.resamplingEnabled, isFalse);
      PerfFlags.fingerScroll(false);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a tap is never resampled (iPhone opens the photo picker only inside the touch); a finger scroll is', (t) async {
    await PerfFlags.set('resample', true);
    var tapped = 0;
    final seen = <bool>[];
    await t.pumpWidget(MaterialApp(
      home: ScrollPerfScope(
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (n) {
            if (n.dragDetails != null) seen.add(GestureBinding.instance.resamplingEnabled);
            return false;
          },
          child: ListView(children: [
            TextButton(onPressed: () => tapped++, child: const Text('pick')),
            for (var i = 0; i < 60; i++) SizedBox(height: 80, child: Text('$i')),
          ]),
        ),
      ),
    ));
    await t.tap(find.text('pick'));
    expect(GestureBinding.instance.resamplingEnabled, isFalse, reason: 'the tap went through at once');
    expect(tapped, 1);
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(seen, contains(true), reason: 'resampled while the finger scrolls');
    expect(GestureBinding.instance.resamplingEnabled, isFalse, reason: 'off again once the finger is up');
    await PerfFlags.set('resample', false);
  });

  testWidgets('switches are kept on the device; resampling follows its switch', (t) async {
    await PerfFlags.set('resample', true);
    PerfFlags.fingerScroll(true);
    expect(GestureBinding.instance.resamplingEnabled, isTrue);
    PerfFlags.fingerScroll(false);
    expect(PerfFlags.summary, 'resample');
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('perf_resample'), isTrue);
    await PerfFlags.set('resample', false);
    expect(GestureBinding.instance.resamplingEnabled, isFalse);
    expect(PerfFlags.summary, '');
  });

  testWidgets('the meter box shows only when its switch is on', (t) async {
    PerfFlags.meter.value = false;
    await t.pumpWidget(MaterialApp(
      home: ScrollPerfScope(child: ListView(children: [for (var i = 0; i < 50; i++) SizedBox(height: 80, child: Text('$i'))])),
    ));
    expect(find.byKey(const ValueKey('perf-meter')), findsNothing);
    PerfFlags.meter.value = true;
    await t.pump();
    expect(find.byKey(const ValueKey('perf-meter')), findsOneWidget);
    expect(find.text('Sürüşdürün…'), findsOneWidget);
    await t.fling(find.byType(ListView), const Offset(0, -600), 1500);
    await t.pumpAndSettle();
    expect(find.textContaining('fps'), findsOneWidget, reason: 'numbers after a scroll');
    PerfFlags.meter.value = false;
  });

  test('wired: app root, admin settings, test switches, AutoFix report', () {
    expect(src('lib/main.dart'), contains('builder: (context, child) => ScrollPerfScope('));
    final settings = src('lib/features/auth/presentation/settings_screen.dart');
    expect(settings, contains("title: 'Sürətölçən (admin)'"));
    expect(settings, contains('if (ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin) ...['));
    expect(src('lib/features/cargo/presentation/widgets/live_map.dart'), contains('if (PerfFlags.mapStill.value) return _stand();'));
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture.dart'), contains('if (PerfFlags.noImages.value) return placeholder;'));
    expect(src('lib/features/market/presentation/market_card.dart'), contains('if (PerfFlags.noImages.value) return placeholder;'));
    final perf = src('lib/core/perf/scroll_perf.dart');
    expect(perf, contains("source: 'perf'"));
    expect(perf, contains('if (_reports >= 6 || (last != null && now.difference(last) < const Duration(minutes: 10))) return;'));
  });
}
