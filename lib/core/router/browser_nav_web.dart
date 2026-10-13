import 'dart:js_interop';

@JS('flNav.recentBrowserNav')
external JSBoolean _recent();

bool recentBrowserNavigation() {
  try {
    return _recent().toDart;
  } catch (_) {
    return false;
  }
}
