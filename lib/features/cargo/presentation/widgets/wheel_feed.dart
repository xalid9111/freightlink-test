import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feedback/wheel_feedback.dart';

/// Open Loads feed scrolling.
///
/// * Plain scroll (owner, 22.10.2026): the cards are drawn as they are —
///   no 3D tilt, shrinking or dark veil while scrolling (it made the feed
///   stutter). [WheelItem] only caches the card (RepaintBoundary).
/// * [WheelScope] listens to the scroll: when a different item reaches the
///   centre it fires one light haptic (detent, switch in Settings); the
///   scroll is free, no snapping.
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
}

class _WheelScopeData extends InheritedWidget {
  final WheelController controller;
  const _WheelScopeData({required this.controller, required super.child});

  @override
  bool updateShouldNotify(_WheelScopeData old) => old.controller != controller;
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

  @override
  void initState() {
    super.initState();
    // Load the saved haptic choice early.
    ref.read(wheelSettingsProvider);
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
    return _WheelScopeData(
      controller: _controller,
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

  /// The card as it is — no scroll animation (owner, 22.10.2026).
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: widget.child);
}
