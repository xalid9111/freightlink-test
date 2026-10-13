import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ads/presentation/catalog_order.dart';

/// Fixed-size photo tiles that can be reordered by drag & drop.
///
/// Press and hold a tile: it lifts (slightly larger, with a shadow) and
/// follows the finger left/right and across rows; the other tiles slide to
/// their new places. On release [onReorder] gets the new order — the
/// parent keeps it (controlled widget). Taps inside a tile (e.g. its ✕
/// button) keep working. [trailing] (e.g. "add photo") stays after the
/// tiles and never moves.
///
/// The long press wins over the page scroll, so the page does not move by
/// accident (iPhone Safari / PWA); near the top/bottom edge the page
/// scrolls on purpose. Only positions animate and every tile is its own
/// RepaintBoundary; no geometry is read during build or layout.
class ReorderTileGrid extends StatefulWidget {
  final List<String> ids;
  final Widget Function(String id) tileBuilder;
  final ValueChanged<List<String>> onReorder;
  final double tileSize;
  final double gap;
  final Widget? trailing;

  const ReorderTileGrid({
    super.key,
    required this.ids,
    required this.tileBuilder,
    required this.onReorder,
    this.tileSize = 84,
    this.gap = 8,
    this.trailing,
  });

  @override
  State<ReorderTileGrid> createState() => _ReorderTileGridState();
}

class _ReorderTileGridState extends State<ReorderTileGrid> {
  static const _move = Duration(milliseconds: 180);
  static const _lift = 1.08;
  static const _edge = 72.0;
  static const _scrollStep = 9.0;

  final GlobalKey _boxKey = GlobalKey();
  List<String>? _working; // order while a tile is lifted
  String? _dragId;
  Offset _finger = Offset.zero;
  Offset _grab = Offset.zero;
  Offset _dragLocal = Offset.zero;
  Timer? _autoScroll;
  GridGeometry _geo = const GridGeometry(width: 0);

  List<String> get _order => _working ?? widget.ids;

  @override
  void didUpdateWidget(ReorderTileGrid old) {
    super.didUpdateWidget(old);
    // Tiles added / removed by the parent during a drag: drop the drag.
    if (_dragId != null && !widget.ids.contains(_dragId)) {
      _autoScroll?.cancel();
      _autoScroll = null;
      _dragId = null;
      _working = null;
    }
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    super.dispose();
  }

  Offset? _toLocal(Offset global) {
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  void _start(String id, LongPressStartDetails d) {
    final local = _toLocal(d.globalPosition);
    if (local == null) return;
    HapticFeedback.mediumImpact();
    final order = List.of(widget.ids);
    setState(() {
      _working = order;
      _dragId = id;
      _finger = d.globalPosition;
      _dragLocal = local;
      _grab = local - _geo.slotOffset(order.indexOf(id));
    });
  }

  void _dragTo(Offset global) {
    final id = _dragId;
    final order = _working;
    if (id == null || order == null) return;
    _finger = global;
    final local = _toLocal(global);
    if (local == null) return;
    final center = local - _grab + Offset(_geo.tile / 2, _geo.tile / 2);
    final to = _geo.slotAt(center, first: 0, last: order.length - 1);
    final from = order.indexOf(id);
    setState(() {
      _dragLocal = local;
      if (from != to) _working = moveItem(order, from, to);
    });
    _updateAutoScroll(global);
  }

  void _updateAutoScroll(Offset global) {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.hasSize) return;
    double dirAt(Offset g) {
      final y = box.globalToLocal(g).dy;
      return y < _edge ? -1.0 : (y > box.size.height - _edge ? 1.0 : 0.0);
    }

    if (dirAt(global) == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final pos = scrollable.position;
      final d = dirAt(_finger);
      final target = (pos.pixels + d * _scrollStep).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (d == 0 || target == pos.pixels || _dragId == null) {
        _autoScroll?.cancel();
        _autoScroll = null;
        return;
      }
      pos.jumpTo(target);
      _dragTo(_finger);
    });
  }

  void _end() {
    _autoScroll?.cancel();
    _autoScroll = null;
    final order = _working;
    if (_dragId == null || order == null) return;
    final changed = !_sameOrder(order, widget.ids);
    setState(() {
      _dragId = null;
      _working = null;
    });
    if (changed) widget.onReorder(order);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _geo = GridGeometry.fixed(width: constraints.maxWidth, tileSize: widget.tileSize, gap: widget.gap);
        final order = _order;
        final slots = order.length + (widget.trailing == null ? 0 : 1);
        final painted = [...order.where((id) => id != _dragId), if (_dragId != null) _dragId!];
        final trailingAt = _geo.slotOffset(order.length);
        return SizedBox(
          key: _boxKey,
          height: _geo.heightFor(slots),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.trailing != null)
                Positioned(left: trailingAt.dx, top: trailingAt.dy, width: _geo.tile, height: _geo.tile, child: widget.trailing!),
              for (final id in painted) _tile(id, order),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(String id, List<String> order) {
    final dragged = id == _dragId;
    final pos = dragged ? _dragLocal - _grab : _geo.slotOffset(order.indexOf(id));
    return AnimatedPositioned(
      key: ValueKey(id),
      duration: dragged ? Duration.zero : _move,
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: _geo.tile,
      height: _geo.tile,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _start(id, d),
        onLongPressMoveUpdate: (d) => _dragTo(d.globalPosition),
        onLongPressEnd: (_) => _end(),
        onLongPressCancel: _end,
        child: AnimatedScale(
          scale: dragged ? _lift : 1,
          duration: const Duration(milliseconds: 120),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: dragged ? const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))] : null,
            ),
            child: RepaintBoundary(child: widget.tileBuilder(id)),
          ),
        ),
      ),
    );
  }
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
