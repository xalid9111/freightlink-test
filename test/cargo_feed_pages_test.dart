// Yüklər page by page (owner, 09.11.2026, SQL 0109): after every page the
// rows on screen are exactly the first rows of the whole feed — same cards,
// same VIP / Premium chessboard and rotation — and the last page gives the
// whole feed.
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/errors/app_exception.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/domain/cargo_repository.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_feed_pager.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_providers.dart';
import 'package:freightlink/features/cargo/domain/cargo_feed_pages.dart';
import 'package:freightlink/features/cargo/domain/vip_rows.dart';
import 'package:freightlink/models/cargo_model.dart';

String src(String p) => File(p).readAsStringSync();

CargoModel _load(int i, DateTime created, Random r, DateTime now) {
  final kind = r.nextInt(10);
  DateTime ago(int h) => now.subtract(Duration(hours: h));
  return CargoModel(
    id: 'c${i.toString().padLeft(4, '0')}',
    ownerId: 'o',
    pickupCountry: 'AZ',
    pickupCity: 'Bakı',
    destinationCountry: 'TR',
    destinationCity: 'İstanbul',
    weightKg: 1000,
    pickupDate: now.add(const Duration(days: 3)),
    offeredPrice: 100,
    createdAt: created,
    isFeatured: kind == 0 || kind == 1,
    featuredUntil: kind == 0 ? now.add(const Duration(days: 2)) : (kind == 1 ? ago(5) : null),
    featuredSince: kind <= 1 ? ago(r.nextInt(200)) : null,
    premiumUntil: kind == 2 ? now.add(const Duration(days: 1)) : null,
    premiumSince: kind == 2 ? ago(r.nextInt(100)) : null,
    bumpStart: kind == 3 ? ago(r.nextInt(300)) : null,
    bumpTotal: kind == 3 ? 1 + r.nextInt(5) : null,
  );
}

class _Server implements CargoRepository {
  _Server(this.normal, {this.missing = false});
  final List<CargoModel> normal;
  final bool missing;
  final afterIds = <String?>[];
  int failNext = 0;
  void _check() {
    if (missing) throw const AppException('Could not find the function public.cargo_feed_promoted', code: 'PGRST202');
  }

  @override
  Future<List<CargoModel>> fetchFeedPromoted() async {
    _check();
    return const [];
  }

  @override
  Future<List<CargoModel>> fetchFeedPage({int limit = kCargoPageSize, CargoModel? after}) async {
    _check();
    if (failNext > 0) {
      failNext--;
      throw Exception('network');
    }
    afterIds.add(after?.id);
    final from = after == null ? 0 : normal.indexWhere((c) => c.id == after.id) + 1;
    return normal.skip(from).take(limit).toList();
  }

  @override
  Future<int> fetchFeedCount() async {
    _check();
    return normal.length;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('every page shows exactly the whole feed\'s first rows; the last page the whole feed (random feeds)', () {
    final now = DateTime(2026, 11, 9, 12);
    for (var seed = 0; seed < 300; seed++) {
      final r = Random(seed);
      var t = now;
      final all = <CargoModel>[];
      for (var i = 0; i < r.nextInt(150); i++) {
        t = t.subtract(Duration(minutes: r.nextInt(3) == 0 ? 0 : 1 + r.nextInt(600)));
        all.add(_load(i, t, r, now));
      }
      // As the server sends them (0109).
      int byNewest(CargoModel a, CargoModel b) {
        final d = b.createdAt!.compareTo(a.createdAt!);
        return d != 0 ? d : b.id.compareTo(a.id);
      }

      final promoted = [for (final c in all) if (c.isVipAt(now) || c.isPremiumAt(now)) c]..sort(byNewest);
      final normal = [for (final c in all) if (!c.isVipAt(now) && !c.isPremiumAt(now)) c]
        ..sort((a, b) {
          final d = b.liftedAt(now).compareTo(a.liftedAt(now));
          return d != 0 ? d : byNewest(a, b);
        });
      final rotation = r.nextInt(40);
      final whole = [...promoted, ...normal];
      final want = buildLoadRows(whole, columns: 2, now: now, rotation: rotation);
      final page = 1 + r.nextInt(25);
      var have = <CargoModel>[];
      var shownBefore = 0;
      for (var m = 0;; m += page) {
        final got = normal.skip(m).take(page).toList();
        have = appendPage(have, got);
        final complete = got.length < page;
        final loads = [...promoted, ...have];
        final rows = pagedRows(loads, complete: complete, columns: 2, now: now, rotation: rotation);
        for (var i = 0; i < rows.length; i++) {
          expect([for (final c in rows[i]) (loads[c.index].id, c.vip)], [for (final c in want[i]) (whole[c.index].id, c.vip)],
              reason: 'seed $seed, after ${m + got.length} loads, row $i');
        }
        expect(rows.length, greaterThanOrEqualTo(shownBefore), reason: 'rows never disappear (seed $seed)');
        shownBefore = rows.length;
        if (complete) {
          expect(rows.length, want.length, reason: 'the last page shows the whole feed (seed $seed)');
          break;
        }
      }
    }
  });

  test('the pager: first page + counter, the next page after the last load, then the end; old feed when 0109 is missing', () async {
    final now = DateTime.now();
    final r = Random(1);
    final normal = [for (var i = 0; i < 45; i++) _load(i, now.subtract(Duration(hours: i + 1)), r, now)]
        .map((c) => CargoModel(
            id: c.id, ownerId: 'o', pickupCountry: 'AZ', pickupCity: 'B', destinationCountry: 'TR', destinationCity: 'I',
            weightKg: 1, pickupDate: now.add(const Duration(days: 2)), offeredPrice: 1, createdAt: c.createdAt))
        .toList();
    final server = _Server(normal);
    final c = ProviderContainer(overrides: [
      cargoRepositoryProvider.overrideWithValue(server),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(cargoFeedPagerProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().ready, isTrue);
    expect(sub.read().normal.length, kCargoPageSize);
    expect(sub.read().count, 45);
    expect(sub.read().complete, isFalse);
    // A failed page is not asked again at once (no tight loop).
    server.failNext = 1;
    await c.read(cargoFeedPagerProvider.notifier).loadMore();
    await c.read(cargoFeedPagerProvider.notifier).loadMore();
    expect(sub.read().normal.length, kCargoPageSize, reason: 'waits a moment after a failure');
    expect(server.afterIds, [null]);
    c.invalidate(cargoFeedPagerProvider); // pull to refresh: starts again
    final sub2 = c.listen(cargoFeedPagerProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await c.read(cargoFeedPagerProvider.notifier).loadMore();
    expect(sub2.read().normal.length, 2 * kCargoPageSize);
    await c.read(cargoFeedPagerProvider.notifier).loadMore();
    expect(sub2.read().normal.length, 45);
    expect(sub2.read().complete, isTrue);
    expect([for (final x in sub2.read().normal) x.id], [for (final x in normal) x.id], reason: 'every load once, in order');
    expect(server.afterIds.last, normal[2 * kCargoPageSize - 1].id, reason: 'the next page starts after the last load');
    await c.read(cargoFeedPagerProvider.notifier).loadMore();
    expect(server.afterIds.length, 4, reason: 'nothing more to ask');
    sub.close();
    sub2.close();

    final old = ProviderContainer(overrides: [
      cargoRepositoryProvider.overrideWithValue(_Server(normal, missing: true)),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(old.dispose);
    final s3 = old.listen(cargoFeedPagerProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(s3.read().legacy, isTrue, reason: 'until the owner runs 0109 the page keeps the old full feed');
  });

  test('a page never brings a load twice', () {
    final now = DateTime(2026, 11, 9);
    CargoModel c(String id) => CargoModel(
        id: id, ownerId: 'o', pickupCountry: 'AZ', pickupCity: 'B', destinationCountry: 'TR', destinationCity: 'I',
        weightKg: 1, pickupDate: now, offeredPrice: 1, createdAt: now);
    expect([for (final x in appendPage([c('a'), c('b')], [c('b'), c('c')])) x.id], ['a', 'b', 'c']);
  });

  test('wired: SQL 0109 functions, old full feed when 0109 is not run yet, next page while scrolling', () {
    final repo = src('lib/features/cargo/data/cargo_repository_impl.dart');
    for (final f in ["rpc('cargo_feed_promoted')", "rpc('cargo_feed_page'", "rpc('cargo_feed_count')"]) {
      expect(repo, contains(f));
    }
    final pager = src('lib/features/cargo/presentation/providers/cargo_feed_pager.dart');
    expect(pager, contains('isMissingFeedFunction(e)'), reason: 'until the owner runs 0109 the old feed is used');
    final screen = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(screen, contains('pagedRows(feed.loads, complete: feed.complete, columns: 2)'));
    expect(screen, contains('ref.read(cargoFeedPagerProvider.notifier).loadMore()'));
    expect(screen, contains('final usePages = !anyFilter && !feed.legacy;'));
  });
}
