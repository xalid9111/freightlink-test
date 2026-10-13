import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/cargo/presentation/providers/cargo_providers.dart';
import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/chat/presentation/providers/group_providers.dart';
import '../config/supabase_config.dart';
import 'autofix_logic.dart';
import 'autofix_platform_stub.dart' if (dart.library.js_interop) 'autofix_platform_web.dart' as platform;

/// AutoFix — free, built-in error tracking and safe recovery.
///
/// * Catches Flutter / uncaught errors, failed providers (API, chat
///   streams), UI freezes, chat send failures and unknown routes.
/// * Runs only pre-defined, limited recoveries by itself: retry a failed
///   read (max 2× in 2 min, with backoff), re-subscribe chats (max 3× in
///   5 min), refresh an expired session (max 1× in 2 min), free image
///   memory after repeated freezes. Nothing writes or deletes user data.
/// * Sends a compact, de-duplicated report to the server
///   (autofix_report, migration 0034) for the admin panel.
/// * Applies the admin's "Problemi həll et" commands (reconnect /
///   refresh data / reload when the app is in the background).
///
/// Light: one 2-second timer, a flush every 30 s only when there is
/// something to send, one tiny query every 5 minutes.
class AutoFix {
  AutoFix._();
  static final AutoFix instance = AutoFix._();

  static const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
  static const _kLastCommand = 'autofix_last_command';

  bool _installed = false;
  ProviderContainer? _container;
  GoRouter? _router;
  String _route = '';
  final List<String> _crumbs = [];
  final Map<String, Map<String, dynamic>> _queue = {};
  final RetryLimiter _retry = RetryLimiter(max: 2, window: const Duration(minutes: 2));
  final RetryLimiter _reconnect = RetryLimiter(max: 3, window: const Duration(minutes: 5));
  final RetryLimiter _session = RetryLimiter(max: 1, window: const Duration(minutes: 2));
  final RetryLimiter _freezeRelief = RetryLimiter(max: 1, window: const Duration(minutes: 5));
  final List<DateTime> _recentFreezes = [];
  Timer? _flushTimer;
  Timer? _watchdog;
  Timer? _poller;
  AppLifecycleListener? _life;
  DateTime _lastBeat = DateTime.now();
  DateTime _shownAt = DateTime.now();
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
  bool _visible = true;
  bool _pendingReload = false;
  bool _flushing = false;
  bool _inCapture = false;

  /// Call once, after WidgetsFlutterBinding.ensureInitialized().
  void install() {
    if (_installed) return;
    _installed = true;
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      prevFlutter?.call(details); // keep the normal console output
      capture(details.exception, details.stack, source: 'flutter');
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      capture(error, stack, source: 'uncaught');
      if (prevPlatform != null) return prevPlatform(error, stack);
      if (kDebugMode) debugPrint('Uncaught: $error\n$stack');
      return true;
    };
    _life = AppLifecycleListener(onShow: _onShow, onResume: _onShow, onHide: _onHide, onPause: _onHide);
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _beat());
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    _poller = Timer.periodic(const Duration(minutes: 5), (_) => _pollCommand());
    Future<void>.delayed(const Duration(seconds: 20), _pollCommand);
  }

  /// The app's Riverpod container (for safe refreshes).
  void attachContainer(ProviderContainer c) => _container ??= c;

  /// Follow the current route (for reports and breadcrumbs).
  void attachRouter(GoRouter r) {
    if (identical(_router, r)) return;
    _router = r;
    r.routerDelegate.addListener(() {
      try {
        final loc = r.routerDelegate.currentConfiguration.uri.toString();
        if (loc != _route) {
          _route = loc;
          breadcrumb('→ $loc');
        }
      } catch (_) {}
    });
  }

  /// Last 15 steps the user took (routes, actions) — shown with a report.
  void breadcrumb(String s) {
    _crumbs.add('${DateTime.now().toIso8601String().substring(11, 19)} $s');
    if (_crumbs.length > 15) _crumbs.removeAt(0);
  }

  /// Unknown route / broken link.
  void captureNavigation(String location, Object? error) {
    capture(error ?? 'No route for $location', StackTrace.current, source: 'router', forceKind: AutoFixKind.navigation);
  }

  /// Record a problem and, when it is safe, try the pre-defined recovery.
  void capture(
    Object error,
    StackTrace? stack, {
    String? source,
    bool messaging = false,
    String? forceKind,
    ProviderBase<Object?>? provider,
  }) {
    if (_inCapture) return; // never loop on our own errors
    _inCapture = true;
    try {
      final text = error.toString();
      final classified = classifyError(error.runtimeType.toString(), text, messaging: messaging);
      final kind = forceKind ?? classified.kind;
      final stackText = stack?.toString() ?? '';
      final loc = parseAppFrame(stackText);
      // Minified release build → no readable frame: use the screen file of
      // the current route, marked with "≈" (probable).
      final probable = loc == null ? screenFileForRoute(_route) : null;
      final file = loc?.file ?? (probable == null ? null : '≈ $probable');
      final fixed = (forceKind == null && classified.transient) ? _recover(kind, provider) : false;
      breadcrumb('✖ $kind ${classified.code}${source == null ? '' : ' ($source)'}');
      final fp = fingerprintFor(kind, classified.code, classified.message, route: _route, file: loc?.file, line: loc?.line);
      final existing = _queue[fp];
      if (existing != null) {
        existing['count'] = (existing['count'] as int) + 1;
        if (fixed) existing['auto_fixed'] = (existing['auto_fixed'] as int) + 1;
      } else {
        if (_queue.length >= 30) _queue.remove(_queue.keys.first);
        _queue[fp] = {
          'fingerprint': fp,
          'kind': kind,
          'code': classified.code,
          'message': classified.message,
          'file': file,
          'line': loc?.line,
          'stack': stackText.length > 4000 ? stackText.substring(0, 4000) : stackText,
          'route': _route,
          'breadcrumbs': _crumbs.join('\n'),
          'app_version': _appVersion,
          'user_agent': platform.userAgent(),
          'count': 1,
          'auto_fixed': fixed ? 1 : 0,
        };
      }
      if (_queue.length >= 10) unawaited(flush());
    } catch (_) {
      // AutoFix must never break the app.
    } finally {
      _inCapture = false;
    }
  }

  // ---- automatic, pre-tested recovery -------------------------------------

  bool _recover(String kind, ProviderBase<Object?>? provider) {
    switch (kind) {
      case AutoFixKind.auth:
        if (!_session.tryAcquire('session')) return false;
        unawaited(_refreshSessionThenRetry(provider));
        return true;
      case AutoFixKind.messaging:
        if (!_reconnect.tryAcquire('chat')) return false;
        Future<void>.delayed(backoffFor(_reconnect.attempts('chat')), _refreshChats);
        return true;
      case AutoFixKind.network:
      case AutoFixKind.api:
        return _retryProvider(provider);
      default:
        return false;
    }
  }

  bool _retryProvider(ProviderBase<Object?>? provider) {
    final c = _container;
    if (provider == null || c == null) return false;
    final key = 'p${provider.hashCode}';
    if (!_retry.tryAcquire(key)) return false;
    Future<void>.delayed(backoffFor(_retry.attempts(key)), () {
      try {
        c.invalidate(provider);
      } catch (_) {}
    });
    return true;
  }

  Future<void> _refreshSessionThenRetry(ProviderBase<Object?>? provider) async {
    try {
      if (SupabaseConfig.client.auth.currentSession != null) {
        await SupabaseConfig.client.auth.refreshSession();
      }
    } catch (_) {}
    _retryProvider(provider);
  }

  bool isChatProvider(ProviderBase<Object?> p) =>
      p == myConversationsProvider ||
      p == receivedMessagesProvider ||
      p == myGroupMessagesProvider ||
      p == myMembershipsProvider ||
      p.from == conversationMessagesProvider ||
      p.from == conversationByIdProvider;

  /// Same refresh the app does after coming back from the background.
  void _refreshChats() {
    final c = _container;
    if (c == null) return;
    try {
      c.invalidate(myConversationsProvider);
      c.invalidate(conversationMessagesProvider);
      c.invalidate(conversationByIdProvider);
      c.invalidate(receivedMessagesProvider);
      c.invalidate(myGroupMessagesProvider);
    } catch (_) {}
  }

  Future<void> _refreshData() async {
    try {
      if (SupabaseConfig.client.auth.currentSession != null) {
        await SupabaseConfig.client.auth.refreshSession();
      }
    } catch (_) {}
    _refreshChats();
    try {
      _container?.invalidate(marketplaceProvider);
    } catch (_) {}
  }

  // ---- freeze watchdog --------------------------------------------------------

  void _beat() {
    final now = DateTime.now();
    final gap = now.difference(_lastBeat);
    _lastBeat = now;
    if (!_visible || platform.pageHidden()) return;
    // Right after coming back, or after a sleep (huge gap): not a freeze.
    if (now.difference(_shownAt) < const Duration(seconds: 4) || gap > const Duration(seconds: 60)) return;
    if (!isFreeze(const Duration(seconds: 2), gap)) return;
    _recentFreezes.add(now);
    _recentFreezes.removeWhere((t) => now.difference(t) > const Duration(minutes: 5));
    var relieved = false;
    // Repeated freezes on a weak phone: free decoded images once (they are
    // re-loaded when needed). Safe — no data is touched.
    if (_recentFreezes.length >= 2 && _freezeRelief.tryAcquire('img')) {
      try {
        PaintingBinding.instance.imageCache.clear();
        relieved = true;
      } catch (_) {}
    }
    capture('UI blocked for ~${gap.inMilliseconds} ms${relieved ? ' (image cache freed)' : ''}', null,
        source: 'watchdog', forceKind: AutoFixKind.freeze);
  }

  // ---- lifecycle ----------------------------------------------------------

  void _onShow() {
    _visible = true;
    _shownAt = DateTime.now();
    _lastBeat = _shownAt;
    if (DateTime.now().difference(_lastPoll) > const Duration(minutes: 1)) unawaited(_pollCommand());
  }

  void _onHide() {
    _visible = false;
    unawaited(flush());
    // Admin asked for a reload: do it while nobody is looking at the app.
    if (_pendingReload) {
      _pendingReload = false;
      platform.reloadPage();
    }
  }

  // ---- admin commands -------------------------------------------------------

  Future<void> _pollCommand() async {
    _lastPoll = DateTime.now();
    if (SupabaseConfig.client.auth.currentSession == null) return;
    try {
      final rows = await SupabaseConfig.client.rpc('autofix_latest_command').timeout(const Duration(seconds: 15));
      if (rows is! List || rows.isEmpty) return;
      final row = Map<String, dynamic>.from(rows.first as Map);
      final id = (row['id'] as num?)?.toInt();
      final action = '${row['action']}';
      if (id == null) return;
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLastCommand);
      await prefs.setInt(_kLastCommand, id);
      // First run on this device: remember, do not replay old commands.
      if (last == null || id <= last) return;
      breadcrumb('⚙ admin: $action');
      switch (action) {
        case 'reconnect':
          _refreshChats();
        case 'refresh_data':
          await _refreshData();
        case 'reload_when_idle':
          if (platform.pageHidden()) {
            platform.reloadPage();
          } else {
            _pendingReload = true;
          }
      }
    } catch (_) {
      // Before migration 0034 / offline: try again later.
    }
  }

  // ---- sending reports --------------------------------------------------------

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    if (SupabaseConfig.client.auth.currentSession == null) return; // kept until sign-in
    _flushing = true;
    try {
      final keys = _queue.keys.take(20).toList();
      final batch = [for (final k in keys) _queue[k]!];
      await SupabaseConfig.client.rpc('autofix_report', params: {'p_events': batch}).timeout(const Duration(seconds: 20));
      for (final k in keys) {
        _queue.remove(k);
      }
    } catch (_) {
      // Keep them (max 30) and try again on the next flush.
    } finally {
      _flushing = false;
    }
  }

  @visibleForTesting
  void dispose() {
    _flushTimer?.cancel();
    _watchdog?.cancel();
    _poller?.cancel();
    _life?.dispose();
  }
}

/// Reports every failed provider (API calls, chat streams …) to AutoFix.
class AutoFixObserver extends ProviderObserver {
  @override
  void providerDidFail(ProviderBase<Object?> provider, Object error, StackTrace stackTrace, ProviderContainer container) {
    final a = AutoFix.instance;
    a.attachContainer(container);
    a.capture(error, stackTrace, source: 'provider', provider: provider, messaging: a.isChatProvider(provider));
  }
}
