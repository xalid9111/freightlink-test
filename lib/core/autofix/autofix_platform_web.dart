import 'dart:js_interop';

@JS('flAutoFix.ua')
external JSString _ua();

@JS('flAutoFix.reload')
external void _reload();

@JS('flAutoFix.hidden')
external JSBoolean _hidden();

@JS('flFreshReload')
external JSBoolean _freshReload();

String userAgent() {
  try {
    return _ua().toDart;
  } catch (_) {
    return '';
  }
}

void reloadPage() {
  try {
    _reload();
  } catch (_) {}
}

bool pageHidden() {
  try {
    return _hidden().toDart;
  } catch (_) {
    return false;
  }
}

/// Fresh app files + one reload (web/pwa_guard.js); false when it was
/// already done in the last minutes (then the page shows the retry button).
bool freshReload() {
  try {
    return _freshReload().toDart;
  } catch (_) {
    return false;
  }
}
