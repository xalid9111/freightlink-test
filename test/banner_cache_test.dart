// TIR Bazarı banner (owner, 09.11.2026): scrolling down and back up made the
// banner "open twice" — its data was dropped when it left the screen, asked
// for again, the default banner showed first and then the picture. Every
// page banner now stays in memory; the picture is decoded at its shown size.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/page_hero.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';

String src(String p) => File(p).readAsStringSync();

class _Repo implements PageHeroRepository {
  final reads = <String>[];
  @override
  Future<PageHero?> fetch(String page) async {
    reads.add(page);
    return PageHero.fromJson({'image_url': 'https://x/$page.jpg'});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('a banner that leaves the screen and comes back is not asked for again (every page)', () async {
    final repo = _Repo();
    final c = ProviderContainer(overrides: [
      pageHeroRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    for (final page in ['market', 'services', 'tirpark', 'shops']) {
      for (var i = 0; i < 3; i++) {
        final sub = c.listen(pageHeroProvider(page), (_, __) {});
        await c.read(pageHeroProvider(page).future);
        expect(sub.read().valueOrNull?.imageUrl, 'https://x/$page.jpg', reason: 'shown at once, no default banner first');
        sub.close(); // scrolled out of view
        await Future<void>.delayed(Duration.zero);
      }
    }
    expect(repo.reads, ['market', 'services', 'tirpark', 'shops'], reason: 'one read per banner');
    // An admin's edit still refreshes it.
    c.invalidate(pageHeroProvider('market'));
    await c.read(pageHeroProvider('market').future);
    expect(repo.reads.where((p) => p == 'market').length, 2);
  });

  test('the picture is decoded at the size it is shown (zoom included), sharp for wide pictures', () {
    expect(heroDecodeWidth(const BoxConstraints(maxWidth: 358, maxHeight: 150), 3, 1), 2148);
    expect(heroDecodeWidth(const BoxConstraints(maxWidth: 358, maxHeight: 150), 2, 1.5), 2148);
    expect(heroDecodeWidth(const BoxConstraints(maxWidth: 1100, maxHeight: 320), 2, 1), 2400, reason: 'at most 2400 px');
    expect(heroDecodeWidth(const BoxConstraints(maxWidth: 100, maxHeight: 50), 1, 1), 480, reason: 'at least 480 px');
    expect(heroDecodeWidth(const BoxConstraints(maxHeight: 150), 3, 1), isNull, reason: 'unknown width: full size');
    expect(src('lib/core/widgets/page_hero.dart'), contains('cacheWidth: heroDecodeWidth(c, MediaQuery.devicePixelRatioOf(context), zoom),'));
  });

  test('the Loads counters ask for the number only (same exact count, one row sent)', () {
    final p = src('lib/features/cargo/presentation/providers/cargo_providers.dart');
    expect('.limit(1)\n        .count(CountOption.exact);'.allMatches(p).length + '.limit(1)\n      .count(CountOption.exact);'.allMatches(p).length, 2);
  });
}
