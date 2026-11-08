import 'dart:js_interop';

@JS('flHideSplash')
external JSFunction? get _flHideSplash;

void hideStartupSplash() {
  try {
    _flHideSplash?.callAsFunction();
  } catch (_) {}
}
