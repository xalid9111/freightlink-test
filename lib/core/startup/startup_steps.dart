import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Faster site, stage 2 (owner, 16.11.2026: "yüklənmə ardıcıllığı"): what
/// the first screen does not need starts after it, one group at a time,
/// instead of everything together with the first screen. Nothing is turned
/// off; only WHEN it starts changes.
///
///  * step 1 (first frame + 1.5 s): messages received (badge, sound);
///  * step 2 (+ 3 s): the live map's movement, who is online, group chats;
///  * step 3 (+ 5 s): new-load watcher, TIRPark / TIR Bazarı new counts.
///
/// Only when the app opens on Yüklər (the heavy first page); opened on any
/// other page (a chat from a notification, Mesajlar, Profil …) every step
/// is free at once. Without [start] (tests, other tools) nothing waits.
class StartupSteps {
  StartupSteps._();

  static const delays = [Duration(milliseconds: 1500), Duration(seconds: 3), Duration(seconds: 5)];

  static bool _gated = false;
  static final List<Completer<void>> _steps = [for (final _ in delays) Completer<void>()];

  /// Called once in main() before runApp(). [firstFrame] / [delays] are
  /// for tests; the app waits for its first drawn frame.
  static void start({required bool stagger, Future<void>? firstFrame, List<Duration> delays = delays}) {
    if (!stagger) return;
    _gated = true;
    (firstFrame ?? SchedulerBinding.instance.endOfFrame).then((_) {
      for (var i = 0; i < delays.length; i++) {
        Timer(delays[i], () => _free(i));
      }
    });
    // Safety net: never wait longer than this, whatever happens.
    Timer(const Duration(seconds: 15), releaseAll);
  }

  static void _free(int i) {
    for (var k = 0; k <= i; k++) {
      if (!_steps[k].isCompleted) _steps[k].complete();
    }
  }

  /// Done when step [n] (1–3) may start.
  static Future<void> reached(int n) => !_gated ? Future<void>.value() : _steps[n - 1].future;

  /// Whether step [n] may start now.
  static bool isFree(int n) => !_gated || _steps[n - 1].isCompleted;

  /// [open] once step [n] may start (its subscription starts then).
  static Stream<T> after<T>(int n, Stream<T> Function() open) =>
      isFree(n) ? open() : Stream.fromFuture(reached(n)).asyncExpand((_) => open());

  /// Every step free (the safety net; tests).
  static void releaseAll() => _free(delays.length - 1);

  @visibleForTesting
  static void resetForTest({bool gated = false}) {
    _gated = gated;
    for (var i = 0; i < _steps.length; i++) {
      _steps[i] = Completer<void>();
    }
  }
}
