import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../autofix/autofix.dart';
import '../autofix/autofix_logic.dart';
import '../theme/app_theme.dart';

// Scroll smoothness (owner, 16.11.2026: "sürüşdürəndə xırda tutmalarla
// hərəkət edir, yazılar titrəyir … sürətölçən qoy və bir mexanizm düzəlt ki,
// axıcılıqda problem yarananda rahat məlumat götürə biləsən").
//
//  * Every vertical scroll is measured on every device (the frames drawn
//    while it moves): frames a second, the longest gap, missed frames.
//  * A poor scroll (under 45 frames a second, or a frame gap over 100 ms) is
//    recorded in AutoFix (kind "freeze", source "perf") with the page, the
//    screen, the browser and the test switches — at most once per page every
//    10 minutes and 6 times per visit. No personal data, nothing changed.
//  * Admins: Ayarlar → "Sürətölçən" shows the numbers live in a small box,
//    and test switches to compare on their own phone (kept on the device).

/// The numbers of one scroll (or of the part so far).
class ScrollPerfStats {
  final int frames;
  final double fps;
  final double worstMs;
  final int missed;
  const ScrollPerfStats({required this.frames, required this.fps, required this.worstMs, required this.missed});

  /// Under 45 frames a second or a gap over 100 ms: the user sees it.
  bool get poor => fps < 45 || worstMs > 100;

  /// From the frame times of a scroll (ms); null when too short to judge.
  static ScrollPerfStats? fromFrameTimes(List<double> ms) {
    // Few frames in a long scroll IS the stutter we look for: 3 frames over
    // 100 ms are enough to judge (a 300 ms scroll drawn in 4 frames = poor).
    if (ms.length < 3) return null;
    final span = ms.last - ms.first;
    if (span < 100) return null;
    var worst = 0.0;
    var missed = 0;
    for (var i = 1; i < ms.length; i++) {
      final gap = ms[i] - ms[i - 1];
      if (gap > worst) worst = gap;
      // At 60 Hz a frame is 16.7 ms: a gap over 25 ms = at least one missed.
      if (gap > 25) missed += (gap / 16.7).round() - 1;
    }
    return ScrollPerfStats(frames: ms.length, fps: (ms.length - 1) * 1000 / span, worstMs: worst, missed: missed);
  }

  @override
  String toString() => '${fps.round()} fps · max ${worstMs.round()} ms · $missed';
}

/// The admin's test switches (kept on this device only).
class PerfFlags {
  PerfFlags._();
  static final meter = ValueNotifier<bool>(false);

  /// Flutter's pointer resampling: finger moves are spread evenly over the
  /// screen's frames (against "small steps" / trembling text).
  static final resample = ValueNotifier<bool>(false);
  static final mapStill = ValueNotifier<bool>(false);
  static final noImages = ValueNotifier<bool>(false);

  /// Draw at 2x instead of 3x (web/index.html reads it before the app
  /// starts, so it counts from the next opening).
  static final render2 = ValueNotifier<bool>(false);

  static const _keys = {'meter': 'perf_meter', 'resample': 'perf_resample', 'map': 'perf_map_still', 'img': 'perf_no_img', 'render2': 'perf_render2'};

  static Map<String, ValueNotifier<bool>> get all =>
      {'meter': meter, 'resample': resample, 'map': mapStill, 'img': noImages, 'render2': render2};

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final e in all.entries) {
        e.value.value = p.getBool(_keys[e.key]!) ?? false;
      }
    } catch (_) {}
    _applyResample();
  }

  static Future<void> set(String key, bool on) async {
    all[key]!.value = on;
    if (key == 'resample') _applyResample();
    try {
      (await SharedPreferences.getInstance()).setBool(_keys[key]!, on);
    } catch (_) {}
  }

  static void _applyResample() {
    try {
      GestureBinding.instance.resamplingEnabled = resample.value;
    } catch (_) {}
  }

  /// "resample,map" — the switches that are on, for the report.
  static String get summary => [
        if (resample.value) 'resample',
        if (mapStill.value) 'map_still',
        if (noImages.value) 'no_images',
        if (render2.value) 'render2x',
      ].join(',');
}

/// Measures the frames of every vertical scroll below it, shows the admin's
/// meter and records poor scrolls in AutoFix.
class ScrollPerfScope extends StatefulWidget {
  final Widget child;
  const ScrollPerfScope({super.key, required this.child});

  @override
  State<ScrollPerfScope> createState() => _ScrollPerfScopeState();
}

class _ScrollPerfScopeState extends State<ScrollPerfScope> {
  static bool _frameHook = false;
  static _ScrollPerfScopeState? _current;

  final _frames = <double>[];
  bool _active = false;
  int _depth = 0;
  DateTime _since = DateTime.now();
  final _shown = ValueNotifier<ScrollPerfStats?>(null);
  final _lastReport = <String, DateTime>{};
  int _reports = 0;

  @override
  void initState() {
    super.initState();
    _current = this;
    if (!_frameHook) {
      _frameHook = true;
      SchedulerBinding.instance.addPersistentFrameCallback((ts) => _current?._onFrame(ts));
    }
    PerfFlags.load();
  }

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    _shown.dispose();
    super.dispose();
  }

  void _onFrame(Duration ts) {
    if (!_active) return;
    _frames.add(ts.inMicroseconds / 1000);
    if (_frames.length > 2000) _frames.removeRange(0, 1000);
    if (PerfFlags.meter.value && _frames.length % 15 == 0) {
      final s = ScrollPerfStats.fromFrameTimes(_frames);
      if (s != null) _shown.value = s;
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      // A scroll whose end never came (its page closed mid-scroll) never
      // keeps the meter busy: after 15 s a new start begins afresh.
      if (_depth > 0 && DateTime.now().difference(_since) > const Duration(seconds: 15)) _depth = 0;
      if (_depth++ == 0) {
        _frames.clear();
        _active = true;
        _since = DateTime.now();
      }
    } else if (n is ScrollEndNotification) {
      if (_depth > 0 && --_depth == 0) _finish();
    }
    return false;
  }

  void _finish() {
    _active = false;
    final s = ScrollPerfStats.fromFrameTimes(_frames);
    _frames.clear();
    if (s == null) return;
    if (PerfFlags.meter.value) _shown.value = s;
    if (s.poor) _report(s);
  }

  void _report(ScrollPerfStats s) {
    final route = AutoFix.instance.currentRoute;
    final now = DateTime.now();
    final last = _lastReport[route];
    if (_reports >= 6 || (last != null && now.difference(last) < const Duration(minutes: 10))) return;
    _lastReport[route] = now;
    _reports++;
    final mq = MediaQuery.maybeOf(context);
    final size = mq == null ? '?' : '${mq.size.width.round()}x${mq.size.height.round()}@${mq.devicePixelRatio}';
    AutoFix.instance.capture('Scroll not smooth (sürüşmə axıcı deyil)', null,
        source: 'perf',
        forceKind: AutoFixKind.freeze,
        detail: 'fps=${s.fps.toStringAsFixed(1)} worst=${s.worstMs.round()}ms missed=${s.missed} frames=${s.frames} '
            'screen=$size switches=${PerfFlags.summary.isEmpty ? '-' : PerfFlags.summary}');
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: PerfFlags.meter,
          builder: (context, on, _) => !on
              ? const SizedBox.shrink()
              : Positioned(
                  left: 6,
                  top: MediaQuery.paddingOf(context).top + 4,
                  child: IgnorePointer(child: _Meter(stats: _shown)),
                ),
        ),
      ]),
    );
  }
}

/// The admin's small live box: frames a second · longest gap · missed.
class _Meter extends StatelessWidget {
  final ValueNotifier<ScrollPerfStats?> stats;
  const _Meter({required this.stats});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScrollPerfStats?>(
      valueListenable: stats,
      builder: (context, s, _) {
        final good = s == null || !s.poor;
        return Material(
          type: MaterialType.transparency,
          child: Container(
            key: const ValueKey('perf-meter'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.card.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: good ? AppColors.online : AppColors.danger),
            ),
            child: Text(
              s == null ? 'Sürüşdürün…' : '${s.fps.round()} fps · ən uzun ${s.worstMs.round()} ms · buraxılan ${s.missed}',
              style: TextStyle(fontSize: 11, color: AppColors.text, fontWeight: FontWeight.w500),
            ),
          ),
        );
      },
    );
  }
}
