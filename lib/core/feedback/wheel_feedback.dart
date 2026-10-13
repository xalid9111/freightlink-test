import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wheel_feedback_stub.dart' if (dart.library.js_interop) 'wheel_feedback_web.dart' as platform;

/// User choice for the cargo-feed wheel (Profile): haptic on / off.
/// (No sound — removed on request.)
class WheelSettings {
  final bool haptic;
  const WheelSettings({this.haptic = true});
}

class WheelSettingsController extends StateNotifier<WheelSettings> {
  static const _kHaptic = 'wheel_haptic';

  WheelSettingsController() : super(const WheelSettings()) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = WheelSettings(haptic: p.getBool(_kHaptic) ?? true);
    } catch (_) {}
  }

  Future<void> setHaptic(bool on) async {
    state = WheelSettings(haptic: on);
    try {
      (await SharedPreferences.getInstance()).setBool(_kHaptic, on);
    } catch (_) {}
  }
}

final wheelSettingsProvider =
    StateNotifierProvider<WheelSettingsController, WheelSettings>((ref) => WheelSettingsController());

/// One "detent" of the wheel: a light haptic if enabled. Never throws.
void wheelDetent(WheelSettings s, {required bool isAd}) {
  if (s.haptic) platform.platformHaptic(isAd);
}
