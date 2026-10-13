import 'dart:js_interop';

@JS('flAutoFix.ua')
external JSString _ua();

@JS('flAutoFix.reload')
external void _reload();

@JS('flAutoFix.hidden')
external JSBoolean _hidden();

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
