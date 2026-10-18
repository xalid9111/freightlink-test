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
import 'core/theme/theme_mode.dart';
import 'core/constants/app_constants.dart';
import 'core/localization/locale_controller.dart';
import 'core/localization/localization_service.dart';

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

  // 1. Load environment variables. The web/PWA release gets its config
  // from --dart-define instead (static hosts may refuse to serve the
  // .env dotfile asset) — so a missing .env must never kill app boot.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No bundled .env — config comes from compile-time dart-defines.
  }

  // 2. Initialize Supabase (auth, database, storage, realtime)
  await SupabaseConfig.initialize();

  // 3. Eager-load all 4 language files ONCE, before the UI exists, so
  // no screen ever has to show a loading state just to read a string.
  final localeCatalog = await LocalizationService.loadAll();

  // 4. Load date-formatting data for all locales (az/tr/ru/en month and
  // weekday names etc.) — without this, `DateFormat` silently falls
  // back to English for any locale it wasn't told about, which would
  // have left pickup/delivery dates in English even when the rest of
  // the UI was switched to Azerbaijani/Turkish/Russian. No argument
  // loads every locale bundled with the intl package.
  await initializeDateFormatting();

  // 5. Day / night mode chosen in Settings (night unless changed).
  await loadSavedTheme();

  // Firebase.initializeApp() and Mapbox.setAccessToken() are added
  // in Phase 10 / Phase 12 once those features are implemented —
  // this project only proves the boot sequence and DI wiring are
  // correct up to the phase that's actually been built.

  runApp(
    ProviderScope(
      observers: [AutoFixObserver()],
      overrides: [localeCatalogProvider.overrideWithValue(localeCatalog)],
      child: const FreightLinkApp(),
    ),
  );
  // Flags font: in the background, after the first screen.
  WidgetsBinding.instance.addPostFrameCallback((_) => loadFlagFont());
}

class FreightLinkApp extends ConsumerWidget {
  const FreightLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(currentLocaleProvider);
    AutoFix.instance.attachRouter(router);
    AutoFix.instance.attachContainer(ProviderScope.containerOf(context, listen: false));
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Night = the approved dark design; day = chosen in Settings.
      theme: AppTheme.current,
      darkTheme: AppTheme.current,
      themeMode: AppColors.isDay ? ThemeMode.light : ThemeMode.dark,
      routerConfig: router,
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
