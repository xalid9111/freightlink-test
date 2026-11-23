import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/cargo_marketplace_screen.dart' show StatCapsule, statRowMaxWidth;
import 'package:freightlink/features/cargo/presentation/providers/cargo_providers.dart' show statCount;
import 'package:freightlink/features/cargo/presentation/widgets/live_map.dart' show LiveCapsule;

/// The map's three capsules (owner's pictures, 22.11.2026): aktiv yük ·
/// qeydiyyatlı istifadəçi · Daşıyıcılar bölməsindəki daşıyıcı; the picture's
/// size is the least, a longer number widens the capsule.
void main() {
  test('numbers with a comma between thousands, as on the picture', () {
    expect(statCount(0), '0');
    expect(statCount(14), '14');
    expect(statCount(6324), '6,324');
    expect(statCount(11280), '11,280');
    expect(statCount(265670), '265,670');
    expect(statCount(1234567), '1,234,567');
  });

  Future<double> widthOf(WidgetTester t, String v) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: StatCapsule(icon: Icons.local_shipping, color: Colors.orange, value: v, label: 'Aktiv yük')),
      ),
    ));
    expect(t.takeException(), isNull);
    return t.getSize(find.byType(StatCapsule)).width;
  }

  testWidgets('a short number keeps the least size, a long one widens it', (t) async {
    final small = await widthOf(t, '14');
    expect(small, StatCapsule.minWidth);
    expect(t.getSize(find.byType(StatCapsule)).height, StatCapsule.height);
    final big = await widthOf(t, '1,234,567');
    expect(big, greaterThan(small));
    // The page's own measure matches the drawn capsule (one scale for all).
    final c = t.element(find.byType(StatCapsule));
    expect(StatCapsule.widthOf(c, '1,234,567'), closeTo(big, 0.5));
    expect(StatCapsule.widthOf(c, '14'), StatCapsule.minWidth);
  });

  testWidgets('"CANLI" is a capsule as tall as the counters, still for less motion', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
            body: Center(
                child: LiveCapsule(label: 'CANLI', height: StatCapsule.height, width: StatCapsule.minWidth))),
      ),
    ));
    expect(t.takeException(), isNull);
    // The same size as a counter (owner, 23.11.2026).
    expect(t.getSize(find.byKey(const ValueKey('live-capsule'))), const Size(StatCapsule.minWidth, StatCapsule.height));
    expect(find.text('CANLI'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('the counters may be as wide as the slogan, measured with the text size', (t) async {
    late double normal, big;
    const span = TextSpan(text: 'Yüklər dünya üzrə hərəkətdədir');
    const style = TextStyle(fontSize: 12.5, height: 1.2);
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      normal = statRowMaxWidth(c, span, style);
      return const SizedBox();
    })));
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
        child: Builder(builder: (c) {
          big = statRowMaxWidth(c, span, style);
          return const SizedBox();
        }),
      ),
    ));
    expect(normal, greaterThan(100));
    expect(big, closeTo(normal * 1.25, 2));
  });

  test('wired: the order, the data, the tap on carriers, phone and computer', () {
    final m = File('lib/features/cargo/presentation/cargo_marketplace_screen.dart').readAsStringSync();
    final a = m.indexOf("ValueKey('stat-loads')");
    final b = m.indexOf("ValueKey('stat-users')");
    final c = m.indexOf("ValueKey('stat-carriers')");
    expect(a > 0 && a < b && b < c, isTrue, reason: 'aktiv yük · istifadəçi · daşıyıcı');
    expect(m, contains('registeredUsersCountProvider'));
    expect(m, contains('truckAdsCountProvider'));
    expect(m, contains('LoadsSection.carriers'), reason: 'a tap on carriers opens Daşıyıcılar');
    expect(m, contains('fit: BoxFit.scaleDown'), reason: 'never cut on a narrow phone');
    // Left right under the slogan, "CANLI" as a capsule on the same line on
    // the right, both ABOVE the map (owner's picture, 23.11.2026).
    final slogan = m.indexOf("ValueKey('home-slogan')");
    final row = m.indexOf("ValueKey('stat-row')");
    final live = m.indexOf("LiveCapsule(label: strings.t('map_live_badge'), height: StatCapsule.height");
    final map = m.indexOf('LiveMap(liveLabel');
    expect(slogan > 0 && slogan < row && row < a && c < live && live < map, isTrue);
    expect(m, contains("LiveMap(liveLabel: strings.t('map_live_badge'), routes: false, showBadge: false)"));
    // Never past the slogan's right end; "CANLI" as wide as a counter.
    expect(m, contains('final statScale = rowWidth > sloganWidth ? sloganWidth / rowWidth : 1.0;'));
    expect(m, contains('width: rowWidth * statScale,'));
    expect(m, contains('width: StatCapsule.minWidth * statScale,'), reason: '"CANLI" shrinks with them');
    final p = File('lib/features/cargo/presentation/providers/cargo_providers.dart').readAsStringSync();
    expect(p, contains(".from('empty_truck_ads')"));
    expect(p, contains(".eq('status', 'active')"));
    expect(p, contains(".from('user_profiles')"));
    final d = File('lib/features/cargo/presentation/cargo_marketplace_desktop.dart').readAsStringSync();
    expect(d.indexOf('registeredUsersCountProvider') < d.indexOf('truckAdsCountProvider'), isTrue);
  });
}
