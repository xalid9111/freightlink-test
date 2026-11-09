// Start-up speed. 24.10.2026: slim fonts, files in parallel. 08.11.2026
// (owner): faster start — the same visual order (logo → app → Yüklər with
// its parts), only sooner and steadier.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/localization/localization_service.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/theme/theme_mode.dart';
import 'package:freightlink/features/cargo/data/cargo_feed_prefetch.dart';
import 'package:freightlink/features/cargo/domain/cargo_feed_first.dart';
import 'package:freightlink/features/cargo/domain/cargo_feed_pages.dart';
import 'package:freightlink/features/cargo/domain/cargo_repository.dart';
import 'package:freightlink/models/cargo_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

class _Repo implements CargoRepository {
  int calls = 0;
  @override
  Future<List<CargoModel>> fetchMarketplace({
    String? pickupCountry,
    String? destinationCountry,
    String? cargoType,
    String? truckType,
    double? minPrice,
    double? maxPrice,
    double? maxWeightKg,
  }) async {
    calls++;
    return const [];
  }

  int firstCalls = 0;
  @override
  Future<CargoFeedPart> fetchMarketplaceFirst({int newest = kCargoFirstPage}) async {
    firstCalls++;
    return (loads: const <CargoModel>[], complete: true, cutoff: null);
  }

  int pageCalls = 0;
  @override
  Future<List<CargoModel>> fetchFeedPromoted() async {
    pageCalls++;
    return const [];
  }

  @override
  Future<List<CargoModel>> fetchFeedPage({int limit = kCargoPageSize, CargoModel? after}) async => const [];

  @override
  Future<int> fetchFeedCount() async => 7;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Owner, 24.10.2026 ("sayt gec yüklənir"): smaller start-up. Guards that
  // the slim fonts stay in use and the start-up files load in parallel.
  test('slim fonts (renamed as the OFL asks), no unused bold italic', () {
    final pub = src('pubspec.yaml');
    for (final s in ['Regular', 'Bold', 'Italic']) {
      expect(pub, contains('assets/fonts/FreightLinkSans-$s.ttf'));
      final f = File('assets/fonts/FreightLinkSans-$s.ttf');
      expect(f.lengthSync(), lessThan(200 * 1024), reason: s);
      // OFL: a changed font must not carry the reserved name "Liberation".
      expect(String.fromCharCodes(f.readAsBytesSync()).contains('Liberation Sans'), isFalse, reason: s);
    }
    expect(pub.contains('LiberationSans-'), isFalse);
    expect(pub.contains('BoldItalic'), isFalse);
    expect(src('assets/fonts/OFL.txt'), contains('FreightLinkSans-*.ttf are Modified Versions of Liberation Sans'));
  });

  test('the app file starts downloading at once; languages load in parallel', () {
    expect(src('web/index.html'), contains('<link rel="preload" href="main.dart.js" as="script">'));
    expect(src('lib/core/localization/localization_service.dart'), contains('await Future.wait('));
  });

  // Owner, 08.11.2026: faster start, the same visual order.

  group('texts', () {
    test('before the first screen only the languages it can use; English fills missing keys', () async {
      final m = await LocalizationService.loadStartup(const Locale('ru'));
      expect(m.keys.toSet(), {const Locale('ru'), const Locale('az'), const Locale('en')});
      expect(m[const Locale('az')]!.t('login_button'), isNot('login_button'));
      expect(m[const Locale('ru')]!.t('login_button'), isNot('login_button'));
    });

    test('a language not loaded yet is fetched when needed (the default shows meanwhile)', () async {
      final start = await LocalizationService.loadStartup(null);
      final catalog = LocaleCatalog(start);
      final c = ProviderContainer(overrides: [localeCatalogProvider.overrideWith((ref) => catalog)]);
      addTearDown(c.dispose);
      expect(catalog.state.containsKey(const Locale('ka')), isFalse);
      await catalog.ensure(const Locale('ka'));
      expect(catalog.state.containsKey(const Locale('ka')), isTrue);
      await catalog.loadRest();
      expect(catalog.state.length, LocalizationService.supportedLocales.length);
    });

    test('English is read once; a version copy is used only for the same published version', () {
      final l = src('lib/core/localization/localization_service.dart');
      expect(l, contains('static Future<Map<String, String>> _file(String code) => _files[code] ??= _read(code);'));
      expect(l, contains("static const String buildId = String.fromEnvironment('BUILD_ID');"));
      final web = src('lib/core/localization/fresh_text_web.dart');
      expect(web, contains('if (nl <= 0 || v.substring(0, nl) != build) return null;'));
      expect(web, contains("RequestInit(cache: 'no-cache')"), reason: 'a new version still reads fresh texts');
      expect(src('.github/workflows/deploy.yml'), contains('--dart-define=BUILD_ID=\${{ github.sha }}'));
      expect(src('.github/workflows/deploy.yml'), contains('    branches: [main]'));
    });
  });

  group('colours', () {
    test('a device that already knows the night palette never waits for the server', () async {
      SharedPreferences.setMockInitialValues({kNightThemeCheckedKey: true});
      final never = Completer<void>().future; // the server never answers
      await loadSavedTheme(serverReady: never).timeout(const Duration(milliseconds: 300));
      expect(AppColors.isDay, isFalse);
    });

    test('day mode: no server at all', () async {
      SharedPreferences.setMockInitialValues({kThemeModeKey: kThemeDay});
      await loadSavedTheme(serverReady: Completer<void>().future).timeout(const Duration(milliseconds: 300));
      expect(AppColors.isDay, isTrue);
      AppColors.use(AppPalette.dark);
    });

    test('a late answer is kept for the next start, never put on an open screen', () {
      final t = src('lib/core/theme/theme_mode.dart');
      expect(t, contains('if (known) return; // kept for the next start'));
      expect(t, contains('final published = await refresh.timeout(const Duration(milliseconds: 1500));'));
      final from = t.indexOf('Future<PublishedNightTheme?> _refreshPublishedNightTheme');
      final body = t.substring(from, t.indexOf('\n}\n', from));
      expect(body.contains('AppColors.use'), isFalse, reason: 'the background refresh only stores');
    });
  });

  group('Yüklər request sent during start-up', () {
    test('taken once, for the same account, while fresh', () async {
      final repo = _Repo();
      CargoFeedPrefetch.start(repo, 'u1');
      expect(CargoFeedPrefetch.takePages(() => 'u2'), isNull, reason: 'another account');
      CargoFeedPrefetch.start(repo, null);
      final p = CargoFeedPrefetch.takePages(() => null)!;
      expect(await p.count, 7);
      expect(CargoFeedPrefetch.takePages(() => null), isNull, reason: 'only once: a refresh asks the server again');
      expect(repo.pageCalls, 2);
      // Page by page (owner, 09.11.2026, 0109): never the whole feed at start-up.
      expect(repo.calls, 0);
      expect(repo.firstCalls, 0);
    });

    test('only when the app opens on Yüklər', () {
      expect(CargoFeedPrefetch.opensOnLoads(Uri.parse('https://x.io/freightlink-test/')), isTrue);
      expect(CargoFeedPrefetch.opensOnLoads(Uri.parse('https://x.io/freightlink-test/#/cargo')), isTrue);
      expect(CargoFeedPrefetch.opensOnLoads(Uri.parse('https://x.io/freightlink-test/#/market/l/5')), isFalse);
      expect(CargoFeedPrefetch.opensOnLoads(Uri.parse('https://x.io/freightlink-test/#/cargo/abc')), isFalse);
    });

    test('start-up sends the small page-by-page requests; the pager takes them once', () {
      expect(src('lib/features/cargo/data/cargo_feed_prefetch.dart'),
          contains('final parts = (promoted: repo.fetchFeedPromoted(), page: repo.fetchFeedPage(), count: repo.fetchFeedCount());'));
      expect(src('lib/features/cargo/presentation/providers/cargo_feed_pager.dart'), contains('CargoFeedPrefetch.takePages(userId)'));
      // The full feed (filters, the computer) is read as before when asked for.
      expect(src('lib/features/cargo/presentation/providers/cargo_providers.dart'), contains('return ref.watch(cargoRepositoryProvider).fetchMarketplace();'));
    });
  });

  test('start-up: independent work at the same time; everything the first screen uses before runApp', () {
    final m = src('lib/main.dart');
    final run = m.indexOf('runApp(\n    ProviderScope(');
    for (final s in ['final catalog = LocaleCatalog(await texts);', 'await dates;', 'await local;', 'await supabaseReady;']) {
      expect(m.indexOf(s), greaterThan(0), reason: s);
      expect(m.indexOf(s) < run, isTrue, reason: s);
    }
    expect(m, contains('Env.definedAtBuild ? Future<void>.sync(() => dotenv.testLoad()) : _loadDotEnv()'));
    expect(m, contains('Future.delayed(const Duration(seconds: 3), catalog.loadRest);'));
  });

  // Owner, 09.11.2026 ("dərhal açılsın"): what the engine waits for before
  // the first screen starts downloading with the page, not one after another.
  test('index.html: connections to Google and the start-up fonts start at once; the flags font is not preloaded', () {
    final html = src('web/index.html');
    expect(html, contains('<link rel="preconnect" href="https://www.gstatic.com">'));
    expect(html, contains('<link rel="preconnect" href="https://www.gstatic.com" crossorigin>'));
    expect(html, contains('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'));
    final pub = src('pubspec.yaml');
    for (final f in ['Regular', 'Bold', 'Italic']) {
      expect(pub, contains('assets/fonts/FreightLinkSans-$f.ttf'));
      expect(html, contains('<link rel="preload" href="assets/assets/fonts/FreightLinkSans-$f.ttf" as="fetch" crossorigin>'));
    }
    expect(html.contains('NotoColorEmoji-Flags.woff2'), isFalse, reason: 'measured: on a slow network it held up the app');
    // The Roboto address must be the one this Flutter version's engine asks for.
    final m = RegExp(r'<link rel="preload" href="https://fonts\.gstatic\.com/s/(roboto/[^"]+)" as="fetch" crossorigin>').firstMatch(html);
    expect(m, isNotNull);
    final root = Platform.environment['FLUTTER_ROOT'];
    final engine = root == null ? null : File('$root/bin/cache/flutter_web_sdk/lib/_engine/engine/canvaskit/fonts.dart');
    if (engine != null && engine.existsSync()) {
      expect(engine.readAsStringSync(), contains(m!.group(1)), reason: 'update the Roboto preload in web/index.html to the engine\'s URL');
    }
  });

  test('the logo stays until the first frame (no empty dark page); a safety timer too', () {
    final html = src('web/index.html');
    expect(html, contains('window.flHideSplash = function () {'));
    expect(html, contains('z-index: 2147483000;'));
    expect(html, contains('<link rel="preload" href="main.dart.js" as="script">'));
    final boot = src('web/flutter_bootstrap.js');
    expect(boot.contains("getElementById('app-loading')"), isFalse, reason: 'not removed before the app draws');
    expect(boot, contains('setTimeout(function () { if (window.flHideSplash) window.flHideSplash(); }, 30000);'));
    final m = src('lib/main.dart');
    expect(m.indexOf('    hideStartupSplash();') > m.indexOf('WidgetsBinding.instance.addPostFrameCallback((_) {'), isTrue);
  });
}
