// TIR Bazarı banner on the first open (owner, 09.11.2026): the old design
// without the banner showed first and the banner came a moment later. Now:
// nothing but the banner's ground in its fixed place until the answer is
// known; a repeat visit shows the banner kept on the device at once; an
// admin's edit still replaces it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/widgets/page_hero.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

class _Repo implements PageHeroRepository {
  final answers = <String, Completer<PageHero?>>{};
  int reads = 0;
  @override
  Future<PageHero?> fetch(String page) {
    reads++;
    return (answers[page] = Completer<PageHero?>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _c(_Repo repo) {
  final c = ProviderContainer(overrides: [
    pageHeroRepositoryProvider.overrideWithValue(repo),
    currentUserIdProvider.overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  return c;
}

const _hero = PageHero(imageUrl: 'https://x/market.jpg', title: 'TIR', titleAccent: 'Bazar');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PageHeroMemory.clear();
    SharedPreferences.setMockInitialValues({});
  });

  test('first visit: not known until the server answers (no default banner first)', () async {
    final repo = _Repo();
    final c = _c(repo);
    final sub = c.listen(pageHeroShownProvider('market'), (_, __) {});
    expect(sub.read().known, isFalse, reason: 'only the ground while the answer is on its way');
    repo.answers['market']!.complete(_hero);
    await c.read(pageHeroProvider('market').future);
    expect(sub.read().known, isTrue);
    expect(sub.read().hero?.imageUrl, 'https://x/market.jpg');
    // A page without a banner: the default design, once the answer says so.
    final s2 = c.listen(pageHeroShownProvider('services'), (_, __) {});
    repo.answers['services']!.complete(null);
    await c.read(pageHeroProvider('services').future);
    expect(s2.read(), (hero: null, known: true));
  });

  test('repeat visit: the kept banner at once, the server answer replaces it; kept on the device', () async {
    SharedPreferences.setMockInitialValues({'page_hero_v1_market': '{"image_url":"https://x/old.jpg","title":"Old"}'});
    await PageHeroMemory.load();
    final repo = _Repo();
    final c = _c(repo);
    final sub = c.listen(pageHeroShownProvider('market'), (_, __) {});
    expect(sub.read().known, isTrue, reason: 'shown before the server answers');
    expect(sub.read().hero?.imageUrl, 'https://x/old.jpg');
    // The admin changed it meanwhile: the new one replaces it and is kept.
    repo.answers['market']!.complete(_hero);
    await c.read(pageHeroProvider('market').future);
    expect(sub.read().hero?.imageUrl, 'https://x/market.jpg');
    await Future<void>.delayed(Duration.zero);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('page_hero_v1_market'), contains('https://x/market.jpg'));
    PageHeroMemory.clear();
    await PageHeroMemory.load();
    expect(PageHeroMemory.of('market')?.title, 'TIR');
  });

  test('offline: the kept banner stays (never the default one)', () async {
    SharedPreferences.setMockInitialValues({'page_hero_v1_market': '{"image_url":"https://x/old.jpg"}'});
    await PageHeroMemory.load();
    final repo = _Repo();
    final c = _c(repo);
    final sub = c.listen(pageHeroShownProvider('market'), (_, __) {});
    repo.answers['market']!.completeError(Exception('offline'));
    await c.read(pageHeroProvider('market').future);
    expect(sub.read().hero?.imageUrl, 'https://x/old.jpg');
  });

  test('an admin edit refreshes it (and the kept copy)', () async {
    final repo = _Repo();
    final c = _c(repo);
    final sub = c.listen(pageHeroShownProvider('market'), (_, __) {});
    repo.answers['market']!.complete(_hero);
    await c.read(pageHeroProvider('market').future);
    c.invalidate(pageHeroProvider('market'));
    expect(sub.read().hero?.imageUrl, 'https://x/market.jpg', reason: 'the old one stays while the new one comes');
    await Future<void>.delayed(Duration.zero);
    repo.answers['market']!.complete(const PageHero(imageUrl: 'https://x/new.jpg'));
    await c.read(pageHeroProvider('market').future);
    expect(sub.read().hero?.imageUrl, 'https://x/new.jpg');
    expect(PageHeroMemory.of('market')?.imageUrl, 'https://x/new.jpg');
    expect(repo.reads, 2);
  });

  test('the start-up request is taken once by the banner', () async {
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/b/#/market')), 'market');
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/b/#/tirpark')), 'tirpark');
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/b/#/services')), 'services');
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/b/#/services?shops=1')), 'shops');
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/b/#/cargo')), isNull);
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/b/')), isNull);
    final early = _Repo();
    PageHeroPrefetch.start(early, Uri.parse('https://a/b/#/market'));
    final repo = _Repo();
    final c = _c(repo);
    final f = c.read(pageHeroProvider('market').future);
    early.answers['market']!.complete(_hero);
    expect((await f)?.imageUrl, 'https://x/market.jpg');
    expect(repo.reads, 0, reason: 'not asked a second time');
    final m = src('lib/main.dart');
    expect(m, contains('PageHeroMemory.load(),'));
    expect(m, contains('PageHeroPrefetch.start(PageHeroRepository(), Uri.base);'));
  });

  testWidgets('the phone banner: ground only while unknown, same height; then the default design', (t) async {
    final repo = _Repo();
    await t.pumpWidget(ProviderScope(
      overrides: [
        pageHeroRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue(null),
        currentUserProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PageHeroBanner(
            page: 'market',
            strings: AppStrings({}),
            kicker: 'TIR Bazarı',
            defaultTitle: 'Reliable trucks',
            defaultAccent: 'always',
            defaultSubtitle: 'sub',
            icon: Icons.local_shipping,
            height: 150,
          ),
        ),
      ),
    ));
    expect(find.text('Reliable trucks', findRichText: true), findsNothing);
    expect(find.byIcon(Icons.local_shipping), findsNothing);
    expect(t.getSize(find.byKey(const ValueKey('page-hero-market'))).height, 150);
    repo.answers['market']!.complete(null);
    await t.pump();
    await t.pump();
    expect(find.textContaining('Reliable trucks', findRichText: true), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('page-hero-market'))).height, 150);
  });

  test('the picture: the ground in its place until the first frame, then picture + texts together', () {
    final p = src('lib/core/widgets/page_hero.dart');
    expect(p, contains('final ready = sync || frame != null;'));
    expect(p, contains('if (!ready) (placeholder ?? fallback)(c),'));
    expect(p, contains('if (ready && overlay != null) overlay!,'));
    expect(p, contains('overlay: texts ? Stack(fit: StackFit.expand, children: [shade, words]) : null,'));
    expect(src('lib/features/market/presentation/market_home_desktop.dart'),
        contains('overlay: texts ? Stack(fit: StackFit.expand, children: [shade, words]) : null)'));
  });
}
