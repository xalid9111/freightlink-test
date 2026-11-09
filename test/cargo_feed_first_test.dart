// Staged Yüklər feed (owner, 09.11.2026): the rows shown from the first,
// small answer must be EXACTLY the first rows of the full feed — the same
// cards, the same VIP / Premium chessboard and rotation — for any mix of
// loads, lifts and promotions.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/cargo_feed_first.dart';
import 'package:freightlink/features/cargo/domain/vip_rows.dart';
import 'package:freightlink/models/cargo_model.dart';

String src(String p) => File(p).readAsStringSync();

CargoModel _load(int i, DateTime created, Random r, DateTime now) {
  final kind = r.nextInt(10);
  DateTime ago(int h) => now.subtract(Duration(hours: h));
  return CargoModel(
    id: 'c$i',
    ownerId: 'o',
    pickupCountry: 'AZ',
    pickupCity: 'Bakı',
    destinationCountry: 'TR',
    destinationCity: 'İstanbul',
    weightKg: 1000,
    pickupDate: now.add(const Duration(days: 3)),
    offeredPrice: 100,
    createdAt: created,
    isHidden: r.nextInt(25) == 0,
    // VIP (some expired), Premium, İrəli çək — and plain loads.
    isFeatured: kind == 0 || kind == 1,
    featuredUntil: kind == 0 ? now.add(const Duration(days: 2)) : (kind == 1 ? ago(5) : null),
    featuredSince: kind <= 1 ? ago(r.nextInt(200)) : null,
    premiumUntil: kind == 2 ? now.add(const Duration(days: 1)) : null,
    premiumSince: kind == 2 ? ago(r.nextInt(100)) : null,
    bumpStart: kind == 3 ? ago(r.nextInt(300)) : null,
    bumpTotal: kind == 3 ? 1 + r.nextInt(5) : null,
  );
}

void main() {
  test('the first rows are exactly the full feed\'s first rows (many random feeds)', () {
    final now = DateTime(2026, 11, 9, 12);
    for (var seed = 0; seed < 400; seed++) {
      final r = Random(seed);
      final n = r.nextInt(120);
      // Newest first, as the server sends them (some loads at the same time).
      var t = now;
      final full = <CargoModel>[];
      for (var i = 0; i < n; i++) {
        t = t.subtract(Duration(minutes: r.nextInt(3) == 0 ? 0 : 1 + r.nextInt(600)));
        full.add(_load(i, t, r, now));
      }
      final listed = [for (final c in full) if (c.isListedOn(now)) c];
      final page = 1 + r.nextInt(30);
      final part = mergeFirstPart(
        newest: full.take(page).toList(),
        promoted: [for (final c in full) if (isPromotedRow(c)) c],
        now: now,
        pageSize: page,
      );
      final rotation = r.nextInt(50);
      final want = buildLoadRows(listed, columns: 2, now: now, rotation: rotation);
      final got = stableFirstRows(part, columns: 2, now: now, rotation: rotation);
      expect(got.length, lessThanOrEqualTo(want.length), reason: 'seed $seed');
      for (var i = 0; i < got.length; i++) {
        expect([for (final c in got[i]) (part.loads[c.index].id, c.vip)], [for (final c in want[i]) (listed[c.index].id, c.vip)],
            reason: 'seed $seed row $i');
      }
      if (part.complete) expect(got.length, want.length, reason: 'a small feed is shown whole (seed $seed)');
    }
  });

  test('with the full first page the screen already shows several rows', () {
    final now = DateTime(2026, 11, 9, 12);
    final r = Random(7);
    final full = [for (var i = 0; i < 200; i++) _load(i, now.subtract(Duration(minutes: 10 * i + 1)), r, now)];
    final part = mergeFirstPart(
      newest: full.take(kCargoFirstPage).toList(),
      promoted: [for (final c in full) if (isPromotedRow(c)) c],
      now: now,
    );
    expect(stableFirstRows(part, columns: 2, now: now).length, greaterThanOrEqualTo(4), reason: 'a phone screen full');
  });

  test('wired: the same promoted filter on the server; page waits for the full feed with filters; count from the full feed', () {
    final repo = src('lib/features/cargo/data/cargo_repository_impl.dart');
    expect(repo, contains('.or(kCargoPromotedFilter)'));
    expect(repo, contains('.limit(newest)'));
    final screen = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(screen, contains('final firstPart = marketplaceAsync.hasValue || anyFilter ? null : ref.watch(marketplaceFirstProvider).valueOrNull;'));
    expect(screen, contains('stableFirstRows(firstPart, columns: 2)'));
    expect(screen, contains('if (marketplaceAsync.hasValue)\n'), reason: 'the result count still waits for the full feed');
  });
}
