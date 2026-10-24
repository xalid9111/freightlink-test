// VIP loads on the Loads page (owner, 23.10.2026, migration 0059). Server
// rules: supabase/tests/local/96_cargo_vip_rows.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/vip_rows.dart';
import 'package:freightlink/models/cargo_model.dart';

final now = DateTime(2026, 10, 23, 12);

CargoModel load(String id, {bool vip = false, DateTime? until}) => CargoModel(
      id: id,
      ownerId: 'o',
      pickupCountry: 'Azerbaijan',
      pickupCity: 'Baku',
      destinationCountry: 'Georgia',
      destinationCity: 'Tbilisi',
      weightKg: 1000,
      pickupDate: DateTime(2026, 10, 24),
      offeredPrice: 100,
      isFeatured: vip,
      featuredUntil: until,
    );

String show(List<CargoModel> l, List<List<LoadCell>> rows) =>
    rows.map((r) => '[${r.map((c) => '${c.vip ? 'V:' : ''}${l[c.index].id}').join(',')}]').join(' ');

void main() {
  test("chessboard: load–VIP, VIP–load, load–VIP, VIP–load (owner's order)", () {
    final l = [
      for (var i = 1; i <= 4; i++) load('n$i'),
      for (var i = 1; i <= 4; i++) load('v$i', vip: true),
    ];
    expect(show(l, buildLoadRows(l, columns: 2, now: now, rotation: 0)),
        '[n1,V:v1] [V:v2,n2] [n3,V:v3] [V:v4,n4]');
  });

  test('when VIPs run out the loads fill the rows (and the other way round)', () {
    final l = [for (var i = 1; i <= 5; i++) load('n$i'), load('v1', vip: true), load('v2', vip: true)];
    expect(show(l, buildLoadRows(l, columns: 2, now: now, rotation: 0)), '[n1,V:v1] [V:v2,n2] [n3,n4] [n5]');
    final m = [load('n1'), for (var i = 1; i <= 4; i++) load('v$i', vip: true)];
    expect(show(m, buildLoadRows(m, columns: 2, now: now, rotation: 0)), '[n1,V:v1] [V:v2,V:v3] [V:v4]');
  });

  test('the VIP order moves on, so every VIP comes to the front in turn', () {
    final l = [load('n1'), load('n2'), load('v1', vip: true), load('v2', vip: true), load('v3', vip: true)];
    expect(show(l, buildLoadRows(l, columns: 2, now: now, rotation: 1)), '[n1,V:v2] [V:v3,n2] [V:v1]');
    expect(show(l, buildLoadRows(l, columns: 2, now: now, rotation: 2)), '[n1,V:v3] [V:v1,n2] [V:v2]');
    expect(show(l, buildLoadRows(l, columns: 2, now: now, rotation: 3)), show(l, buildLoadRows(l, columns: 2, now: now, rotation: 0)));
    final t0 = DateTime(2026, 10, 24, 12, 0);
    expect(vipRotation(t0.add(const Duration(minutes: kVipRotateMinutes))), vipRotation(t0) + 1);
  });

  test('pairs everywhere; only the last card may stand alone; each load once', () {
    final l = [for (var i = 1; i <= 6; i++) load('n$i'), load('v1', vip: true), load('v2', vip: true), load('v3', vip: true)];
    final rows = buildLoadRows(l, columns: 2, now: now, rotation: 0);
    for (final r in rows.take(rows.length - 1)) {
      expect(r.length, 2);
    }
    expect(rows.expand((r) => r).map((c) => c.index).toSet().length, l.length);
  });

  test('no VIP → just the loads, newest first; a VIP that ended is a normal load', () {
    final l = [load('old', vip: true, until: now.subtract(const Duration(hours: 1))), load('n1'), load('open', vip: true)];
    expect(show(l, buildLoadRows(l, columns: 2, now: now, rotation: 0)), '[old,V:open] [n1]');
    final m = [load('a'), load('b'), load('c')];
    expect(show(m, buildLoadRows(m, columns: 2, now: now)), '[a,b] [c]');
  });

  test('computer: the same chessboard with wider rows', () {
    final l = [for (var i = 1; i <= 3; i++) load('n$i'), for (var i = 1; i <= 3; i++) load('v$i', vip: true)];
    expect(show(l, buildLoadRows(l, columns: 3, now: now, rotation: 0)), '[n1,V:v1,n2] [V:v2,n3,V:v3]');
  });

  test('VIP is read from the load, never sent when a load is saved', () {
    final c = CargoModel.fromJson({
      'id': 'x', 'owner_id': 'o', 'pickup_country': 'A', 'pickup_city': 'a', 'destination_country': 'B',
      'destination_city': 'b', 'weight_kg': 1, 'pickup_date': '2026-10-22', 'offered_price': 1,
      'is_featured': true, 'featured_until': '2026-10-30T00:00:00Z',
    });
    expect(c.isVipAt(now), isTrue);
    expect(c.toInsertJson().containsKey('is_featured'), isFalse);
    expect(c.toInsertJson().containsKey('featured_until'), isFalse);
  });

  group('wiring', () {
    String src(String p) => File(p).readAsStringSync();
    test('phone + computer: VIP rows, no old wide ad banner, 3 mm gaps, cards as in the owner\'s picture', () {
      final m = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
      final d = src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart');
      expect(m.contains('buildLoadRows(list, columns: 2)'), isTrue);
      expect(d.contains('buildLoadRows(list, columns: columns)'), isTrue);
      for (final f in [m, d]) {
        expect(f.contains('SponsoredBanner('), isFalse);
        expect(f.contains('vip: '), isTrue);
      }
      expect(m.contains('const kTileGap = 19.0;'), isTrue);
      expect(m.contains('const kTileWidth = 169.0;'), isTrue);
    });

    test("owner's design: gold VIP frame on the picture (no orange frame / medal twice), normal price, no panel", () {
      final card = src('lib/features/cargo/presentation/widgets/cargo_card.dart');
      // Owner, 24.10.2026: the picture in the gold VIP frame replaces the
      // orange card frame and the medal — one VIP mark only.
      expect(card.contains('VipPictureFrame('), isTrue);
      expect(card.contains('color: vip ? AppColors.accent : AppColors.tileLine'), isFalse);
      expect(card.contains('child: VipMedal(size: 50)'), isFalse);
      expect(card.contains('vipGoldText'), isFalse);
      // No coloured panel behind the tiles any more (owner, 24.10.2026).
      expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart').contains('DecoratedSliver('), isFalse);
      expect(src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart').contains('color: AppColors.cardAlt'), isFalse);
    });

    test('my own load without a picture: "Şəkil əlavə et" saves only the pictures', () {
      final d = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
      expect(d.contains("key: const ValueKey('cargo-add-picture')"), isTrue);
      // Up to 6 pictures since 0060; only the pictures are saved.
      expect(d.contains('media.setCargoPictures(cargo.id, picked)'), isTrue);
      expect(src('lib/features/cargo/data/cargo_media_repository.dart')
          .contains(".update({'image_urls': urls, 'image_url': urls.isEmpty ? null : urls.first})"), isTrue);
    });

    test('admin: VIP on / off on a load', () {
      final a = src('lib/features/admin/presentation/admin_pages.dart');
      // The 2 / 3 / 4 interval is no longer used (VIP and loads alternate), so it is not shown.
      expect(a.contains('_VipEveryBar'), isFalse);
      expect(a.contains("key: const ValueKey('admin-cargo-vip')"), isTrue);
      expect(kVipEveryChoices, [2, 3, 4]);
      expect(kDefaultVipEvery, 3);
    });

    test('0059 is safe and admin-checked', () {
      final sql = File('supabase/migrations/0059_cargo_vip_rows.sql').readAsStringSync().toLowerCase();
      expect(sql.contains('drop table'), isFalse);
      expect(sql.contains('truncate'), isFalse);
      expect(RegExp(r'delete\s+from').hasMatch(sql), isFalse);
      for (final fn in ['admin_set_cargo_vip(', 'admin_set_cargo_vip_every(']) {
        final body = sql.substring(sql.indexOf('function public.$fn'));
        expect(body.substring(0, body.indexOf(r'end $$')).contains('_require_admin()'), isTrue, reason: fn);
      }
    });
  });
}
