import 'dart:js_interop';

/// Web / PWA: flWheelHaptic in web/index.html (navigator.vibrate where
/// available, best-effort switch-haptic on iPhone). Fails silently.
@JS('flWheelHaptic')
external void _haptic(int kind);

void platformHaptic(bool isAd) {
  try {
    _haptic(isAd ? 1 : 0);
  } catch (_) {}
}
