import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_strings.dart';
import 'localization_service.dart';

const _prefsKey = 'fl_locale';
// Set once the device's choice and the account agree (owner, 04.11.2026).
const _syncedKey = 'fl_locale_account_synced';

/// Languages the account (users.preferred_lang) can hold; Chinese is kept
/// on the device only (the column's check allows az, tr, en, ru, ka).
const kAccountLangs = {'az', 'tr', 'en', 'ru', 'ka'};

/// The signed-in account's language (users.preferred_lang). Injected so
/// tests run without Supabase.
abstract class AccountLanguage {
  /// Null when nobody is signed in (or the server cannot be reached).
  Future<String?> read();
  /// True when it was written to a signed-in account.
  Future<bool> write(String code);
  /// Fires when someone signs in.
  Stream<void> get signedIn;
}

class SupabaseAccountLanguage implements AccountLanguage {
  SupabaseClient? get _c {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase not initialised (tests)
    }
  }

  @override
  Future<String?> read() async {
    final c = _c;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) return null;
    final row = await c.from('users').select('preferred_lang').eq('id', uid).maybeSingle().timeout(const Duration(seconds: 10));
    return row?['preferred_lang'] as String?;
  }

  @override
  Future<bool> write(String code) async {
    final c = _c;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null || !kAccountLangs.contains(code)) return false;
    await c.from('users').update({'preferred_lang': code}).eq('id', uid).timeout(const Duration(seconds: 10));
    return true;
  }

  @override
  Stream<void> get signedIn {
    final c = _c;
    if (c == null) return const Stream<void>.empty();
    return c.auth.onAuthStateChange.where((s) => s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession).map((_) {});
  }
}

/// Populated once in main.dart (via ProviderScope overrides) after
/// LocalizationService.loadAll() completes, before runApp(). Every
/// other localization provider reads from this — nothing re-fetches
/// the JSON files.
final localeCatalogProvider = Provider<Map<Locale, AppStrings>>((ref) {
  throw StateError(
    'localeCatalogProvider was not overridden — main.dart must call '
    'LocalizationService.loadAll() and override this provider before runApp().',
  );
});

/// The app's language.
///
/// Owner (04.11.2026): the chosen language must hold everywhere. Safari,
/// a messenger's in-app browser and the Home Screen app each keep their own
/// storage, so a choice saved only on the device was missing in the others
/// and the phone's language (e.g. Turkish) showed instead. Now the choice
/// is also kept on the account (users.preferred_lang): a signed-in user
/// gets the account's language in every browser; a new choice is written
/// to both. Chinese stays on the device (the account column has no 'zh').
class LocaleController extends StateNotifier<Locale> {
  LocaleController({AccountLanguage? account})
      : _account = account ?? SupabaseAccountLanguage(),
        super(LocalizationService.fallbackLocale) {
    _restored = _restore();
    try {
      _sub = _account.signedIn.listen((_) => unawaited(syncWithAccount()));
    } catch (_) {}
  }

  final AccountLanguage _account;
  StreamSubscription<void>? _sub;
  late final Future<void> _restored;
  String? _local; // the choice saved on this device, if any

  static Locale? _supported(String? code) {
    if (code == null) return null;
    final m = LocalizationService.supportedLocales.where((l) => l.languageCode == code);
    return m.isEmpty ? null : m.first;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = _supported(prefs.getString(_prefsKey));
      if (saved != null) {
        _local = saved.languageCode;
        if (mounted) state = saved;
        return;
      }
    } catch (_) {
      // SharedPreferences unavailable: never block the app from launching.
    }

    // Nothing saved on this device: the browser's language as a start
    // (before sign-in); a signed-in account's language replaces it.
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    if (mounted) state = _supported(deviceLocale.languageCode) ?? LocalizationService.fallbackLocale;
  }

  /// After sign-in (and at start with a session): the account's language
  /// is the one used everywhere. The first time a device that already had
  /// its own choice meets the account, that choice is written to the
  /// account (the app never wrote it before). Chinese stays local.
  Future<void> syncWithAccount() async {
    await _restored;
    String? acc;
    try {
      acc = await _account.read();
    } catch (_) {
      return; // offline: keep what is shown
    }
    if (acc == null || !mounted) return;
    if (_local == 'zh') return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final synced = prefs?.getBool(_syncedKey) ?? false;
    if (_local != null && !synced && _local != acc && kAccountLangs.contains(_local)) {
      try {
        if (await _account.write(_local!)) await prefs?.setBool(_syncedKey, true);
      } catch (_) {}
      return;
    }
    final l = _supported(acc);
    if (l == null) return;
    if (mounted) state = l;
    _local = l.languageCode;
    try {
      await prefs?.setString(_prefsKey, l.languageCode);
      await prefs?.setBool(_syncedKey, true);
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    _local = locale.languageCode;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, locale.languageCode);
    } catch (_) {
      // Selection still applies for this session even if it can't be
      // persisted — never block the user's action on storage working.
    }
    // The same language in every browser and on every device. Not written
    // (signed out, offline, Chinese): this device's choice goes to the
    // account at the next sign-in instead of being replaced by it.
    var written = false;
    try {
      written = await _account.write(locale.languageCode);
    } catch (_) {}
    try {
      await prefs?.setBool(_syncedKey, written);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final currentLocaleProvider = StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController();
});

/// What every screen actually watches: `ref.watch(stringsProvider).t('key')`.
final stringsProvider = Provider<AppStrings>((ref) {
  final catalog = ref.watch(localeCatalogProvider);
  final locale = ref.watch(currentLocaleProvider);
  return catalog[locale] ?? catalog[LocalizationService.fallbackLocale]!;
});
