// AutoFix — pure logic (no Flutter, no Supabase), so it is unit-tested
// in test/autofix_logic_test.dart by `flutter test` in GitHub Actions.

/// Problem kinds — must match the check in migration 0034.
class AutoFixKind {
  static const runtime = 'runtime';
  static const api = 'api';
  static const network = 'network';
  static const freeze = 'freeze';
  static const messaging = 'messaging';
  static const navigation = 'navigation';
  static const auth = 'auth';
}

/// The pre-tested recovery for a kind, or null = no safe automatic fix
/// (manual fix needed). Same table as public.autofix_action_for() in SQL.
String? autofixActionFor(String kind) => switch (kind) {
      AutoFixKind.messaging => 'reconnect',
      AutoFixKind.network => 'refresh_data',
      AutoFixKind.api => 'refresh_data',
      AutoFixKind.auth => 'refresh_data',
      AutoFixKind.freeze => 'reload_when_idle',
      _ => null,
    };

/// What a problem looks like after classification.
class ErrorInfo {
  final String kind;
  final String code;
  final String message;

  /// True when retrying / reconnecting can help (network, timeouts, 5xx,
  /// expired session, dropped realtime socket). False for code bugs.
  final bool transient;
  const ErrorInfo({required this.kind, required this.code, required this.message, required this.transient});
}

String _short(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Classifies an error from its type name and text. [typeName] is the
/// runtime type as a string (may be minified in release builds, so the
/// text is checked too). [messaging] = it came from a chat stream.
ErrorInfo classifyError(String typeName, String text, {bool messaging = false}) {
  final t = text.toLowerCase();
  final type = typeName;
  String code = type.isEmpty ? 'Error' : _short(type, 60);

  // Postgrest / database error code inside the text, e.g.
  // "PostgrestException(message: …, code: 42501, …)" or "AppException(PGRST301): …".
  final pg = RegExp(r'(?:code:\s*"?|AppException\()(PGRST\d{3}|[0-9A-Z]{5})\b').firstMatch(text);
  final pgCode = pg?.group(1);

  final isAuth = t.contains('jwt expired') ||
      t.contains('invalid jwt') ||
      t.contains('refresh token') ||
      t.contains('session expired') ||
      t.contains('not_authenticated') ||
      pgCode == 'PGRST301' ||
      t.contains('statuscode: 401') ||
      t.contains('status: 401');
  if (isAuth) {
    return ErrorInfo(kind: AutoFixKind.auth, code: pgCode ?? 'auth', message: _short(text, 1000), transient: true);
  }

  final isNetwork = t.contains('failed to fetch') ||
      t.contains('xmlhttprequest error') ||
      t.contains('clientexception') ||
      t.contains('socketexception') ||
      t.contains('connection closed') ||
      t.contains('connection refused') ||
      t.contains('network') ||
      t.contains('timeoutexception') ||
      t.contains('timed out') ||
      type.contains('TimeoutException') ||
      type.contains('ClientException') ||
      RegExp(r'\b(502|503|504)\b').hasMatch(t);
  final isRealtime = t.contains('realtime') || t.contains('websocket') || t.contains('channel') || t.contains('subscribe');

  if (messaging || isRealtime) {
    return ErrorInfo(
      kind: AutoFixKind.messaging,
      code: isRealtime ? 'realtime' : (pgCode ?? code),
      message: _short(text, 1000),
      // A dropped socket / network problem → reconnecting helps.
      transient: isNetwork || isRealtime,
    );
  }
  if (isNetwork) {
    return ErrorInfo(kind: AutoFixKind.network, code: pgCode ?? 'network', message: _short(text, 1000), transient: true);
  }
  final isApi = type.contains('Postgrest') || type.contains('AppException') || t.contains('postgrest') || pgCode != null;
  if (isApi) {
    // 5xx / connection-pool problems are transient; 4xx / constraint errors are not.
    final transient = RegExp(r'\b(500|PGRST000|PGRST001|PGRST002|57014|53300|08006)\b').hasMatch(text);
    return ErrorInfo(kind: AutoFixKind.api, code: pgCode ?? 'api', message: _short(text, 1000), transient: transient);
  }
  if (t.contains('goexception') || t.contains('no routes for location') || t.contains('go_router')) {
    return ErrorInfo(kind: AutoFixKind.navigation, code: 'route', message: _short(text, 1000), transient: false);
  }
  return ErrorInfo(kind: AutoFixKind.runtime, code: code, message: _short(text, 1000), transient: false);
}

/// A code location parsed from a stack trace.
class CodeLocation {
  final String file;
  final int? line;
  const CodeLocation(this.file, this.line);
}

/// First frame that belongs to this app (`package:freightlink/…` or
/// `lib/…`). Release web builds have minified stacks → usually null.
CodeLocation? parseAppFrame(String stack) {
  final re = RegExp(r'(?:package:freightlink/|\blib/)([A-Za-z0-9_/]+\.dart)[ :]+(\d+)');
  final m = re.firstMatch(stack);
  if (m == null) return null;
  return CodeLocation('lib/${m.group(1)}', int.tryParse(m.group(2) ?? ''));
}

/// Probable screen file for a route — shown when the stack has no
/// readable file (minified release build).
String? screenFileForRoute(String route) {
  final r = route.split('?').first;
  const map = <String, String>{
    '/cargo/create': 'lib/features/cargo/presentation/cargo_create_screen.dart',
    '/cargo/': 'lib/features/cargo/presentation/cargo_detail_screen.dart',
    '/cargo': 'lib/features/cargo/presentation/cargo_marketplace_screen.dart',
    '/load/': 'lib/features/cargo/presentation/cargo_detail_screen.dart',
    '/my-cargo': 'lib/features/cargo/presentation/my_cargo_screen.dart',
    '/messages/group/': 'lib/features/chat/presentation/group_thread_screen.dart',
    '/messages/with/': 'lib/features/chat/presentation/conversation_thread_screen.dart',
    '/messages/': 'lib/features/chat/presentation/conversation_thread_screen.dart',
    '/messages': 'lib/features/chat/presentation/conversations_screen.dart',
    '/chat/': 'lib/features/chat/presentation/conversation_thread_screen.dart',
    '/chat-group/': 'lib/features/chat/presentation/group_thread_screen.dart',
    '/search': 'lib/features/cargo/presentation/search_screen.dart',
    '/shipments': 'lib/features/shipment/presentation/shipments_screen.dart',
    '/services': 'lib/features/services/presentation/services_map_screen.dart',
    '/service/': 'lib/features/services/presentation/service_detail_screen.dart',
    '/profile': 'lib/features/auth/presentation/profile_screen.dart',
    '/settings': 'lib/features/auth/presentation/settings_screen.dart',
    '/user/': 'lib/features/ads/presentation/public_profile_screen.dart',
    '/ads': 'lib/features/ads/presentation/advertise_screen.dart',
    '/ad-create': 'lib/features/ads/presentation/ad_create_screen.dart',
    '/ad-order/': 'lib/features/ads/presentation/ad_order_screen.dart',
    '/admin': 'lib/features/admin/presentation/admin_shell.dart',
    '/login': 'lib/features/auth/presentation/login_screen.dart',
  };
  String? best;
  var bestLen = -1;
  map.forEach((prefix, file) {
    final match = prefix.endsWith('/') ? r.startsWith(prefix) : (r == prefix || r.startsWith('$prefix/'));
    if (match && prefix.length > bestLen) {
      best = file;
      bestLen = prefix.length;
    }
  });
  return best;
}

/// Stable id of a problem: same kind + code + route area + first stack
/// line (or message without numbers/ids) → same fingerprint. Only the
/// characters the server accepts ([0-9a-z_:.-], max 120).
String fingerprintFor(String kind, String code, String message, {String? route, String? file, int? line}) {
  String clean(String s) => s
      // Flutter object hashes ("RenderFoo#78ac7") differ per instance of
      // the same problem; without this one bug becomes many groups.
      .replaceAll(RegExp(r'#[0-9a-fA-F]{5}\b'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[0-9a-f]{8}-[0-9a-f-]{27,}'), '') // uuids
      .replaceAll(RegExp(r'\d+'), '') // numbers / ids / times
      .replaceAll(RegExp(r'[^a-z_:.-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final area = route == null ? '' : clean(route.split('/').where((p) => p.isNotEmpty).take(1).join());
  final where = file != null ? '${clean(file.split('/').last)}${line ?? ''}' : clean(_short(message, 60));
  final fp = '${clean(kind)}:${clean(code)}:$area:$where';
  final out = fp.length > 120 ? fp.substring(0, 120) : fp;
  return out.length < 4 ? '$out----' : out;
}

/// Allows at most [max] attempts per key inside [window] (e.g. "retry a
/// failed load twice in 2 minutes"), so a recovery can never loop.
class RetryLimiter {
  final int max;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _hits = {};
  RetryLimiter({required this.max, required this.window, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// True (and counts it) when one more attempt is allowed for [key].
  bool tryAcquire(String key) {
    final now = _now();
    final list = _hits.putIfAbsent(key, () => <DateTime>[]);
    list.removeWhere((t) => now.difference(t) > window);
    if (list.length >= max) return false;
    list.add(now);
    if (_hits.length > 200) _hits.remove(_hits.keys.first);
    return true;
  }

  /// How many attempts were made for [key] in the current window.
  int attempts(String key) {
    final now = _now();
    return (_hits[key] ?? const <DateTime>[]).where((t) => now.difference(t) <= window).length;
  }
}

/// Backoff for attempt n (1, 2, …): 3 s, 10 s, 30 s (capped).
Duration backoffFor(int attempt) => switch (attempt) {
      <= 1 => const Duration(seconds: 3),
      2 => const Duration(seconds: 10),
      _ => const Duration(seconds: 30),
    };

/// Freeze watchdog: a periodic tick that arrives much later than planned
/// while the app is visible means the UI thread was blocked.
bool isFreeze(Duration expected, Duration actual, {Duration threshold = const Duration(seconds: 4)}) =>
    actual - expected >= threshold;

// ---- diagnostics (kept small and free of personal data) -------------------

/// Removes personal data from text that goes into a report: e-mail
/// addresses, phone-like numbers, access tokens and URL query strings.
/// Stack positions such as `main.dart.js:1234:56` are kept.
String scrubPii(String s) => s
    .replaceAll(RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '<email>')
    .replaceAll(RegExp(r'\beyJ[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]+){0,2}'), '<token>')
    .replaceAll(RegExp(r'\b(?:sb_(?:publishable|secret)_)[A-Za-z0-9_-]+'), '<token>')
    // Phones: "+994 50 123 45 67", "050 123 45 67", or 9+ digits in a row.
    // Dates, times, error codes and stack positions stay readable.
    .replaceAll(RegExp(r'\+\d[\d \-]{6,16}\d(?!\w)'), '<num>')
    .replaceAll(RegExp(r'\b0\d{2}[ -]?\d{3}[ -]?\d{2}[ -]?\d{2}\b'), '<num>')
    .replaceAll(RegExp(r'(?<![\w:.#/])\d{9,15}(?![\w:])'), '<num>')
    .replaceAll(RegExp(r'\?[^\s#]*'), '');

/// Route for a report: no query string, ids replaced by `:id`
/// (`/user/1b2c…` → `/user/:id`).
String maskRoute(String route) => route
    .split('?')
    .first
    .replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}'), ':id')
    .replaceAll(RegExp(r'(?<=/)\d+(?=/|$)'), ':id');

/// The last [max] steps before a problem (screens, taps, dialogs, errors).
/// The same step repeated right away is kept once with a counter, so a
/// burst of identical errors does not push the user's steps out.
class Breadcrumbs {
  final int max;
  final List<String> _times = [];
  final List<String> _steps = [];
  final List<int> _repeats = [];
  Breadcrumbs({this.max = 10});

  void add(String time, String step) {
    final s = scrubPii(step);
    if (_steps.isNotEmpty && _steps.last == s) {
      _repeats[_repeats.length - 1]++;
      return;
    }
    _times.add(time);
    _steps.add(s);
    _repeats.add(1);
    if (_steps.length > max) {
      _times.removeAt(0);
      _steps.removeAt(0);
      _repeats.removeAt(0);
    }
  }

  @override
  String toString() => [
        for (var i = 0; i < _steps.length; i++)
          '${_times[i]} ${_steps[i]}${_repeats[i] > 1 ? ' ×${_repeats[i]}' : ''}',
      ].join('\n');
}

/// Where on the screen a tap was, without anything that is on the screen:
/// a 3×3 zone plus the position in percent (e.g. `tap ↘ 88%,94%`).
String tapLabel(double x, double y, double width, double height, {bool swipe = false}) {
  if (width <= 0 || height <= 0) return swipe ? 'swipe' : 'tap';
  final px = (x / width * 100).clamp(0, 100).round();
  final py = (y / height * 100).clamp(0, 100).round();
  const zones = [
    ['↖', '↑', '↗'],
    ['←', '•', '→'],
    ['↙', '↓', '↘'],
  ];
  final zone = zones[(py * 3 ~/ 101)][(px * 3 ~/ 101)];
  return '${swipe ? 'swipe' : 'tap'} $zone $px%,$py%';
}

/// Device line for a report: screen in logical pixels, pixel ratio, PWA
/// or browser tab, language, then the browser's user agent (max 300).
String deviceSummary({
  required double width,
  required double height,
  required double pixelRatio,
  required bool standalone,
  required String language,
  required String userAgent,
}) {
  final head = '${width.round()}×${height.round()} @${pixelRatio.toStringAsFixed(1)} · '
      '${standalone ? 'pwa' : 'browser'} · $language | ';
  final out = '$head$userAgent';
  return out.length > 300 ? out.substring(0, 300) : out;
}

/// Stack for a report: what Flutter was doing (e.g. "during
/// performLayout()") first, then the trace, max 4000 characters.
String stackForReport(String stack, {String? context}) {
  final head = (context == null || context.isEmpty) ? '' : 'context: $context\n';
  final out = scrubPii('$head$stack');
  return out.length > 4000 ? out.substring(0, 4000) : out;
}
