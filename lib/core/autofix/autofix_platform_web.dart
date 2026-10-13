import 'dart:js_interop';

@JS('flAutoFix.ua')
external JSString _ua();

@JS('flAutoFix.reload')
external void _reload();

@JS('flAutoFix.hidden')
external JSBoolean _hidden();

@JS('flAutoFix.standalone')
external JSBoolean _standalone();

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

/// Opened from the home screen (PWA) rather than in a browser tab.
bool standalone() {
  try {
    return _standalone().toDart;
  } catch (_) {
    return false;
  }
}
