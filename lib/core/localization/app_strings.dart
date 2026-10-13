/// Thin wrapper around one language's translation map. `t()` never
/// throws on a missing key — it falls back to the key itself, which
/// makes a missing translation visible in the UI (e.g. "profile_title"
/// shown literally) instead of crashing the screen. That fallback is
/// intentional: a visibly-wrong string is a bug report waiting to
/// happen; a crash is an outage.
class AppStrings {
  final Map<String, String> _values;
  const AppStrings(this._values);

  String t(String key, [Map<String, String>? params]) {
    var value = _values[key] ?? key;
    if (params != null) {
      params.forEach((k, v) => value = value.replaceAll('{$k}', v));
    }
    return value;
  }

  /// Looks up a translation for an AppException by its `code` (e.g.
  /// "error_duplicate_pending_offer"). Falls back to a generic
  /// localized error rather than ever showing a raw backend message in
  /// the wrong language. See core/errors/app_exception.dart — every
  /// throw site in the data layer now sets `code` specifically so this
  /// lookup has something stable to key off, instead of matching on
  /// message text.
  String error(String? code) {
    if (code != null && _values.containsKey('error_$code')) {
      return t('error_$code');
    }
    return t('error_generic');
  }
}
