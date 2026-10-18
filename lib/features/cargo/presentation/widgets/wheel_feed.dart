import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/wheel_feedback.dart';
import '../../../../core/theme/app_theme.dart';

/// "3D wheel" presentation of the Open Loads feed.
///
/// * Every visible feed item ([WheelItem]) measures how far its centre is
///   from the centre of the screen and, from that single number, gets a
///   slightly smaller scale, a darker veil and (on capable devices) a
///   small perspective tilt. Items are NOT rebuilt per frame — only the
///   cheap transform/veil around a cached (RepaintBoundary) card.
/// * [WheelScope] listens to the scroll: when a different item reaches the
///   centre it fires one light haptic (detent); when the finger lifts and
///   the scroll stops, it simply stops — no snapping (free, smooth scroll).
/// * An adaptive frame monitor switches to "lite" (no tilt) when frames
///   get slow, and reduce-motion turns tilt and snapping off.
/// App-wide scroll signals of the home feed (used to pause the animated
/// map while the user scrolls, so the feed gets the whole frame budget).
class WheelSignals {
  WheelSignals._();
  static final ValueNotifier<bool> scrolling = ValueNotifier(false);
  static double offset = 0;
}

/// True when [box] and every box above it already has a size, so
/// `localToGlobal` can run. Right after a page transition is rebuilt its
/// new SlideTransition box is not laid out yet; asking through it threw
/// "RenderBox was not laid out" (AutoFix, /cargo /market /services ...).
bool wheelBoxReady(RenderObject? box) {
  if (box is! RenderBox || !box.attached || !box.hasSize) return false;
  for (RenderObject? p = box.parent; p != null; p = p.parent) {
    if (p is RenderBox && !p.hasSize) return false;
  }
  return true;
}

class WheelController {
  final Map<int, _WheelItemState> _items = {};
  final ValueNotifier<bool> lite = ValueNotifier(false);
  int? _focused;
  DateTime _lastDetent = DateTime.fromMillisecondsSinceEpoch(0);

  void _register(int index, _WheelItemState s) => _items[index] = s;
  void _unregister(int index, _WheelItemState s) {
    if (identical(_items[index], s)) _items.remove(index);
  }

  /// Nearest item to the viewport centre: (index, signed distance in px
  /// from centre, item height, isAd). Null when no item is near.
  ({int index, double delta, double height, bool isAd})? nearest(double viewportCenterGlobal) {
    ({int index, double delta, double height, bool isAd})? best;
    for (final e in _items.entries) {
      final m = e.value._measure();
      if (m == null) continue;
      final delta = m.center - viewportCenterGlobal;
      if (best == null || delta.abs() < best.delta.abs()) {
        best = (index: e.key, delta: delta, height: m.height, isAd: e.value.widget.isAd);
      }
    }
    return best;
  }

  void dispose() => lite.dispose();
}

class _WheelScopeData extends InheritedWidget {
  final WheelController controller;
  final bool reduceMotion;
  const _WheelScopeData({required this.controller, required this.reduceMotion, required super.child});

  @override
  bool updateShouldNotify(_WheelScopeData old) => old.controller != controller || old.reduceMotion != reduceMotion;
}

/// Wrap the feed's scroll view with this.
class WheelScope extends ConsumerStatefulWidget {
  final Widget child;
  const WheelScope({super.key, required this.child});

  @override
  ConsumerState<WheelScope> createState() => _WheelScopeState();
}

class _WheelScopeState extends ConsumerState<WheelScope> {
  final _controller = WheelController();
  final List<double> _frameMs = [];
  int _slowBatches = 0;
  int _fastBatches = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Load the saved haptic choice early.
    ref.read(wheelSettingsProvider);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _controller.dispose();
    super.dispose();
  }

  /// Adaptive quality: average build+raster time of the last frames.
  /// > 22 ms twice in a row → lite (no tilt); < 12 ms for a long while →
  /// back to full. Scale, veil, focus and snapping always stay.
  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frameMs.add((t.buildDuration + t.rasterDuration).inMicroseconds / 1000.0);
    }
    if (_frameMs.length < 20) return;
    final avg = _frameMs.reduce((a, b) => a + b) / _frameMs.length;
    _frameMs.clear();
    if (avg > 22) {
      _fastBatches = 0;
      if (++_slowBatches >= 2) _controller.lite.value = true;
    } else if (avg < 12) {
      _slowBatches = 0;
      if (++_fastBatches >= 6) _controller.lite.value = false;
    }
  }

  double? _viewportCenter(ScrollMetrics _, BuildContext scrollContext) {
    final box = scrollContext.findRenderObject();
    if (box is! RenderBox || !wheelBoxReady(box)) return null;
    return box.localToGlobal(Offset(0, box.size.height / 2)).dy;
  }

  bool _onNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      WheelSignals.scrolling.value = true;
    } else if (n is ScrollEndNotification) {
      WheelSignals.scrolling.value = false;
    }
    WheelSignals.offset = n.metrics.pixels;
    if (n is! ScrollUpdateNotification) return false;
    final scrollContext = n.context;
    if (scrollContext == null) return false;
    final center = _viewportCenter(n.metrics, scrollContext);
    if (center == null) return false;
    _checkDetent(center);
    return false;
  }

  void _checkDetent(double center) {
    final hit = _controller.nearest(center);
    // Focus only counts when an item actually covers the centre line
    // (not while the user is still looking at the map/hero on top).
    if (hit == null || hit.delta.abs() > hit.height * 0.5) {
      _controller._focused = null;
      return;
    }
    if (hit.index == _controller._focused) return;
    _controller._focused = hit.index;
    final now = DateTime.now();
    // One tick per detent; during a very fast fling at most ~1 per 45 ms
    // so it reads "tick-tick-tick", never "trrrr".
    if (now.difference(_controller._lastDetent).inMilliseconds < 45) return;
    _controller._lastDetent = now;
    wheelDetent(ref.read(wheelSettingsProvider), isAd: hit.isAd);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return _WheelScopeData(
      controller: _controller,
      reduceMotion: reduceMotion,
      child: NotificationListener<ScrollNotification>(onNotification: _onNotification, child: widget.child),
    );
  }
}

/// One feed entry (cargo card or sponsored banner) on the wheel.
class WheelItem extends StatefulWidget {
  final int index;
  final bool isAd;
  final Widget child;
  const WheelItem({super.key, required this.index, required this.isAd, required this.child});

  @override
  State<WheelItem> createState() => _WheelItemState();
}

class _WheelItemState extends State<WheelItem> {
  WheelController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.dependOnInheritedWidgetOfExactType<_WheelScopeData>()?.controller;
    if (c != _controller) {
      _controller?._unregister(widget.index, this);
      _controller = c;
      _controller?._register(widget.index, this);
    }
  }

  @override
  void didUpdateWidget(WheelItem old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _controller?._unregister(old.index, this);
      _controller?._register(widget.index, this);
    }
  }

  @override
  void dispose() {
    _controller?._unregister(widget.index, this);
    super.dispose();
  }

  /// Untransformed centre (global y) and height of this item.
  ({double center, double height})? _measure() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !wheelBoxReady(box)) return null;
    return (center: box.localToGlobal(Offset(0, box.size.height / 2)).dy, height: box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_WheelScopeData>();
    final scrollable = Scrollable.maybeOf(context);
    final cached = RepaintBoundary(child: widget.child);
    if (scope == null || scrollable == null) return cached;
    final reduceMotion = scope.reduceMotion;
    final lite = scope.controller.lite;

    return AnimatedBuilder(
      animation: Listenable.merge([scrollable.position, lite]),
      child: cached,
      builder: (context, child) {
        // Normalised distance from the viewport centre: 0 = centre,
        // ±1 = top/bottom edge of the screen.
        double d = 0;
        final me = _measure();
        final vp = scrollable.context.findRenderObject();
        if (me != null && vp is RenderBox && wheelBoxReady(vp)) {
          final vpCenter = vp.localToGlobal(Offset(0, vp.size.height / 2)).dy;
          d = ((me.center - vpCenter) / (vp.size.height / 2)).clamp(-1.3, 1.3);
        }
        final a = math.min(d.abs(), 1.0);
        // Smoothstep: flat around the centre, soft towards the edges — no
        // visible "steps" while scrolling.
        final e = a * a * (3 - 2 * a);
        final scale = 1.0 - 0.07 * e;
        final veil = 0.50 * e;
        final tilt = (reduceMotion || lite.value) ? 0.0 : -d.clamp(-1.0, 1.0) * 0.16;

        // Same widget structure every frame (so the cached card is never
        // re-mounted): Transform → foreground veil → card.
        final m = Matrix4.identity();
        if (tilt != 0) {
          m
            ..setEntry(3, 2, 0.0008)
            ..rotateX(tilt);
        }
        m.multiply(Matrix4.diagonal3Values(scale, scale, 1));
        final veiled = DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(color: AppColors.background.withValues(alpha: veil)),
          child: child,
        );
        return Transform(alignment: Alignment.center, transform: m, child: veiled);
      },
    );
  }
}
