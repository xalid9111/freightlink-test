import 'package:flutter/services.dart';

/// Native (iOS / Android app): system haptics. Fire-and-forget; errors
/// are swallowed — the wheel never depends on it.
void platformHaptic(bool isAd) {
  try {
    if (isAd) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  } catch (_) {}
}
