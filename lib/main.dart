import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/autofix/autofix.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/flag_font.dart';
import 'core/theme/night_preview_badge.dart';
import 'core/theme/theme_mode.dart';
import 'core/theme/ui_scale.dart';
import 'core/layout/desktop_preview.dart';
import 'core/constants/app_constants.dart';
import 'core/localization/locale_controller.dart';
import 'core/localization/localization_service.dart';
import 'core/site/site_access.dart';
import 'features/cargo/presentation/providers/category_providers.dart';
import 'core/config/env.dart';
import 'core/startup/splash.dart';
import 'features/cargo/data/cargo_feed_prefetch.dart';
import 'features/cargo/data/cargo_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // AutoFix: error tracking + safe recovery (lib/core/autofix).
  AutoFix.instance.install();
  // iPhone Safari / Home Screen apps have a small memory budget: keep the
  // decoded-image cache smaller than Flutter's default (100 MB).
  if (kIsWeb) {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 48 << 20
      ..maximumSize = 300;
  }

  // Faster start (owner, 08.11.2026): the independent steps below run at
  // the same time instead of one after another; runApp() still waits for
  // everything the first screen uses (colours, texts, date names, saved
  // choices), so the first screen looks exactly as before.

  // 1. Environment. The web release / CI build has it from --dart-define;
  // only other builds read the bundled .env (a missing .env must never
  // kill app boot).
  final env = Env.definedAtBuild ? Future<void>.sync(() => dotenv.testLoad()) : _loadDotEnv();

  // 2. Supabase (auth, database, storage, realtime) — after the env.
  final supabaseReady = env.then((_) => SupabaseConfig.initialize());

  // 3. Texts: the saved / device language, Azerbaijani and English before
  // the first screen; the other languages after it (LocaleCatalog).
  final prefs = _prefs();
  final texts = prefs.then((p) => LocalizationService.loadStartup(_startLocale(p)));

  // 4. Date names for every locale (az/tr/ru/en … months and weekdays) —
  // without this `DateFormat` silently falls back to English.
  final dates = initializeDateFormatting();

  // 5. Day / night colours (the server's night palette is waited for only
  // on a device's very first start), display size, desktop preview and the
  // load type last chosen on the Loads page.
  final local = Future.wait([
    loadSavedTheme(serverReady: supabaseReady),
    loadSavedUiScale(),
    loadSavedDesktopPreview(),
    loadCargoCategoryPrefs(),
  ]);

  // 6. Yüklər: the open-loads request leaves now (it waits for the network
  // while the rest starts); the page takes this answer (CargoFeedPrefetch).
  await supabaseReady;
  if (CargoFeedPrefetch.opensOnLoads(Uri.base)) {
    CargoFeedPrefetch.start(CargoRepositoryImpl(), SupabaseConfig.client.auth.currentUser?.id);
  }

  final catalog = LocaleCatalog(await texts);
  await dates;
  await local;

  runApp(
    ProviderScope(
      observers: [AutoFixObserver()],
      overrides: [localeCatalogProvider.overrideWith((ref) => catalog)],
      child: const FreightLinkApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // The logo of index.html goes away only now: the first screen is drawn.
    hideStartupSplash();
    // Flags font: in the background, after the first screen.
    loadFlagFont();
    // The other languages, a little later (the first screen's own requests
    // go first on a slow network).
    Future.delayed(const Duration(seconds: 3), catalog.loadRest);
  });
}

Future<void> _loadDotEnv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No bundled .env — config comes from compile-time dart-defines.
  }
}

Future<SharedPreferences?> _prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}

/// The language the first screen will show: the one saved on this device,
/// else the browser's (as LocaleController decides).
Locale? _startLocale(SharedPreferences? prefs) {
  final saved = prefs == null ? null : LocalizationService.supported(savedLocaleCode(prefs));
  return saved ?? LocalizationService.supported(WidgetsBinding.instance.platformDispatcher.locale.languageCode);
}

class FreightLinkApp extends ConsumerWidget {
  const FreightLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(currentLocaleProvider);
    final uiScale = ref.watch(uiScaleProvider);
    final desktopPreview = ref.watch(desktopPreviewProvider);
    AutoFix.instance.attachRouter(router);
    AutoFix.instance.attachContainer(ProviderScope.containerOf(context, listen: false));
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Night = the approved dark design; day = chosen in Settings.
      theme: themeForUiScale(AppTheme.current, uiScale),
      darkTheme: themeForUiScale(AppTheme.current, uiScale),
      themeMode: AppColors.isDay ? ThemeMode.light : ThemeMode.dark,
      routerConfig: router,
      // Site closed (0068): only admins see the app, others the notice.
      // An admin's try-out of night colours shows a "Bitir" pill (0076).
      builder: (context, child) => NightPreviewBadge(
          child: SiteGate(child: applyDesktopPreview(context, desktopPreview, applyUiScale(context, uiScale, child)))),
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocalizationService.supportedLocales,
    );
  }
}
