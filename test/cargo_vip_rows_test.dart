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

String show(List<CargoModel> l, List<LoadRow> rows) =>
    rows.map((r) => '${r.vip ? 'V' : ''}[${r.loads.map((i) => l[i].id).join(',')}]').join(' ');

void main() {
  test('a VIP row (2 side by side) after every 3 normal rows by default; normal order kept', () {
    final l = [
      for (var i = 1; i <= 14; i++) load('n$i'),
      load('v1', vip: true), load('v2', vip: true), load('v3', vip: true), load('v4', vip: true),
    ];
    expect(show(l, buildLoadRows(l, vipEvery: kDefaultVipEvery, columns: 2, now: now)),
        '[n1,n2] [n3,n4] [n5,n6] V[v1,v2] [n7,n8] [n9,n10] [n11,n12] V[v3,v4] [n13,n14]');
  });

  test('admin interval 2 / 3 / 4 rows', () {
    final l = [for (var i = 1; i <= 8; i++) load('n$i'), load('v1', vip: true), load('v2', vip: true), load('v3', vip: true)];
    expect(show(l, buildLoadRows(l, vipEvery: 2, columns: 2, now: now)), '[n1,n2] [n3,n4] V[v1,v2] [n5,n6] [n7,n8] V[v3]');
    expect(show(l, buildLoadRows(l, vipEvery: 4, columns: 2, now: now)), '[n1,n2] [n3,n4] [n5,n6] [n7,n8] V[v1,v2] V[v3]');
    // Anything else falls back to the default (3).
    expect(show(l, buildLoadRows(l, vipEvery: 7, columns: 2, now: now)), '[n1,n2] [n3,n4] [n5,n6] V[v1,v2] [n7,n8] V[v3]');
  });

  test('no VIP left → no VIP row, never an empty card; each VIP shown once', () {
    final l = [for (var i = 1; i <= 12; i++) load('n$i'), load('v1', vip: true)];
    final rows = buildLoadRows(l, vipEvery: 3, columns: 2, now: now);
    expect(show(l, rows), '[n1,n2] [n3,n4] [n5,n6] V[v1] [n7,n8] [n9,n10] [n11,n12]');
    expect(rows.every((r) => r.loads.isNotEmpty), isTrue);
    expect(rows.expand((r) => r.loads).toSet().length, l.length);
  });

  test('a VIP that ended is a normal load; no end date = VIP', () {
    final l = [load('old', vip: true, until: now.subtract(const Duration(hours: 1))), load('open', vip: true), load('n1')];
    expect(show(l, buildLoadRows(l, vipEvery: 3, columns: 2, now: now)), '[old,n1] V[open]');
  });

  test('computer: wider normal rows, VIP rows still 2 cards', () {
    final l = [for (var i = 1; i <= 9; i++) load('n$i'), load('v1', vip: true), load('v2', vip: true), load('v3', vip: true)];
    expect(show(l, buildLoadRows(l, vipEvery: 3, columns: 3, now: now)), '[n1,n2,n3] [n4,n5,n6] [n7,n8,n9] V[v1,v2] V[v3]');
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
    test('phone + computer: VIP rows, no old wide ad banner, 3 mm gaps, 2 cm cards', () {
      final m = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
      final d = src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart');
      expect(m.contains('buildLoadRows(list, vipEvery: vipEvery, columns: 2)'), isTrue);
      expect(d.contains('buildLoadRows(list, vipEvery: vipEvery, columns: columns)'), isTrue);
      for (final f in [m, d]) {
        expect(f.contains('SponsoredBanner('), isFalse);
        expect(f.contains('vip: '), isTrue);
      }
      expect(m.contains('const kTileGap = 19.0;'), isTrue);
      expect(m.contains('const kTileWidth = 128.0;'), isTrue);
    });

    test("owner's design: orange VIP frame, gold medal, normal price, tiles on a panel", () {
      final card = src('lib/features/cargo/presentation/widgets/cargo_card.dart');
      expect(card.contains('color: vip ? AppColors.accent : AppColors.tileLine'), isTrue);
      expect(card.contains('child: VipMedal(size: 44)'), isTrue);
      expect(card.contains('vipGoldText'), isFalse);
      expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart').contains('DecoratedSliver('), isTrue);
      expect(src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart').contains('color: AppColors.cardAlt'), isTrue);
    });

    test('my own load without a picture: "Şəkil əlavə et" saves only the picture', () {
      final d = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
      expect(d.contains("key: const ValueKey('cargo-add-picture')"), isTrue);
      expect(d.contains('media.setCargoImage(cargo.id, picked)'), isTrue);
      expect(src('lib/features/cargo/data/cargo_media_repository.dart').contains(".update({'image_url': url})"), isTrue);
    });

    test('admin: interval 2 / 3 / 4 and VIP on / off on a load', () {
      final a = src('lib/features/admin/presentation/admin_pages.dart');
      expect(a.contains('const _VipEveryBar()'), isTrue);
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
