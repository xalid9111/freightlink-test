import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/cargo_marketplace_screen.dart' show StatCapsule;
import 'package:freightlink/features/cargo/presentation/providers/cargo_providers.dart' show statCount;

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
    final p = File('lib/features/cargo/presentation/providers/cargo_providers.dart').readAsStringSync();
    expect(p, contains(".from('empty_truck_ads')"));
    expect(p, contains(".eq('status', 'active')"));
    expect(p, contains(".from('user_profiles')"));
    final d = File('lib/features/cargo/presentation/cargo_marketplace_desktop.dart').readAsStringSync();
    expect(d.indexOf('registeredUsersCountProvider') < d.indexOf('truckAdsCountProvider'), isTrue);
  });
}
