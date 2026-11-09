// TIRPark · Servislər · Mağazalar switch (owner, 08.11.2026): the banner
// picture must not be fetched again (default picture first, then reload)
// when going back and forth between the map pages.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/page_hero.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';

class _Repo implements PageHeroRepository {
  final calls = <String, int>{};
  @override
  Future<PageHero?> fetch(String page) async {
    calls[page] = (calls[page] ?? 0) + 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> visit(ProviderContainer c, String page) async {
  final sub = c.listen(pageHeroProvider(page), (_, __) {});
  await c.read(pageHeroProvider(page).future);
  sub.close(); // the page is left
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('TIRPark / Servislər banners stay loaded when switching back and forth', () async {
    final repo = _Repo();
    final c = ProviderContainer(overrides: [
      pageHeroRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    for (var i = 0; i < 3; i++) {
      await visit(c, 'tirpark');
      await visit(c, 'services'); // Servislər and Mağazalar share it
    }
    expect(repo.calls['tirpark'], 1);
    expect(repo.calls['services'], 1);
  });

  // Owner, 09.11.2026: the TIR Bazarı banner stays in memory too (it
  // "opened twice" when scrolled away and back).
  test('the TIR Bazarı banner is kept too', () async {
    final repo = _Repo();
    final c = ProviderContainer(overrides: [
      pageHeroRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    await visit(c, 'market');
    await visit(c, 'market');
    expect(repo.calls['market'], 1);
  });

  test('an admin edit still refreshes it', () async {
    final repo = _Repo();
    final c = ProviderContainer(overrides: [
      pageHeroRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    await visit(c, 'tirpark');
    c.invalidate(pageHeroProvider('tirpark'));
    await visit(c, 'tirpark');
    expect(repo.calls['tirpark'], 2);
  });
}
